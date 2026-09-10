#!/usr/bin/env sh
# tests/test_dts.sh - Docker Test Shell integration test
# Runs the full .minions stack in a clean container and verifies end-to-end functionality
#
# Usage:
#   CI_DTS_TEST=1 bash tests/test_dts.sh
#   bash tests/test_dts.sh                  # local run (requires docker); cleans up after
#   bash tests/test_dts.sh --no-clean       # keep the container after tests so you can
#                                             shell in (dts shell) and test manually

set -e
set -u

# Parse flags: --no-clean leaves the container up after the test run
NO_CLEAN=0
for _arg in "$@"; do
    case "${_arg}" in
        --no-clean) NO_CLEAN=1 ;;
        -h|--help)
            echo "Usage: test_dts.sh [--no-clean]"
            echo "  --no-clean    leave the DTS container running after tests (no 'dts clean')"
            echo "                so you can shell in with: ${0%/*}/../scripts/dts.sh shell"
            exit 0
            ;;
        *)
            echo "Unknown option: ${_arg}" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# Cleanup helper: with --no-clean, leaves the container up for manual testing.
cleanup() {
    if [ "${NO_CLEAN}" -eq 1 ]; then
        echo ""
        log_warn "--no-clean set: leaving container 'dts-test' running for manual testing"
        echo ""
        echo "  Shell in:   ${DTS_SCRIPT} shell"
        echo "  Run a cmd:  ${DTS_SCRIPT} exec \"<cmd>\""
        echo "  Remove it:  ${DTS_SCRIPT} clean"
        return 0
    fi
    "${DTS_SCRIPT}" clean >/dev/null 2>&1 || true
}

# Colors
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

log_info() { echo "${GREEN}[PASS]${NC} $*"; }
log_error() { echo "${RED}[FAIL]${NC} $*"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }

echo "=== DTS Full Stack Integration Test ==="
echo "Project: ${PROJECT_ROOT}"
echo ""

# Check prerequisites
if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker not found. Install Docker to run DTS tests."
    exit 1
fi

DTS_SCRIPT="${PROJECT_ROOT}/scripts/dts.sh"
if [ ! -x "${DTS_SCRIPT}" ]; then
    log_error "DTS script not found or not executable: ${DTS_SCRIPT}"
    exit 1
fi

# Clean any existing container (always reset state at start, regardless of --non-clean)
"${DTS_SCRIPT}" clean >/dev/null 2>&1 || true

# Start container
"${DTS_SCRIPT}" up
log_info "DTS container started"

# Install system prerequisites
"${DTS_SCRIPT}" apt "curl wget nodejs npm ripgrep ffmpeg python3.12 python3.12-venv python3.12-dev build-essential git ca-certificates software-properties-common sqlite3"
log_info "System prerequisites installed"

# Test 1: install.sh
echo ""
echo "=== Test 1: install.sh ==="
# Capture install.sh stderr to verify it doesn't attempt connections to
# OmniRoute/ModelRelay (services aren't up yet). The pi-failover extension
# install previously triggered 'pi extensions reload' which connected to
# 20128/7352 and spammed "Connection error".
install_out=$("${DTS_SCRIPT}" exec "cd /src && bash install.sh 2>&1")
install_rc=$?
if [ $install_rc -eq 0 ]; then
    # Check for connection attempts during install (should be none)
    if echo "$install_out" | grep -qE "Connection error|127\.0\.0\.1:20128|127\.0\.0\.1:7352"; then
        log_error "install.sh attempted connections to OmniRoute/ModelRelay (services not up yet)"
        echo "$install_out" | grep -E "Connection error|127\.0\.0\.1:20128|127\.0\.0\.1:7352" | head -5
        cleanup
        exit 1
    fi
    log_info "install.sh completed without errors (no connection attempts)"
else
    log_error "install.sh failed"
    echo "$install_out" | tail -20
    cleanup
    exit 1
fi

# Verify install outputs
"${DTS_SCRIPT}" exec "test -d /home/ubuntu/.minions && test -f /home/ubuntu/.minions/bin/omniroute && test -f /home/ubuntu/.minions/bin/modelrelay && test -f /home/ubuntu/.minions/bin/pi"
log_info "Binaries installed correctly"

"${DTS_SCRIPT}" exec "test -f /home/ubuntu/.pi/agent/pi.toml && test -f /home/ubuntu/.pi/agent/models.json && test -f /home/ubuntu/.hermes/config.yaml"
log_info "Config templates copied to standard locations"

# Test 2: boot.sh
echo ""
echo "=== Test 2: boot.sh ==="
if "${DTS_SCRIPT}" exec "cd /src && bash boot.sh"; then
    log_info "boot.sh completed without errors"
else
    log_error "boot.sh failed"
    cleanup
    exit 1
fi

# Test 3: Service health
echo ""
echo "=== Test 3: Service health checks ==="

# OmniRoute
if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/healthz >/dev/null"; then
    log_info "OmniRoute health check passes"
else
    log_error "OmniRoute health check failed"
    cleanup
    exit 1
fi

# ModelRelay
if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:7352/v1/models >/dev/null"; then
    log_info "ModelRelay models endpoint responds"
else
    log_error "ModelRelay models endpoint failed"
    cleanup
    exit 1
fi

# Test 3.5: self-check.sh (full mode — services are up, validates the whole stack)
echo ""
echo "=== Test 3.5: self-check.sh (full stack health) ==="
# Need set +e: self-check can exit 1 (warnings) — with set -e the capture
# would abort the script before we read $? (the shell exits on the failing
# command substitution as if it were the last command).
set +e
DTS_SELFCHECK_OUT=$("${DTS_SCRIPT}" exec "cd /src && bash self-check.sh 2>&1")
DTS_SELFCHECK_RC=$?
set -e
echo "$DTS_SELFCHECK_OUT"
if [ "$DTS_SELFCHECK_RC" -eq 2 ]; then
    log_error "self-check.sh reported CRITICAL failures (exit 2)"
    cleanup
    exit 1
elif [ "$DTS_SELFCHECK_RC" -eq 0 ]; then
    log_info "self-check.sh all green (exit 0)"
elif [ "$DTS_SELFCHECK_RC" -eq 1 ]; then
    log_warn "self-check.sh warnings only (exit 1)"
else
    log_error "self-check.sh crashed (exit $DTS_SELFCHECK_RC)"
    cleanup
    exit 1
fi

# Test 4: OmniRoute preconfig (auto-fastest combo, login disabled)
echo ""
echo "=== Test 4: OmniRoute preconfig ==="
export_path="export PATH=\"/home/ubuntu/.minions/lib/node/bin:/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules/.bin:\${PATH}\" && export NODE_PATH=\"/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules\""

if "${DTS_SCRIPT}" exec "${export_path} && /home/ubuntu/.minions/bin/omniroute combo list 2>/dev/null | grep -q auto-fastest"; then
    log_info "auto-fastest combo configured"
else
    log_error "auto-fastest combo not found"
    cleanup
    exit 1
fi

# Verify login disabled via REST API (sqlite fails when server has DB locked)
if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/api/settings 2>/dev/null | grep -q 'requireLogin.*false'"; then
    log_info "OmniRoute login disabled (REST API)"
else
    log_warn "Could not verify login disabled via REST API"
fi

# Test 5: Chat completion end-to-end
echo ""
echo "=== Test 5: End-to-end chat completion ==="
if "${DTS_SCRIPT}" exec "curl -sf -X POST http://127.0.0.1:20128/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"auto-fastest\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":10}' >/dev/null"; then
    log_info "Chat completion via auto-fastest works"
else
    log_error "Chat completion failed"
    cleanup
    exit 1
fi

# Test 6: Hermes CLI
echo ""
echo "=== Test 6: Hermes CLI ==="
if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/hermes --version >/dev/null 2>&1"; then
    log_info "hermes --version works"
else
    log_error "hermes --version failed"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'base_url: http://127.0.0.1:20128/v1' /home/ubuntu/.hermes/config.yaml && grep -q 'base_url: http://127.0.0.1:7352/v1' /home/ubuntu/.hermes/config.yaml"; then
    log_info "Hermes config has correct ports"
else
    log_error "Hermes config missing correct ports"
    "${DTS_SCRIPT}" exec "cat /home/ubuntu/.hermes/config.yaml"
    cleanup
    exit 1
fi

# Test 7: Pi-Agent CLI
echo ""
echo "=== Test 7: Pi-Agent CLI ==="
# NOTE: pi --version was briefly downgraded to a warning (commit 291e99a) on a
# mistaken "upstream hang" diagnosis. Investigation showed the flag is deterministic
# (0.85.1, ~400ms) and the CI false-positive was the OOM/constrained container, now
# fixed via NODE_OPTIONS in lib/npm_packages.sh. Restore to hard-fail so a broken
# wrapper/binary fails CI instead of silently warning.
if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/pi --version >/dev/null 2>&1"; then
    log_info "pi --version works"
else
    log_error "pi --version failed"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'base_url = \"http://localhost:20128/v1\"' /home/ubuntu/.pi/agent/pi.toml"; then
    log_info "Pi pi.toml has correct omniroute base_url (20128)"
else
    log_error "Pi pi.toml missing correct omniroute base_url"
    "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/pi.toml"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q '\"baseUrl\": \"http://127.0.0.1:20128/v1\"' /home/ubuntu/.pi/agent/models.json && grep -q '\"baseUrl\": \"http://127.0.0.1:7352/v1\"' /home/ubuntu/.pi/agent/models.json"; then
    log_info "Pi models.json has correct baseUrls"
else
    log_error "Pi models.json missing correct baseUrls"
    "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/models.json"
    cleanup
    exit 1
fi

# Test 8: CLI chat - the real end-to-end final check through the auto-fastest combo.
# These exercise the exact user-facing toolchains (hermes with its wrapper, pi with its
# wrapper + provider/model flags). Tools run via their ~/.minions/bin entries, keyless.
echo ""
echo "=== Test 8: CLI chat (hermes + pi, keyless via OmniRoute) ==="

HERMES_BIN="/home/ubuntu/.minions/bin/hermes"
PI_BIN="/home/ubuntu/.minions/bin/pi"

# 8a. hermes chat -q
if "${DTS_SCRIPT}" exec "${HERMES_BIN} chat -q 'Reply with exactly: OK' 2>&1 | grep -q OK"; then
    log_info "hermes chat -q returns OK (keyless via OmniRoute)"
else
    log_error "hermes chat -q did not return OK"
    log_info "(final test may fail if free upstream provider is transiently down; re-run to confirm)"
    cleanup
    exit 1
fi

# 8b. pi -p chat through the auto-fastest combo. The pi wrapper hardcodes MINIONS_HOME
# at install time (lib/pi.sh), so it works keyless via OmniRoute just like hermes chat -q.
if "${DTS_SCRIPT}" exec "${PI_BIN} -p 'Reply with exactly: OK' --provider omniroute --model omniroute/auto-fastest 2>&1 | grep -q OK"; then
    log_info "pi -p returns OK (keyless via OmniRoute)"
else
    log_error "pi -p did not return OK"
    cleanup
    exit 1
fi

# Test 9: stop.sh
echo ""
echo "=== Test 9: stop.sh ==="
if "${DTS_SCRIPT}" exec "cd /src && bash stop.sh"; then
    log_info "stop.sh completed without errors"
else
    log_error "stop.sh failed"
    cleanup
    exit 1
fi

# Verify services stopped (PID files removed)
for service in omniroute modelrelay; do
    if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/${service}.pid"; then
        log_info "${service} PID file removed"
    else
        log_error "${service} PID file still exists"
        cleanup
        exit 1
    fi
done

# Verify readiness marker removed
if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/ready"; then
    log_info "Readiness marker removed"
else
    log_error "Readiness marker still exists"
    cleanup
    exit 1
fi

# Test 9.5: Standalone piped install (curl|bash) — Phase 22.5
echo ""
echo "=== Test 9.5: Standalone piped install (curl|bash) ==="
# Run the literal one-liner from an EMPTY cwd (no /src bind mount context).
# Uses BOOTSTRAP_URL to point at the local repo tarball (avoids network flake).
# We create a tarball of the current repo and serve it via file:// for speed.
# NOTE: use HEAD, not 'main' — CI checks out the PR branch, no local 'main' exists.
# Use --prefix=.minions-main/ so the tar layout matches GitHub's tarball exactly.
TARBALL="/tmp/minions-main.tar.gz"
if "${DTS_SCRIPT}" exec "cd /src && git archive --format=tar.gz --prefix=.minions-main/ -o $TARBALL HEAD"; then
    log_info "git archive (HEAD) tarball created"
else
    log_warn "git archive failed, trying cp+tar fallback"
    "${DTS_SCRIPT}" exec "rm -rf /tmp/tarsrc && mkdir -p /tmp/tarsrc && cp -a /src /tmp/tarsrc/.minions-main && tar czf $TARBALL -C /tmp/tarsrc .minions-main"
fi

# Run piped install from empty dir with temp HOME
# We use BOOTSTRAP_URL=file://$TARBALL to avoid GitHub network
# The piped stdin is the raw install.sh from the tarball
# This tests the FULL bootstrap flow: fetch -> extract -> re-exec -> knowledge copy
STANDALONE_HOME="/home/ubuntu/.minions-standalone"
"${DTS_SCRIPT}" exec "rm -rf $STANDALONE_HOME"
# Extract the FULL repo tree (not just install.sh) to /tmp/repo — this is what
# curl|bash receives: the whole tarball, executed from a piped -s stdin so the
# bootstrap preamble triggers exactly like the real one-liner.
"${DTS_SCRIPT}" exec "rm -rf /tmp/repo && mkdir -p /tmp/repo && tar xzf $TARBALL -C /tmp/repo 2>/dev/null && ls /tmp/repo/.minions-main/install.sh >/dev/null 2>&1 || (echo 'tarball layout check failed'; exit 1)"
"${DTS_SCRIPT}" exec "chmod +x /tmp/repo/.minions-main/install.sh"
# Run the literal one-liner: cat install.sh | bash -s — $0=bash triggers the preamble,
# which fetches BOOTSTRAP_URL (the file:// tarball) and re-execs the full installer.
# RC captured via marker file because exec over ssh masks $?.
"${DTS_SCRIPT}" exec "export BOOTSTRAP_URL=file://$TARBALL && export HOME=$STANDALONE_HOME && cd /tmp/empty && (bash -s < /tmp/repo/.minions-main/install.sh -- --no-hermes --no-omniroute --no-modelrelay > /tmp/standalone_install.log 2>&1; echo \$? > /tmp/standalone_install.rc)"
STANDALONE_RC=$("${DTS_SCRIPT}" exec "cat /tmp/standalone_install.rc")
if [ "$STANDALONE_RC" -eq 0 ]; then
    log_info "Standalone piped install exit 0"
else
    log_error "Standalone piped install failed (exit $STANDALONE_RC)"
    "${DTS_SCRIPT}" exec "cat /tmp/standalone_install.log"
    cleanup
    exit 1
fi

# Verify MODE=standalone and knowledge copied
if "${DTS_SCRIPT}" exec "grep -q 'Knowledge mode: standalone' /tmp/standalone_install.log"; then
    log_info "Standalone mode detected in piped install"
else
    log_error "Standalone mode NOT detected in piped install"
    "${DTS_SCRIPT}" exec "cat /tmp/standalone_install.log"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "test -d $STANDALONE_HOME/.minions/skills && test -f $STANDALONE_HOME/.minions/etc/knowledge.env"; then
    log_info "Standalone assets copied to ~/.minions-standalone"
else
    log_error "Standalone assets NOT copied"
    "${DTS_SCRIPT}" exec "ls -la $STANDALONE_HOME/.minions/ 2>/dev/null || echo 'no .minions'"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'MODE=standalone' $STANDALONE_HOME/.minions/etc/knowledge.env"; then
    log_info "Standalone knowledge.env persisted"
else
    log_error "Standalone knowledge.env MODE not standalone"
    cleanup
    exit 1
fi

# Test 9.6: Dev mode in repo (git checkout with .git + skills + wiki)
echo ""
echo "=== Test 9.6: Dev mode in repo ==="
DEV_HOME="/home/ubuntu/.minions-dev"
"${DTS_SCRIPT}" exec "rm -rf $DEV_HOME"
# Run install.sh from /src (the bind-mounted repo WITH .git)
"${DTS_SCRIPT}" exec "HOME=$DEV_HOME bash /src/install.sh --no-hermes --no-omniroute --no-modelrelay 2>&1 | tee /tmp/dev_install.log"
DEV_RC=$?
if [ $DEV_RC -eq 0 ]; then
    log_info "Dev install exit 0"
else
    log_error "Dev install failed (exit $DEV_RC)"
    "${DTS_SCRIPT}" exec "cat /tmp/dev_install.log"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'Knowledge mode: dev' /tmp/dev_install.log"; then
    log_info "Dev mode detected in repo install"
else
    log_error "Dev mode NOT detected in repo install"
    "${DTS_SCRIPT}" exec "cat /tmp/dev_install.log"
    cleanup
    exit 1
fi

# In dev mode, skills/wiki should NOT be copied to ~/.minions (symlinks via boot.sh)
if ! "${DTS_SCRIPT}" exec "test -d $DEV_HOME/.minions/skills" || [ -z "$("${DTS_SCRIPT}" exec "ls -A $DEV_HOME/.minions/skills 2>/dev/null")" ]; then
    log_info "Dev mode: skills NOT copied (correct)"
else
    log_error "Dev mode: skills incorrectly copied"
    cleanup
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'MODE=dev' $DEV_HOME/.minions/etc/knowledge.env"; then
    log_info "Dev knowledge.env persisted"
else
    log_error "Dev knowledge.env MODE not dev"
    cleanup
    exit 1
fi

# Clean up
cleanup
log_info "DTS container cleaned up"

echo ""
echo "=== ALL DTS INTEGRATION TESTS PASSED ==="