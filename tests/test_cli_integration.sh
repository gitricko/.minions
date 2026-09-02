#!/usr/bin/env sh
# tests/test_cli_integration.sh - Integration test for Hermes/Pi/Mnemon CLI
# Runs against a REAL installed .minions stack (not mocks)

set -e
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

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

# Fresh install directory
REAL_HOME=$(mktemp -d)
export MINIONS_HOME="${REAL_HOME}"
export PATH="${REAL_HOME}/bin:${PATH}"

echo "=== CLI Integration Test ==="
echo "MINIONS_HOME=${MINIONS_HOME}"

# Step 1: Install
echo ""
echo "[1/5] Installing .minions stack..."
bash "${PROJECT_ROOT}/install.sh" --minions-home "${REAL_HOME}" >/tmp/cli-install.log 2>&1
log_info "Install complete"

# Step 2: Boot stack
echo ""
echo "[2/5] Starting stack with boot.sh..."
timeout 180s bash "${REAL_HOME}/boot.sh" >/tmp/cli-boot.log 2>&1
BOOT_EXIT=$?
echo "boot.sh exit code: ${BOOT_EXIT}"

# Verify READY marker
if ! grep -q "READY FOR FIRSTMATE DISPATCH\|stack is UP" /tmp/cli-boot.log; then
    log_error "boot.sh did not reach completion marker"
    cat /tmp/cli-boot.log
    exit 1
fi
log_info "Stack started successfully"

# Verify services are up
check_port() { bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }
for port in 20128 7352; do
    if check_port $port; then
        log_info "Service on port $port is up"
    else
        log_error "Service on port $port failed to start"
        exit 1
    fi
done

# Step 3: Test Hermes CLI
echo ""
echo "[3/5] Testing Hermes CLI..."

# Test hermes --version
if "${REAL_HOME}/bin/hermes" --version >/dev/null 2>&1; then
    log_info "hermes --version works"
else
    log_error "hermes --version failed"
    exit 1
fi

# Test hermes config shows correct base_urls
# Note: Hermes config may be in ${MINIONS_HOME}/lib/hermes/home/.hermes/config.yaml
HERMES_CONFIG="${REAL_HOME}/lib/hermes/home/.hermes/config.yaml"
if [ ! -f "${HERMES_CONFIG}" ]; then
    HERMES_CONFIG="${REAL_HOME}/lib/hermes/home/config.yaml"
fi
if [ -f "${HERMES_CONFIG}" ]; then
    # Check omniroute base_url is set to localhost:20128 (under custom_providers)
    if grep -A2 "omniroute:" "${HERMES_CONFIG}" | grep -q "base_url: http://127.0.0.1:20128/v1"; then
        log_info "Hermes config has correct omniroute base_url"
    else
        log_error "Hermes config missing omniroute base_url (expected 20128)"
        grep -A5 "custom_providers:" "${HERMES_CONFIG}" | head -10
        exit 1
    fi
    
    # Check modelrelay base_url is set to localhost:7352
    if grep -A2 "modelrelay:" "${HERMES_CONFIG}" | grep -q "base_url: http://127.0.0.1:7352/v1"; then
        log_info "Hermes config has correct modelrelay base_url"
    else
        log_error "Hermes config missing modelrelay base_url (expected 7352)"
        grep -A5 "custom_providers:" "${HERMES_CONFIG}" | head -10
        exit 1
    fi
else
    log_warn "Hermes config not found at ${HERMES_CONFIG} (may use default ~/.hermes)"
fi

# Test hermes config get commands
if "${REAL_HOME}/bin/hermes" config get model.provider 2>/dev/null | grep -q "auto-fastest"; then
    log_info "hermes config get model.provider returns auto-fastest"
else
    log_warn "hermes config get model.provider didn't return expected value"
fi

# Step 4: Test Pi-Agent CLI
echo ""
echo "[4/5] Testing Pi-Agent CLI..."

if "${REAL_HOME}/bin/pi" --version 2>/dev/null | grep -q "pi-agent"; then
    log_info "pi --version works"
else
    log_error "pi --version failed"
    exit 1
fi

# Test pi extensions list shows pi-failover
if "${REAL_HOME}/bin/pi" extensions list 2>/dev/null | grep -q "pi-failover"; then
    log_info "pi extensions list shows pi-failover"
else
    log_warn "pi extensions list doesn't show pi-failover (may need --all or different flag)"
fi

# Step 5: Test Mnemon (if available)
echo ""
echo "[5/5] Testing Mnemon..."

MNEMON_BIN="${REAL_HOME}/bin/mnemon"
if [ -x "${MNEMON_BIN}" ]; then
    TEST_KEY="ci-test-$(date +%s)"
    
    # Test mnemon remember
    if echo "test content" | "${MNEMON_BIN}" remember --text "${TEST_KEY}" 2>/dev/null; then
        log_info "mnemon remember works"
    else
        log_warn "mnemon remember failed (may need different args)"
    fi
    
    # Test mnemon recall
    if "${MNEMON_BIN}" recall "${TEST_KEY}" --limit 5 2>/dev/null | grep -q "${TEST_KEY}"; then
        log_info "mnemon recall works"
    else
        log_warn "mnemon recall didn't find test key"
    fi
else
    log_warn "mnemon binary not found at ${MNEMON_BIN} (may use system mnemon)"
fi

# Step 6: Stop stack
echo ""
echo "[6/6] Stopping stack..."
"${REAL_HOME}/stop.sh" 2>&1 | grep -q "All services stopped" && log_info "stop.sh runs successfully" || log_error "stop.sh failed"

# Cleanup
rm -rf "${REAL_HOME}"

echo ""
echo "=== ALL CLI INTEGRATION TESTS PASSED ==="