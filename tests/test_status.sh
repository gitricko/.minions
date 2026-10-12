#!/usr/bin/env bash
# tests/test_status.sh — TDD tests for status consolidation (#66)
# Seam: status.sh as invoked (output + exit code), boot.sh footer, lib/status-lib.sh
# Run: bash tests/test_status.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
TMPDIR_BASE="${TMPDIR:-/tmp}"

ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1 — $2"; }

# Helper: run status.sh with a temp MINIONS_HOME and PATH mocks
# Usage: run_status <tmp_home> [extra_env]
# Returns output in $out, rc in $rc
run_status() {
  local mh="$1"
  shift || true
  # shellcheck disable=SC2016
  out=$(MINIONS_HOME="$mh" bash "${REPO_ROOT}/status.sh" 2>&1); rc=$?
}

# ── Setup helpers ──
make_fake_bin() {
  local dir="$1" name="$2" version_output="$3"
  mkdir -p "$dir"
  cat > "$dir/$name" <<EOF
#!/bin/sh
echo "$version_output"
EOF
  chmod +x "$dir/$name"
}

make_listener() {
  # Start a tiny TCP listener on a random port via python3, print port, return pid in $listener_pid
  listener_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  python3 -c "import socket, time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('127.0.0.1', $listener_port)); s.listen(1); time.sleep(30)" &
  listener_pid=$!
  sleep 0.3
}

kill_listener() {
  kill "$listener_pid" 2>/dev/null || true
  wait "$listener_pid" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────
# Test 1: No truncation when omniroute down — full report printed
test_no_truncation_when_down() {
  local tmp; tmp=$(mktemp -d -t status-XXXXXX)
  local mh="$tmp/.minions"; mkdir -p "$mh/var/run" "$mh/etc" "$mh/bin"
  # No omniroute pid, but create 9router pid that is alive (use current shell pid)
  echo "$$" > "$mh/var/run/9router.pid"
  # Keep tailscale absent so it doesn't dominate
  local fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
  make_fake_bin "$fakebin" "pi" "1.1.0"
  make_fake_bin "$fakebin" "hermes" "Hermes Agent v0.21.5 (2026.9.24) · upstream 7770e397"
  PATH="$fakebin:$PATH" MINIONS_HOME="$mh" bash "${REPO_ROOT}/status.sh" >"$tmp/out" 2>&1; rc=$?
  local out; out=$(cat "$tmp/out")
  # Must contain 9router, pi-agent, hermes, READY even though omniroute down
  if echo "$out" | grep -qi "9router" && echo "$out" | grep -qi "pi-agent" && echo "$out" | grep -qi "hermes"; then
    ok "test_no_truncation_when_down — later rows still printed when omniroute down"
  else
    bad "test_no_truncation_when_down" "output truncated when omniroute down: $out"
  fi
  # Also must contain READY line
  if echo "$out" | grep -q "READY"; then
    ok "test_no_truncation_includes_ready"
  else
    bad "test_no_truncation_includes_ready" "READY line missing after omniroute down: $out"
  fi
  rm -rf "$tmp"
}

# Test 2: Single icon per service (not two rows)
test_single_icon_per_service() {
  local tmp; tmp=$(mktemp -d -t status-XXXXXX)
  local mh="$tmp/.minions"; mkdir -p "$mh/var/run" "$mh/etc" "$mh/bin"
  echo "$$" > "$mh/var/run/omniroute.pid"
  echo "$$" > "$mh/var/run/9router.pid"
  # Start listeners to make ports open so healthy row is ✅
  local saved_port_omni="${OMNIROUTE_PORT:-20128}" saved_port_9r="${NINEROUTER_PORT:-7352}"
  # Use a free port for testing to avoid colliding with real services
  make_listener
  local test_port="$listener_port"
  # Probe via status.sh env override: point omniroute to our test listener
  local fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
  make_fake_bin "$fakebin" "pi" "1.1.0"
  make_fake_bin "$fakebin" "hermes" "Hermes Agent v0.21.5 (2026.9.24) · upstream 7770e397"
  PATH="$fakebin:$PATH" MINIONS_HOME="$mh" OMNIROUTE_PORT="$test_port" NINEROUTER_PORT="$test_port" bash "${REPO_ROOT}/status.sh" >"$tmp/out" 2>&1 || true
  local out; out=$(cat "$tmp/out")
  kill_listener
  # Count omniroute occurrences — should be one line containing omniroute
  local omni_lines; omni_lines=$(echo "$out" | grep -ci "omniroute" || true)
  if [ "$omni_lines" -eq 1 ]; then
    ok "test_single_icon_per_service — omniroute appears once"
  else
    bad "test_single_icon_per_service" "expected omniroute once, got $omni_lines: $out"
  fi
  # After fix, a healthy omniroute should be one ✅ row, not ❌ then ✅ on next line
  # Detect the bug pattern: omniroute line followed by ❌ on next line and ✅ on the line after
  if echo "$out" | grep -A2 "omniroute" | grep -q "❌" && echo "$out" | grep -A3 "omniroute" | grep -q "✅ (pid"; then
    # If both appear near omniroute, it's the bug (two rows)
    # With fix, omniroute's ✅ and pid are on the SAME line
    if echo "$out" | grep "omniroute" | grep -q "✅.*pid"; then
      ok "test_single_icon_combined_row"
    else
      bad "test_single_icon_combined_row" "bug: omniroute ❌ and ✅ on separate lines: $out"
    fi
  else
    # No ❌ near omniroute in healthy case is also OK if single ✅ row
    if echo "$out" | grep "omniroute" | grep -q "✅"; then
      ok "test_single_icon_combined_row"
    else
      bad "test_single_icon_combined_row" "no ✅ found for healthy omniroute: $out"
    fi
  fi
  rm -rf "$tmp"
}

# Test 3: ollama + mnemon rows present
test_ollama_mnemon_rows() {
  local tmp; tmp=$(mktemp -d -t status-XXXXXX)
  local mh="$tmp/.minions"; mkdir -p "$mh/var/run" "$mh/etc" "$mh/bin"
  echo "$$" > "$mh/var/run/omniroute.pid"
  echo "$$" > "$mh/var/run/9router.pid"
  local fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
  make_fake_bin "$fakebin" "pi" "1.1.0"
  make_fake_bin "$fakebin" "hermes" "Hermes Agent v0.21.5 (2026.9.24) · upstream 7770e397"
  # Provide ollama + mnemon bins
  make_fake_bin "$fakebin" "ollama" "ollama version is 0.40.3"
  make_fake_bin "$fakebin" "mnemon" "mnemon version 0.2.10"
  mkdir -p "$tmp/home/.mnemon" # mnemon DB marker
  HOME="$tmp/home" PATH="$fakebin:$PATH" MINIONS_HOME="$mh" bash "${REPO_ROOT}/status.sh" >"$tmp/out" 2>&1 || true
  local out; out=$(cat "$tmp/out")
  if echo "$out" | grep -qi "ollama"; then
    ok "test_ollama_row_present"
  else
    bad "test_ollama_row_present" "ollama row missing: $out"
  fi
  if echo "$out" | grep -qi "mnemon"; then
    ok "test_mnemon_row_present"
  else
    bad "test_mnemon_row_present" "mnemon row missing: $out"
  fi
  rm -rf "$tmp"
}

# Test 4: Versions for omniroute + 9router shown
test_versions_omniroute_9router() {
  local tmp; tmp=$(mktemp -d -t status-XXXXXX)
  local mh="$tmp/.minions"; mkdir -p "$mh/var/run" "$mh/etc" "$mh/bin"
  echo "$$" > "$mh/var/run/omniroute.pid"
  echo "$$" > "$mh/var/run/9router.pid"
  # Provide versioned bins
  local fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
  make_fake_bin "$fakebin" "omniroute" "3.8.51"
  make_fake_bin "$fakebin" "9router" "0.5.99"
  make_fake_bin "$fakebin" "pi" "1.1.0"
  make_fake_bin "$fakebin" "hermes" "Hermes Agent v0.21.5 (2026.9.24) · upstream 7770e397"
  ln -sf "$fakebin/omniroute" "$mh/bin/omniroute"
  ln -sf "$fakebin/9router" "$mh/bin/9router"
  # Provide versions.env fallback too
  cat > "$mh/etc/versions.env" <<EOF
OMNIROUTE_VERSION="3.8.51"
NINEROUTER_VERSION="0.5.99"
EOF
  HOME="$tmp/home" PATH="$fakebin:$PATH" MINIONS_HOME="$mh" bash "${REPO_ROOT}/status.sh" >"$tmp/out" 2>&1 || true
  local out; out=$(cat "$tmp/out")
  if echo "$out" | grep -q "3.8.51"; then
    ok "test_versions_omniroute"
  else
    bad "test_versions_omniroute" "omniroute version not shown: $out"
  fi
  if echo "$out" | grep -q "0.5.99"; then
    ok "test_versions_9router"
  else
    bad "test_versions_9router" "9router version not shown: $out"
  fi
  rm -rf "$tmp"
}

# Test 5: Exit codes per severity (0 ok, 1 warn, 2 critical)
test_exit_codes() {
  local tmp; tmp=$(mktemp -d -t status-XXXXXX)
  local mh="$tmp/.minions"; mkdir -p "$mh/var/run" "$mh/etc" "$mh/bin"
  local fakebin="$tmp/fakebin"; mkdir -p "$fakebin"
  make_fake_bin "$fakebin" "pi" "1.1.0"
  make_fake_bin "$fakebin" "hermes" "Hermes Agent v0.21.5 (2026.9.24) · upstream 7770e397"
  # Healthy: both pids alive, use live ports or fake them
  echo "$$" > "$mh/var/run/omniroute.pid"
  echo "$$" > "$mh/var/run/9router.pid"
  touch "$mh/var/run/ready"
  # Need ports open — use listener and env override
  make_listener; local p="$listener_port"
  PATH="$fakebin:$PATH" MINIONS_HOME="$mh" OMNIROUTE_PORT="$p" NINEROUTER_PORT="$p" bash "${REPO_ROOT}/status.sh" >/dev/null 2>&1; rc=$?
  kill_listener
  if [ "$rc" -eq 0 ]; then ok "test_exit_code_healthy_0"; else bad "test_exit_code_healthy_0" "expected 0, got $rc"; fi
  # Critical: remove omniroute pid + block port (use closed port 9)
  rm -f "$mh/var/run/omniroute.pid"
  PATH="$fakebin:$PATH" MINIONS_HOME="$mh" OMNIROUTE_PORT="9" NINEROUTER_PORT="$p" bash "${REPO_ROOT}/status.sh" >/dev/null 2>&1; rc=$?
  # Need 9router still healthy, so use listener again for 9router
  if [ "$rc" -eq 2 ]; then ok "test_exit_code_critical_2"; else bad "test_exit_code_critical_2" "expected 2 when omniroute down, got $rc"; fi
  rm -rf "$tmp"
}

# Test 6: Port probe dash fix — lib must use bash fallback, not broken /dev/tcp
test_port_probe_lib() {
  if [ -f "${REPO_ROOT}/lib/status-lib.sh" ]; then
    if grep -q 'bash -c "exec 3<>/dev/tcp' "${REPO_ROOT}/lib/status-lib.sh"; then
      ok "test_port_probe_uses_bash_fallback"
    else
      bad "test_port_probe_uses_bash_fallback" "lib/status-lib.sh missing bash -c fallback"
    fi
    if grep -q '(echo > "/dev/tcp' "${REPO_ROOT}/lib/status-lib.sh"; then
      bad "test_port_probe_no_broken_fallback" "lib still contains broken (echo > /dev/tcp) under dash"
    else
      ok "test_port_probe_no_broken_fallback"
    fi
  else
    bad "test_port_probe_lib_exists" "lib/status-lib.sh not found"
  fi
}

# Test 7: boot.sh footer uses status-lib (truthful)
test_boot_footer_truthful() {
  if grep -q "status-lib.sh" "${REPO_ROOT}/boot.sh" && grep -q "status_collect" "${REPO_ROOT}/boot.sh"; then
    ok "test_boot_footer_uses_status_lib"
  else
    bad "test_boot_footer_uses_status_lib" "boot.sh does not source status-lib or call status_collect"
  fi
  if grep -q "DEGRADED" "${REPO_ROOT}/boot.sh" && grep -q "stack is UP" "${REPO_ROOT}/boot.sh"; then
    ok "test_boot_footer_keeps_grep_string"
  else
    bad "test_boot_footer_keeps_grep_string" "boot.sh missing DEGRADED/stack is UP compat strings"
  fi
}

# Test 8: status-lib invariants — no exit, status_collect returns 0 when degraded
test_status_lib_invariants() {
  if [ -f "${REPO_ROOT}/lib/status-lib.sh" ]; then
    if grep -qE '^\s*exit' "${REPO_ROOT}/lib/status-lib.sh"; then
      bad "test_lib_no_exit" "lib/status-lib.sh contains bare exit (must not — callers decide)"
    else
      ok "test_lib_no_exit"
    fi
    if grep -q "status_collect" "${REPO_ROOT}/lib/status-lib.sh"; then
      ok "test_lib_has_status_collect"
    else
      bad "test_lib_has_status_collect" "lib missing status_collect"
    fi
    if grep -q "status_exit_code" "${REPO_ROOT}/lib/status-lib.sh"; then
      ok "test_lib_has_status_exit_code"
    else
      bad "test_lib_has_status_exit_code" "lib missing status_exit_code"
    fi
  else
    bad "test_lib_exists" "lib/status-lib.sh not found"
  fi
}

# Test 9: status.sh thin wrapper — no set -e, single row, --help
test_status_sh_wrapper() {
  if grep -q "^set -e" "${REPO_ROOT}/status.sh"; then
    bad "test_status_sh_no_set_e" "status.sh still has set -e (must not — reporter must not abort)"
  else
    ok "test_status_sh_no_set_e"
  fi
  if grep -q "status-lib.sh" "${REPO_ROOT}/status.sh"; then
    ok "test_status_sh_sources_lib"
  else
    bad "test_status_sh_sources_lib" "status.sh does not source status-lib.sh"
  fi
  if bash "${REPO_ROOT}/status.sh" --help 2>&1 | grep -q "Usage"; then
    ok "test_status_sh_help"
  else
    bad "test_status_sh_help" "--help missing or no Usage"
  fi
}

# ── Run ──
echo "════════════════════════════════════════════════════════════"
echo " Status Consolidation Tests (#66) — TDD red phase"
echo " Repo: ${REPO_ROOT}"
echo "════════════════════════════════════════════════════════════"
test_no_truncation_when_down
test_single_icon_per_service
test_ollama_mnemon_rows
test_versions_omniroute_9router
test_exit_codes
test_port_probe_lib
test_boot_footer_truthful
test_status_lib_invariants
test_status_sh_wrapper

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -eq 0 ]; then echo "Status: GREEN"; exit 0; fi
echo "Status: RED (expected before fix)"
exit 1
