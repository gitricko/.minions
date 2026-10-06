#!/usr/bin/env sh
# tests/test_pi_trust.sh — TDD for issue #49: pi defaultProjectTrust: always
# Seam: lib/pi-settings.sh::wire_pi_default_trust_always SETTINGS_FILE
set -e

if [ -t 1 ]; then RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else RED=''; GREEN=''; YELLOW=''; NC=''; fi
log_info() { echo "${GREEN}[INFO]${NC} $*"; }
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

# Minimal stubs so lib/pi-settings.sh can source (it calls log_warn/log_info)
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }

# Source helper under test
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/pi-settings.sh"

# 1. fresh file (no file) -> creates defaultProjectTrust: always
test_fresh_no_file() {
  log_info "Test: fresh (no file) -> always"
  d="$(mktemp -d)"; f="$d/settings.json"
  wire_pi_default_trust_always "$f"
  if [ -f "$f" ] && python3 -c "import json; assert json.load(open('$f')).get('defaultProjectTrust')=='always'" 2>/dev/null; then ok "fresh no-file creates always"
  else bad "fresh no-file creates always" "$(cat "$f" 2>/dev/null || echo no file)"; fi
  rm -rf "$d"
}

# 2. existing file with defaultProjectTrust: ask -> upgraded to always, skills preserved
test_upgrade_ask_preserves_skills() {
  log_info "Test: upgrade ask -> always, preserve skills+packages"
  d="$(mktemp -d)"; f="$d/settings.json"
  python3 - "$f" <<'PY'
import json,sys
json.dump({"defaultProjectTrust":"ask","skills":["/tmp/skills"],"packages":["git:github.com/x/y@main"],"lastChangelogVersion":"1.2.3"}, open(sys.argv[1],"w"), indent=2)
PY
  wire_pi_default_trust_always "$f"
  python3 - "$f" <<'PY' || { bad "ask upgraded — py assertion failed" "$(cat "$f" 2>/dev/null | head -c 500)"; rm -rf "$d"; return 0; }
import json,sys
d=json.load(open(sys.argv[1]))
assert d.get("defaultProjectTrust")=="always", d
assert d.get("skills")==["/tmp/skills"], d
assert d.get("packages")==["git:github.com/x/y@main"], d
assert d.get("lastChangelogVersion")=="1.2.3", d
print("  PASS: ask upgraded, keys preserved")
PY
  # shellcheck: verify from shell too
  if python3 -c "import json; d=json.load(open('$f')); assert d['defaultProjectTrust']=='always' and d['skills']==['/tmp/skills']" 2>/dev/null; then
    ok "ask upgraded without dropping keys"
  else
    bad "ask upgraded without dropping keys" "$(cat "$f")"
  fi
  rm -rf "$d"
}

# 3. idempotent re-run (already always) -> unchanged (still always, single write is fine)
test_idempotent_already_always() {
  log_info "Test: idempotent when already always"
  d="$(mktemp -d)"; f="$d/settings.json"
  printf '{"defaultProjectTrust":"always","skills":["/a"]}\n' > "$f"
  wire_pi_default_trust_always "$f"
  wire_pi_default_trust_always "$f"
  if python3 -c "import json; d=json.load(open('$f')); assert d['defaultProjectTrust']=='always' and d['skills']==['/a']" 2>/dev/null; then ok "idempotent already always"
  else bad "idempotent already always" "$(cat "$f")"; fi
  rm -rf "$d"
}

# 4. file with skills+packages but no trust key -> adds always, preserves both
test_adds_always_preserves_existing() {
  log_info "Test: adds always when missing, preserves skills+packages"
  d="$(mktemp -d)"; f="$d/settings.json"
  printf '{"skills":["/a/b"],"packages":["git:github.com/x/y@main"]}\n' > "$f"
  wire_pi_default_trust_always "$f"
  if python3 -c "import json; d=json.load(open('$f')); assert d['defaultProjectTrust']=='always' and d['skills']==['/a/b'] and 'packages' in d" 2>/dev/null; then ok "adds always preserves skills+packages"
  else bad "adds always preserves skills+packages" "$(cat "$f")"; fi
  rm -rf "$d"
}

# 5. empty/corrupt file -> recovers to always
test_empty_file() {
  log_info "Test: empty file recovers to always"
  d="$(mktemp -d)"; f="$d/settings.json"
  mkdir -p "$(dirname "$f")"; printf '' > "$f"
  wire_pi_default_trust_always "$f"
  if python3 -c "import json; assert json.load(open('$f')).get('defaultProjectTrust')=='always'" 2>/dev/null; then ok "empty file recovers"
  else bad "empty file recovers" "$(cat "$f" 2>/dev/null | head -c 500)"; fi
  rm -rf "$d"
}

main() {
  echo ""; log_info "=== Pi Trust tests (issue #49) ==="; echo ""
  test_fresh_no_file
  test_upgrade_ask_preserves_skills
  test_idempotent_already_always
  test_adds_always_preserves_existing
  test_empty_file
  echo ""
  log_info "=== Results: $PASS passed, $FAIL failed ==="
  [ "$FAIL" -eq 0 ]
}
main "$@"
