#!/usr/bin/env bash
# tests/test_self_update.sh — unit tests for the self-update scaffolding:
#   - etc/deps.yaml catalog integrity vs etc/versions.env
#   - scripts/check-updates.sh (read-only contract)
#   - scripts/bump.sh (hermetic, temp fixtures; dry-run never mutates)
#
# Usage:
#   bash tests/test_self_update.sh
# Exit 0 = all pass; 1 = any failure.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$REPO_ROOT/etc/versions.env"
Y="$REPO_ROOT/etc/deps.yaml"
PASS=0
FAIL=0

ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1 — $2"; }

# ─── Guard fixture helper ──────────────────────────────────────────────
# Copy real versions.env AND deps.yaml into a temp dir; run a fixture
# function (given by NAME) with all env overrides set; clean up;
# propagate exit code.
with_temp_env() { # <fixture-fn-name>
  local fn="$1" tmpdir tmpenv tmpdeps tmpnode rc
  tmpdir="$(mktemp -d)"
  tmpenv="$tmpdir/versions.env"
  tmpdeps="$tmpdir/deps.yaml"
  tmpnode="$tmpdir/.node-version"
  cp "${D}" "$tmpenv"
  cp "${Y}" "$tmpdeps"
  # Do NOT pre-create .node-version — dry-run should not create it,
  # and real-run should write it.
  VERSIONS_ENV="$tmpenv" DEPS_YAML="$tmpdeps" NODE_VERSION_FILE="$tmpnode" \
    "$fn" "$tmpenv" "$tmpdeps" "$tmpnode"
  rc=$?
  rm -rf "$tmpdir"
  return $rc
}

# ─── Test 1: deps.yaml parses as YAML ────────────────────────────
test_deps_yaml_parses() {
  python3 - "${Y}" <<'PY' && ok "deps.yaml is valid YAML" || bad "deps.yaml is valid YAML" "python yaml.load failed"
import sys, yaml
yaml.safe_load(open(sys.argv[1]))
PY
}

# ─── Test 2: every catalog name has a version field ────────────
test_catalog_has_versions() {
  local missing=0 name
  for name in $(python3 - "${Y}" <<'PY'
import sys, yaml
for d in yaml.safe_load(open(sys.argv[1]))["dependencies"]:
    print(d["name"])
PY
  ); do
    grep -q "^  - name: ${name}$" "${Y}" || { echo "  no ${name} entry"; missing=1; }
  done
  [ "$missing" -eq 0 ] && ok "all catalog names have version fields" \
                       || bad "all catalog names have version fields" "found missing entries"
}

# ─── Test 3: check-updates.sh --json emits valid JSON, exit 0 ──
test_check_updates_json() {
  local out
  out="$(bash "${REPO_ROOT}/scripts/check-updates.sh" --json)" || {
    bad "check-updates --json" "non-zero exit"; return
  }
  echo "$out" | python3 -c 'import sys,json; json.load(sys.stdin)' || {
    bad "check-updates --json" "output not valid JSON"; return
  }
  ok "check-updates.sh --json emits valid JSON, exit 0"
}

# ─── Test 4: check-updates.sh fails fast if deps.yaml missing ──
test_check_updates_missing_catalog() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  if VERSIONS_ENV="${D}" DEPS_YAML="$tmpdir/nope.yaml" bash "${REPO_ROOT}/scripts/check-updates.sh" >/dev/null 2>&1; then
    bad "check-updates missing catalog" "expected non-zero exit"
  else
    ok "check-updates.sh fails when catalog missing"
  fi
  rm -rf "$tmpdir"
}

# ─── Test 5: bump.sh requires at least one DEP=VERSION ───────────
test_bump_requires_arg() {
  if bash "${REPO_ROOT}/scripts/bump.sh" >/dev/null 2>&1; then
    bad "bump.sh no-args" "expected usage error/non-zero exit"
  else
    ok "bump.sh with no args exits non-zero"
  fi
}

# ─── Test 6: bump.sh unknown arg exits non-zero ──────────────────
test_bump_unknown_arg() {
  if bash "${REPO_ROOT}/scripts/bump.sh" --bogus NODE=1 >/dev/null 2>&1; then
    bad "bump.sh unknown arg" "expected non-zero exit"
  else
    ok "bump.sh rejects unknown args"
  fi
}

# ─── Test 7: bump.sh rejects bumping a non-existent component ────
test_bump_unknown_component() {
  if bash "${REPO_ROOT}/scripts/bump.sh" NOPE_APP=9.9.9 >/dev/null 2>&1; then
    bad "bump.sh unknown component" "expected non-zero exit"
  else
    ok "bump.sh rejects unknown component"
  fi
}

# ─── Test 8: dry-run must NOT modify versions.env ────────────────
_fixture_dry_run() { # tmpenv tmpdeps tmpnode
  local tmpenv="$1" tmpdeps="$2" tmpnode="$3" before after
  before=$(sha256sum "$tmpenv" | awk '{print $1}')
  if ! VERSIONS_ENV="$tmpenv" DEPS_YAML="$tmpdeps" NODE_VERSION_FILE="$tmpnode" \
      bash "${REPO_ROOT}/scripts/bump.sh" --dry-run NODE=99.0.0 >/dev/null 2>&1; then
    bad "dry-run bump" "non-zero exit"; return 1
  fi
  after=$(sha256sum "$tmpenv" | awk '{print $1}')
  [ "$before" = "$after" ] || { bad "dry-run no mutation" "versions.env checksum changed"; return 1; }
  [ ! -e "$tmpnode" ] || { bad "dry-run no mutation" ".node-version was created"; return 1; }
  # Also verify deps.yaml was NOT modified
  local deps_before=$(sha256sum "${Y}" | awk '{print $1}')
  local deps_after=$(sha256sum "$tmpdeps" | awk '{print $1}')
  [ "$deps_before" = "$deps_after" ] || { bad "dry-run no mutation" "deps.yaml changed"; return 1; }
  ok "bump.sh --dry-run leaves versions.env, deps.yaml and .node-version untouched"
}
test_bump_dry_run_no_mutation() { with_temp_env _fixture_dry_run; }

# ─── Test 9: real run bumps the version line and regenerates .node-version
_fixture_real_write() { # tmpenv tmpdeps tmpnode
  local tmpenv="$1" tmpdeps="$2" tmpnode="$3"
  if ! VERSIONS_ENV="$tmpenv" DEPS_YAML="$tmpdeps" NODE_VERSION_FILE="$tmpnode" \
      bash "${REPO_ROOT}/scripts/bump.sh" NODE=25.0.0 >/dev/null 2>&1; then
    bad "real bump" "non-zero exit"; return 1
  fi
  grep -q '^NODE_VERSION="25.0.0"' "$tmpenv" || { bad "real bump" "versions.env NODE_VERSION not set"; return 1; }
  grep -q 'version: "25.0.0"' "$tmpdeps" || { bad "real bump" "deps.yaml NODE version not set"; return 1; }
  [ "$(cat "$tmpnode")" = "25.0.0" ] || { bad "real bump" ".node-version wrong: $(cat "$tmpnode" 2>/dev/null)"; return 1; }
  ok "bump.sh real run sets NODE_VERSION, deps.yaml, and writes .node-version"
}
test_bump_real_write() { with_temp_env _fixture_real_write; }

# ─── Test 10: bumping NODE_VERSION leaves OTHER pins unchanged ─
_fixture_only_target() { # tmpenv tmpdeps tmpnode
  local tmpenv="$1" tmpdeps="$2" tmpnode="$3" before after
  before=$(grep . "$tmpenv" | sed /^NODE_VERSION=/d | sha256sum | awk '{print $1}')
  if ! VERSIONS_ENV="$tmpenv" DEPS_YAML="$tmpdeps" NODE_VERSION_FILE="$tmpnode" \
      bash "${REPO_ROOT}/scripts/bump.sh" NODE=25.0.0 >/dev/null 2>&1; then
    return 1
  fi
  after=$(grep . "$tmpenv" | sed /^NODE_VERSION=/d | sha256sum | awk '{print $1}')
  [ "$before" = "$after" ] || { bad "bump targets only dep" "other pins changed"; return 1; }
  ok "bump.sh touches only the targeted version line"
}
test_bump_only_touches_target() { with_temp_env _fixture_only_target; }

# ─── Test 11: sync-versions.sh generates versions.env from deps.yaml
test_sync_versions_generates() {
  local tmpdir tmpenv tmpdeps
  tmpdir="$(mktemp -d)"
  tmpenv="$tmpdir/versions.env"
  tmpdeps="$tmpdir/deps.yaml"
  cp "${D}" "$tmpenv"
  cp "${Y}" "$tmpdeps"
  # sync-versions.sh should produce versions.env with NODE_VERSION line
  VERSIONS_ENV="$tmpenv" DEPS_YAML="$tmpdeps" \
    bash "${REPO_ROOT}/scripts/sync-versions.sh" >/dev/null 2>&1 || {
    bad "sync-versions.sh" "non-zero exit"; rm -rf "$tmpdir"; return 1
  }
  grep -q '^NODE_VERSION="22.22.2"' "$tmpenv" || { bad "sync-versions.sh" "NODE_VERSION missing"; rm -rf "$tmpdir"; return 1; }
  grep -q '^UV_VERSION="0.6.14"' "$tmpenv" || { bad "sync-versions.sh" "UV_VERSION missing"; rm -rf "$tmpdir"; return 1; }
  ok "sync-versions.sh generates versions.env from deps.yaml"
  rm -rf "$tmpdir"
}

# ─── Run all ─────────────────────────────────────────────────────
test_deps_yaml_parses
test_catalog_has_versions
test_check_updates_json
test_check_updates_missing_catalog
test_bump_requires_arg
test_bump_unknown_arg
test_bump_unknown_component
test_bump_dry_run_no_mutation
test_bump_real_write
test_bump_only_touches_target
test_sync_versions_generates

echo ""
echo "PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
exit 0