#!/usr/bin/env sh
# tests/test_pi_settings.sh — Phase 24 unit tests for Pi-Agent settings.json skills wiring
# Tests lib/pi-settings.sh wire_pi_skills_path: merges "skills": ["<path>"] into
# ~/.pi/agent/settings.json while preserving existing keys (e.g. packages).
#
# RED phase: lib/pi-settings.sh does not exist yet — these all FAIL (helper missing).

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

# JSON read helper using python3 (same dependency install.sh uses for the merge)
json_get() {
    # json_get <file> <python-expr> — prints the result of <python-expr> on the JSON
    python3 -c "import json,sys; d=json.load(open('$1')); print($2)"
}

assert_exit_code() {
    local expected="$1" actual="$2" name="$3"
    if [ "$expected" -eq "$actual" ]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected exit $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# Test: helper creates the settings file if it doesn't exist
wire_creates_missing_file() {
    log_info "Test: helper creates missing settings file"
    local dir="/tmp/pi_settings_created_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_$$"
    mkdir -p "$skills_path"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh
    wire_pi_skills_path "$file" "$skills_path"
    local code=$?

    assert_exit_code 0 "$code" "wire_pi_skills_path exits 0 on missing file"
    if [ -f "$file" ]; then
        echo "  PASS: settings file created"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: settings file not created"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Test: skills array written with the exact path
wire_writes_skills() {
    log_info "Test: skills array written"
    local dir="/tmp/pi_settings_skills_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_2_$$"
    mkdir -p "$skills_path"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh
    wire_pi_skills_path "$file" "$skills_path"

    local actual
    actual="$(json_get "$file" 'd.get("skills", [])')"
    if [ "$actual" = "['$skills_path']" ]; then
        echo "  PASS: skills contains the path"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: skills = $actual, expected ['$skills_path']"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Test: existing packages key is preserved (pi-failover must survive)
wire_preserves_packages() {
    log_info "Test: existing packages preserved"
    local dir="/tmp/pi_settings_pkg_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_3_$$"
    mkdir -p "$skills_path"
    printf '%s\n' '{"packages": ["git:github.com/gitricko/pi-failover@hermes-impl"]}' > "$file"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh
    wire_pi_skills_path "$file" "$skills_path"

    local pkgs
    pkgs="$(json_get "$file" 'd.get("packages", [])')"
    if [ "$pkgs" = "['git:github.com/gitricko/pi-failover@hermes-impl']" ]; then
        echo "  PASS: packages preserved"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: packages = $pkgs, expected pi-failover preserved"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Test: idempotent — second call leaves the file byte-identical
wire_is_idempotent() {
    log_info "Test: idempotent (byte-identical after re-run)"
    local dir="/tmp/pi_settings_idem_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_4_$$"
    mkdir -p "$skills_path"
    printf '%s\n' '{"packages": ["git:github.com/gitricko/pi-failover@hermes-impl"]}' > "$file"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh
    wire_pi_skills_path "$file" "$skills_path"
    local first_hash
    first_hash="$(sha256sum "$file" | cut -d' ' -f1)"

    wire_pi_skills_path "$file" "$skills_path"
    local second_hash
    second_hash="$(sha256sum "$file" | cut -d' ' -f1)"

    if [ "$first_hash" = "$second_hash" ]; then
        echo "  PASS: file byte-identical after second call"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: file changed on second call ($first_hash vs $second_hash)"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Test: dedupe — same path twice in the array becomes one entry
wire_dedupes_skills() {
    log_info "Test: duplicate skills deduped"
    local dir="/tmp/pi_settings_dedupe_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_5_$$"
    mkdir -p "$skills_path"
    printf '%s\n' "{\"skills\": [\"$skills_path\"]}" > "$file"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh
    wire_pi_skills_path "$file" "$skills_path"

    local count
    count="$(json_get "$file" 'len(d.get("skills", []))')"
    if [ "$count" = "1" ]; then
        echo "  PASS: skills array has one entry"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: skills array has $count entries, expected 1"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Test: absolute path kept as-is (no ~-expansion or relative collapse)
wire_keeps_absolute_path() {
    log_info "Test: absolute path stored as-is"
    local dir="/tmp/pi_settings_abs_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_6_$$"
    mkdir -p "$skills_path"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh
    wire_pi_skills_path "$file" "$skills_path"

    local stored
    stored="$(json_get "$file" 'd["skills"][0]')"
    if [ "$stored" = "$skills_path" ]; then
        echo "  PASS: absolute path stored as-is"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: stored = $stored, expected $skills_path"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Test: re-assert — simulate boot.sh re-running after the skills entry was
# removed (drift): helper re-adds it. (Mirrors the boot.sh Phase 24 call.)
wire_reasserts_on_drift() {
    log_info "Test: re-assert re-adds missing skills (boot drift recovery)"
    local dir="/tmp/pi_settings_reassert_$$"
    mkdir -p "$dir"
    local file="$dir/settings.json"
    local skills_path="/tmp/minions_skills_7_$$"
    mkdir -p "$skills_path"

    # shellcheck disable=SC1091
    . /workspaces/.minions/lib/pi-settings.sh

    # First call creates skills
    wire_pi_skills_path "$file" "$skills_path"
    # Simulate drift: user/other process drops the skills entry
    printf '%s\n' '{"packages": ["git:github.com/gitricko/pi-failover@hermes-impl"]}' > "$file"
    # Boot re-assert
    wire_pi_skills_path "$file" "$skills_path"

    local actual
    actual="$(json_get "$file" 'd.get("skills", [])')"
    if [ "$actual" = "['$skills_path']" ]; then
        echo "  PASS: skills re-added after drift"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: skills = $actual after re-assert, expected ['$skills_path']"
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$dir" "$skills_path"
}

# Run
main() {
    log_info "=== Phase 24 Pi Settings Unit Tests ==="
    echo ""
    wire_creates_missing_file
    wire_writes_skills
    wire_preserves_packages
    wire_is_idempotent
    wire_dedupes_skills
    wire_keeps_absolute_path
    wire_reasserts_on_drift
    echo ""
    log_info "=== Results: $PASS passed, $FAIL failed ==="
    [ "$FAIL" -eq 0 ]
}

main "$@"