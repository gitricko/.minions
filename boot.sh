#!/usr/bin/env sh
# .minions boot.sh - starts the LLM proxy stack
#
# Boot sequence:
#   1. OmniRoute (port OMNIROUTE_PORT) - LLM proxy
#   2. 9Router (port NINEROUTER_PORT) - LLM proxy (alternative)
#
# Pi-Agent, Hermes, and Mnemon are CLI tools (invoked on demand), not servers.
# No --daemon flag - services are backgrounded with setsid and boot returns.
#
# Usage: boot.sh [--doctor]

set -e
set -u

# Defaults - fixed install location
MINIONS_HOME="${HOME}/.minions"

# Port configuration (env-overridable with defaults)
OMNIROUTE_HOST="${OMNIROUTE_HOST:-127.0.0.1}"
OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"
NINEROUTER_HOST="${NINEROUTER_HOST:-127.0.0.1}"
NINEROUTER_PORT="${NINEROUTER_PORT:-7352}"
export MINIONS_LLM_BASE_URL="http://localhost:${OMNIROUTE_PORT}/v1"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --doctor)
            DOCTOR=1
            shift
            ;;
        -h|--help)
            echo "Usage: boot.sh [--doctor]"
            echo "  --doctor    Repair a broken component"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
    esac
done

# Color output (only if interactive)
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

log_info() { echo "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo "${RED}[ERROR]${NC} $*" >&2; }

# Source lib functions
LIB_DIR="${MINIONS_HOME}/lib"

# shellcheck disable=SC1091
. "${LIB_DIR}/process.sh"

# Phase 23: knowledge symlink wiring (dev mode)
# shellcheck disable=SC1091
. "${LIB_DIR}/knowledge-symlinks.sh"

# Phase 22: knowledge mode detection (shared with install.sh)
# shellcheck disable=SC1091
. "${LIB_DIR}/knowledge-detection.sh"
detect_knowledge_mode

# Dev-mode symlinks (from knowledge.env MODE + MINIONS_REPO_ROOT)
setup_knowledge_symlinks "${MINIONS_HOME}" "${MINIONS_REPO_ROOT:-}" "${MODE}"

# Hermes user-skills link: ~/.hermes/skills/minions -> repo skills (dev) or
# ~/.minions/skills (standalone) -- so Hermes discovers the .minions skills.
if [ "${MODE}" = "dev" ]; then
    _HERMES_SKILL_TARGET="${MINIONS_REPO_ROOT}/skills"
else
    _HERMES_SKILL_TARGET="${MINIONS_HOME}/skills"
fi
setup_hermes_skill_link "${HOME}/.hermes" "${_HERMES_SKILL_TARGET}"

# Hermes memories link: ~/.hermes/memories -> repo memories (dev) or
# ~/.minions/memories (standalone) -- so MEMORY.md/USER.md are git-tracked.
if [ "${MODE}" = "dev" ]; then
    _HERMES_MEM_TARGET="${MINIONS_REPO_ROOT}/memories"
else
    _HERMES_MEM_TARGET="${MINIONS_HOME}/memories"
fi
setup_hermes_memories_link "${HOME}/.hermes" "${_HERMES_MEM_TARGET}"

# Phase 24: Pi shared-skills wiring -- re-assert the SAME skills/ Path on every
# boot (idempotent; survives reinstall/drift). dev -> repo skills; standalone
# -> ~/.minions/skills.
# shellcheck disable=SC1091
. "${LIB_DIR}/pi-settings.sh"
if [ "${MODE}" = "dev" ]; then
    _PI_SKILLS_PATH="${MINIONS_REPO_ROOT}/skills"
else
    _PI_SKILLS_PATH="${MINIONS_HOME}/skills"
fi
wire_pi_skills_path "${HOME}/.pi/agent/settings.json" "${_PI_SKILLS_PATH}"
wire_pi_default_trust_always "${HOME}/.pi/agent/settings.json"

# Tailscale install choice (persisted by install.sh --tailscale) -- presence-gated boot.
# Source knowledge.env if present to get TAILSCALE_MODE/TAILSCALE_SOCKET.
if [ -f "${MINIONS_HOME}/etc/knowledge.env" ]; then
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/knowledge.env"
fi
TAILSCALE_MODE="${TAILSCALE_MODE:-userspace}"
TAILSCALE_STATEDIR="${MINIONS_HOME}/var/tailscale"
TAILSCALE_SOCKET="${TAILSCALE_SOCKET:-${MINIONS_HOME}/var/run/tailscaled.sock}"
export TAILSCALE_SOCKET

# Ensure directories exist
mkdir -p "${MINIONS_HOME}/var/run" "${MINIONS_HOME}/var/log"

# Log boot start
boot_log="${MINIONS_HOME}/var/log/boot.log"
{
    echo "=== boot.sh started at $(date) ==="
    echo "MINIONS_HOME=${MINIONS_HOME}"
    echo "DRY_RUN=${DRY_RUN:-0}"
    echo "DOCTOR=${DOCTOR:-0}"
    echo "OMNIROUTE_PORT=${OMNIROUTE_PORT}"
    echo "NINEROUTER_PORT=${NINEROUTER_PORT}"
} >> "${boot_log}" 2>&1

echo ""
log_info "Starting .minions stack..."
echo ""

# Step 1: OmniRoute
log_info "Starting OmniRoute (${OMNIROUTE_HOST}:${OMNIROUTE_PORT})..."
# OmniRoute 3.8.x: `serve` is the Commander-based CLI. There is NO --host flag
# (host is bound to 127.0.0.1 by default); old --host/--port invocation misparses.
# --no-open suppresses the browser. NO --daemon: start_service backgrounds via
# setsid and tracks the PID; --daemon would fork a detached child the pid files
# can't track (verified working invocation is `nohup omniroute serve --no-open`).
# Fix for 504 "Fetch timeout after 110000ms": OMNIROUTE_FETCH_START_TIMEOUT_CAP_MS
# is the streaming response-header wait (default 110000ms, open-sse
# fetchStartTimeoutPolicy) — it fired on the slow 100.79.117.84:11434 provider.
# NOT OMNIROUTE_DIRECT_HEADERS_TIMEOUT_MS: that's the pooled direct-socket
# response-start window (zombie-keepalive detection, default 30s). Left at 30s —
# public upstreams keep fast dead-socket retries; local/LAN targets (incl. Tailscale
# 100.x, ollama) already get the built-in 300s local floor (LOCAL_DIRECT default).
export OMNIROUTE_FETCH_START_TIMEOUT_CAP_MS=300000
start_service "omniroute" \
    "${MINIONS_HOME}/bin/omniroute" \
    serve --port "${OMNIROUTE_PORT}" --no-open \
    >> "${boot_log}" 2>&1 || log_error "Failed to start OmniRoute"

wait_for_port "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" 300 "omniroute"

# Step 2: 9Router
log_info "Starting 9Router (${NINEROUTER_HOST}:${NINEROUTER_PORT})..."
# 9Router 0.5.81 CLI: -H/--host, -p/--port, -n/--no-browser, --skip-update.
# --no-browser + --skip-update are required in headless/CI environments --
# otherwise it tries to open a browser and runs an auto-update check that can
# stall startup. Default port is 20128, so --port is mandatory here.
start_service "9router" \
    "${MINIONS_HOME}/bin/9router" \
    --host "${NINEROUTER_HOST}" \
    --port "${NINEROUTER_PORT}" \
    --no-browser \
    --skip-update \
    --log \
    >> "${boot_log}" 2>&1 || log_error "Failed to start 9Router"

wait_for_port "${NINEROUTER_HOST}" "${NINEROUTER_PORT}" 300 "9router"

# Step 3: Ollama (for mnemon embeddings)
log_info "Starting Ollama (localhost:11434)..."
start_service "ollama" \
    "${MINIONS_HOME}/bin/ollama" \
    serve \
    >> "${boot_log}" 2>&1 || log_error "Failed to start Ollama"

wait_for_health "http://localhost:11434/api/tags" 60 "ollama"

# Pull embedding model for mnemon
log_info "Pulling mnemon embedding model (nomic-embed-text)..."
# shellcheck disable=SC1091
. "${LIB_DIR}/ollama.sh"
pull_ollama_model "nomic-embed-text" >> "${boot_log}" 2>&1 &

# Mnemon default seed import — single source in lib/mnemon.sh (deduplicated per #74 review 6133588996 §2.2).
# Non-fatal, deduped, MODE-based seed path, --dry-run gated, embed --status.
# shellcheck disable=SC1091
. "${LIB_DIR}/mnemon.sh"
# Log to boot.log; keep boot non-fatal even if seed missing/invalid.
setup_mnemon_all "${MINIONS_HOME:-${HOME}/.minions}" >>"${boot_log}" 2>&1 || log_warn "Mnemon seed import encountered issues (non-fatal, see ${boot_log})"

# Step 3b: Tailscale (opt-in, presence-gated, non-fatal)
# Gate ONLY on managed install (MINIONS_HOME/bin) -- not system tailscale (fixes #2)
# Auto-detect kernel TUN when host allows it (sudo + /dev/net/tun) else fallback to userspace+proxy.
_ts_can_use_kernel_tun() {
    [ -c /dev/net/tun ] || return 1
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n true 2>/dev/null || return 1
    if command -v ip >/dev/null 2>&1; then
        sudo -n ip tuntap add dev tsprobe0 mode tun 2>/dev/null || return 1
        sudo -n ip tuntap del dev tsprobe0 mode tun 2>/dev/null || true
    fi
    return 0
}
if [ -x "${MINIONS_HOME}/bin/tailscaled" ] || [ -x "${MINIONS_HOME}/bin/tailscale" ]; then
    if [ "${TAILSCALE_MODE}" = "root" ]; then
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet tailscaled 2>/dev/null; then
            log_info "Tailscale: systemd tailscaled already active -- deferring (root mode)"
        elif pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
            log_info "Tailscale: tailscaled already running -- skipping start (root mode)"
        else
            log_info "Tailscale: root mode requested but no systemd/pgrep daemon found -- skipping (run: sudo tailscale up)"
        fi
    else
        # Guard against existing daemon (any mode) to avoid double-start + socket collision
        if pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
            log_info "Tailscale: tailscaled already running -- skipping start"
        else
            if _ts_can_use_kernel_tun; then _TS_MODE="kernel"; else _TS_MODE="userspace"; fi
            mkdir -p "${TAILSCALE_STATEDIR}" "$(dirname "${TAILSCALE_SOCKET}")"
            # Prefer managed binary, fall back to PATH
            if [ -x "${MINIONS_HOME}/bin/tailscaled" ]; then
                _TS_DAEMON="${MINIONS_HOME}/bin/tailscaled"
            else
                _TS_DAEMON="$(command -v tailscaled 2>/dev/null || echo tailscaled)"
            fi
            if [ "${_TS_MODE}" = "kernel" ]; then
                log_info "Starting Tailscale (kernel, statedir=${TAILSCALE_STATEDIR}, socket=${TAILSCALE_SOCKET})..."
                _ts_start_daemon "${_TS_DAEMON}" --statedir "${TAILSCALE_STATEDIR}" --socket "${TAILSCALE_SOCKET}" >> "${boot_log}" 2>&1 || log_warn "Failed to start tailscaled (non-fatal)"
            else
                log_info "Starting Tailscale (userspace, statedir=${TAILSCALE_STATEDIR}, socket=${TAILSCALE_SOCKET})..."
                start_service "tailscaled" "${_TS_DAEMON}" --statedir "${TAILSCALE_STATEDIR}" --socket "${TAILSCALE_SOCKET}" --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1056 >> "${boot_log}" 2>&1 || log_warn "Failed to start tailscaled (non-fatal)"
                # Persist proxy env for user shells (boot env dies with process)
                mkdir -p "${MINIONS_HOME}/etc"
                cat > "${MINIONS_HOME}/etc/tailscale.env" <<TSEOF
# Generated by boot.sh (userspace mode) -- source this in your shell for outbound tailnet
export ALL_PROXY=socks5://localhost:1055
export HTTP_PROXY=http://localhost:1056
export HTTPS_PROXY=http://localhost:1056
export http_proxy=http://localhost:1056
export https_proxy=http://localhost:1056
TSEOF
                log_warn "Tailscale: userspace fallback -- outbound tailnet needs proxy: source ${MINIONS_HOME}/etc/tailscale.env (or ALL_PROXY=socks5://localhost:1055); inbound kernel daemons not reachable (use tailscale serve/ssh)"
                echo "Tailscale userspace -- proxy :1056 -- kernel daemons not reachable" >> "${boot_log}" 2>&1
            fi
            if [ "${_TS_MODE}" = "kernel" ]; then
                # remove stale userspace proxy env if we switched to kernel
                rm -f "${MINIONS_HOME}/etc/tailscale.env" 2>/dev/null || true
            fi
            # Status probe with retry -- userspace sock can take 2-5s (fixes #4); kernel socket may be root-owned
            if [ -x "${MINIONS_HOME}/bin/tailscale" ]; then
                _TS_CLI="${MINIONS_HOME}/bin/tailscale"
            else
                _TS_CLI="$(command -v tailscale 2>/dev/null || echo tailscale)"
            fi
            _TS_STATUS=""
            _ts_attempt=0
            _TS_SOCK_UID=$(stat -c %u "${TAILSCALE_SOCKET}" 2>/dev/null || stat -f %u "${TAILSCALE_SOCKET}" 2>/dev/null || true)
            # Root-owned socket (kernel mode) is world-writable (srw-rw-rw- root:root) -- ownership, not writability (6102925874 #2)
            if [ -S "${TAILSCALE_SOCKET}" ] && [ -n "${_TS_SOCK_UID:-}" ] && [ "${_TS_SOCK_UID}" != "$(id -u)" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
                _TS_SUDO_STATUS=1
            else
                _TS_SUDO_STATUS=0
            fi
            unset _TS_SOCK_UID
            while [ "${_ts_attempt}" -lt 5 ]; do
                if [ "${_TS_SUDO_STATUS}" = "1" ]; then
                    _TS_STATUS="$(sudo -n "${_TS_CLI}" --socket="${TAILSCALE_SOCKET}" status 2>&1 || true)"
                else
                    _TS_STATUS="$("${_TS_CLI}" --socket="${TAILSCALE_SOCKET}" status 2>&1 || true)"
                fi
                case "${_TS_STATUS}" in
                    *"stopped"*|*"no state"*) _ts_attempt=$((_ts_attempt + 1)); sleep 1; continue ;;
                    *) break ;;
                esac
            done
            _TS_FIRST_LINE="$(printf '%s' "${_TS_STATUS}" | head -n 1)"
            case "${_TS_STATUS}" in
                *"Logged out."*) log_warn "Tailscale: not logged in -- run: ts up (or: ts up --authkey=\$TAILSCALE_AUTHKEY) [mode=${_TS_MODE}]" ;;
                *"stopped"*|*"no state"*) log_info "Tailscale: daemon starting (status: ${_TS_FIRST_LINE}) [mode=${_TS_MODE}]" ;;
                *) log_info "Tailscale: ${_TS_FIRST_LINE} [mode=${_TS_MODE}]" ;;
            esac
            unset _TS_DAEMON _TS_CLI _TS_STATUS _TS_FIRST_LINE _ts_attempt
            # Persist mode for visibility (re-detected every boot)
            if [ -f "${MINIONS_HOME}/etc/knowledge.env" ]; then
                if grep -q "^TAILSCALE_MODE=" "${MINIONS_HOME}/etc/knowledge.env" 2>/dev/null; then
                    _tmp_ke="${MINIONS_HOME}/etc/knowledge.env.tmp.$$"
                    if sed "s/^TAILSCALE_MODE=.*/TAILSCALE_MODE=${_TS_MODE}/" "${MINIONS_HOME}/etc/knowledge.env" > "${_tmp_ke}"; then
                        mv "${_tmp_ke}" "${MINIONS_HOME}/etc/knowledge.env"
                    else
                        rm -f "${_tmp_ke}"
                    fi
                    unset _tmp_ke
                fi
            fi
            unset _TS_MODE
        fi
    fi
else
    log_info "Tailscale: not installed -- skipping (install with install.sh --tailscale)"
fi
unset -f _ts_can_use_kernel_tun 2>/dev/null || true

# Step 4: Configure 9Router (auto-fastest combo, disable login/API key)
log_info "Preconfiguring 9Router..."
# shellcheck disable=SC1091
. "${LIB_DIR}/9router.sh"
if ninerouter_preconfigure >> "${boot_log}" 2>&1; then
    log_info "9Router preconfig complete"
else
    log_warn "9Router preconfig had issues (see ${boot_log})"
fi

# Step 4: Wait for OmniRoute health (needed for any post-boot checks)
log_info "Waiting for OmniRoute health..."
wait_for_health "http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/healthz" 120 "omniroute"

# Step 5: Preconfigure OmniRoute (auto-fastest combo; login-off done at install)
log_info "Preconfiguring OmniRoute..."
# shellcheck disable=SC1091
. "${LIB_DIR}/omniroute.sh"
if omniroute_preconfigure >> "${boot_log}" 2>&1; then
    log_info "OmniRoute preconfig complete"
else
    log_warn "OmniRoute preconfig had issues (see ${boot_log})"
fi

# Step 6: Configure Hermes CLI (model, providers, fallback) -- matches hermes-codespace post-create
log_info "Configuring Hermes..."
HERMES_BIN="${MINIONS_HOME}/bin/hermes"
if [ -x "${HERMES_BIN}" ]; then
    {
        "${HERMES_BIN}" config set model.default auto-fastest
        "${HERMES_BIN}" config set model.provider omniroute
        "${HERMES_BIN}" config set providers.omniroute.base_url "http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/v1"
        "${HERMES_BIN}" config set providers.omniroute.api_key "no-key-needed"
        "${HERMES_BIN}" config set providers.9router.base_url "http://${NINEROUTER_HOST}:${NINEROUTER_PORT}/v1"
        "${HERMES_BIN}" config set providers.9router.api_key "no-key-needed"
        "${HERMES_BIN}" config set telemetry.shared_metrics.enabled false
        "${HERMES_BIN}" config set telemetry.shared_metrics.send false
        "${HERMES_BIN}" config set telemetry.shared_metrics.offer_version 2
    } >> "${boot_log}" 2>&1 || {
        log_warn "Hermes config had issues (see ${boot_log})"
    }
    log_info "Hermes config complete"
else
    log_warn "Hermes binary not found at ${HERMES_BIN}, skipping config"
fi

# Step 7: Readiness marker
touch "${MINIONS_HOME}/var/run/ready"

# Step 8: Print READY message (truthful, via status-lib)
# Uses the shared probes so boot footer and status.sh agree.
# Guarded for set -e: status_collect always returns 0; signal is status_exit_code.
# Try installed lib first, then repo lib (fresh clone without install), else hardcoded fallback (L1).
if [ -f "${LIB_DIR}/status-lib.sh" ]; then
    # shellcheck disable=SC1091
    . "${LIB_DIR}/status-lib.sh"
    set +e; status_collect; set -e
    echo ""
    echo "=============================================="
    if [ "$(status_exit_code)" -eq 0 ]; then
        echo "  .minions stack is UP"
    else
        echo "  .minions stack is DEGRADED (see below)"
    fi
    echo ""
    status_render_human
    echo "=============================================="
elif [ -f "$(dirname "$0")/lib/status-lib.sh" ]; then
    # shellcheck disable=SC1091
    . "$(dirname "$0")/lib/status-lib.sh"
    set +e; status_collect; set -e
    echo ""
    echo "=============================================="
    if [ "$(status_exit_code)" -eq 0 ]; then
        echo "  .minions stack is UP"
    else
        echo "  .minions stack is DEGRADED (see below)"
    fi
    echo ""
    status_render_human
    echo "=============================================="
else
    # Fallback if lib missing (should not happen after install)
    echo ""
    echo "=============================================="
    echo "  .minions stack is UP"
    echo ""
    echo "  ✅ omniroute    http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/v1"
    echo "  ✅ 9router      http://${NINEROUTER_HOST}:${NINEROUTER_PORT}/v1"
    echo "  ✅ pi-agent     CLI ready (invoked on demand)"
    echo "  ✅ hermes       CLI ready (preinstalled)"
    echo "  ✅ mnemon       memory layer ready"
    if [ -x "${MINIONS_HOME}/bin/ollama" ]; then
        echo "  ✅ ollama       http://localhost:11434 (embeddings: nomic-embed-text)"
    fi
    echo "=============================================="
fi
echo ""
