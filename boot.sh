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
# ~/.minions/skills (standalone) — so Hermes discovers the .minions skills.
if [ "${MODE}" = "dev" ]; then
    _HERMES_SKILL_TARGET="${MINIONS_REPO_ROOT}/skills"
else
    _HERMES_SKILL_TARGET="${MINIONS_HOME}/skills"
fi
setup_hermes_skill_link "${HOME}/.hermes" "${_HERMES_SKILL_TARGET}"

# Hermes memories link: ~/.hermes/memories -> repo memories (dev) or
# ~/.minions/memories (standalone) — so MEMORY.md/USER.md are git-tracked.
if [ "${MODE}" = "dev" ]; then
    _HERMES_MEM_TARGET="${MINIONS_REPO_ROOT}/memories"
else
    _HERMES_MEM_TARGET="${MINIONS_HOME}/memories"
fi
setup_hermes_memories_link "${HOME}/.hermes" "${_HERMES_MEM_TARGET}"

# Phase 24: Pi shared-skills wiring — re-assert the SAME skills/ Path on every
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

# Tailscale install choice (persisted by install.sh --tailscale) — presence-gated boot.
# Source knowledge.env if present to get TAILSCALE_MODE (userspace|root); default userspace.
if [ -f "${MINIONS_HOME}/etc/knowledge.env" ]; then
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/knowledge.env"
fi
TAILSCALE_MODE="${TAILSCALE_MODE:-userspace}"
TAILSCALE_STATEDIR="${MINIONS_HOME}/var/tailscale"
TAILSCALE_SOCKET="${MINIONS_HOME}/var/run/tailscaled.sock"
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
start_service "omniroute" \
    "${MINIONS_HOME}/bin/omniroute" \
    serve --port "${OMNIROUTE_PORT}" --no-open \
    >> "${boot_log}" 2>&1 || log_error "Failed to start OmniRoute"

wait_for_port "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" 300 "omniroute"

# Step 2: 9Router
log_info "Starting 9Router (${NINEROUTER_HOST}:${NINEROUTER_PORT})..."
# 9Router 0.5.81 CLI: -H/--host, -p/--port, -n/--no-browser, --skip-update.
# --no-browser + --skip-update are required in headless/CI environments —
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

# Step 3b: Tailscale (opt-in, presence-gated, non-fatal)
# - If --tailscale-root was chosen, defer to systemd (do NOT start a second daemon).
# - Otherwise use userspace networking with socket under MINIONS_HOME so status/stop can work unprivileged.
if [ -x "${MINIONS_HOME}/bin/tailscaled" ] || [ -x "${MINIONS_HOME}/bin/tailscale" ] || command -v tailscaled >/dev/null 2>&1 || command -v tailscale >/dev/null 2>&1; then
    if [ "${TAILSCALE_MODE}" = "root" ]; then
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet tailscaled 2>/dev/null; then
            log_info "Tailscale: systemd tailscaled already active — deferring (root mode)"
        elif pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
            log_info "Tailscale: tailscaled already running — skipping start (root mode)"
        else
            log_info "Tailscale: root mode requested but no systemd/pgrep daemon found — skipping (run: sudo tailscale up)"
        fi
    else
        # Guard against existing daemon (any mode) to avoid double-start + socket collision
        if pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
            log_info "Tailscale: tailscaled already running — skipping start"
        else
            log_info "Starting Tailscale (userspace, statedir=${TAILSCALE_STATEDIR}, socket=${TAILSCALE_SOCKET})..."
            mkdir -p "${TAILSCALE_STATEDIR}" "$(dirname "${TAILSCALE_SOCKET}")"
            # Prefer managed binary, fall back to PATH
            if [ -x "${MINIONS_HOME}/bin/tailscaled" ]; then
                _TS_DAEMON="${MINIONS_HOME}/bin/tailscaled"
            else
                _TS_DAEMON="$(command -v tailscaled 2>/dev/null || echo tailscaled)"
            fi
            start_service "tailscaled" "${_TS_DAEMON}" --statedir "${TAILSCALE_STATEDIR}" --socket "${TAILSCALE_SOCKET}" --tun=userspace-networking >> "${boot_log}" 2>&1 || log_warn "Failed to start tailscaled (non-fatal)"
            # Best-effort status probe — guarded against set -e and missing socket
            if [ -x "${MINIONS_HOME}/bin/tailscale" ]; then
                _TS_CLI="${MINIONS_HOME}/bin/tailscale"
            else
                _TS_CLI="$(command -v tailscale 2>/dev/null || echo tailscale)"
            fi
            _TS_STATUS="$(TAILSCALE_SOCKET="${TAILSCALE_SOCKET}" "${_TS_CLI}" status 2>&1 || true)"
            _TS_FIRST_LINE="$(printf '%s' "${_TS_STATUS}" | head -n 1)"
            case "${_TS_STATUS}" in
                *"Logged out."*) log_warn "Tailscale: not logged in — run: tailscale up (or: sudo tailscale up --authkey=\$TAILSCALE_AUTHKEY)" ;;
                *"stopped"*|*"no state"*) log_info "Tailscale: daemon starting (status: ${_TS_FIRST_LINE})" ;;
                *) log_info "Tailscale: ${_TS_FIRST_LINE}" ;;
            esac
            unset _TS_DAEMON _TS_CLI _TS_STATUS _TS_FIRST_LINE
        fi
    fi
else
    log_info "Tailscale: not installed — skipping (install with install.sh --tailscale)"
fi

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

# Step 6: Configure Hermes CLI (model, providers, fallback) — matches hermes-codespace post-create
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
    } >> "${boot_log}" 2>&1 || {
        log_warn "Hermes config had issues (see ${boot_log})"
    }
    log_info "Hermes config complete"
else
    log_warn "Hermes binary not found at ${HERMES_BIN}, skipping config"
fi

# Step 7: Readiness marker
touch "${MINIONS_HOME}/var/run/ready"

# Step 8: Print READY message
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
echo ""
