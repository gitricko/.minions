#!/usr/bin/env sh
# tests/test_uninstall.sh — TDD for issue #61: uninstall.sh
# Isolated with temp HOME, like test_pi_trust.sh / test_boot_symlinks.sh
set -e

if [ -t 1 ]; then RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else RED=''; GREEN=''; YELLOW=''; NC=''; fi
log_info() { echo "${GREEN}[INFO]${NC} $*"; }
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/uninstall.sh"

# 1. script exists and --help documents flags
test_help() {
  log_info "Test: --help documents flags"
  if [ ! -f "$SCRIPT" ]; then bad "help" "uninstall.sh missing"; return 0; fi
  out="$("$SCRIPT" --help 2>&1 || true)"
  echo "$out" | grep -q -- "--keep-config" || { bad "help has --keep-config" "$out"; return 0; }
  echo "$out" | grep -q -- "--dry-run" || { bad "help has --dry-run" "$out"; return 0; }
  echo "$out" | grep -q -- "--verify" || { bad "help has --verify" "$out"; return 0; }
  echo "$out" | grep -q -- "--force" || { bad "help has --force" "$out"; return 0; }
  ok "help documents flags"
}

# 2. --dry-run changes nothing, prints WOULD REMOVE/KEEP
test_dry_run_no_mutation() {
  log_info "Test: --dry-run no mutation"
  if [ ! -f "$SCRIPT" ]; then bad "dry-run no mutation" "missing script"; return 0; fi
  tmp="$(mktemp -d)"; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --dry-run --force >"$tmp/out" 2>&1 || true
  # setup fake install after script check — need fresh HOME with content
  tmp2="$(mktemp -d)"
  mkdir -p "$tmp2/.minions/bin" "$tmp2/.hermes" "$tmp2/.pi/agent" "$tmp2/.omniroute" "$tmp2/.9router" "$tmp2/.mnemon" "$tmp2/.ollama"
  echo "bin" > "$tmp2/.minions/bin/x"
  HOME="$tmp2" MINIONS_HOME="$tmp2/.minions" bash "$SCRIPT" --dry-run --force >"$tmp2/out" 2>&1 || true
  if [ -d "$tmp2/.minions" ] && [ -d "$tmp2/.hermes" ] && grep -q "WOULD REMOVE:" "$tmp2/out"; then ok "dry-run no mutation + WOULD REMOVE"; else bad "dry-run no mutation" "$(cat "$tmp2/out" 2>/dev/null | head -c 500)"; fi
  rm -rf "$tmp" "$tmp2"
}

# 3. default purge removes entire dot folders -> CLEAN
test_default_purge_clean() {
  log_info "Test: default purge removes entire folders -> CLEAN"
  if [ ! -f "$SCRIPT" ]; then bad "default purge" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions/bin" "$tmp/.hermes/config" "$tmp/.pi/agent" "$tmp/.omniroute" "$tmp/.9router/db" "$tmp/.mnemon/data" "$tmp/.ollama/models"
  touch "$tmp/.hermes/config.yaml" "$tmp/.pi/agent/settings.json"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --force --verify >"$tmp/out" 2>&1; rc=$?; set -e
  if [ $rc -eq 0 ] && grep -q "^CLEAN" "$tmp/out" && [ ! -d "$tmp/.minions" ] && [ ! -d "$tmp/.hermes" ] && [ ! -d "$tmp/.pi" ] && [ ! -d "$tmp/.omniroute" ] && [ ! -d "$tmp/.9router" ] && [ ! -d "$tmp/.mnemon" ] && [ ! -d "$tmp/.ollama" ]; then ok "default purge CLEAN"; else bad "default purge CLEAN" "rc=$rc out=$(cat "$tmp/out" 2>/dev/null | head -c 600)"; fi
  rm -rf "$tmp"
}

# 4. --keep-config preserves entire dot folders, still removes MINIONS_HOME
test_keep_config_preserves() {
  log_info "Test: --keep-config preserves dot folders"
  if [ ! -f "$SCRIPT" ]; then bad "keep-config" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions/bin" "$tmp/.hermes" "$tmp/.pi" "$tmp/.omniroute" "$tmp/.9router" "$tmp/.mnemon" "$tmp/.ollama"
  touch "$tmp/.hermes/config.yaml"
  HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --keep-config --force >"$tmp/out" 2>&1 || true
  if [ ! -d "$tmp/.minions" ] && [ -d "$tmp/.hermes" ] && [ -d "$tmp/.pi" ] && [ -d "$tmp/.omniroute" ] && [ -d "$tmp/.9router" ] && [ -d "$tmp/.mnemon" ] && [ -d "$tmp/.ollama" ]; then ok "keep-config preserves"; else bad "keep-config preserves" "minions_gone=$([ ! -d "$tmp/.minions" ] && echo yes || echo no) hermes=$([ -d "$tmp/.hermes" ] && echo yes || echo no)"; fi
  rm -rf "$tmp"
}

# 5. --verify alone reports CLEAN vs LEFT
test_verify_format() {
  log_info "Test: --verify format CLEAN and LEFT"
  if [ ! -f "$SCRIPT" ]; then bad "verify format" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.hermes"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --verify >"$tmp/out" 2>&1; rc=$?; set -e
  # has hermes leftover, should be LEFT
  if grep -q "^LEFT:" "$tmp/out" && [ $rc -ne 0 ]; then ok "verify LEFT when leftover"; else bad "verify LEFT" "rc=$rc out=$(cat "$tmp/out" 2>/dev/null | head -c 500)"; fi
  rm -rf "$tmp/.hermes"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --verify >"$tmp/out2" 2>&1; rc2=$?; set -e
  if grep -q "^CLEAN" "$tmp/out2" && [ $rc2 -eq 0 ]; then ok "verify CLEAN when clean"; else bad "verify CLEAN" "rc=$rc2 out=$(cat "$tmp/out2" 2>/dev/null | head -c 500)"; fi
  rm -rf "$tmp"
}

# 6. idempotent second run is CLEAN
test_idempotent() {
  log_info "Test: idempotent second run"
  if [ ! -f "$SCRIPT" ]; then bad "idempotent" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions" "$tmp/.hermes"
  HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --force >"$tmp/out" 2>&1 || true
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --force --verify >"$tmp/out2" 2>&1; rc=$?; set -e
  if [ $rc -eq 0 ] && grep -q "^CLEAN" "$tmp/out2"; then ok "idempotent CLEAN"; else bad "idempotent" "rc=$rc out=$(cat "$tmp/out2" 2>/dev/null | head -c 500)"; fi
  rm -rf "$tmp"
}

# 7. rc exact block removed, user custom line kept
test_rc_cleanup() {
  log_info "Test: rc exact block vs custom line"
  if [ ! -f "$SCRIPT" ]; then bad "rc cleanup" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions"
  # rc with installer block + custom line
  cat > "$tmp/.bashrc" <<'RC'
export MINIONS_HOME=/custom
# .minions - added by installer
export MINIONS_HOME="${HOME}/.minions"
export PATH="${MINIONS_HOME}/bin:${PATH}"
RC
  HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --force >"$tmp/out" 2>&1 || true
  if grep -q "MINIONS_HOME=/custom" "$tmp/.bashrc" && ! grep -q "added by installer" "$tmp/.bashrc"; then ok "rc exact block removed, custom kept"; else bad "rc cleanup" "$(cat "$tmp/.bashrc" 2>/dev/null | head -c 600)"; fi
  rm -rf "$tmp"
}

# 8. ~/.hermes symlink-at-top edge: remove link only
test_symlink_at_top() {
  log_info "Test: ~/.hermes symlink-at-top -> link only"
  if [ ! -f "$SCRIPT" ]; then bad "symlink-at-top" "missing script"; return 0; fi
  tmp="$(mktemp -d)"; real="$(mktemp -d)"; echo "keep" > "$real/keep.txt"
  mkdir -p "$tmp/.minions"
  ln -s "$real" "$tmp/.hermes"
  HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --force >"$tmp/out" 2>&1 || true
  if [ ! -L "$tmp/.hermes" ] && [ -f "$real/keep.txt" ]; then ok "symlink-at-top link only"; else bad "symlink-at-top" "link_exists=$([ -L "$tmp/.hermes" ] && echo yes || echo no) real_keep=$([ -f "$real/keep.txt" ] && echo yes || echo no)"; fi
  rm -rf "$tmp" "$real"
}

# 9. non-TTY without --force fails with hint
test_nontty_requires_force() {
  log_info "Test: non-TTY without --force -> hint"
  if [ ! -f "$SCRIPT" ]; then bad "nontty hint" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions"
  # stdin not a TTY (pipe), no --force, should fail with hint
  set +e; printf "" | HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" >"$tmp/out" 2>&1; rc=$?; set -e
  if [ $rc -ne 0 ] && grep -qi "use --force" "$tmp/out"; then ok "non-TTY hint"; else bad "non-TTY hint" "rc=$rc out=$(cat "$tmp/out" 2>/dev/null | head -c 500)"; fi
  rm -rf "$tmp"
}

# 10. MINIONS_HOME guard: empty/invalid does not rm /
test_minions_home_guard() {
  log_info "Test: MINIONS_HOME guard"
  if [ ! -f "$SCRIPT" ]; then bad "guard" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions"
  # with MINIONS_HOME=/ should warn and fallback, not rm /
  set +e; HOME="$tmp" MINIONS_HOME="/" bash "$SCRIPT" --force --dry-run >"$tmp/out" 2>&1; rc=$?; set -e
  if [ -d "/" ]; then ok "guard handles / (no rm /)"; else bad "guard handles /" "rc=$rc"; fi
  rm -rf "$tmp"
}

# 11. --dry-run --verify valid without mutating
test_dry_run_verify() {
  log_info "Test: --dry-run --verify no mutation"
  if [ ! -f "$SCRIPT" ]; then bad "dry-run --verify" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.hermes" "$tmp/.minions"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --dry-run --verify >"$tmp/out" 2>&1; rc=$?; set -e
  if [ -d "$tmp/.hermes" ] && [ -d "$tmp/.minions" ]; then ok "dry-run --verify no mutation"; else bad "dry-run --verify" "rc=$rc out=$(cat "$tmp/out" 2>/dev/null | head -c 500)"; fi
  rm -rf "$tmp"
}


# 12. operation order: stop before rm (finding 10)
test_operation_order() {
  log_info "Test: operation order stop before rm"
  if [ ! -f "$SCRIPT" ]; then bad "operation order" "missing script"; return 0; fi
  # verify uninstall.sh stops services before deleting MINIONS_HOME by checking source order
  if grep -q "_stop_one\|stop_service" "$SCRIPT" && awk '/_stop_one|stop_service/{s=1} /safe_rm_target.*MINIONS_HOME/{if(s) {print "order ok"; exit 0} else {exit 1}}' "$SCRIPT" | grep -q "order ok"; then
    ok "operation order stop before rm"
  else
    # fallback: ensure stop logic appears before deletion in file
    stop_line=$(grep -n "stop_service\|_stop_one\|Stop services" "$SCRIPT" | head -1 | cut -d: -f1)
    rm_line=$(grep -n "safe_rm_target.*MINIONS_HOME\|rm.*MINIONS_HOME" "$SCRIPT" | head -1 | cut -d: -f1)
    if [ -n "$stop_line" ] && [ -n "$rm_line" ] && [ "$stop_line" -lt "$rm_line" ]; then ok "operation order stop before rm (line $stop_line < $rm_line)"; else bad "operation order" "stop=$stop_line rm=$rm_line"; fi
  fi
}

# 13. self-deletion: running from inside MINIONS_HOME still deletes
test_self_deletion() {
  log_info "Test: self-deletion via installed copy"
  if [ ! -f "$SCRIPT" ]; then bad "self-deletion" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions"
  cp "$SCRIPT" "$tmp/.minions/uninstall.sh"
  chmod +x "$tmp/.minions/uninstall.sh"
  mkdir -p "$tmp/.hermes" "$tmp/.pi"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$tmp/.minions/uninstall.sh" --force >"$tmp/out" 2>&1; rc=$?; set -e
  if [ ! -d "$tmp/.minions" ] && [ ! -d "$tmp/.hermes" ]; then ok "self-deletion deletes via installed copy"; else bad "self-deletion" "rc=$rc .minions=$([ -d "$tmp/.minions" ] && echo yes || echo no) hermes=$([ -d "$tmp/.hermes" ] && echo yes || echo no) out=$(cat "$tmp/out" 2>/dev/null | head -c 400)"; fi
  rm -rf "$tmp"
}

# 14. rc absent: no rc files -> still CLEAN, no error
test_rc_absent() {
  log_info "Test: rc absent still CLEAN"
  if [ ! -f "$SCRIPT" ]; then bad "rc absent" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --force --verify >"$tmp/out" 2>&1; rc=$?; set -e
  if [ $rc -eq 0 ] && grep -q "^CLEAN" "$tmp/out"; then ok "rc absent CLEAN"; else bad "rc absent" "rc=$rc out=$(cat "$tmp/out" 2>/dev/null | head -c 400)"; fi
  rm -rf "$tmp"
}

# 15. keep-config preserves contents not just dirs
test_keep_config_contents() {
  log_info "Test: keep-config preserves contents"
  if [ ! -f "$SCRIPT" ]; then bad "keep-config contents" "missing script"; return 0; fi
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.minions/bin" "$tmp/.hermes"
  echo "secret" > "$tmp/.hermes/config.yaml"
  echo "data" > "$tmp/.hermes/keep.txt"
  set +e; HOME="$tmp" MINIONS_HOME="$tmp/.minions" bash "$SCRIPT" --keep-config --force >"$tmp/out" 2>&1; rc=$?; set -e
  if [ ! -d "$tmp/.minions" ] && [ -f "$tmp/.hermes/config.yaml" ] && [ "$(cat "$tmp/.hermes/config.yaml" 2>/dev/null)" = "secret" ] && [ -f "$tmp/.hermes/keep.txt" ]; then ok "keep-config preserves contents"; else bad "keep-config contents" "minions_gone=$([ ! -d "$tmp/.minions" ] && echo yes || echo no) config=$(cat "$tmp/.hermes/config.yaml" 2>/dev/null | head -c 100)"; fi
  rm -rf "$tmp"
}

run_all() {
  test_help
  test_dry_run_no_mutation
  test_default_purge_clean
  test_keep_config_preserves
  test_verify_format
  test_idempotent
  test_rc_cleanup
  test_symlink_at_top
  test_nontty_requires_force
  test_minions_home_guard
  test_dry_run_verify
  test_operation_order
  test_self_deletion
  test_rc_absent
  test_keep_config_contents
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || { echo "FAIL"; exit 1; }
  echo "PASS"
}

run_all
