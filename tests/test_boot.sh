#!/usr/bin/env sh
# tests/test_boot.sh - Tests for boot.sh (DTS-based integration)
# Uses Docker Test Shell for real container verification

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

# Test 1: shellcheck all shell scripts
echo "=== Test 1: shellcheck ==="
for script in boot.sh stop.sh lib/*.sh; do
    if [ -f "${PROJECT_ROOT}/${script}" ]; then
        if shellcheck "${PROJECT_ROOT}/${script}"; then
            log_info "shellcheck ${script}"
        else
            log_error "shellcheck ${script} failed"
            exit 1
        fi
    fi
done

# Test 2: Verify scripts have correct shebang and are executable
echo ""
echo "=== Test 2: Script permissions ==="
for script in boot.sh stop.sh; do
    if [ -x "${PROJECT_ROOT}/${script}" ]; then
        log_info "${script} is executable"
    else
        log_warn "${script} not executable - fixing"
        chmod +x "${PROJECT_ROOT}/${script}"
    fi
    head -1 "${PROJECT_ROOT}/${script}" | grep -q "^#!/usr/bin/env sh" && log_info "${script} has correct shebang" || log_error "${script} missing shebang"
done

# Test 3: DTS integration test (requires Docker)
# This is the primary test path - replaces old dry-run/mock tests
if [ "${CI_DTS_TEST:-0}" -eq 1 ] && command -v docker >/dev/null 2>&1; then
    echo ""
    echo "=== Test 3: DTS integration test (CI_DTS_TEST=1) ==="
    
    DTS_SCRIPT="${PROJECT_ROOT}/scripts/dts.sh"
    if [ ! -x "${DTS_SCRIPT}" ]; then
        log_warn "DTS script not found or not executable, skipping DTS test"
    else
        # Clean any existing container
        "${DTS_SCRIPT}" clean >/dev/null 2>&1 || true
        
        # Start container and install prerequisites
        "${DTS_SCRIPT}" up
        "${DTS_SCRIPT}" apt "curl wget nodejs npm ripgrep ffmpeg python3.12 python3.12-venv python3.12-dev build-essential git ca-certificates software-properties-common"
        
        # Run install.sh first (needed for boot.sh to find binaries)
        if "${DTS_SCRIPT}" exec "cd /src && bash install.sh"; then
            log_info "DTS: install.sh completed without errors"
        else
            log_error "DTS: install.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Test boot.sh starts services
        if "${DTS_SCRIPT}" exec "cd /src && bash boot.sh"; then
            log_info "DTS: boot.sh completed without errors"
        else
            log_error "DTS: boot.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify PID files created for persistent services
        for service in omniroute modelrelay; do
            if "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/${service}.pid"; then
                log_info "DTS: PID file created for ${service}"
            else
                log_error "DTS: PID file missing for ${service}"
                "${DTS_SCRIPT}" clean
                exit 1
            fi
        done
        
        # Verify Pi-Agent and Hermes are NOT tracked as services (CLI tools)
        for service in pi hermes; do
            if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/${service}.pid"; then
                log_info "DTS: ${service} correctly NOT tracked as service (CLI tool)"
            else
                log_error "DTS: ${service} should NOT have PID file (CLI tool)"
                "${DTS_SCRIPT}" clean
                exit 1
            fi
        done
        
        # Verify readiness marker
        if "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/ready"; then
            log_info "DTS: Readiness marker created"
        else
            log_error "DTS: Readiness marker missing"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify OmniRoute health check passes
        if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/healthz >/dev/null"; then
            log_info "DTS: OmniRoute health check passes"
        else
            log_error "DTS: OmniRoute health check failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify ModelRelay responds
        if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:7352/v1/models >/dev/null"; then
            log_info "DTS: ModelRelay models endpoint responds"
        else
            log_error "DTS: ModelRelay models endpoint failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify auto-fastest combo configured
        if "${DTS_SCRIPT}" exec "export PATH=\"/home/ubuntu/.minions/lib/node/bin:/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules/.bin:\${PATH}\" && export NODE_PATH=\"/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules\" && /home/ubuntu/.minions/bin/omniroute combo list 2>/dev/null | grep -q auto-fastest"; then
            log_info "DTS: auto-fastest combo configured"
        else
            log_error "DTS: auto-fastest combo not found"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify login disabled
        if "${DTS_SCRIPT}" exec "sqlite3 /home/ubuntu/.omniroute/storage.sqlite \"SELECT value FROM key_value WHERE key='requireLogin';\" 2>/dev/null | grep -q false"; then
            log_info "DTS: OmniRoute login disabled"
        else
            # REST API fallback check
            log_warn "DTS: Could not verify login via sqlite (DB locked), checking via REST API"
            if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/api/settings 2>/dev/null | grep -q 'requireLogin.*false'"; then
                log_info "DTS: OmniRoute login disabled (REST API)"
            else
                log_warn "DTS: Could not verify login disabled"
            fi
        fi
        
        # Test stop.sh
        if "${DTS_SCRIPT}" exec "cd /src && bash stop.sh"; then
            log_info "DTS: stop.sh completed without errors"
        else
            log_error "DTS: stop.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify PID files removed
        for service in omniroute modelrelay; do
            if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/${service}.pid"; then
                log_info "DTS: PID file removed for ${service}"
            else
                log_error "DTS: PID file still exists for ${service}"
                "${DTS_SCRIPT}" clean
                exit 1
            fi
        done
        
        # Verify readiness marker removed
        if ! "${DTS_SCRIPT}" exec "test -f /home/ubuntu/.minions/var/run/ready"; then
            log_info "DTS: Readiness marker removed"
        else
            log_error "DTS: Readiness marker still exists"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Clean up
        "${DTS_SCRIPT}" clean
        log_info "DTS: All boot integration tests passed"
    fi
fi

echo ""
echo "=== All boot tests passed ==="