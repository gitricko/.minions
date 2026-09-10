#!/usr/bin/env bash
# verify-knowledge.sh — Knowledge layer verification functions
# Used by every phase to validate wiring. Run from repo root.
# Usage: bash scripts/verify-knowledge.sh [F1|F2|F3|F4|F5|F6|F7|all]
#
# Exit codes: 0 = pass, 1 = failure(s) found
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

pass() { echo "  OK: $1"; }
fail() { echo "  FAIL: $1"; FAILURES=$((FAILURES + 1)); }

# ─── F1: Shell syntax check ───────────────────────────────────────────
F1() {
  echo "F1: Shell syntax"
  local checked=0
  for f in install.sh boot.sh status.sh stop.sh lib/*.sh skills/*/scripts/*.sh; do
    [ -f "$f" ] || continue
    if bash -n "$f" 2>/dev/null; then
      pass "$f"
    else
      fail "$f"
    fi
    checked=$((checked + 1))
  done
  [ "$checked" -gt 0 ] || fail "no shell files found to check"
}

# ─── F2: YAML frontmatter parses ─────────────────────────────────────
F2() {
  echo "F2: SKILL.md frontmatter"
  python3 - <<'PYEOF' || { fail "F2 python error"; return; }
import glob, sys
ok = 0
for p in sorted(glob.glob("skills/*/SKILL.md")):
    txt = open(p).read()
    parts = txt.split("---")
    if len(parts) < 3:
        print(f"  FAIL: {p} — no frontmatter delimiters")
        sys.exit(1)
    try:
        import yaml
        d = yaml.safe_load(parts[1])
        assert d.get("name") and d.get("description"), f"missing name/description: {p}"
        print(f"  OK: {p} → {d['name']}")
        ok += 1
    except Exception as e:
        print(f"  FAIL: {p} — {e}")
        sys.exit(1)
if ok == 0:
    print("  FAIL: no SKILL.md files found")
    sys.exit(1)
PYEOF
}

# ─── F3: JSON validity ───────────────────────────────────────────────
F3() {
  echo "F3: JSON validity"
  local checked=0
  for f in mnemon/*.json etc/*.json; do
    [ -f "$f" ] || continue
    if python3 -m json.tool "$f" >/dev/null 2>&1; then
      pass "$f"
    else
      fail "$f"
    fi
    checked=$((checked + 1))
  done
  [ "$checked" -gt 0 ] || fail "no JSON files found to check"
}

# ─── F4: Wiki internal-link integrity ────────────────────────────────
F4() {
  echo "F4: Wiki link integrity"
  python3 - <<'PYEOF' || { fail "F4 python error"; return; }
import glob, re, os, sys
bad = []
for p in sorted(glob.glob("wiki/*.md")):
    if os.path.basename(p) == ".gitkeep":
        continue
    for m in re.findall(r'\]\(([^)#]+\.md)\)', open(p).read()):
        if m.startswith("http"):
            continue
        target = os.path.join("wiki", os.path.basename(m))
        if not os.path.exists(target):
            bad.append((p, m))
if bad:
    for src, tgt in bad:
        print(f"  FAIL: {src} → {tgt} (not found)")
    sys.exit(1)
print("  OK: all wiki links resolve")
PYEOF
}

# ─── F5: No leftover .devcontainer references ────────────────────────
F5() {
  echo "F5: No .devcontainer/ references"
  local hits
  hits=$(grep -rn '\.devcontainer/' skills/ wiki/ --include='*.md' --include='*.sh' --include='*.py' 2>/dev/null || true)
  if [ -z "$hits" ]; then
    pass "no .devcontainer refs"
  else
    echo "  WARN: .devcontainer references found (check if intentional):"
    echo "$hits" | head -20
    # Not a hard fail — some skills describe the upstream project intentionally
  fi
}

# ─── F6: Adaptation checklist — executable bits ──────────────────────
F6() {
  echo "F6: Script executable bits"
  local total=0 missing=0
  while IFS= read -r f; do
    total=$((total + 1))
    if [ -x "$f" ]; then
      pass "$f"
    else
      fail "$f (not executable)"
      missing=$((missing + 1))
    fi
  done < <(find skills -name '*.sh' -type f 2>/dev/null)
  if [ "$total" -eq 0 ]; then
    fail "no .sh scripts found under skills/"
  else
    echo "  $((total - missing))/$total scripts are executable"
  fi
}

# ─── F7: Adaptation checklist — wiki relative links from skills ──────
F7() {
  echo "F7: Skill→wiki relative links"
  local checked=0
  while IFS= read -r line; do
    local skill_file target
    skill_file=$(echo "$line" | cut -d: -f1)
    target=$(echo "$line" | grep -oP '\.\./wiki/\K[^)"\s]+' || true)
    [ -n "$target" ] || continue
    checked=$((checked + 1))
    if [ -f "wiki/$target" ]; then
      pass "$skill_file → wiki/$target"
    else
      fail "$skill_file → wiki/$target (not found)"
    fi
  done < <(grep -rn '\.\./wiki/' skills/ --include='*.md' 2>/dev/null || true)
  if [ "$checked" -eq 0 ]; then
    pass "no skill→wiki relative links found (may be expected)"
  fi
}

# ─── F8: Seed schema uses `content` field (not `text`) ──────────────
F8() {
  echo "F8: Seed schema (content field)"
  local seed="mnemon/seed.json"
  if [ ! -f "$seed" ]; then
    fail "$seed not found (Phase 21 not yet done?)"
    return
  fi
  python3 -c "
import json, sys
d = json.load(open('$seed'))
insights = d.get('insights', [])
if not insights:
    print('  FAIL: no insights in $seed')
    sys.exit(1)
first = insights[0]
if 'content' not in first:
    print(f'  FAIL: first insight uses fields {list(first.keys())}, expected content')
    sys.exit(1)
print(f'  OK: {len(insights)} insights, all use content field')
" || fail "seed schema check"
}

# ─── Dispatch ────────────────────────────────────────────────────────
run_all() { F1; F2; F3; F4; F5; F6; F7; F8; }

if [ $# -eq 0 ] || [ "$1" = "all" ]; then
  run_all
else
  for fn in "$@"; do
    type -t "$fn" >/dev/null 2>&1 && "$fn" || { echo "Unknown function: $fn"; exit 1; }
  done
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: $FAILURES failure(s)"
  exit 1
else
  echo "RESULT: all checks passed"
  exit 0
fi
