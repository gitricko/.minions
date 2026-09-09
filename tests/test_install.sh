#!/usr/bin/env sh
# tests/test_install.sh - Tests for install.sh
# Runs shellcheck and DTS-based integration test

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
log_error() { echo "${RED}[FAIL]${NC} $*" >&2; }
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }

# Test 1: shellcheck all shell scripts
echo "=== Test 1: shellcheck ==="
for script in install.sh boot.sh stop.sh lib/*.sh; do
    if [ -f "${PROJECT_ROOT}/${script}" ]; then
        if shellcheck "${PROJECT_ROOT}/${script}"; then
            log_info "shellcheck ${script}"
        else
            log_error "shellcheck ${script} failed"
            exit 1
        fi
    fi
done

# Test 2: Verify install.sh has correct shebang and is executable
echo ""
echo "=== Test 2: Script permissions ==="
for script in install.sh boot.sh stop.sh; do
    if [ -x "${PROJECT_ROOT}/${script}" ]; then
        log_info "${script} is executable"
    else
        log_warn "${script} not executable - fixing"
        chmod +x "${PROJECT_ROOT}/${script}"
    fi
    head -1 "${PROJECT_ROOT}/${script}" | grep -q "^#!/usr/bin/env sh" && log_info "${script} has correct shebang" || log_error "${script} missing shebang"
done

for lib in lib/*.sh; do
    if [ -f "${PROJECT_ROOT}/${lib}" ]; then
        head -1 "${PROJECT_ROOT}/${lib}" | grep -q "^#!/usr/bin/env sh" && log_info "${lib} has correct shebang" || log_error "${lib} missing shebang"
    fi
done

# Test 3: DTS integration test (requires Docker)
# This is the primary test path now - replaces old dry-run
if [ "${CI_DTS_TEST:-0}" -eq 1 ] && command -v docker >/dev/null 2>&1; then
    echo ""
    echo "=== Test 3: DTS integration test (CI_DTS_TEST=1) ==="
    
    # Use the dts.sh script from repo
    DTS_SCRIPT="${PROJECT_ROOT}/scripts/dts.sh"
    if [ ! -x "${DTS_SCRIPT}" ]; then
        log_warn "DTS script not found or not executable, skipping DTS test"
    else
        # Clean any existing container
        "${DTS_SCRIPT}" clean >/dev/null 2>&1 || true
        
        # Start container and install prerequisites
        "${DTS_SCRIPT}" up
        "${DTS_SCRIPT}" apt "curl wget nodejs npm ripgrep ffmpeg python3.12 python3.12-venv python3.12-dev build-essential git ca-certificates software-properties-common"
        
        # Run install.sh
        if "${DTS_SCRIPT}" exec "cd /src && bash install.sh --no-hermes"; then
            log_info "DTS: install.sh completed without errors"
        else
            log_error "DTS: install.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Run boot.sh
        if "${DTS_SCRIPT}" exec "cd /src && bash boot.sh"; then
            log_info "DTS: boot.sh completed without errors"
        else
            log_error "DTS: boot.sh failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify OmniRoute API responds
        if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:20128/healthz >/dev/null"; then
            log_info "DTS: OmniRoute health check passes"
        else
            log_error "DTS: OmniRoute health check failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify ModelRelay API responds
        if "${DTS_SCRIPT}" exec "curl -sf http://127.0.0.1:7352/v1/models >/dev/null"; then
            log_info "DTS: ModelRelay models endpoint responds"
        else
            log_error "DTS: ModelRelay models endpoint failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify auto-fastest combo works
        if "${DTS_SCRIPT}" exec "export PATH=\"/home/ubuntu/.minions/lib/node/bin:/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules/.bin:\${PATH}\" && export NODE_PATH=\"/home/ubuntu/.minions/lib/omniroute/npm/lib/node_modules\" && /home/ubuntu/.minions/bin/omniroute combo list 2>/dev/null | grep -q auto-fastest"; then
            log_info "DTS: auto-fastest combo configured"
        else
            log_error "DTS: auto-fastest combo not found"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Verify chat completion works
        if "${DTS_SCRIPT}" exec "curl -sf -X POST http://127.0.0.1:20128/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"auto-fastest\",\"messages\":[{\"role\":\"user\",\"content\":\"test\"}],\"max_tokens\":5}' >/dev/null"; then
            log_info "DTS: Chat completion via auto-fastest works"
        else
            log_error "DTS: Chat completion failed"
            "${DTS_SCRIPT}" clean
            exit 1
        fi
        
        # Clean up
        "${DTS_SCRIPT}" clean
        log_info "DTS: All integration tests passed"
    fi
fi

# Test 4: Real install (only if CI_REAL_INSTALL=1) - kept for backward compat
if [ "${CI_REAL_INSTALL:-0}" -eq 1 ]; then
    echo ""
    echo "=== Test 4: Real install (CI_REAL_INSTALL=1) ==="

    echo "Running real install (this downloads packages)..."
    if sh "${PROJECT_ROOT}/install.sh"; then
        log_info "install.sh completed without errors"
    else
        log_error "install.sh failed during real install"
        exit 1
    fi

    # Verify binaries exist in fixed install location
    for bin in omniroute modelrelay pi; do
        if [ -x "${HOME}/.minions/bin/${bin}" ]; then
            log_info "${bin} installed"
        else
            log_error "${bin} not found in ${HOME}/.minions/bin"
            exit 1
        fi
    done

    # Verify config templates copied to standard locations
    for cfg in pi.toml models.json; do
        if [ -f "${HOME}/.pi/agent/${cfg}" ]; then
            log_info "Pi config ${cfg} created at ~/.pi/agent/"
        else
            log_warn "Pi config ${cfg} not found at ~/.pi/agent/"
        fi
    done
    
    if [ -f "${HOME}/.hermes/config.yaml" ]; then
        log_info "Hermes config created at ~/.hermes/config.yaml"
    else
        log_warn "Hermes config not found at ~/.hermes/config.yaml"
    fi
fi

echo ""
echo "=== All install tests passed ==="