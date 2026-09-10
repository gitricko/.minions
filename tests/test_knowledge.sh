#!/usr/bin/env bash
# test_knowledge.sh — End-to-end knowledge layer test contract (Phase 0.5)
# Written BEFORE any wiring. Starts RED. Phases turn individual assertions GREEN.
#
# Usage:
#   bash tests/test_knowledge.sh                          # run all functions
#   KNOWLEDGE_TEST_FUNCTION=test_dev_symlinks bash tests/test_knowledge.sh
#   KNOWLEDGE_TEST_MODE=dev bash tests/test_knowledge.sh  # set mode context
#
# EXPECTED FAILURE MAP (phases → functions that should be GREEN at that phase):
# Phase 0.5: ALL functions RED (symlinks not wired, skills/wiki not ported)
# Phase 15:  test_skill_count goes GREEN (15 skills exist, but 4 new → count=15)
# Phase 20:  test_wiki_* go GREEN (23+INDEX, but 4 new → count=24+INDEX=25)
# Phase 21:  test_seed_* go GREEN
# Phase 23:  test_dev_* go GREEN (symlinks wired), test_standalone_* go GREEN (in DTS)
# Phase 24:  test_pi_* go GREEN
# Phase 26:  test_skill_* → count=19, all GREEN
# Phase 28:  test_wiki_* → count=28, all GREEN
# Phase 31:  Everything GREEN
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KNOWLEDGE_TEST_MODE="${KNOWLEDGE_TEST_MODE:-}"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

pass() { TEST_COUNT=$((TEST_COUNT + 1)); PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { TEST_COUNT=$((TEST_COUNT + 1)); FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1 — $2"; }

# ─── Dev Mode Tests ────────────────────────────────────────────────────────

test_dev_detection() {
  # Detect mode based on git root and skill/wiki dirs
  local mode="standalone"
  if git -C "$REPO_ROOT" rev-parse --show-toplevel &>/dev/null; then
    local git_root
    git_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)"
    if [ -d "${git_root}/skills" ] && [ -d "${git_root}/wiki" ]; then
      mode="dev"
    fi
  fi
  if [ "$mode" = "dev" ]; then
    pass "test_dev_detection"
  else
    fail "test_dev_detection" "expected MODE=dev when run from .minions repo, got $mode"
  fi
}

test_dev_symlinks() {
  # ~/.hermes/skills/minions should be a symlink pointing to <REPO_ROOT>/skills
  local link="${HOME}/.hermes/skills/minions"
  if [ -L "$link" ]; then
    local target
    target="$(readlink "$link")"
    if [ "$target" = "${REPO_ROOT}/skills" ]; then
      pass "test_dev_symlinks"
    else
      fail "test_dev_symlinks" "symlink target='$target', expected='${REPO_ROOT}/skills'"
    fi
  else
    fail "test_dev_symlinks" "no symlink at $link"
  fi
}

test_dev_memories() {
  # ~/.hermes/memories should be a symlink pointing to <REPO_ROOT>/memories
  local link="${HOME}/.hermes/memories"
  if [ -L "$link" ]; then
    local target
    target="$(readlink "$link")"
    if [ "$target" = "${REPO_ROOT}/memories" ]; then
      pass "test_dev_memories"
    else
      fail "test_dev_memories" "symlink target='$target', expected='${REPO_ROOT}/memories'"
    fi
  else
    fail "test_dev_memories" "no symlink at $link"
  fi
}

test_dev_no_wiki_link() {
  # ~/.hermes/wiki should NOT exist as a symlink (wiki is not symlinked)
  if [ -L "${HOME}/.hermes/wiki" ]; then
    fail "test_dev_no_wiki_link" "~/.hermes/wiki should NOT be a symlink"
  else
    pass "test_dev_no_wiki_link"
  fi
}

# ─── Seed Tests (Phase 21) ─────────────────────────────────────────────────

test_seed_schema() {
  # Verify seed.json has 'content' field, not 'text'
  local seed="${REPO_ROOT}/mnemon/seed.json"
  if [ ! -f "$seed" ]; then
    fail "test_seed_schema" "$seed does not exist"
    return
  fi
  python3 -c "
import json, sys
d = json.load(open('$seed'))
insights = d.get('insights', [])
if not insights:
    print('FAIL: no insights in $seed', file=sys.stderr); sys.exit(1)
first = insights[0]
if 'content' not in first:
    print(f'FAIL: first insight has keys {list(first.keys())}, expected content', file=sys.stderr); sys.exit(1)
print(f'OK: {len(insights)} insights, content field present')
" && pass "test_seed_schema" || fail "test_seed_schema" "schema validation failed"
}

test_seed_validate() {
  # Validator script exits 0
  local validator="${REPO_ROOT}/mnemon/validate-seed.py"
  local seed="${REPO_ROOT}/mnemon/seed.json"
  if [ ! -f "$validator" ]; then
    fail "test_seed_validate" "$validator not found"
    return
  fi
  if [ ! -f "$seed" ]; then
    fail "test_seed_validate" "$seed not found"
    return
  fi
  if python3 "$validator" "$seed" 2>&1; then
    pass "test_seed_validate"
  else
    fail "test_seed_validate" "validator exited non-zero"
  fi
}

# ─── Wiki Tests (Phase 16-20) ──────────────────────────────────────────────

test_wiki_count() {
  # 23 ported + INDEX.md + 4 new = 28 total .md files (excluding .gitkeep)
  local count
  count="$(find "${REPO_ROOT}/wiki" -maxdepth 1 -name '*.md' ! -name '.gitkeep' 2>/dev/null | wc -l)"
  if [ "$count" -eq 28 ]; then
    pass "test_wiki_count"
  else
    fail "test_wiki_count" "expected 28 wiki articles, got $count"
  fi
}

test_wiki_index_count() {
  # INDEX.md table should have 27 rows (23 ported + 4 new)
  local index="${REPO_ROOT}/wiki/INDEX.md"
  if [ ! -f "$index" ]; then
    fail "test_wiki_index_count" "INDEX.md not found"
    return
  fi
  local rows
  rows="$(grep -c '^|' "$index" 2>/dev/null || echo 0)"
  # Subtract 2 for header separator line and header row
  local data_rows=$((rows - 2))
  if [ "$data_rows" -eq 27 ]; then
    pass "test_wiki_index_count"
  else
    fail "test_wiki_index_count" "expected 27 data rows in INDEX.md, got $data_rows ($rows total | lines)"
  fi
}

test_wiki_links() {
  # Run F4 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F4 2>&1 | grep -q "all wiki links resolve\|no wiki files found"; then
    pass "test_wiki_links"
  else
    fail "test_wiki_links" "F4 link integrity check failed"
  fi
}

# ─── Skill Tests (Phase 1-15) ──────────────────────────────────────────────

test_skill_count() {
  # 15 ported + 4 new = 19 skills
  local count
  count="$(find "${REPO_ROOT}/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)"
  if [ "$count" -eq 19 ]; then
    pass "test_skill_count"
  else
    fail "test_skill_count" "expected 19 skills, got $count"
  fi
}

test_skill_spot_check() {
  # Verify specific key skills exist
  local missing=""
  for name in docker-test-shell pi-agent-basics hermes-configuration omniroute-guide; do
    if [ ! -f "${REPO_ROOT}/skills/${name}/SKILL.md" ]; then
      missing="$missing $name"
    fi
  done
  if [ -z "$missing" ]; then
    pass "test_skill_spot_check"
  else
    fail "test_skill_spot_check" "missing skills:$missing"
  fi
}

test_frontmatter() {
  # Run F2 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F2 2>&1 | grep -q "OK:"; then
    pass "test_frontmatter"
  else
    fail "test_frontmatter" "F2 frontmatter check failed"
  fi
}

test_executable_bits() {
  # Run F6 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F6 2>&1 | grep -q "scripts are executable\|no .sh scripts found"; then
    pass "test_executable_bits"
  else
    fail "test_executable_bits" "F6 executable bits check failed"
  fi
}

test_skill_wiki_links() {
  # Run F7 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F7 2>&1 | grep -q "skill→wiki\|no skill→wiki"; then
    pass "test_skill_wiki_links"
  else
    fail "test_skill_wiki_links" "F7 skill→wiki links check failed"
  fi
}

# ─── Pi Settings Tests (Phase 24) ──────────────────────────────────────────

test_pi_settings() {
  # ~/.pi/agent/settings.json should have skills array
  local settings="${HOME}/.pi/agent/settings.json"
  if [ ! -f "$settings" ]; then
    fail "test_pi_settings" "$settings not found"
    return
  fi
  python3 -c "
import json, sys
with open('$settings') as f:
    cfg = json.load(f)
skills = cfg.get('skills', [])
if not skills:
    print('FAIL: no skills array in settings.json', file=sys.stderr); sys.exit(1)
print(f'OK: {len(skills)} skill paths configured')
" && pass "test_pi_settings" || fail "test_pi_settings" "settings.json validation failed"
}

# ─── Standalone Tests (Phase 23) ───────────────────────────────────────────

test_standalone_skills() {
  # ~/.minions/skills should exist and have 19 skills
  local count
  count="$(find "${HOME}/.minions/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)"
  if [ "$count" -eq 19 ]; then
    pass "test_standalone_skills"
  else
    fail "test_standalone_skills" "expected 19 skills, got $count"
  fi
}

test_standalone_wiki() {
  # ~/.minions/wiki should have 28 articles
  local count
  count="$(find "${HOME}/.minions/wiki" -maxdepth 1 -name '*.md' ! -name '.gitkeep' 2>/dev/null | wc -l)"
  if [ "$count" -eq 28 ]; then
    pass "test_standalone_wiki"
  else
    fail "test_standalone_wiki" "expected 28 wiki articles, got $count"
  fi
}

test_idempotency() {
  # Running boot knowledge wiring twice should produce same result
  # This test requires boot.sh to exist and be runnable
  if [ ! -f "${REPO_ROOT}/boot.sh" ]; then
    fail "test_idempotency" "boot.sh not found"
    return
  fi
  # Capture symlink state before
  local before_skills=""
  if [ -L "${HOME}/.hermes/skills/minions" ]; then
    before_skills="$(readlink "${HOME}/.hermes/skills/minions")"
  fi
  # Run knowledge wiring portion of boot (if detect_knowledge_mode exists)
  if bash -c "source ${REPO_ROOT}/lib/knowledge-detection.sh 2>/dev/null && detect_knowledge_mode" 2>/dev/null; then
    # Capture state after second run
    local after_skills=""
    if [ -L "${HOME}/.hermes/skills/minions" ]; then
      after_skills="$(readlink "${HOME}/.hermes/skills/minions")"
    fi
    if [ "$before_skills" = "$after_skills" ]; then
      pass "test_idempotency"
    else
      fail "test_idempotency" "symlink changed between runs: '$before_skills' → '$after_skills'"
    fi
  else
    fail "test_idempotency" "knowledge-detection.sh not available"
  fi
}

# ─── Standalone Full Test (DTS only) ───────────────────────────────────────

test_standalone_full() {
  # Full install+boot in DTS, all assertions pass
  # This is a placeholder — actual DTS test runs from test_dts.sh
  fail "test_standalone_full" "placeholder — run in DTS via test_dts.sh"
}

# ─── Global Tests (always run) ─────────────────────────────────────────────

test_global_shell_syntax() {
  # Run F1 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F1 2>&1 | grep -q "shell\|no shell files"; then
    pass "test_global_shell_syntax"
  else
    fail "test_global_shell_syntax" "F1 shell syntax check failed"
  fi
}

test_global_json() {
  # Run F3 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F3 2>&1 | grep -q "OK\|no JSON files"; then
    pass "test_global_json"
  else
    fail "test_global_json" "F3 JSON validity check failed"
  fi
}

test_global_devcontainer() {
  # Run F5 from verify-knowledge.sh
  if bash "${REPO_ROOT}/scripts/verify-knowledge.sh" F5 2>&1 | grep -q "no .devcontainer\|no leftover"; then
    pass "test_global_devcontainer"
  else
    fail "test_global_devcontainer" "F5 .devcontainer ref check failed"
  fi
}

# ─── Dispatch ──────────────────────────────────────────────────────────────

ALL_FUNCTIONS=(
  test_dev_detection
  test_dev_symlinks
  test_dev_memories
  test_dev_no_wiki_link
  test_seed_schema
  test_seed_validate
  test_wiki_count
  test_wiki_index_count
  test_wiki_links
  test_skill_count
  test_skill_spot_check
  test_frontmatter
  test_executable_bits
  test_skill_wiki_links
  test_pi_settings
  test_standalone_skills
  test_standalone_wiki
  test_idempotency
  test_standalone_full
  test_global_shell_syntax
  test_global_json
  test_global_devcontainer
)

echo "═══════════════════════════════════════════════════════════════"
echo " Knowledge Layer Test Contract"
echo " Mode: ${KNOWLEDGE_TEST_MODE:-auto}"
echo " Repo: ${REPO_ROOT}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ -n "${KNOWLEDGE_TEST_FUNCTION:-}" ]; then
  # Run single function
  if type -t "$KNOWLEDGE_TEST_FUNCTION" >/dev/null 2>&1; then
    "$KNOWLEDGE_TEST_FUNCTION"
  else
    echo "ERROR: unknown function: $KNOWLEDGE_TEST_FUNCTION"
    exit 1
  fi
else
  # Run all functions
  for fn in "${ALL_FUNCTIONS[@]}"; do
    "$fn"
  done
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed (total: ${TEST_COUNT})"
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo " Status: RED (${FAIL_COUNT} failures — expected before wiring phases)"
  exit 1
else
  echo " Status: GREEN (all assertions pass)"
  exit 0
fi
