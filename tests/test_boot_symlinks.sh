#!/usr/bin/env sh
# tests/test_boot_symlinks.sh — Phase 23 unit tests for boot.sh symlink wiring
# Tests dev mode symlinks: ~/.minions/{skills,wiki,mnemon,memories} -> MINIONS_REPO_ROOT/{skills,wiki,mnemon,memories}

set -e

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

log_info() { echo "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo "${RED}[ERROR]${NC} $*" >&2; }

PASS=0
FAIL=0

assert_exit_code() {
    local expected="$1" actual="$2" name="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_symlink() {
    local link="$1" target="$2" name="$3"
    if [ -L "$link" ]; then
        local actual=$(readlink "$link")
        if [ "$actual" = "$target" ]; then
            echo "  PASS: $name"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: $name (points to $actual, expected $target)"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: $name (not a symlink)"
        FAIL=$((FAIL + 1))
    fi
}

# Test: boot.sh creates symlinks in dev mode
test_dev_mode_symlinks() {
    log_info "Test: dev mode symlinks"

    # Source the real lib
    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/knowledge-symlinks.sh

    # Mock log_info for test
    log_info() { echo "[INFO] $*"; }

    # Setup: create a fake repo root with knowledge dirs
    REPO_ROOT="/tmp/test_repo_$$"
    mkdir -p "$REPO_ROOT/skills" "$REPO_ROOT/wiki" "$REPO_ROOT/mnemon" "$REPO_ROOT/memories"
    echo "test" > "$REPO_ROOT/skills/test_skill.md"
    echo "test" > "$REPO_ROOT/wiki/test_wiki.md"
    echo "test" > "$REPO_ROOT/mnemon/test_mnemon.json"
    echo "test" > "$REPO_ROOT/memories/test_memory.md"

    # Setup: create a fake HOME with knowledge.env pointing to repo
    TEST_HOME="/tmp/test_home_$$"
    mkdir -p "$TEST_HOME/.minions/etc" "$TEST_HOME/.minions/var/run" "$TEST_HOME/.minions/var/log"
    echo "MODE=dev" > "$TEST_HOME/.minions/etc/knowledge.env"
    echo "MINIONS_REPO_ROOT=$REPO_ROOT" >> "$TEST_HOME/.minions/etc/knowledge.env"

    # Call the real function
    setup_knowledge_symlinks "$TEST_HOME/.minions" "$REPO_ROOT" "dev"

    # Assertions
    assert_symlink "$TEST_HOME/.minions/skills" "$REPO_ROOT/skills" "skills symlink"
    assert_symlink "$TEST_HOME/.minions/wiki" "$REPO_ROOT/wiki" "wiki symlink"
    assert_symlink "$TEST_HOME/.minions/mnemon" "$REPO_ROOT/mnemon" "mnemon symlink"
    assert_symlink "$TEST_HOME/.minions/memories" "$REPO_ROOT/memories" "memories symlink"

    # Verify content accessible through symlink
    if [ -f "$TEST_HOME/.minions/skills/test_skill.md" ]; then
        echo "  PASS: skills content accessible"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: skills content not accessible"
        FAIL=$((FAIL + 1))
    fi

    # Test: standalone mode does NOT create symlinks
    log_info "Test: standalone mode no symlinks"
    TEST_HOME2="/tmp/test_home2_$$"
    mkdir -p "$TEST_HOME2/.minions/etc" "$TEST_HOME2/.minions/var/run" "$TEST_HOME2/.minions/var/log"
    echo "MODE=standalone" > "$TEST_HOME2/.minions/etc/knowledge.env"
    echo "MINIONS_REPO_ROOT=" >> "$TEST_HOME2/.minions/etc/knowledge.env"

    setup_knowledge_symlinks "$TEST_HOME2/.minions" "" "standalone"

    if [ ! -L "$TEST_HOME2/.minions/skills" ] && [ ! -L "$TEST_HOME2/.minions/wiki" ]; then
        echo "  PASS: no symlinks in standalone mode"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: symlinks created in standalone mode"
        FAIL=$((FAIL + 1))
    fi

    # Test: dev mode with missing MINIONS_REPO_ROOT does nothing
    log_info "Test: dev mode missing repo root does nothing"
    TEST_HOME3="/tmp/test_home3_$$"
    mkdir -p "$TEST_HOME3/.minions/etc" "$TEST_HOME3/.minions/var/run" "$TEST_HOME3/.minions/var/log"
    echo "MODE=dev" > "$TEST_HOME3/.minions/etc/knowledge.env"
    echo "MINIONS_REPO_ROOT=" >> "$TEST_HOME3/.minions/etc/knowledge.env"

    setup_knowledge_symlinks "$TEST_HOME3/.minions" "" "dev"

    if [ ! -L "$TEST_HOME3/.minions/skills" ]; then
        echo "  PASS: no symlinks when MINIONS_REPO_ROOT empty"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: symlinks created with empty repo root"
        FAIL=$((FAIL + 1))
    fi

    # Cleanup
    rm -rf "$REPO_ROOT" "$TEST_HOME" "$TEST_HOME2" "$TEST_HOME3"
}

# Run
main() {
    log_info "=== Phase 23 Boot Symlink Unit Tests ==="
    echo ""
    test_dev_mode_symlinks
    echo ""
    log_info "=== Results: $PASS passed, $FAIL failed ==="
    [ "$FAIL" -eq 0 ]
}

main "$@"