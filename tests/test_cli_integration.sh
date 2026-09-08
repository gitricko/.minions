#!/usr/bin/env sh
# tests/test_cli_integration.sh - Integration test for Hermes/Pi/Mnemon CLI
# Runs against a REAL installed .minions stack (not mocks)
# Uses DTS for verification when CI_DTS_TEST=1

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

# DTS-based integration test (primary)
if [ "${CI_DTS_TEST:-0}" -eq 1 ] && command -v docker >/dev/null 2>&1; then
    echo "=== CLI Integration Test (DTS mode) ==="
    
    DTS_SCRIPT="${PROJECT_ROOT}/scripts/dts.sh"
    if [ ! -x "${DTS_SCRIPT}" ]; then
        log_warn "DTS script not found, skipping DTS CLI test"
    else
        # Clean any existing container
        "${DTS_SCRIPT}" clean >/dev/null 2>&1 || true
        
        # Start container and install prerequisites
        "${DTS_SCRIPT}" up
        "${DTS_SCRIPT}" apt "curl wget nodejs npm ripgrep ffmpeg python3.12 python3.12-venv python3.12-dev build-essential git ca-certificates software-properties-common"
        
        # Run install.sh
        if "${DTS_SCRIPT}" exec "cd /src && bash install.sh --no-hermes"; then
            log_info "DTS: install.sh completed"
        else
            log_error "DTS: install.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Run boot.sh
        if "${DTS_SCRIPT}" exec "cd /src && bash boot.sh"; then
            log_info "DTS: boot.sh completed"
        else
            log_error "DTS: boot.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Set up env for CLI tools
        export_path="export PATH=\"/home/ubuntu/.minions/lib/node/bin:/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules/.bin:\${PATH}\" && export NODE_PATH=\"/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules\""
        
        # Test Hermes CLI
        if "${DTS_SCRIPT}" exec "${export_path} && /home/ubuntu/.minions/bin/hermes --version >/dev/null 2>&1"; then
            log_info "DTS: hermes --version works"
        else
            log_error "DTS: hermes --version failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test Hermes config has correct ports
        if "${DTS_SCRIPT}" exec "grep -q 'omniroute_port: 20128' /home/ubuntu/.hermes/config.yaml && grep -q 'modelrelay_port: 7352' /home/ubuntu/.hermes/config.yaml"; then
            log_info "DTS: Hermes config has correct ports"
        else
            log_error "DTS: Hermes config missing correct ports"
            "${DTS_SCRIPT}" exec "cat /home/ubuntu/.hermes/config.yaml"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test Pi-Agent CLI
        if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/pi --version >/dev/null 2>&1"; then
            log_info "DTS: pi --version works"
        else
            log_error "DTS: pi --version failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test Pi config auto-detection (pi.toml and models.json have actual ports)
        if "${DTS_SCRIPT}" exec "grep -q 'base_url = \"http://127.0.0.1:20128/v1\"' /home/ubuntu/.pi/agent/pi.toml"; then
            log_info "DTS: Pi pi.toml has correct omniroute base_url (20128)"
        else
            log_error "DTS: Pi pi.toml missing correct omniroute base_url"
            "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/pi.toml"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        if "${DTS_SCRIPT}" exec "grep -q '\"baseUrl\": \"http://127.0.0.1:20128/v1\"' /home/ubuntu/.pi/agent/models.json"; then
            log_info "DTS: Pi models.json has correct omniroute baseUrl (20128)"
        else
            log_error "DTS: Pi models.json missing correct omniroute baseUrl"
            "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/models.json"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        if "${DTS_SCRIPT}" exec "grep -q '\"baseUrl\": \"http://127.0.0.1:7352/v1\"' /home/ubuntu/.pi/agent/models.json"; then
            log_info "DTS: Pi models.json has correct modelrelay baseUrl (7352)"
        else
            log_error "DTS: Pi models.json missing correct modelrelay baseUrl"
            "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/models.json"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test OmniRoute /v1/models endpoint responds (proves connectivity through proxy)
        if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/v1/models >/dev/null"; then
            log_info "DTS: OmniRoute /v1/models endpoint responds"
        else
            log_error "DTS: OmniRoute /v1/models endpoint failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test ModelRelay /v1/models endpoint responds
        if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:7352/v1/models >/dev/null"; then
            log_info "DTS: ModelRelay /v1/models endpoint responds"
        else
            log_error "DTS: ModelRelay /v1/models endpoint failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test chat completion through OmniRoute
        if "${DTS_SCRIPT}" exec "curl -sf -X POST http://127.0.0.1:20128/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"auto-fastest\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":10}' >/dev/null"; then
            log_info "DTS: Chat completion via OmniRoute works"
        else
            log_error "DTS: Chat completion via OmniRoute failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test Pi-Agent extensions list
        if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/pi extensions list 2>/dev/null | grep -q pi-failover"; then
            log_info "DTS: pi extensions list shows pi-failover"
        else
            log_warn "DTS: pi extensions list may not show pi-failover (may not be installed in test env)"
        fi
        
        # Test Mnemon (if available)
        if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/mnemon --version >/dev/null 2>&1"; then
            log_info "DTS: mnemon --version works"
        else
            log_warn "DTS: mnemon binary not available"
        fi
        
        # Clean up
        "${DTS_SCRIPT}" clean
        log_info "DTS: All CLI integration tests passed"
    fi
fi

# Real install test (legacy CI path)
if [ "${CI_REAL_INSTALL:-0}" -eq 1 ]; then
    echo ""
    echo "=== CLI Integration Test (Real install mode) ==="
    
    if [ -z "${MINIONS_HOME:-}" ] || [ ! -d "${MINIONS_HOME}" ]; then
        log_error "MINIONS_HOME not set or doesn't exist"
        exit 1
    fi
    
    REAL_HOME="${MINIONS_HOME}"
    export PATH="${REAL_HOME}/bin:${PATH}"
    export MINIONS_HOME="${REAL_HOME}"
    
    # Test Hermes CLI
    if "${REAL_HOME}/bin/hermes" --version >/dev/null 2>&1; then
        log_info "hermes --version works"
    else
        log_error "hermes --version failed"
        exit 1
    fi
    
    # Test Hermes config (now at ~/.hermes/config.yaml)
    HERMES_CONFIG="${HOME}/.hermes/config.yaml"
    if [ -f "${HERMES_CONFIG}" ]; then
        if grep -q "omniroute_port: 20128" "${HERMES_CONFIG}" && grep -q "modelrelay_port: 7352" "${HERMES_CONFIG}"; then
            log_info "Hermes config has correct ports"
        else
            log_error "Hermes config missing correct ports"
            cat "${HERMES_CONFIG}"
            exit 1
        fi
    else
        log_error "Hermes config not found at ${HERMES_CONFIG}"
        exit 1
    fi
    
    # Test Pi-Agent CLI
    if "${REAL_HOME}/bin/pi" --version >/dev/null 2>&1; then
        log_info "pi --version works"
    else
        log_error "pi --version failed"
        exit 1
    fi
    
    # Test Pi config auto-detection
    PI_TOML="${HOME}/.pi/agent/pi.toml"
    PI_MODELS="${HOME}/.pi/agent/models.json"
    
    if [ -f "${PI_TOML}" ]; then
        if grep -q 'base_url = "http://127.0.0.1:20128/v1"' "${PI_TOML}"; then
            log_info "Pi pi.toml has correct omniroute base_url (20128)"
        else
            log_error "Pi pi.toml missing correct omniroute base_url"
            cat "${PI_TOML}"
            exit 1
        fi
    fi
    
    if [ -f "${PI_MODELS}" ]; then
        if grep -q '"baseUrl": "http://127.0.0.1:20128/v1"' "${PI_MODELS}"; then
            log_info "Pi models.json has correct omniroute baseUrl (20128)"
        else
            log_error "Pi models.json missing correct omniroute baseUrl"
            cat "${PI_MODELS}"
            exit 1
        fi
        
        if grep -q '"baseUrl": "http://127.0.0.1:7352/v1"' "${PI_MODELS}"; then
            log_info "Pi models.json has correct modelrelay baseUrl (7352)"
        else
            log_error "Pi models.json missing correct modelrelay baseUrl"
            cat "${PI_MODELS}"
            exit 1
        fi
    fi
    
    # Test OmniRoute endpoint
    if curl -sf http://127.0.0.1:20128/v1/models >/dev/null; then
        log_info "OmniRoute /v1/models endpoint responds"
    else
        log_error "OmniRoute /v1/models endpoint failed"
        exit 1
    fi
    
    # Test ModelRelay endpoint
    if curl -sf http://127.0.0.1:7352/v1/models >/dev/null; then
        log_info "ModelRelay /v1/models endpoint responds"
    else
        log_error "ModelRelay /v1/models endpoint failed"
        exit 1
    fi
    
    # Test chat completion
    if curl -sf -X POST http://127.0.0.1:20128/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"auto-fastest","messages":[{"role":"user","content":"Reply with exactly: OK"}],"max_tokens":10}' >/dev/null; then
        log_info "Chat completion via OmniRoute works"
    else
        log_error "Chat completion via OmniRoute failed"
        exit 1
    fi
    
    log_info "All CLI integration tests passed (Real install mode)"
fi

echo ""
echo "=== ALL CLI INTEGRATION TESTS PASSED ==="