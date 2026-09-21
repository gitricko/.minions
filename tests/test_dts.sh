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
    # Preserve in-container logs to the host-mounted /tmp/ci (bind-mounted from
    # $LOGS_DIR by dts.sh) so they survive container removal and CI can collect
    # them: service/boot logs from ~/.minions/var/log, plus the self-check report.
    "${DTS_SCRIPT}" exec "mkdir -p /tmp/ci && cp -a \$HOME/.minions/var/log/. /tmp/ci/ 2>/dev/null || true; cp /tmp/health-report.json /tmp/ci/ 2>/dev/null || true" >/dev/null 2>&1 || true
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
# LOGS_DIR drives dts.sh bind-mount: host dir -> /tmp/ci in container
export LOGS_DIR="${LOGS_DIR:-/tmp/dts-logs}"

# Clean any existing container (always reset state at start, regardless of --non-clean)
"${DTS_SCRIPT}" clean >/dev/null 2>&1 || true

# Start container
"${DTS_SCRIPT}" up
log_info "DTS container started"

# Install system prerequisites
"${DTS_SCRIPT}" apt "curl wget nodejs npm ripgrep ffmpeg python3 python3-venv python3-dev python3-yaml build-essential git ca-certificates software-properties-common sqlite3"
log_info "System prerequisites installed"

# Test 1: install.sh
echo ""
echo "=== Test 1: install.sh ==="
# Capture install.sh stderr to verify it doesn't attempt connections to
# OmniRoute/9Router (services aren't up yet). The pi-failover extension
# install previously triggered 'pi extensions reload' which connected to
# 20128/7352 and spammed "Connection error".
install_out=$("${DTS_SCRIPT}" exec "cd /src && bash install.sh 2>&1")
install_rc=$?
if [ $install_rc -eq 0 ]; then
    # Check for connection attempts during install (should be none)
    if echo "$install_out" | grep -qE "Connection error|127\.0\.0\.1:20128|127\.0\.0\.1:7352"; then
        log_error "install.sh attempted connections to OmniRoute/9Router (services not up yet)"
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
"${DTS_SCRIPT}" exec "test -d /home/ubuntu/.minions && test -f /home/ubuntu/.minions/bin/omniroute && test -f /home/ubuntu/.minions/bin/9router && test -f /home/ubuntu/.minions/bin/pi"
log_info "Binaries installed correctly"

"${DTS_SCRIPT}" exec "test -f /home/ubuntu/.pi/agent/pi.toml && test -f /home/ubuntu/.pi/agent/models.json && test -f /home/ubuntu/.hermes/config.yaml"
log_info "Config templates copied to standard locations"

# Phase 24: Pi shared-skills wiring — settings.json must have a "skills" array
# pointing at an existing skills dir (dev: /src/skills, standalone: ~/.minions/skills).
# Detect mode to check the right path.
"${DTS_SCRIPT}" exec 'if grep -q "\"skills\"" /home/ubuntu/.pi/agent/settings.json 2>/dev/null; then
  if [ -d /src/.git ]; then grep -q /src/skills /home/ubuntu/.pi/agent/settings.json; else grep -q /home/ubuntu/.minions/skills /home/ubuntu/.pi/agent/settings.json; fi
else exit 1; fi'
log_info "Pi settings.json wired with skills path"

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

# 9Router
if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:7352/v1/models >/dev/null"; then
    log_info "9Router models endpoint responds"
else
    log_error "9Router models endpoint failed"
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

# Test 5: Chat completion end-to-end (OPTIONAL — auto-fastest routes to
# oc/opencode-zen free-tier providers which reject non-OpenCode requests.
# Known upstream OmniRoute OC bug — gate with CI_OMNIROUTE_CHAT_REQUIRED=1)
echo ""
echo "=== Test 5: End-to-end chat completion (optional) ==="
# 5a. OmniRoute chat completion
if "${DTS_SCRIPT}" exec "curl -sf -X POST http://127.0.0.1:20128/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"auto-fastest\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":10}' >/dev/null"; then
    log_info "Chat completion via OmniRoute auto-fastest works"
elif [ "${CI_OMNIROUTE_CHAT_REQUIRED:-0}" -eq 1 ]; then
    log_error "Chat completion via OmniRoute failed (CI_OMNIROUTE_CHAT_REQUIRED=1)"
    cleanup
    exit 1
else
    log_warn "Chat completion via OmniRoute skipped (known OC provider bug; set CI_OMNIROUTE_CHAT_REQUIRED=1 to enforce)"
fi

# 5b. 9Router chat completion (OpenAI-compatible /v1/chat/completions with model=auto-fastest)
if "${DTS_SCRIPT}" exec "curl -sf -X POST http://127.0.0.1:7352/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"auto-fastest\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":10}' >/dev/null"; then
    log_info "Chat completion via 9Router auto-fastest works"
else
    log_warn "Chat completion via 9Router skipped (may need OC credentials; same upstream OC bug)"
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

# 8a. hermes chat -q — uses hermes default failover (omniroute → 9router)
# If OmniRoute auto-fastest fails (OC provider bug), hermes wrapper should failover to 9router.
if "${DTS_SCRIPT}" exec "${HERMES_BIN} chat -q 'Reply with exactly: OK' 2>&1 | grep -q OK"; then
    log_info "hermes chat -q returns OK (failover: omniroute → 9router)"
else
    log_warn "hermes chat -q did not return OK (failover may not have triggered)"
fi

# 8b. pi -p chat — uses pi-failover default (no hardcoded flags)
# pi-failover routes omniroute → 9router automatically; no --provider flags.
if "${DTS_SCRIPT}" exec "${PI_BIN} -p 'Reply with exactly: OK' 2>&1 | grep -q OK"; then
    log_info "pi -p chat returns OK (failover via pi-failover → 9router)"
else
    log_warn "pi -p chat did not return OK (failover may not have triggered)"
fi

# 8c. pi -p discovers the minions skills in standalone mode (Phase 24)
# Ask the model to list the skills available to it; the system prompt includes the
# <available_skills> block. A known minions skill name (docker-test-shell) must
# appear. (The model may answer indirectly; grep for the skill name is the check.)
# Uses default provider/model (pi-failover routes to 9Router); no hardcoded flags.
if "${DTS_SCRIPT}" exec "${PI_BIN} -p 'List the names of the skills available to you. Read-only.' 2>&1 | grep -qi docker-test-shell"; then
    log_info "pi -p sees the minions skills (docker-test-shell) in standalone mode"
elif "${DTS_SCRIPT}" exec "grep -q '\"skills\"' /home/ubuntu/.pi/agent/settings.json && grep -q '/home/ubuntu/.minions/skills' /home/ubuntu/.pi/agent/settings.json"; then
    log_warn "pi -p may not have listed skills (model-dependent); settings.json skills array is correct (standalone path)"
else
    log_error "pi -p did not list skills AND settings.json skills missing in standalone"
    cleanup
    exit 1
fi

# 8d. hermes skills list discovers the minions skills (Phase 24).
# `hermes skills list` prints a table of ALL skills (builtin + local).
# The minions skills show as source=local, category=minions. We check for a
# known skill name in the output. NOTE: may exit 1 when model not configured;
# pipeline exit is grep's (not hermes), so the `if` tests content, not code.
if "${DTS_SCRIPT}" exec "${HERMES_BIN} skills list 2>&1" | grep -q memory-automation; then
    log_info "hermes skills list shows minions skills (memory-automation)"
else
    log_error "hermes skills list did not show minions skills"
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
for service in omniroute 9router; do
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
"${DTS_SCRIPT}" exec "mkdir -p /tmp/empty && export BOOTSTRAP_URL=file://$TARBALL && export HOME=$STANDALONE_HOME && cd /tmp/empty && (bash -s < /tmp/repo/.minions-main/install.sh -- --no-hermes --no-omniroute --no-9router > /tmp/standalone_install.log 2>&1; echo \\$? > /tmp/standalone_install.rc)"
STANDALONE_RC=$("${DTS_SCRIPT}" exec "cat /tmp/standalone_install.rc 2>/dev/null || echo 999")
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
"${DTS_SCRIPT}" exec "HOME=$DEV_HOME bash /src/install.sh --no-hermes --no-omniroute --no-9router 2>&1 | tee /tmp/dev_install.log"
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

# In dev mode, skills/wiki should NOT be copied to ~/.minions; install.sh
# (Phase 23) creates a SYMLINK ~/.minions/skills -> /src/skills instead.
# Accept either: a symlink (new Phase 23 behavior) or an absent dir (pre-23).
if "${DTS_SCRIPT}" exec "test -L $DEV_HOME/.minions/skills"; then
    log_info "Dev mode: skills is a symlink (correct)"
elif "${DTS_SCRIPT}" exec "test -d $DEV_HOME/.minions/skills" && [ -n "$("${DTS_SCRIPT}" exec "ls -A $DEV_HOME/.minions/skills 2>/dev/null")" ]; then
    log_error "Dev mode: skills incorrectly copied (real dir, not symlink)"
    cleanup
    exit 1
else
    log_info "Dev mode: skills not present (correct, pre-23 behavior)"
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