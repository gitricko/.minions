#!/usr/bin/env bash
# tests/test_self_check.sh — unit tests for self-check.sh persistence checks
# Tests the symlink/directory logic for knowledge assets in both dev and standalone modes.
#
# Usage:
#   bash tests/test_self_check.sh
# Exit 0 = all pass; 1 = any failure.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1 — $2"; }

# ── Test helper: run self-check --ci in a controlled environment ───────────
run_self_check() {
    local minions_home="$1"
    local mode="$2"  # "dev" or "standalone"
    MINIONS_HOME="$minions_home" bash "${REPO_ROOT}/self-check.sh" --ci 2>&1
}

# ── Test 1: dev mode — all four are symlinks ────────────────────────────────
test_dev_mode_all_symlinks() {
    local tmp
    tmp="$(mktemp -d)"
    local mh="${tmp}/.minions"
    mkdir -p "${mh}"
    # Create symlinks for all four (dev mode)
    ln -s "${REPO_ROOT}/skills" "${mh}/skills"
    ln -s "${REPO_ROOT}/wiki" "${mh}/wiki"
    ln -s "${REPO_ROOT}/mnemon" "${mh}/mnemon"
    ln -s "${REPO_ROOT}/memories" "${mh}/memories"

    local output
    output=$(run_self_check "${mh}" "dev")
    local rc=$?

    # Should PASS (exit 0) — all symlinks present
    if [ $rc -eq 0 ]; then
        ok "test_dev_mode_all_symlinks"
    else
        bad "test_dev_mode_all_symlinks" "expected exit 0, got $rc. Output: $output"
    fi
    rm -rf "$tmp"
}

# ── Test 2: standalone mode — all four are real directories ────────────────
test_standalone_mode_all_directories() {
    local tmp
    tmp="$(mktemp -d)"
    local mh="${tmp}/.minions"
    mkdir -p "${mh}"
    # Create REAL directories for all four (standalone mode)
    mkdir -p "${mh}/skills"
    mkdir -p "${mh}/wiki"
    mkdir -p "${mh}/mnemon"
    mkdir -p "${mh}/memories"
    # Put some content to make them non-empty
    touch "${mh}/skills/.keep"
    touch "${mh}/wiki/.keep"
    touch "${mh}/mnemon/.keep"
    touch "${mh}/memories/.keep"

    local output
    output=$(run_self_check "${mh}" "standalone")
    local rc=$?

    # Should PASS (exit 0) — directories are OK in standalone mode
    # THIS IS THE BUG: currently fails because Skills and Memories require symlinks
    if [ $rc -eq 0 ]; then
        ok "test_standalone_mode_all_directories"
    else
        bad "test_standalone_mode_all_directories" "expected exit 0 (directories OK in standalone), got $rc. Output: $output"
    fi
    rm -rf "$tmp"
}

# ── Test 3: mixed mode — some symlinks, some directories (should all pass) ──
test_mixed_mode() {
    local tmp
    tmp="$(mktemp -d)"
    local mh="${tmp}/.minions"
    mkdir -p "${mh}"
    # Skills and Wiki as symlinks, Mnemon and Memories as directories
    ln -s "${REPO_ROOT}/skills" "${mh}/skills"
    ln -s "${REPO_ROOT}/wiki" "${mh}/wiki"
    mkdir -p "${mh}/mnemon"
    mkdir -p "${mh}/memories"
    touch "${mh}/mnemon/.keep"
    touch "${mh}/memories/.keep"

    local output
    output=$(run_self_check "${mh}" "mixed")
    local rc=$?

    # Should PASS — both symlinks and directories are valid
    if [ $rc -eq 0 ]; then
        ok "test_mixed_mode"
    else
        bad "test_mixed_mode" "expected exit 0, got $rc. Output: $output"
    fi
    rm -rf "$tmp"
}

# ── Test 4: missing knowledge entirely (should warn, not fail) ─────────────
test_missing_knowledge() {
    local tmp
    tmp="$(mktemp -d)"
    local mh="${tmp}/.minions"
    mkdir -p "${mh}"
    # No skills/, wiki/, mnemon/, memories/ at all

    local output
    output=$(run_self_check "${mh}" "missing")
    local rc=$?

    # Should exit 1 (warnings only, no critical failures)
    if [ $rc -eq 1 ]; then
        ok "test_missing_knowledge"
    else
        bad "test_missing_knowledge" "expected exit 1 (warnings), got $rc. Output: $output"
    fi
    rm -rf "$tmp"
}

# ── Test 5: broken symlink (should fail) ───────────────────────────────────
test_broken_symlink() {
    local tmp
    tmp="$(mktemp -d)"
    local mh="${tmp}/.minions"
    mkdir -p "${mh}"
    # Create a broken symlink for skills
    ln -s "/nonexistent/path" "${mh}/skills"
    mkdir -p "${mh}/wiki"
    mkdir -p "${mh}/mnemon"
    mkdir -p "${mh}/memories"
    touch "${mh}/wiki/.keep"
    touch "${mh}/mnemon/.keep"
    touch "${mh}/memories/.keep"

    local output
    output=$(run_self_check "${mh}" "broken")
    local rc=$?

    # Should FAIL (exit 2) — broken symlink is critical
    if [ $rc -eq 2 ]; then
        ok "test_broken_symlink"
    else
        bad "test_broken_symlink" "expected exit 2 (critical), got $rc. Output: $output"
    fi
    rm -rf "$tmp"
}

# ── Run all tests ──────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo " Self-Check Persistence Unit Tests"
echo " Repo: ${REPO_ROOT}"
echo "════════════════════════════════════════════════════════════"

test_dev_mode_all_symlinks
test_standalone_mode_all_directories
test_mixed_mode
test_missing_knowledge
test_broken_symlink

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ] && echo "Status: GREEN" && exit 0
echo "Status: RED"
exit 1