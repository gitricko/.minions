#!/usr/bin/env sh
# .minions boot.sh - starts the LLM proxy stack
#
# Boot sequence:
#   1. OmniRoute (port OMNIROUTE_PORT) - LLM proxy
#   2. ModelRelay (port MODELRELAY_PORT) - LLM proxy (alternative)
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
MODELRELAY_HOST="${MODELRELAY_HOST:-127.0.0.1}"
MODELRELAY_PORT="${MODELRELAY_PORT:-7352}"
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
    echo "MODELRELAY_PORT=${MODELRELAY_PORT}"
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

# Step 2: ModelRelay
log_info "Starting ModelRelay (${MODELRELAY_HOST}:${MODELRELAY_PORT})..."
start_service "modelrelay" \
    "${MINIONS_HOME}/bin/modelrelay" \
    --host "${MODELRELAY_HOST}" \
    --port "${MODELRELAY_PORT}" \
    >> "${boot_log}" 2>&1 || log_error "Failed to start ModelRelay"

wait_for_port "${MODELRELAY_HOST}" "${MODELRELAY_PORT}" 300 "modelrelay"

# Step 3: Wait for OmniRoute health (needed for any post-boot checks)
log_info "Waiting for OmniRoute health..."
wait_for_health "http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/healthz" 120 "omniroute"

# Step 4: Preconfigure OmniRoute (auto-fastest combo; login-off done at install)
log_info "Preconfiguring OmniRoute..."
# shellcheck disable=SC1091
. "${LIB_DIR}/omniroute.sh"
if omniroute_preconfigure; then
    log_info "OmniRoute preconfig complete"
else
    log_warn "OmniRoute preconfig had issues (non-fatal)"
fi

# Step 5: Readiness marker
touch "${MINIONS_HOME}/var/run/ready"

# Step 6: Print READY message
echo ""
echo "=============================================="
echo "  .minions stack is UP"
echo ""
echo "  ✅ omniroute    http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/v1"
echo "  ✅ modelrelay   http://${MODELRELAY_HOST}:${MODELRELAY_PORT}/v1"
echo "  ✅ pi-agent     CLI ready (invoked on demand)"
echo "  ✅ hermes       CLI ready (preinstalled)"
echo "  ✅ mnemon       memory layer ready"
echo "=============================================="
echo ""
echo "READY FOR FIRSTMATE DISPATCH"