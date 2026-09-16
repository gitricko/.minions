#!/usr/bin/env sh
# tests/test_skill_yaml.sh - Validates SKILL.md frontmatter YAML parses correctly
# Issue #39: Self-update-fix skill YAML error
#
# Checks that all SKILL.md files in the skills/ directory have valid YAML
# frontmatter (between the first two --- markers).

set -e
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
SKILLS_DIR="${PROJECT_ROOT}/skills"

# Colors
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    NC=''
fi

PASS_COUNT=0
FAIL_COUNT=0

log_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "${GREEN}[PASS]${NC} $*"; }
log_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "${RED}[FAIL]${NC} $*" >&2; }

echo "=== Validating SKILL.md YAML frontmatter ==="

if [ ! -d "${SKILLS_DIR}" ]; then
    echo "No skills directory found at ${SKILLS_DIR}"
    exit 0
fi

for skill_dir in "${SKILLS_DIR}"/*/; do
    [ -d "${skill_dir}" ] || continue
    skill_file="${skill_dir}SKILL.md"
    [ -f "${skill_file}" ] || continue

    skill_name=$(basename "${skill_dir}")

    # Extract frontmatter (between first two --- lines)
    # Use awk to get content between line 2 and the next ---
    frontmatter=$(awk '
        /^---$/ { count++; next }
        count == 1 { print }
        count >= 2 { exit }
    ' "${skill_file}")

    if [ -z "${frontmatter}" ]; then
        log_fail "${skill_name}: No frontmatter found"
        continue
    fi

    # Check YAML parse with Python
    parse_result=$(python3 -c "
import yaml, sys
try:
    data = yaml.safe_load('''${frontmatter}''')
    if not isinstance(data, dict):
        print('NOT_A_DICT')
        sys.exit(1)
    if 'name' not in data:
        print('MISSING_NAME')
        sys.exit(1)
    print('OK')
except yaml.YAMLError as e:
    print(f'YAML_ERROR: {e}')
    sys.exit(1)
" 2>&1)

    if echo "${parse_result}" | grep -q "^OK$"; then
        log_pass "${skill_name}: YAML frontmatter valid"
    else
        log_fail "${skill_name}: YAML error - ${parse_result}"
    fi
done

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
