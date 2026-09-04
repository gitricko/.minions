#!/usr/bin/env sh
# .minions boot.sh - starts the LLM proxy stack
#
# Boot sequence:
#   1. OmniRoute (port OMNIROUTE_PORT) - LLM proxy
#   2. ModelRelay (port MODELRELAY_PORT) - LLM proxy (alternative)
#   3. OmniRoute preconfiguration (login off, auto-fastest combo, MCP)
#
# Pi-Agent, Hermes, and Mnemon are CLI tools (invoked on demand), not servers.
# No --daemon flag - services are backgrounded with setsid and boot returns.
#
# Usage: boot.sh [--doctor]

set -e
set -u

# Defaults
MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"
DRY_RUN=0
DOCTOR=0

# Default config values (all env-overridable; minions.env may refine them)
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
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            echo "Usage: boot.sh [--doctor] [--dry-run]"
            echo "  --doctor    Repair a broken component"
            echo "  --dry-run   Print actions without executing"
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
    echo "DOCTOR=${DOCTOR}"
    echo "OMNIROUTE_PORT=${OMNIROUTE_PORT}"
    echo "MODELRELAY_PORT=${MODELRELAY_PORT}"
} >> "${boot_log}" 2>&1

echo ""
log_info "Starting .minions stack..."
echo ""

# Step 1: OmniRoute
log_info "Starting OmniRoute (${OMNIROUTE_HOST}:${OMNIROUTE_PORT})..."
start_service "omniroute" \
    "${MINIONS_HOME}/bin/omniroute" \
    --host "${OMNIROUTE_HOST}" \
    --port "${OMNIROUTE_PORT}" \
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

# Step 3: Wait for OmniRoute health (needed for preconfig)
log_info "Waiting for OmniRoute health..."
wait_for_health "${OMNIROUTE_BASE_URL}/models" 30 "omniroute"

# Step 4: OmniRoute preconfiguration
if [ "${DRY_RUN}" -eq 0 ]; then
    log_info "Preconfiguring OmniRoute..."
    # shellcheck disable=SC1091
    . "${LIB_DIR}/omniroute.sh"
    omniroute_preconfigure "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" >> "${boot_log}" 2>&1 || log_warn "OmniRoute preconfig had issues (non-fatal)"
fi

# Step 5: Readiness marker
touch "${MINIONS_HOME}/var/run/ready"

# Step 5b: Update Hermes config with actual ports
if [ "${DRY_RUN}" -eq 0 ] && [ "${INSTALL_HERMES:-1}" -eq 1 ]; then
    # Set HERMES_HOME so hermes_update_config finds the right config
    export HERMES_HOME="${MINIONS_HOME}/lib/hermes/home"
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/hermes.sh"
    hermes_update_config "${OMNIROUTE_PORT}" "${MODELRELAY_PORT}"
fi

# Step 5c: Update Pi config with actual ports
if [ "${DRY_RUN}" -eq 0 ]; then
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/pi.sh"
    pi_update_config "${OMNIROUTE_PORT}" "${MODELRELAY_PORT}"
    
    # Install pi-failover extension (needs config in place and proxies running)
    # Do this synchronously with output visible
    echo "[INFO] Installing pi-failover extension..."
    if "${MINIONS_HOME}/bin/pi" install git:github.com/gitricko/pi-failover@hermes-impl 2>&1; then
        echo "[INFO] pi-failover extension installed"
        # Reload extensions to register the provider
        "${MINIONS_HOME}/bin/pi" extensions reload 2>&1 || true
        echo "[INFO] Extensions reloaded"
    else
        echo "[WARN] pi-failover extension install failed (non-fatal)"
    fi
    
    # Verify extension is loaded
    echo "[INFO] Verifying pi-failover extension..."
    "${MINIONS_HOME}/bin/pi" extensions list 2>&1 | grep -i failover || echo "[WARN] pi-failover not in extensions list yet"
    "${MINIONS_HOME}/bin/pi" --list-models 2>&1 | grep -i omniroute || echo "[WARN] omniroute not in models list"
fi

# Step 6: Print READY message
echo ""
echo "=============================================="
echo "  .minions stack is UP"
echo ""
echo "  ✅ omniroute    ${OMNIROUTE_BASE_URL}"
echo "  ✅ modelrelay   ${MODELRELAY_BASE_URL}"
echo "  ✅ pi-agent     CLI ready (invoked on demand)"
echo "  ✅ hermes       CLI ready (preinstalled)"
echo "  ✅ mnemon       memory layer ready"
echo "=============================================="
echo ""
echo "READY FOR FIRSTMATE DISPATCH"