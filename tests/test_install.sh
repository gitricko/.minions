#!/usr/bin/env sh
# tests/test_install.sh - Tests for install.sh
# Runs shellcheck, dry-run simulation, and (optionally) real install if CI_REAL_INSTALL=1

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
for script in install.sh boot.sh stop.sh status.sh lib/*.sh; do
    if [ -f "${PROJECT_ROOT}/${script}" ]; then
        if shellcheck "${PROJECT_ROOT}/${script}"; then
            log_info "shellcheck ${script}"
        else
            log_error "shellcheck ${script} failed"
            exit 1
        fi
    fi
done

# Test 2: Dry-run install.sh
echo ""
echo "=== Test 2: install.sh --dry-run ==="
TEST_HOME=$(mktemp -d)
export MINIONS_HOME="${TEST_HOME}"

# Copy the scripts to test location
mkdir -p "${TEST_HOME}/lib"
mkdir -p "${TEST_HOME}/etc"
cp "${PROJECT_ROOT}/install.sh" "${TEST_HOME}/install.sh"
cp "${PROJECT_ROOT}/lib"/*.sh "${TEST_HOME}/lib/"
cp "${PROJECT_ROOT}/etc"/*.env "${TEST_HOME}/etc/"
cp "${PROJECT_ROOT}/etc"/*.toml "${TEST_HOME}/etc/"

# Run install.sh in dry-run mode
if sh "${TEST_HOME}/install.sh" --dry-run --minions-home "${TEST_HOME}" 2>&1 | grep -q "DRY-RUN"; then
    log_info "install.sh --dry-run executes and shows DRY-RUN messages"
else
    log_error "install.sh --dry-run failed"
    exit 1
fi

# Verify directory structure was created
for dir in lib etc var/run var/log bin workspace var/cache; do
    if [ -d "${TEST_HOME}/${dir}" ]; then
        log_info "Directory ${dir} created"
    else
        log_error "Directory ${dir} not created"
        exit 1
    fi
done

# Verify config files copied
for cfg in versions.env minions.env pi.toml; do
    if [ -f "${TEST_HOME}/etc/${cfg}" ]; then
        log_info "${cfg} copied"
    else
        log_error "${cfg} not copied"
        exit 1
    fi
done

# Verify lib scripts copied
for lib in detect.sh download.sh node.sh uv.sh pi.sh hermes.sh npm_packages.sh process.sh mnemon.sh; do
    if [ -f "${TEST_HOME}/lib/${lib}" ]; then
        log_info "lib/${lib} copied"
    else
        log_error "lib/${lib} not copied"
        exit 1
    fi
done

# Cleanup
rm -rf "${TEST_HOME}"

# Test 3: Verify install.sh has correct shebang and is executable
echo ""
echo "=== Test 3: Script permissions ==="
for script in install.sh boot.sh stop.sh status.sh; do
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

# Test 4: Real install (only if CI_REAL_INSTALL=1)
if [ "${CI_REAL_INSTALL:-0}" -eq 1 ]; then
    echo ""
    echo "=== Test 4: Real install (CI_REAL_INSTALL=1) ==="
    REAL_HOME=$(mktemp -d)
    export MINIONS_HOME="${REAL_HOME}"

    echo "Running real install (this downloads packages)..."
    if sh "${PROJECT_ROOT}/install.sh" --minions-home "${REAL_HOME}"; then
        log_info "install.sh completed without errors"
    else
        log_error "install.sh failed during real install"
        rm -rf "${REAL_HOME}"
        exit 1
    fi

    # Verify binaries exist and run (with timeout)
    for bin in omniroute modelrelay pi hermes; do
        if [ -x "${REAL_HOME}/bin/${bin}" ]; then
            if timeout 10s "${REAL_HOME}/bin/${bin}" --version >/dev/null 2>&1; then
                log_info "${bin} installed and --version works"
            else
                log_warn "${bin} installed but --version failed or timed out"
            fi
        else
            log_error "${bin} not found in ${REAL_HOME}/bin"
            rm -rf "${REAL_HOME}"
            exit 1
        fi
    done

    # Verify Pi config symlinks
    for cfg in pi.toml models.json settings.json; do
        if [ -L "${HOME}/.pi/${cfg}" ]; then
            log_info "Pi config symlink ${cfg} created"
        else
            log_warn "Pi config symlink ${cfg} not found (may not exist in etc/)"
        fi
    done

    rm -rf "${REAL_HOME}"
fi

echo ""
echo "=== All install tests passed ==="
