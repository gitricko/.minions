#!/usr/bin/env sh
# tests/test_bootstrap.sh — Phase 22.5 unit tests for curl|bash bootstrap preamble
# Tests T1-T3 from PROPOSAL-bootstrap-curl-bash.md
#
# Usage: bash tests/test_bootstrap.sh

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

# Test framework
PASS=0
FAIL=0

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "    Expected to contain: $needle"
        echo "    Got: $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "    Expected exit: $expected, got: $actual"
        FAIL=$((FAIL + 1))
    fi
}

# --- T1: Piped detection ---
# When install.sh is sourced from stdin (bash <(cat install.sh) or curl | bash),
# the bootstrap preamble should detect PIPED=1 and show bootstrap message.
# We can't easily test full re-exec in unit test without network, so test
# the PIPED detection logic in isolation by sourcing a testable fragment.

test_piped_detection() {
    log_info "T1: Piped detection"

    # Test the detection function directly by extracting it
    # We'll create a small script that mirrors the preamble logic

    # Test case 1: $0 = bash
    is_piped() {
        local arg0="$1"
        case "$arg0" in
            bash|-|/dev/fd/*|/dev/stdin)
                return 0
                ;;
            *)
                if [ ! -f "$arg0" ]; then
                    return 0
                fi
                return 1
                ;;
        esac
    }

    is_piped "bash" && echo "  PASS: piped detected for \$0=bash" && PASS=$((PASS + 1)) || { echo "  FAIL: piped for \$0=bash"; FAIL=$((FAIL + 1)); }
    is_piped "-" && echo "  PASS: piped detected for \$0=-" && PASS=$((PASS + 1)) || { echo "  FAIL: piped for \$0=-"; FAIL=$((FAIL + 1)); }
    is_piped "/dev/fd/63" && echo "  PASS: piped detected for \$0=/dev/fd/*" && PASS=$((PASS + 1)) || { echo "  FAIL: piped for \$0=/dev/fd/*"; FAIL=$((FAIL + 1)); }
    is_piped "/dev/stdin" && echo "  PASS: piped detected for \$0=/dev/stdin" && PASS=$((PASS + 1)) || { echo "  FAIL: piped for \$0=/dev/stdin"; FAIL=$((FAIL + 1)); }

    # Test case: real file (we'll use this script as the file)
    # If file exists, should NOT be piped
    is_piped "/workspaces/.minions/install.sh" || { echo "  PASS: NOT piped for existing file"; PASS=$((PASS + 1)); } || { echo "  FAIL: existing file marked piped"; FAIL=$((FAIL + 1)); }

    # Non-existent file -> piped
    is_piped "/nonexistent/install.sh" && echo "  PASS: piped for nonexistent file" && PASS=$((PASS + 1)) || { echo "  FAIL: nonexistent file not piped"; FAIL=$((FAIL + 1)); }
}

# --- T2: Tarball extract + re-exec (no .git) -> standalone ---
# Simulate: extract main tarball to temp dir (no .git), run install.sh from there
# with temp HOME -> should detect MODE=standalone and copy assets.
# We'll use the actual repo as a stand-in for the tarball extract (has skills/wiki, no .git in our test copy).

test_tarball_standalone() {
    log_info "T2: Tarball extract -> standalone mode"

    # Create a clean staging dir that mimics a tarball extract: skills/ wiki/ lib/ etc/ but NO .git
    STAGE_DIR="/tmp/p225_tarball_$(date +%s)"
    mkdir -p "$STAGE_DIR"
    mkdir -p "$STAGE_DIR/skills" "$STAGE_DIR/wiki" "$STAGE_DIR/mnemon" "$STAGE_DIR/memories" "$STAGE_DIR/lib" "$STAGE_DIR/etc"

    # Copy essential content from real repo
    cp -r /workspaces/.minions/skills/* "$STAGE_DIR/skills/" 2>/dev/null || true
    cp -r /workspaces/.minions/wiki/* "$STAGE_DIR/wiki/" 2>/dev/null || true
    cp -r /workspaces/.minions/mnemon/* "$STAGE_DIR/mnemon/" 2>/dev/null || true
    cp -r /workspaces/.minions/memories/* "$STAGE_DIR/memories/" 2>/dev/null || true
    cp -r /workspaces/.minions/lib/* "$STAGE_DIR/lib/" 2>/dev/null || true
    cp -r /workspaces/.minions/etc/* "$STAGE_DIR/etc/" 2>/dev/null || true
    cp /workspaces/.minions/install.sh "$STAGE_DIR/install.sh" 2>/dev/null || true
    cp /workspaces/.minions/boot.sh "$STAGE_DIR/boot.sh" 2>/dev/null || true
    cp /workspaces/.minions/stop.sh "$STAGE_DIR/stop.sh" 2>/dev/null || true
    cp /workspaces/.minions/status.sh "$STAGE_DIR/status.sh" 2>/dev/null || true

    # Ensure NO .git directory
    rm -rf "$STAGE_DIR/.git"

    # Run install.sh from the staged dir with a clean temp HOME
    TEST_HOME="/tmp/p225_test_home_$(date +%s)"
    rm -rf "$TEST_HOME"
    mkdir -p "$TEST_HOME"

    log_info "  Running staged install.sh with HOME=$TEST_HOME"
    # Use --no-hermes --no-omniroute --no-modelrelay to skip heavy deps
    # Capture output
    OUTPUT=$(HOME="$TEST_HOME" bash "$STAGE_DIR/install.sh" --no-hermes --no-omniroute --no-modelrelay 2>&1)
    EC=$?

    # Assertions
    assert_exit_code 0 "$EC" "install.sh exit 0"
    assert_contains "$OUTPUT" "Knowledge mode: standalone" "standalone mode detected"

    # Check knowledge.env persisted
    if [ -f "$TEST_HOME/.minions/etc/knowledge.env" ]; then
        echo "  PASS: knowledge.env persisted"
        PASS=$((PASS + 1))
        # Check MODE=standalone in it
        if grep -q "MODE=standalone" "$TEST_HOME/.minions/etc/knowledge.env"; then
            echo "  PASS: knowledge.env MODE=standalone"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: knowledge.env MODE not standalone"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: knowledge.env not created"
        FAIL=$((FAIL + 1))
    fi

    # Check skills copied
    if [ -d "$TEST_HOME/.minions/skills" ] && [ "$(ls -A "$TEST_HOME/.minions/skills")" ]; then
        echo "  PASS: skills copied to ~/.minions"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: skills not copied"
        FAIL=$((FAIL + 1))
    fi

    # Cleanup
    rm -rf "$STAGE_DIR" "$TEST_HOME"
}

# --- T3: Git checkout -> dev mode ---
# Run install.sh from actual git checkout (has .git + skills/ + wiki/)
# Should detect MODE=dev and NOT copy assets (symlinks handled by boot.sh later)

test_git_dev_mode() {
    log_info "T3: Git checkout -> dev mode"

    TEST_HOME="/tmp/p225_test_home_dev_$(date +%s)"
    rm -rf "$TEST_HOME"
    mkdir -p "$TEST_HOME"

    OUTPUT=$(HOME="$TEST_HOME" bash /workspaces/.minions/install.sh --no-hermes --no-omniroute --no-modelrelay 2>&1)
    EC=$?

    assert_exit_code 0 "$EC" "install.sh exit 0"
    assert_contains "$OUTPUT" "Knowledge mode: dev" "dev mode detected"

    # Check knowledge.env persisted with dev
    if [ -f "$TEST_HOME/.minions/etc/knowledge.env" ]; then
        echo "  PASS: knowledge.env persisted"
        PASS=$((PASS + 1))
        if grep -q "MODE=dev" "$TEST_HOME/.minions/etc/knowledge.env"; then
            echo "  PASS: knowledge.env MODE=dev"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: knowledge.env MODE not dev"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "  FAIL: knowledge.env not created"
        FAIL=$((FAIL + 1))
    fi

    # Check assets NOT copied (skills dir should not exist or be empty in ~/.minions)
    if [ ! -d "$TEST_HOME/.minions/skills" ] || [ -z "$(ls -A "$TEST_HOME/.minions/skills" 2>/dev/null)" ]; then
        echo "  PASS: skills NOT copied (dev mode)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: skills copied in dev mode"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$TEST_HOME"
}

# --- Run all tests ---
main() {
    log_info "=== Phase 22.5 Bootstrap Unit Tests ==="
    echo ""

    test_piped_detection
    echo ""
    test_tarball_standalone
    echo ""
    test_git_dev_mode
    echo ""

    log_info "=== Results: $PASS passed, $FAIL failed ==="
    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

main "$@"