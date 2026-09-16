#!/usr/bin/env sh
# tests/test_pi_wrapper_cwd.sh - Tests for pi wrapper working directory
# Issue #38: pi always launches in the wrong working directory
#
# Tests the installer template in lib/pi.sh to verify the generated
# wrapper would produce correct CWD behavior. Works both in CI (no
# install needed) and locally (validates the installed wrapper too).

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

PASS_COUNT=0
FAIL_COUNT=0

log_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "${GREEN}[PASS]${NC} $*"; }
log_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "${RED}[FAIL]${NC} $*" >&2; }
log_skip() { echo "${YELLOW}[SKIP]${NC} $*"; }

# Helper: render the wrapper from lib/pi.sh template with a test MINIONS_HOME
# Extracts the heredoc content and substitutes test values.
render_wrapper() {
    local test_home="$1"
    local outfile="$2"
    local source_file="${PROJECT_ROOT}/lib/pi.sh"

    # The heredoc in lib/pi.sh uses \${} to write literal ${} to the output.
    # When we extract and re-run it, we need to unescape those for shell expansion.
    sed -n '/^    cat > "\${install_dir}\/pi" << EOF$/,/^EOF$/p' "${source_file}" \
        | sed '1d;$d' \
        | sed "s|\${MINIONS_HOME}|${test_home}|g" \
        | sed 's|\\${|${|g; s|\\$PWD|$PWD|g; s|\\$@|$@|g; s|\\$PATH|$PATH|g' \
        | sed 's|^exec .*|pwd|' \
        > "${outfile}"
    chmod +x "${outfile}"
}

# ============================================================
# Test 1: lib/pi.sh exists and contains the wrapper template
# ============================================================
echo "=== Test 1: Installer template exists ==="
SOURCE_FILE="${PROJECT_ROOT}/lib/pi.sh"
if [ -f "${SOURCE_FILE}" ]; then
    log_pass "lib/pi.sh exists"
else
    log_fail "lib/pi.sh not found at ${SOURCE_FILE}"
    echo "=== Tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed ==="
    exit 1
fi

if grep -q 'cat > "${install_dir}/pi"' "${SOURCE_FILE}"; then
    log_pass "lib/pi.sh contains wrapper template"
else
    log_fail "lib/pi.sh missing wrapper heredoc"
fi

# ============================================================
# Test 2: Wrapper respects $PWD (launch directory) by default
# ============================================================
echo ""
echo "=== Test 2: Wrapper respects \$PWD ==="

TEST_HOME="/tmp/test-pi-home-$$"
TEST_DIR_A="${TEST_HOME}/project-a"
TEST_DIR_B="${TEST_HOME}/project-b"
mkdir -p "${TEST_DIR_A}" "${TEST_DIR_B}"

render_wrapper "${TEST_HOME}" /tmp/test-wrapper-$$

# Launch from directory A - should resolve to A
RESULT_A=$(cd "${TEST_DIR_A}" && sh /tmp/test-wrapper-$$)
if [ "${RESULT_A}" = "${TEST_DIR_A}" ]; then
    log_pass "Wrapper from dir-A resolves to dir-A (got: ${RESULT_A})"
else
    log_fail "Wrapper from dir-A should resolve to ${TEST_DIR_A}, got: ${RESULT_A}"
fi

# Launch from directory B - should resolve to B
RESULT_B=$(cd "${TEST_DIR_B}" && sh /tmp/test-wrapper-$$)
if [ "${RESULT_B}" = "${TEST_DIR_B}" ]; then
    log_pass "Wrapper from dir-B resolves to dir-B (got: ${RESULT_B})"
else
    log_fail "Wrapper from dir-B should resolve to ${TEST_DIR_B}, got: ${RESULT_B}"
fi

# Verify it does NOT resolve to hardcoded npm dir
HARDCODED="${TEST_HOME}/lib/pi/npm"
if [ "${RESULT_A}" != "${HARDCODED}" ] && [ "${RESULT_B}" != "${HARDCODED}" ]; then
    log_pass "Wrapper does not use hardcoded npm path"
else
    log_fail "Wrapper incorrectly resolves to hardcoded path: ${HARDCODED}"
fi

# ============================================================
# Test 3: PI_CWD override works
# ============================================================
echo ""
echo "=== Test 3: PI_CWD override ==="

RESULT_OVERRIDE=$(cd "${TEST_DIR_A}" && PI_CWD="${TEST_DIR_B}" sh /tmp/test-wrapper-$$)
if [ "${RESULT_OVERRIDE}" = "${TEST_DIR_B}" ]; then
    log_pass "PI_CWD override from dir-A to dir-B works (got: ${RESULT_OVERRIDE})"
else
    log_fail "PI_CWD override should resolve to ${TEST_DIR_B}, got: ${RESULT_OVERRIDE}"
fi

RESULT_OVERRIDE2=$(cd "${TEST_DIR_B}" && PI_CWD="${TEST_DIR_A}" sh /tmp/test-wrapper-$$)
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

# Render a non-modified wrapper (with exec, not pwd) to check exports
sed -n '/^    cat > "\${install_dir}\/pi" << EOF$/,/^EOF$/p' "${SOURCE_FILE}" \
    | sed '1d;$d' \
    | sed "s|\${MINIONS_HOME}|${TEST_HOME}|g" \
    | sed 's|\\${|${|g; s|\\$PWD|$PWD|g; s|\\$@|$@|g; s|\\$PATH|$PATH|g' \
    > /tmp/test-wrapper-full-$$

if grep -q 'export PATH=.*node_modules/.bin' /tmp/test-wrapper-full-$$; then
    log_pass "Wrapper exports PATH with node_modules/.bin"
else
    log_fail "Wrapper missing PATH export with node_modules/.bin"
fi

if grep -q 'export NODE_PATH=.*node_modules' /tmp/test-wrapper-full-$$; then
    log_pass "Wrapper exports NODE_PATH"
else
    log_fail "Wrapper missing NODE_PATH export"
fi

# ============================================================
# Test 5: Wrapper uses exec (not subshell) for pi binary
# ============================================================
echo ""
echo "=== Test 5: Wrapper uses exec ==="

if grep -q '^exec ' /tmp/test-wrapper-full-$$; then
    log_pass "Wrapper uses exec for pi binary"
else
    log_fail "Wrapper does not use exec (subshell may cause signal issues)"
fi

# ============================================================
# Test 6: Wrapper uses PI_CWD with fallback to $PWD
# ============================================================
echo ""
echo "=== Test 6: Wrapper uses PI_CWD with \$PWD fallback ==="

if grep -q 'PI_CWD' /tmp/test-wrapper-full-$$; then
    log_pass "Wrapper references PI_CWD"
else
    log_fail "Wrapper does not reference PI_CWD"
fi

if grep -q '${PI_CWD:-$PWD}' /tmp/test-wrapper-full-$$; then
    log_pass "Wrapper uses \${PI_CWD:-\$PWD} fallback pattern"
else
    log_fail "Wrapper missing \${PI_CWD:-\$PWD} fallback pattern"
fi

# ============================================================
# Test 7 (local only): Installed wrapper matches template
# ============================================================
echo ""
echo "=== Test 7: Installed wrapper consistency ==="

INSTALLED_WRAPPER="${HOME}/.minions/lib/pi/pi"
if [ -f "${INSTALLED_WRAPPER}" ]; then
    if grep -q 'PI_CWD' "${INSTALLED_WRAPPER}"; then
        log_pass "Installed wrapper uses PI_CWD"
    else
        log_fail "Installed wrapper missing PI_CWD (stale install?)"
    fi
    if grep -q 'cd "/home/.*\.minions/lib/pi/npm"' "${INSTALLED_WRAPPER}"; then
        log_fail "Installed wrapper still has hardcoded cd to npm dir"
    else
        log_pass "Installed wrapper has no hardcoded cd"
    fi
else
    log_skip "No installed wrapper found (CI or fresh env)"
fi

# Cleanup
rm -rf "${TEST_HOME}" /tmp/test-wrapper-$$ /tmp/test-wrapper-full-$$

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
