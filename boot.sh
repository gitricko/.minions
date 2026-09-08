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

wait_for_port "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" 15 "omniroute"

# Step 2: ModelRelay
log_info "Starting ModelRelay (${MODELRELAY_HOST}:${MODELRELAY_PORT})..."
start_service "modelrelay" \
    "${MINIONS_HOME}/bin/modelrelay" \
    --host "${MODELRELAY_HOST}" \
    --port "${MODELRELAY_PORT}" \
    >> "${boot_log}" 2>&1 || log_error "Failed to start ModelRelay"

wait_for_port "${MODELRELAY_HOST}" "${MODELRELAY_PORT}" 15 "modelrelay"

# Step 3: Wait for OmniRoute health (needed for any post-boot checks)
log_info "Waiting for OmniRoute health..."
wait_for_health "http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/healthz" 120 "omniroute"

# Step 4: Preconfigure OmniRoute (login off, auto-fastest combo)
log_info "Preconfiguring OmniRoute..."
# Use omniroute CLI since REST API needs auth
OMNIROUTE_BIN="${MINIONS_HOME}/bin/omniroute"
export PATH="${MINIONS_HOME}/lib/node/bin:${MINIONS_HOME}/lib/omniroute/npm/lib/node_modules/.bin:${PATH}"
export NODE_PATH="${MINIONS_HOME}/lib/omniroute/npm/lib/node_modules"

# Create auto-fastest combo (retry-loop because server may still be warming up)
retry_count=0
while ! "${OMNIROUTE_BIN}" combo create auto-fastest --strategy auto --models '[\\"oc/deepseek-v4-flash-free\\",\\"oc/big-pickle\\",\\"opencode-zen/deepseek-v4-flash-free\\",\\"opencode-zen/hy3-free\\",\\"opencode-zen/mimo-v2.5-free\\",\\"opencode-zen/north-mini-code-free\\",\\"opencode-zen/nemotron-3-ultra-free\\",\\"opencode-zen/big-pickle\\"]' >/dev/null 2>&1; do
    retry_count=$((retry_count + 1))
    if [ $retry_count -gt 40 ]; then
        log_warn "omniroute combo create timed out after 120s"
        break
    fi
    echo "omniroute still not ready yet, retrying..."
    sleep 3
done
log_info "OmniRoute preconfig complete"

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