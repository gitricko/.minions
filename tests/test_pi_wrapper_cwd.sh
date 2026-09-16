#!/usr/bin/env sh
# tests/test_pi_wrapper_cwd.sh - Tests for pi wrapper working directory
# Issue #38: pi always launches in the wrong working directory
#
# Verifies:
# - Wrapper respects $PWD by default (launch dir becomes session cwd)
# - PI_CWD env var overrides the launch directory
# - Wrapper doesn't break pi binary execution (PATH/NODE_PATH correct)
# - Symlink from bin/pi to lib/pi/pi is intact

set -e
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
MINIONS_HOME="${HOME}/.minions"

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

PASS_COUNT=0
FAIL_COUNT=0

log_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "${GREEN}[PASS]${NC} $*"; }
log_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "${RED}[FAIL]${NC} $*" >&2; }
log_skip() { echo "${YELLOW}[SKIP]${NC} $*"; }

# Helper: extract wrapper logic without exec (replace exec line with pwd)
extract_wrapper_logic() {
    local wrapper="$1"
    local outfile="$2"
    sed 's|^exec .*|pwd|' "${wrapper}" > "${outfile}"
    chmod +x "${outfile}"
}

# ============================================================
# Test 1: Wrapper exists and is syntactically valid
# ============================================================
echo "=== Test 1: Wrapper script exists ==="
WRAPPER="${MINIONS_HOME}/lib/pi/pi"
if [ -f "${WRAPPER}" ]; then
    log_pass "Wrapper script exists at ${WRAPPER}"
else
    log_fail "Wrapper script not found at ${WRAPPER}"
    echo "=== Tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="
    exit 1
fi

# ============================================================
# Test 2: Wrapper respects $PWD (launch directory) by default
# ============================================================
echo ""
echo "=== Test 2: Wrapper respects \$PWD ==="

# Create test directories with marker files
TEST_DIR_A="/tmp/test-pi-cwd-$$/project-a"
TEST_DIR_B="/tmp/test-pi-cwd-$$/project-b"
mkdir -p "${TEST_DIR_A}" "${TEST_DIR_B}"
echo "marker-a" > "${TEST_DIR_A}/marker.txt"
echo "marker-b" > "${TEST_DIR_B}/marker.txt"

# Extract wrapper logic (replace exec with pwd)
extract_wrapper_logic "${WRAPPER}" /tmp/test-wrapper-logic-$$

# Launch from directory A - should resolve to A
RESULT_A=$(cd "${TEST_DIR_A}" && sh /tmp/test-wrapper-logic-$$)
if [ "${RESULT_A}" = "${TEST_DIR_A}" ]; then
    log_pass "Wrapper from dir-A resolves to dir-A (got: ${RESULT_A})"
else
    log_fail "Wrapper from dir-A should resolve to ${TEST_DIR_A}, got: ${RESULT_A}"
fi

# Launch from directory B - should resolve to B
RESULT_B=$(cd "${TEST_DIR_B}" && sh /tmp/test-wrapper-logic-$$)
if [ "${RESULT_B}" = "${TEST_DIR_B}" ]; then
    log_pass "Wrapper from dir-B resolves to dir-B (got: ${RESULT_B})"
else
    log_fail "Wrapper from dir-B should resolve to ${TEST_DIR_B}, got: ${RESULT_B}"
fi

# Verify it does NOT resolve to hardcoded npm dir
HARDCODED="${MINIONS_HOME}/lib/pi/npm"
if [ "${RESULT_A}" != "${HARDCODED}" ] && [ "${RESULT_B}" != "${HARDCODED}" ]; then
    log_pass "Wrapper does not use hardcoded npm path: ${HARDCODED}"
else
    log_fail "Wrapper incorrectly resolves to hardcoded path: ${HARDCODED}"
fi

# ============================================================
# Test 3: PI_CWD override works
# ============================================================
echo ""
echo "=== Test 3: PI_CWD override ==="

# Launch from dir-A but override with PI_CWD=dir-B
RESULT_OVERRIDE=$(cd "${TEST_DIR_A}" && PI_CWD="${TEST_DIR_B}" sh /tmp/test-wrapper-logic-$$)
if [ "${RESULT_OVERRIDE}" = "${TEST_DIR_B}" ]; then
    log_pass "PI_CWD override from dir-A to dir-B works (got: ${RESULT_OVERRIDE})"
else
    log_fail "PI_CWD override should resolve to ${TEST_DIR_B}, got: ${RESULT_OVERRIDE}"
fi

# Launch from dir-B but override with PI_CWD=dir-A
RESULT_OVERRIDE2=$(cd "${TEST_DIR_B}" && PI_CWD="${TEST_DIR_A}" sh /tmp/test-wrapper-logic-$$)
if [ "${RESULT_OVERRIDE2}" = "${TEST_DIR_A}" ]; then
    log_pass "PI_CWD override from dir-B to dir-A works (got: ${RESULT_OVERRIDE2})"
else
    log_fail "PI_CWD override should resolve to ${TEST_DIR_A}, got: ${RESULT_OVERRIDE2}"
fi

# ============================================================
# Test 4: Wrapper sets PATH and NODE_PATH correctly
# ============================================================
echo ""
echo "=== Test 4: PATH and NODE_PATH exports ==="

# Check that wrapper exports PATH with node_modules/.bin
if grep -q 'export PATH=.*node_modules/.bin' "${WRAPPER}"; then
    log_pass "Wrapper exports PATH with node_modules/.bin"
else
    log_fail "Wrapper missing PATH export with node_modules/.bin"
fi

# Check that wrapper exports NODE_PATH
if grep -q 'export NODE_PATH=.*node_modules' "${WRAPPER}"; then
    log_pass "Wrapper exports NODE_PATH"
else
    log_fail "Wrapper missing NODE_PATH export"
fi

# ============================================================
# Test 5: Symlink from bin/pi to lib/pi/pi is intact
# ============================================================
echo ""
echo "=== Test 5: bin/pi symlink ==="

BIN_PI="${MINIONS_HOME}/bin/pi"
if [ -L "${BIN_PI}" ]; then
    LINK_TARGET=$(readlink "${BIN_PI}")
    if [ "${LINK_TARGET}" = "${MINIONS_HOME}/lib/pi/pi" ]; then
        log_pass "bin/pi symlinks correctly to lib/pi/pi"
    else
        log_fail "bin/pi symlinks to wrong target: ${LINK_TARGET}"
    fi
else
    log_fail "bin/pi is not a symlink"
fi

# ============================================================
# Test 6: Wrapper uses exec (not subshell) for pi binary
# ============================================================
echo ""
echo "=== Test 6: Wrapper uses exec ==="

if grep -q '^exec ' "${WRAPPER}"; then
    log_pass "Wrapper uses exec for pi binary"
else
    log_fail "Wrapper does not use exec (subshell may cause signal issues)"
fi

# Cleanup
rm -rf /tmp/test-pi-cwd-$$ /tmp/test-wrapper-logic-$$

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Test Summary ==="
echo "  Passed: ${PASS_COUNT}"
echo "  Failed: ${FAIL_COUNT}"
echo ""

if [ "${FAIL_COUNT}" -gt 0 ]; then
    echo "${RED}Some tests failed!${NC}"
    exit 1
else
    echo "${GREEN}All tests passed!${NC}"
    exit 0
fi
