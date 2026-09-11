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
        # Isolate HOME so the REAL ~/.minions/etc/knowledge.env (dev-persisted on
        # a dev-installed machine) can't leak into this standalone simulation.
        HOME="${tmp}/home"
        # Also isolate MINIONS_HOME — it may be exported from a prior boot.sh run
        unset MINIONS_HOME
        # No .git, no skills/: must be standalone regardless of cwd
        detect_knowledge_mode >/dev/null 2>&1
        [ "${MODE}" = "standalone" ] || { echo "mode=${MODE}"; exit 1; }
        [ -z "${MINIONS_REPO_ROOT}" ] || { echo "root=${MINIONS_REPO_ROOT}"; exit 1; }
        # MINIONS_HOME default must be ${HOME}/.minions
        [ "${MINIONS_HOME}" = "${HOME}/.minions" ] || { echo "home=${MINIONS_HOME}"; exit 1; }
    )
    local rc=$?
    rm -rf "$tmp"
    [ $rc -eq 0 ] && ok "test_standalone_mode" || bad "test_standalone_mode" "expected MODE=standalone with empty MINIONS_REPO_ROOT"
}

# ─── Test 4: live git checkout wins over stale persisted env ───────────────
# Regression: after a dev install, knowledge.env persists MODE=dev + the repo
# root. If the checkout is later MOVED and install.sh re-run from the new
# location, the live git probe must win — not the stale persisted root.
test_live_checkout_wins() {
    local tmp
    tmp="$(mktemp -d)"
    # Fake a STALE persisted dev root: a real dir with skills/+wiki/ so the
    # persisted branch considers it valid — but it is NOT the current checkout.
    local stale_root="${tmp}/stale-repo"
    local fake_home="${tmp}/home"
    mkdir -p "${stale_root}/skills" "${stale_root}/wiki"
    mkdir -p "${fake_home}/.minions/etc"
    {
        echo "MINIONS_HOME=${fake_home}/.minions"
        echo "MODE=dev"
        echo "MINIONS_REPO_ROOT=${stale_root}"
    } > "${fake_home}/.minions/etc/knowledge.env"
    (
        cd "${REPO_ROOT}" || exit 1  # real checkout with skills/ + wiki/
        # bash -c so $0 is "bash" (not the test script) -> probe uses cwd only
        ROOT="${REPO_ROOT}" MINIONS_HOME="${fake_home}/.minions" bash -c '
            source "$ROOT/lib/knowledge-detection.sh" 2>/dev/null
            log_info() { :; }
            detect_knowledge_mode >/dev/null 2>&1
            [ "$MODE" = "dev" ] || { echo "mode=$MODE"; exit 1; }
            [ "$MINIONS_REPO_ROOT" = "$ROOT" ] || { echo "root=$MINIONS_REPO_ROOT"; exit 1; }
        '
    )
    local rc=$?
    rm -rf "$tmp"
    [ $rc -eq 0 ] && ok "test_live_checkout_wins" || bad "test_live_checkout_wins" "live checkout should override stale persisted root"
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
test_live_checkout_wins

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "${FAIL}" -eq 0 ] && echo "Status: GREEN" && exit 0
echo "Status: RED"
exit 1