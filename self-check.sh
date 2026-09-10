#!/usr/bin/env bash
# self-check.sh — .minions boot-time health diagnostics
# Ported from hermes-codespace, adapted for .minions.
#
# Probes all components of the .minions stack and produces a
# human-readable health report + machine-parseable JSON summary.
#
# Flags:
#   --ci  — skip service port probes (no services in CI), only validate
#            file/symlink/config existence.
#
# Exit codes:
#   0  — all checks passed (or only warnings)
#   1  — one or more warnings (disk, cron, missing optional)
#   2  — one or more critical failures (missing required files, broken symlinks)

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
CI_MODE=false
[ "${1:-}" = "--ci" ] && CI_MODE=true

SKIP_CHECKS="${MINIONS_SKIP_CHECKS:-}"
DISK_WARN_PCT="${MINIONS_DISK_WARN_PCT:-85}"

HERMES_CONFIG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
REPORT_FILE="/tmp/health-report.json"
MINIONS_HOME="${MINIONS_HOME:-$HOME/.minions}"

# Colours (disabled if stderr is not a terminal, e.g. CI)
if [ -t 2 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BOLD=''; NC=''
fi

# ── State ────────────────────────────────────────────────────────────────────
CRITICAL=0
WARNINGS=0
JSON_RESULTS='[]'
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Helpers ──────────────────────────────────────────────────────────────────
_ok()   { local label="$1" msg="$2"; printf "  ${GREEN}✅${NC} %-18s %s\n" "$label" "$msg"; }
_warn() { local label="$1" msg="$2"; printf "  ${YELLOW}⚠️ ${NC}%-18s %s\n" "$label" "$msg"; ((WARNINGS++)) || true; }
_fail() { local label="$1" msg="$2"; printf "  ${RED}❌${NC} %-18s %s\n" "$label" "$msg"; ((CRITICAL++)) || true; }

json_add() {
  local name="$1" status="$2" message="$3" detail="${4:-null}"
  JSON_RESULTS=$(echo "$JSON_RESULTS" | python3 -c "
import json,sys
results = json.loads(sys.stdin.read())
results.append({
  'name': '$name',
  'status': '$status',
  'message': '$(echo "$message" | sed "s/'/\\\\'/g")',
  'detail': $detail
})
print(json.dumps(results))
")
}

should_skip() {
  local name="$1"
  [ -z "$SKIP_CHECKS" ] && return 1
  for s in $(echo "$SKIP_CHECKS" | tr ',' ' '); do
    [ "$s" = "$name" ] && return 0
  done
  return 1
}

section() {
  echo ""
  echo " ${BOLD}$1${NC}"
  echo " ───────────────────────────────────────────────"
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo " ════════════════════════════════════════════════════════════"
echo "  ${BOLD}.MINIONS HEALTH REPORT${NC}"
echo "  $(date -u)"
[ "$CI_MODE" = "true" ] && echo "  ${YELLOW}CI MODE — service ports skipped${NC}"
echo " ════════════════════════════════════════════════════════════"

# ── 1. Services ──────────────────────────────────────────────────────────────
section "Services"

if ! should_skip "services" && [ "$CI_MODE" = "false" ]; then
  PORT_POLL_TIMEOUT=30
  POLL_STARTED_AT=$(date +%s)

  for pair in "7352:ModelRelay" "20128:OmniRoute"; do
    PORT="${pair%%:*}"
    NAME="${pair##*:}"
    RESPONDED=false

    for _attempt in 1 2 3 4 5 6; do
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${PORT}" 2>/dev/null || HTTP_CODE="000")
      HTTP_CODE=$(echo "$HTTP_CODE" | tr -d '[:space:]')
      if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
        RESPONDED=true
        break
      fi
      sleep 5
    done

    if [ "$RESPONDED" = "true" ]; then
      _ok "$NAME" ":$PORT — HTTP ${HTTP_CODE}"
      json_add "service:${NAME}" "ok" "HTTP ${HTTP_CODE}" "{\"port\":${PORT},\"http_code\":${HTTP_CODE}}"
    else
      _fail "$NAME" ":$PORT — no response"
      json_add "service:${NAME}" "fail" "no response" "{\"port\":${PORT}}"
    fi
  done
elif [ "$CI_MODE" = "true" ]; then
  echo "   (skipped — CI mode)"
else
  echo "   (skipped)"
fi

# ── 2. Models ────────────────────────────────────────────────────────────────
section "Models"

if ! should_skip "models" && [ "$CI_MODE" = "false" ]; then
  models_json=$(curl -s --max-time 5 "http://localhost:20128/v1/models" 2>/dev/null || echo '{}')
  model_count=$(echo "$models_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "0")
  default_model=$(grep -A1 '^model:' "$HERMES_CONFIG" 2>/dev/null | grep 'default' | head -1 | sed 's/.*default: *//' || echo "unknown")
  default_model="${default_model:-unknown}"

  if [ "$model_count" -gt 0 ] 2>/dev/null; then
    _ok "OmniRoute" "${model_count} models (default: ${default_model})"
    json_add "models" "ok" "${model_count} models" "{\"count\":${model_count},\"default\":\"${default_model}\"}"
  else
    _warn "OmniRoute" "no models from /v1/models"
    json_add "models" "warn" "no models" "{\"count\":0}"
  fi
elif [ "$CI_MODE" = "true" ]; then
  echo "   (skipped — CI mode)"
else
  echo "   (skipped)"
fi

# ── 3. Mnemon ────────────────────────────────────────────────────────────────
section "Mnemon"

if ! should_skip "mnemon"; then
  mnemon_version=$(mnemon --version 2>/dev/null || echo "not-found")

  if [ "$mnemon_version" != "not-found" ]; then
    _ok "Binary" "${mnemon_version}"
    json_add "mnemon:binary" "ok" "mnemon ${mnemon_version}" "{\"version\":\"${mnemon_version}\"}"
  else
    _warn "Binary" "mnemon not found in PATH"
    json_add "mnemon:binary" "warn" "mnemon not found" "{}"
  fi

  mnemon_db=$(find "$HOME" -maxdepth 3 -name ".mnemon" -type d 2>/dev/null | head -1) || true
  if [ -n "$mnemon_db" ]; then
    _ok "Database" "found at ${mnemon_db}"
    json_add "mnemon:db" "ok" "db at ${mnemon_db}" "{\"path\":\"${mnemon_db}\"}"
  else
    _warn "Database" "no .mnemon dir (created on first use)"
    json_add "mnemon:db" "warn" "no .mnemon dir" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 4. Hermes config ─────────────────────────────────────────────────────────
section "Hermes"

if ! should_skip "hermes"; then
  if [ -f "$HERMES_CONFIG" ]; then
    cfg_model=$(grep -A1 '^model:' "$HERMES_CONFIG" 2>/dev/null | grep 'default' | head -1 | sed 's/.*default: *//' || echo "")
    cfg_provider=$(grep -A1 '^model:' "$HERMES_CONFIG" 2>/dev/null | grep 'provider' | head -1 | sed 's/.*provider: *//' || echo "")

    if [ -n "$cfg_model" ]; then
      _ok "Config" "model=${cfg_model}, provider=${cfg_provider:-unset}"
      json_add "hermes:config" "ok" "model=$cfg_model, provider=$cfg_provider" "{\"model\":\"${cfg_model}\",\"provider\":\"${cfg_provider}\"}"
    else
      _warn "Config" "model not set (fresh install?)"
      json_add "hermes:config" "warn" "model not configured" "{}"
    fi
  else
    _fail "Config" "no config at ${HERMES_CONFIG}"
    json_add "hermes:config" "fail" "config not found" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 5. Disk ──────────────────────────────────────────────────────────────────
section "Disk"

if ! should_skip "disk"; then
  disk_raw=$(df "$HOME" 2>/dev/null | tail -1 || true)
  if [ -n "$disk_raw" ]; then
    disk_pct=$(echo "$disk_raw" | awk '{print $5}' | tr -d '%')
    disk_avail=$(echo "$disk_raw" | awk '{print $4}')

    if [ -n "$disk_avail" ] && [[ "$disk_avail" =~ ^[0-9]+$ ]]; then
      disk_avail_gb=$(( disk_avail / 1024 / 1024 ))
    else
      disk_avail_gb="$disk_avail"
    fi

    if [ "$disk_pct" -ge 95 ] 2>/dev/null; then
      _fail "Usage" "${disk_pct}% used (${disk_avail_gb}G free) — CRITICAL"
      json_add "disk" "fail" "${disk_pct}% used" "{\"used_pct\":${disk_pct},\"available_gb\":${disk_avail_gb}}"
    elif [ "$disk_pct" -ge "$DISK_WARN_PCT" ] 2>/dev/null; then
      _warn "Usage" "${disk_pct}% used (${disk_avail_gb}G free) — threshold: ${DISK_WARN_PCT}%"
      json_add "disk" "warn" "${disk_pct}% used" "{\"used_pct\":${disk_pct},\"available_gb\":${disk_avail_gb}}"
    else
      _ok "Usage" "${disk_pct}% used (${disk_avail_gb}G free)"
      json_add "disk" "ok" "${disk_pct}% used" "{\"used_pct\":${disk_pct},\"available_gb\":${disk_avail_gb}}"
    fi
  else
    _warn "Usage" "could not read disk stats"
    json_add "disk" "warn" "df failed" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 6. Memory ────────────────────────────────────────────────────────────────
section "Memory"

if ! should_skip "memory"; then
  mem_raw=$(free -m 2>/dev/null | grep "^Mem:" || true)
  if [ -n "$mem_raw" ]; then
    mem_total=$(echo "$mem_raw" | awk '{print $2}')
    mem_used=$(echo "$mem_raw" | awk '{print $3}')
    mem_pct=$(( mem_used * 100 / mem_total ))

    if [ "$mem_pct" -ge 90 ] 2>/dev/null; then
      _warn "Usage" "${mem_pct}% used (${mem_used}M / ${mem_total}M)"
      json_add "memory" "warn" "${mem_pct}% used" "{\"used_pct\":${mem_pct}}"
    else
      _ok "Usage" "${mem_pct}% used (${mem_used}M / ${mem_total}M)"
      json_add "memory" "ok" "${mem_pct}% used" "{\"used_pct\":${mem_pct}}"
    fi
  else
    _warn "Usage" "could not read memory stats"
    json_add "memory" "warn" "free -m failed" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── 7. Persistence (symlinks) ───────────────────────────────────────────────
section "Persistence"

if ! should_skip "persistence"; then
  PERSIST_FAIL=0

  # 7a. Skills symlink: ~/.hermes/skills/minions
  SKILLS_LINK="${HOME}/.hermes/skills/minions"
  if [ -d "${MINIONS_HOME}/skills" ]; then
    # Knowledge assets exist — symlink should be present
    if [ -L "$SKILLS_LINK" ]; then
      _ok "Skills" "symlink → $(readlink "$SKILLS_LINK")"
      json_add "skills_symlink" "ok" "symlink correct" "{\"target\":\"$(readlink "$SKILLS_LINK")\"}"
    else
      _fail "Skills" "knowledge exists but no symlink at $SKILLS_LINK"
      json_add "skills_symlink" "fail" "symlink missing" "{}"
      PERSIST_FAIL=1
    fi
  else
    _warn "Skills" "knowledge not installed (${MINIONS_HOME}/skills missing)"
    json_add "skills_symlink" "warn" "knowledge not installed" "{}"
  fi

  # 7b. Memories symlink: ~/.hermes/memories
  MEMORIES_LINK="${HOME}/.hermes/memories"
  if [ -d "${MINIONS_HOME}/memories" ]; then
    if [ -L "$MEMORIES_LINK" ]; then
      _ok "Memories" "symlink → $(readlink "$MEMORIES_LINK")"
      json_add "memories_symlink" "ok" "symlink correct" "{\"target\":\"$(readlink "$MEMORIES_LINK")\"}"
    else
      _fail "Memories" "knowledge exists but no symlink at $MEMORIES_LINK"
      json_add "memories_symlink" "fail" "symlink missing" "{}"
      PERSIST_FAIL=1
    fi
  else
    _warn "Memories" "knowledge not installed (${MINIONS_HOME}/memories missing)"
    json_add "memories_symlink" "warn" "knowledge not installed" "{}"
  fi

  # 7c. Wiki — NOT symlinked (by design), just verify it exists
  if [ -d "${MINIONS_HOME}/wiki" ]; then
    _ok "Wiki" "${MINIONS_HOME}/wiki exists (not symlinked, by design)"
    json_add "wiki" "ok" "wiki dir exists" "{}"
  else
    _warn "Wiki" "knowledge not installed (${MINIONS_HOME}/wiki missing)"
    json_add "wiki" "warn" "knowledge not installed" "{}"
  fi
else
  echo "   (skipped)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
section "Summary"
echo ""
if [ "$CRITICAL" -gt 0 ]; then
  echo "  ${RED}${BOLD}FAILED${NC} — ${CRITICAL} critical, ${WARNINGS} warning(s)"
  EXIT_CODE=2
elif [ "$WARNINGS" -gt 0 ]; then
  echo "  ${YELLOW}${BOLD}WARNINGS${NC} — ${WARNINGS} warning(s), 0 critical"
  EXIT_CODE=1
else
  echo "  ${GREEN}${BOLD}PASSED${NC} — all checks ok"
  EXIT_CODE=0
fi
echo ""

# ── Write JSON report ────────────────────────────────────────────────────────
rm -f "$REPORT_FILE" 2>/dev/null || true
cat > "$REPORT_FILE" <<EOF || true
{
  "timestamp": "$TIMESTAMP",
  "exit_code": $EXIT_CODE,
  "critical": $CRITICAL,
  "warnings": $WARNINGS,
  "checks": $JSON_RESULTS
}
EOF

echo "  Report saved to: $REPORT_FILE"
exit "$EXIT_CODE"
