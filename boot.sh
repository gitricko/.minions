#!/usr/bin/env sh
# .minions boot script - starts the full stack
#
# Boot sequence:
#   1. OmniRoute (port 20128) - LLM proxy
#   2. ModelRelay (port 7352) - LLM proxy (alternative)
#   3. Hermes gateway (optional, if MINIONS_HERMES=on)
#   4. Pi-Agent RPC mode (reads port from etc/pi.toml)
#
# Then polls health endpoints and prints "READY FOR FIRSTMATE DISPATCH"
#
# Usage: boot.sh [--daemon] [--dry-run]

set -e
set -u

# Defaults
MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"
DRY_RUN=0

# Default config values (overridden by etc/minions.env)
OMNIROUTE_HOST="127.0.0.1"
OMNIROUTE_PORT="20128"
MODELRELAY_HOST="127.0.0.1"
MODELRELAY_PORT="7352"
PI_RPC_HOST="127.0.0.1"
PI_RPC_PORT="8080"
HERMES_HOST="127.0.0.1"
HERMES_GATEWAY_PORT="8081"
MINIONS_HERMES="${MINIONS_HERMES:-off}"
MINIONS_LLM_BASE_URL="http://localhost:20128/v1"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --daemon)
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            echo "Usage: boot.sh [--daemon] [--dry-run]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
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
log_dry() { echo "${YELLOW}[DRY-RUN]${NC} $*"; }

# Source lib functions
LIB_DIR="${MINIONS_HOME}/lib"

# shellcheck disable=SC1091
. "${LIB_DIR}/process.sh"

# In dry-run mode, override start_service
if [ "${DRY_RUN}" -eq 1 ]; then
    log_dry "Running in dry-run mode - services will not actually start"
    start_service() {
        name=$1
        shift
        echo "  [DRY-RUN] Would start ${name}: $*"
        # Create pid file with fake pid
        (sleep 3600) &
        pid=$!
        echo "${pid}" > "${MINIONS_HOME}/var/run/${name}.pid"
    }
    wait_for_port() {
        log_dry "Would wait for $4 on $1:$2 (timeout ${3}s)"
        return 0
    }
    wait_for_health() {
        log_dry "Would wait for $3 health at $1 (timeout ${2}s)"
        return 0
    }
fi

# Source config (overrides defaults)
if [ -f "${MINIONS_HOME}/etc/minions.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${MINIONS_HOME}/etc/minions.env"
fi

# Re-derive composite URLs after sourcing config
OMNIROUTE_BASE_URL="http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/v1"
MODELRELAY_BASE_URL="http://${MODELRELAY_HOST}:${MODELRELAY_PORT}/v1"
PI_RPC_BASE_URL="http://${PI_RPC_HOST}:${PI_RPC_PORT}"

# Ensure PATH includes our bins
export PATH="${MINIONS_HOME}/bin:${MINIONS_HOME}/lib/node/bin:${MINIONS_HOME}/lib/uv:${PATH}"

# Ensure directories exist
mkdir -p "${MINIONS_HOME}/var/run" "${MINIONS_HOME}/var/log"

# Log boot start
boot_log="${MINIONS_HOME}/var/log/boot.log"
{
    echo "=== boot.sh started at $(date) ==="
    echo "MINIONS_HOME=${MINIONS_HOME}"
    echo "DRY_RUN=${DRY_RUN}"
    echo "MINIONS_HERMES=${MINIONS_HERMES:-off}"
} >> "${boot_log}" 2>&1

echo ""
log_info "Starting .minions stack..."
echo ""

# Step 1: OmniRoute (port 20128)
log_info "Starting OmniRoute (${OMNIROUTE_HOST}:${OMNIROUTE_PORT})..."
start_service "omniroute" \
    "${MINIONS_HOME}/bin/omniroute" \
    --host "${OMNIROUTE_HOST}" \
    --port "${OMNIROUTE_PORT}" \
    >> "${boot_log}" 2>&1 || log_error "Failed to start OmniRoute"

wait_for_port "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" 15 "omniroute"

# Step 2: ModelRelay (port 7352)
log_info "Starting ModelRelay (${MODELRELAY_HOST}:${MODELRELAY_PORT})..."
start_service "modelrelay" \
    "${MINIONS_HOME}/bin/modelrelay" \
    --host "${MODELRELAY_HOST}" \
    --port "${MODELRELAY_PORT}" \
    >> "${boot_log}" 2>&1 || log_error "Failed to start ModelRelay"

wait_for_port "${MODELRELAY_HOST}" "${MODELRELAY_PORT}" 15 "modelrelay"

# Step 3: Hermes gateway (optional)
if [ "${MINIONS_HERMES:-off}" = "on" ]; then
    log_info "Starting Hermes gateway (${HERMES_HOST}:${HERMES_GATEWAY_PORT})..."
    start_service "hermes" \
        "${MINIONS_HOME}/bin/hermes" \
        gateway \
        --host "${HERMES_HOST}" \
        --port "${HERMES_GATEWAY_PORT}" \
        >> "${boot_log}" 2>&1 || log_error "Failed to start Hermes"

    wait_for_port "${HERMES_HOST}" "${HERMES_GATEWAY_PORT}" 15 "hermes"
else
    log_info "Skipping Hermes (set MINIONS_HERMES=on to enable)"
fi

# Step 4: Pi-Agent in RPC mode
log_info "Starting Pi-Agent (RPC mode on ${PI_RPC_HOST}:${PI_RPC_PORT})..."
# Read Pi RPC port from pi.toml if available
if [ -f "${MINIONS_HOME}/etc/pi.toml" ] && command -v grep >/dev/null 2>&1; then
    # Parse port from [rpc] port = XXX
    toml_port=$(grep -A5 '^\[rpc\]' "${MINIONS_HOME}/etc/pi.toml" 2>/dev/null | grep 'port' | head -1 | sed 's/.*= *//; s/"//g; s/ //g')
    if [ -n "${toml_port}" ]; then
        PI_RPC_PORT="${toml_port}"
        PI_RPC_BASE_URL="http://${PI_RPC_HOST}:${PI_RPC_PORT}"
    fi
fi

# Determine base URL for Pi-Agent to use
PI_BASE_URL="${MINIONS_LLM_BASE_URL:-http://localhost:20128/v1}"

start_service "pi" \
    "${MINIONS_HOME}/bin/pi" \
    --rpc \
    --rpc-host "${PI_RPC_HOST}" \
    --rpc-port "${PI_RPC_PORT}" \
    --base-url "${PI_BASE_URL}" \
    --config "${MINIONS_HOME}/etc/pi.toml" \
    >> "${boot_log}" 2>&1 || log_error "Failed to start Pi-Agent"

wait_for_health "http://${PI_RPC_HOST}:${PI_RPC_PORT}/health" 15 "pi-agent"

# Step 5: Print READY message
echo ""
echo "=============================================="
echo "  .minions stack is UP"
echo ""
echo "  ✅ omniroute   ${OMNIROUTE_BASE_URL}"
echo "  ✅ modelrelay  ${MODELRELAY_BASE_URL}"
if [ "${MINIONS_HERMES:-off}" = "on" ]; then
    echo "  ✅ hermes      http://${HERMES_HOST}:${HERMES_GATEWAY_PORT}"
fi
echo "  ✅ pi-agent    ${PI_RPC_BASE_URL}"
echo "=============================================="
echo ""
echo "READY FOR FIRSTMATE DISPATCH"
