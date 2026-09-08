#!/usr/bin/env sh
# tests/test_dts.sh - Docker Test Shell integration test
# Runs the full .minions stack in a clean container and verifies end-to-end functionality
#
# Usage:
#   CI_DTS_TEST=1 bash tests/test_dts.sh
#   bash tests/test_dts.sh  # local run (requires docker)

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

# Clean any existing container
"${DTS_SCRIPT}" clean >/dev/null 2>&1 || true

# Start container
"${DTS_SCRIPT}" up
log_info "DTS container started"

# Install system prerequisites
"${DTS_SCRIPT}" apt "curl wget nodejs npm ripgrep ffmpeg python3.12 python3.12-venv python3.12-dev build-essential git ca-certificates software-properties-common sqlite3"
log_info "System prerequisites installed"

# Test 1: install.sh
echo ""
echo "=== Test 1: install.sh ==="
if "${DTS_SCRIPT}" exec "cd /src && bash install.sh --no-hermes"; then
    log_info "install.sh completed without errors"
else
    log_error "install.sh failed"
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Verify install outputs
"${DTS_SCRIPT}" exec "test -d /home/ubuntu/.minions && test -f /home/ubuntu/.minions/bin/omniroute && test -f /home/ubuntu/.minions/bin/modelrelay && test -f /home/ubuntu/.minions/bin/pi"
log_info "Binaries installed correctly"

"${DTS_SCRIPT}" exec "test -f /home/ubuntu/.pi/agent/pi.toml && test -f /home/ubuntu/.pi/agent/models.json && test -f /home/ubuntu/.hermes/config.yaml"
log_info "Config templates copied to standard locations"

# Test 2: boot.sh
echo ""
echo "=== Test 2: boot.sh ==="
if "${DTS_SCRIPT}" exec "cd /src && bash boot.sh"; then
    log_info "boot.sh completed without errors"
else
    log_error "boot.sh failed"
    "${DTS_SCRIPT}" clean
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
    "${DTS_SCRIPT}" clean
    exit 1
fi

# ModelRelay
if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:7352/v1/models >/dev/null"; then
    log_info "ModelRelay models endpoint responds"
else
    log_error "ModelRelay models endpoint failed"
    "${DTS_SCRIPT}" clean
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
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Verify login disabled via REST API (sqlite fails when server has DB locked)
if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/api/settings 2>/dev/null | grep -q 'requireLogin.*false'"; then
    log_info "OmniRoute login disabled (REST API)"
else
    log_warn "Could not verify login disabled via REST API"
fi

# Test 5: Chat completion end-to-end
echo ""
echo "=== Test 5: End-to-end chat completion ==="
if "${DTS_SCRIPT}" exec "curl -sf -X POST http://127.0.0.1:20128/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"auto-fastest\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":10}' >/dev/null"; then
    log_info "Chat completion via auto-fastest works"
else
    log_error "Chat completion failed"
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Test 6: Hermes CLI
echo ""
echo "=== Test 6: Hermes CLI ==="
if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/hermes --version >/dev/null 2>&1"; then
    log_info "hermes --version works"
else
    log_error "hermes --version failed"
    "${DTS_SCRIPT}" clean
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'omniroute_port: 20128' /home/ubuntu/.hermes/config.yaml && grep -q 'modelrelay_port: 7352' /home/ubuntu/.hermes/config.yaml"; then
    log_info "Hermes config has correct ports"
else
    log_error "Hermes config missing correct ports"
    "${DTS_SCRIPT}" exec "cat /home/ubuntu/.hermes/config.yaml"
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Test 7: Pi-Agent CLI
echo ""
echo "=== Test 7: Pi-Agent CLI ==="
if "${DTS_SCRIPT}" exec "/home/ubuntu/.minions/bin/pi --version >/dev/null 2>&1"; then
    log_info "pi --version works"
else
    log_error "pi --version failed"
    "${DTS_SCRIPT}" clean
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q 'base_url = \"http://127.0.0.1:20128/v1\"' /home/ubuntu/.pi/agent/pi.toml"; then
    log_info "Pi pi.toml has correct omniroute base_url (20128)"
else
    log_error "Pi pi.toml missing correct omniroute base_url"
    "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/pi.toml"
    "${DTS_SCRIPT}" clean
    exit 1
fi

if "${DTS_SCRIPT}" exec "grep -q '\"baseUrl\": \"http://127.0.0.1:20128/v1\"' /home/ubuntu/.pi/agent/models.json && grep -q '\"baseUrl\": \"http://127.0.0.1:7352/v1\"' /home/ubuntu/.pi/agent/models.json"; then
    log_info "Pi models.json has correct baseUrls"
else
    log_error "Pi models.json missing correct baseUrls"
    "${DTS_SCRIPT}" exec "cat /home/ubuntu/.pi/agent/models.json"
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Test 8: stop.sh
echo ""
echo "=== Test 8: stop.sh ==="
if "${DTS_SCRIPT}" exec "cd /src && bash stop.sh"; then
    log_info "stop.sh completed without errors"
else
    log_error "stop.sh failed"
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Verify services stopped (PID files removed)
for service in omniroute modelrelay; do
    if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/${service}.pid"; then
        log_info "${service} PID file removed"
    else
        log_error "${service} PID file still exists"
        "${DTS_SCRIPT}" clean
        exit 1
    fi
done

# Verify readiness marker removed
if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/ready"; then
    log_info "Readiness marker removed"
else
    log_error "Readiness marker still exists"
    "${DTS_SCRIPT}" clean
    exit 1
fi

# Clean up
"${DTS_SCRIPT}" clean
log_info "DTS container cleaned up"

echo ""
echo "=== ALL DTS INTEGRATION TESTS PASSED ==="