#!/usr/bin/env bash
# tests/test_knowledge_mode.sh — Phase 22 unit tests for lib/knowledge-detection.sh
# Exercises the REAL functions (sources the lib), not inline duplicates.
#
# Usage:
#   bash tests/test_knowledge_mode.sh
# Exit 0 = all pass; 1 = any failure.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1 — $2"; }

# log_info is defined by install.sh; provide a stub for standalone sourcing
log_info() { :; }
log_warn() { :; }

# ─── Test 1: dev mode from a git checkout with skills/ + wiki/ ────────────
test_dev_mode() {
    if ! . "${REPO_ROOT}/lib/knowledge-detection.sh" 2>/dev/null; then
        bad "test_dev_mode" "lib/knowledge-detection.sh failed to source"
        return 1
    fi
    # Run inside the repo (has .git + skills/ + wiki/)
    (
        cd "${REPO_ROOT}" || return 1
        detect_knowledge_mode >/dev/null 2>&1
        [ "${MODE}" = "dev" ] || { echo "mode=${MODE}"; return 1; }
        [ "${MINIONS_REPO_ROOT}" = "${REPO_ROOT}" ] || { echo "root=${MINIONS_REPO_ROOT}"; return 1; }
    ) && ok "test_dev_mode" || bad "test_dev_mode" "expected MODE=dev, MINIONS_REPO_ROOT=${REPO_ROOT}"
}

# ─── Test 2: standalone mode outside a git repo ───────────────────────────
test_standalone_mode() {
    local tmp
    tmp="$(mktemp -d)"
    (
        cd "$tmp" || exit 1
        # No .git, no skills/: must be standalone regardless of cwd
        detect_knowledge_mode >/dev/null 2>&1
        [ "${MODE}" = "standalone" ] || { echo "mode=${MODE}"; exit 1; }
        [ -z "${MINIONS_REPO_ROOT}" ] || { echo "root=${MINIONS_REPO_ROOT}"; exit 1; }
        # MINIONS_HOME default must be ~/.minions
        [ "${MINIONS_HOME}" = "${HOME}/.minions" ] || { echo "home=${MINIONS_HOME}"; exit 1; }
    )
    local rc=$?
    rm -rf "$tmp"
    [ $rc -eq 0 ] && ok "test_standalone_mode" || bad "test_standalone_mode" "expected MODE=standalone with empty MINIONS_REPO_ROOT"
}

# ─── Test 3: MINIONS_HOME respects env override ───────────────────────────
test_minions_home_override() {
    local tmp
    tmp="$(mktemp -d)"
    (
        cd "$tmp" || exit 1
        MINIONS_HOME="/tmp/custom-minions" detect_knowledge_mode >/dev/null 2>&1
        [ "${MINIONS_HOME}" = "/tmp/custom-minions" ] || { echo "home=${MINIONS_HOME}"; exit 1; }
    )
    local rc=$?
    rm -rf "$tmp"
    [ $rc -eq 0 ] && ok "test_minions_home_override" || bad "test_minions_home_override" "MINIONS_HOME env not respected"
}

echo "════════════════════════════════════════"
echo " Knowledge Mode Unit Tests (Phase 22)"
echo " Repo: ${REPO_ROOT}"
echo "════════════════════════════════════════"

test_dev_mode
test_standalone_mode
test_minions_home_override

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ] && echo "Status: GREEN" && exit 0
echo "Status: RED"
exit 1