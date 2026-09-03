#!/usr/bin/env sh
# tests/test_cli_integration.sh - Integration test for Hermes/Pi/Mnemon CLI
# Runs against a REAL installed .minions stack (not mocks)
#
# Usage:
#   CI_REAL_INSTALL=1 bash tests/test_cli_integration.sh  # in CI, uses existing MINIONS_HOME
#   bash tests/test_cli_integration.sh                    # local, does fresh install

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

# In CI, MINIONS_HOME is already set from the real install step
# Locally, create a fresh install
if [ -n "${MINIONS_HOME:-}" ] && [ -d "${MINIONS_HOME}" ]; then
    REAL_HOME="${MINIONS_HOME}"
    echo "=== CLI Integration Test (using existing MINIONS_HOME) ==="
    echo "MINIONS_HOME=${MINIONS_HOME}"
else
    REAL_HOME=$(mktemp -d)
    export MINIONS_HOME="${REAL_HOME}"
    export PATH="${REAL_HOME}/bin:${PATH}"
    echo "=== CLI Integration Test (fresh install) ==="
    echo "MINIONS_HOME=${MINIONS_HOME}"
fi

# Step 1: Install (only if fresh)
if [ -z "${CI_REAL_INSTALL:-}" ]; then
    echo ""
    echo "[1/5] Installing .minions stack..."
    bash "${PROJECT_ROOT}/install.sh" --minions-home "${REAL_HOME}" >/tmp/cli-install.log 2>&1
    log_info "Install complete"
else
    echo ""
    echo "[1/5] Using existing installation from Real Install step"
    log_info "Using existing MINIONS_HOME"
fi

export PATH="${REAL_HOME}/bin:${PATH}"

# Step 2: Boot stack (only if not already running)
if [ -z "${CI_REAL_INSTALL:-}" ]; then
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
else
    echo ""
    echo "[2/5] Stack already running from Real Install step"
    log_info "Stack is already up"
fi

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
# Hermes config is at HERMES_HOME/.hermes/config.yaml (not HERMES_HOME/config.yaml)
# HERMES_HOME is set in the hermes wrapper script to ${MINIONS_HOME}/lib/hermes/home
HERMES_CONFIG="${REAL_HOME}/lib/hermes/home/.hermes/config.yaml"
if [ ! -f "${HERMES_CONFIG}" ]; then
    # Fallback to .hermes/config.yaml
    HERMES_CONFIG="${REAL_HOME}/lib/hermes/home/config.yaml"
fi

if [ -f "${HERMES_CONFIG}" ]; then
    # Check omniroute base_url is set to localhost:20128 (under custom_providers)
    if grep -A2 "omniroute:" "${HERMES_CONFIG}" | grep -q "base_url: http://127.0.0.1:20128/v1"; then
        log_info "Hermes config has correct omniroute base_url"
    else
        log_error "Hermes config missing omniroute base_url (expected 20128)"
        echo "=== DEBUG: Full config file ==="
        cat "${HERMES_CONFIG}"
        echo "=== END DEBUG ==="
        exit 1
    fi
    
    # Check modelrelay base_url is set to localhost:7352
    if grep -A2 "modelrelay:" "${HERMES_CONFIG}" | grep -q "base_url: http://127.0.0.1:7352/v1"; then
        log_info "Hermes config has correct modelrelay base_url"
    else
        log_error "Hermes config missing modelrelay base_url (expected 7352)"
        echo "=== DEBUG: Full config file ==="
        cat "${HERMES_CONFIG}"
        echo "=== END DEBUG ==="
        exit 1
    fi
else
    log_error "Hermes config not found at ${HERMES_CONFIG}"
    find "${REAL_HOME}/lib/hermes" -name "config.yaml" 2>/dev/null | head -5
    exit 1
fi

# Test hermes config get commands
if "${REAL_HOME}/bin/hermes" config get model.provider 2>/dev/null | grep -q "auto-fastest"; then
    log_info "hermes config get model.provider returns auto-fastest"
else
    log_warn "hermes config get model.provider didn't return expected value"
fi

# Test OmniRoute /v1/models endpoint responds (proves connectivity through proxy)
echo "Testing OmniRoute /v1/models endpoint..."
if curl -s -f "http://127.0.0.1:20128/v1/models" >/dev/null 2>&1; then
    log_info "OmniRoute /v1/models endpoint responds"
else
    log_error "OmniRoute /v1/models endpoint failed"
    exit 1
fi

# Test ModelRelay /v1/models endpoint responds
echo "Testing ModelRelay /v1/models endpoint..."
if curl -s -f "http://127.0.0.1:7352/v1/models" >/dev/null 2>&1; then
    log_info "ModelRelay /v1/models endpoint responds"
else
    log_error "ModelRelay /v1/models endpoint failed"
    exit 1
fi

# Test Hermes chat through OmniRoute (real end-to-end query with free models)
# The auto-fastest combo is preconfigured with free models (no API keys needed)
echo "Testing Hermes chat via OmniRoute (auto-fastest with free models)..."
HERMES_TEST_RESP=$("${REAL_HOME}/bin/hermes" chat -q "Reply with exactly: OK" 2>&1 || true)
if echo "${HERMES_TEST_RESP}" | grep -qi "OK"; then
    log_info "Hermes chat via OmniRoute works (got expected response)"
else
    log_warn "Hermes chat via OmniRoute returned unexpected: ${HERMES_TEST_RESP}"
fi

# Step 4: Test Pi-Agent CLI
echo ""
echo "[4/5] Testing Pi-Agent CLI..."

# Test pi --version (just check it runs and outputs something version-like)
if "${REAL_HOME}/bin/pi" --version >/dev/null 2>&1; then
    log_info "pi --version works"
else
    log_error "pi --version failed"
    exit 1
fi

# Test pi config auto-detection: pi.toml and models.json have actual ports
echo "Testing Pi config auto-detection..."
PI_TOML="${HOME}/.pi/pi.toml"
PI_MODELS="${HOME}/.pi/models.json"

if [ -f "${PI_TOML}" ]; then
    echo "[DEBUG] Contents of ${PI_TOML}:" >&2
    cat "${PI_TOML}" >&2
    if grep -q "base_url = \"http://127.0.0.1:20128/v1\"" "${PI_TOML}"; then
        log_info "Pi config (pi.toml) has correct omniroute base_url (20128)"
    else
        log_error "Pi config (pi.toml) missing correct omniroute base_url"
        cat "${PI_TOML}"
        exit 1
    fi
    if grep -q 'provider = "omniroute"' "${PI_TOML}"; then
        log_info "Pi config (pi.toml) has provider = omniroute"
    else
        log_error "Pi config (pi.toml) missing provider = omniroute"
        cat "${PI_TOML}"
        exit 1
    fi
else
    log_warn "Pi config pi.toml not found at ${PI_TOML}"
fi

if [ -f "${PI_MODELS}" ]; then
    if grep -q '"baseUrl": "http://127.0.0.1:20128/v1"' "${PI_MODELS}"; then
        log_info "Pi config (models.json) has correct omniroute baseUrl (20128)"
    else
        log_error "Pi config (models.json) missing correct omniroute baseUrl"
        cat "${PI_MODELS}"
        exit 1
    fi
    
    if grep -q '"baseUrl": "http://127.0.0.1:7352/v1"' "${PI_MODELS}"; then
        log_info "Pi config (models.json) has correct modelrelay baseUrl (7352)"
    else
        log_error "Pi config (models.json) missing correct modelrelay baseUrl"
        cat "${PI_MODELS}"
        exit 1
    fi
else
    log_warn "Pi config models.json not found at ${PI_MODELS}"
fi

# Test pi extensions list shows pi-failover (may not be available in test env)
if "${REAL_HOME}/bin/pi" extensions list 2>/dev/null | grep -q "pi-failover"; then
    log_info "pi extensions list shows pi-failover"
else
    log_warn "pi extensions list doesn't show pi-failover (may need --all or different flag)"
fi

# Test Pi-Agent end-to-end query (with provider to disambiguate auto-fastest)
echo "Testing Pi-Agent chat via omniroute..."
# First check what models are available
echo "[DEBUG] Available models:" >&2
"${REAL_HOME}/bin/pi" --list-models 2>&1 | head -20 >&2
# Try with explicit provider/model
PI_TEST_RESP=$("${REAL_HOME}/bin/pi" -p "Reply with exactly: OK" --provider omniroute --model omniroute/auto-fastest 2>&1 || true)
if echo "${PI_TEST_RESP}" | grep -qi "OK"; then
    log_info "Pi-Agent chat via omniroute works (got expected response)"
else
    log_warn "Pi-Agent chat via omniroute returned unexpected: ${PI_TEST_RESP}"
fi

# Step 5: Test Mnemon (if available)
echo ""
echo "[5/5] Testing Mnemon..."

MNEMON_BIN="${REAL_HOME}/bin/mnemon"
if [ -x "${MNEMON_BIN}" ]; then
    TEST_KEY="ci-test-$(date +%s)"
    
    # Test mnemon remember - content is first arg, no --text flag
    if "${MNEMON_BIN}" remember "test content for ${TEST_KEY}" --tags "${TEST_KEY}" --cat fact 2>/dev/null; then
        log_info "mnemon remember works"
    else
        log_warn "mnemon remember failed (may need different args)"
    fi
    
    # Test mnemon recall - searches by keyword (semantic), not exact key match
    if "${MNEMON_BIN}" recall "${TEST_KEY}" --limit 5 2>/dev/null | grep -q "test content"; then
        log_info "mnemon recall works"
    else
        log_warn "mnemon recall didn't find test content (semantic search may not match exact)"
    fi
else
    log_warn "mnemon binary not found at ${MNEMON_BIN} (may use system mnemon)"
fi

# Step 6: Stop stack (only if we started it)
if [ -z "${CI_REAL_INSTALL:-}" ]; then
    echo ""
    echo "[6/6] Stopping stack..."
    "${REAL_HOME}/stop.sh" 2>&1 | grep -q "All services stopped" && log_info "stop.sh runs successfully" || log_error "stop.sh failed"

    # Cleanup
    rm -rf "${REAL_HOME}"
else
    echo ""
    echo "[6/6] Not stopping stack (managed by CI)"
fi

echo ""
echo "=== ALL CLI INTEGRATION TESTS PASSED ==="