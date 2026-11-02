#!/usr/bin/env bash
# probe-service.sh — generic dumper for the codespace-service-discovery method.
# Given one or more PIDs, print: cmdline, comm, filtered+full env, open log files,
# listening ports, and any endpoint/model/token strings in recently-opened logs.
#
# Usage:
#   bash probe-service.sh <PID> [PID ...]         # dump specifics for explicit pids
#   bash probe-service.sh --family copilot        # auto-pick: ps grep, then dump each
#
# Read-only, non-destructive. Never mutates the targets.
set -euo pipefail

FILTER='token|key|secret|copilot|anthropic|claude|openai|codex|model|provider|base_url|endpoint|proxy|auth|bearer|license|plan|tier|127\.0\.0\.1|api\.|https?://'

dump_pid() {
  local pid=$1
  echo "============================================================"
  echo "PID $pid"
  echo "============================================================"
  if [[ ! -d /proc/$pid ]]; then echo "  (not running)"; return; fi
  echo "--- comm / cmdline"
  echo "  comm=$(cat /proc/$pid/comm 2>/dev/null)"
  echo "  cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | cut -c1-300)"
  echo "--- env (filtered)"
  tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | sort | grep -iE "$FILTER" | sed 's/^/  env: /' || true
  echo "--- open log files"
  ls -l /proc/$pid/fd 2>/dev/null | awk '/log|\.log/ {print "  " $9 " -> " $NF}' || true
}

auto_family() {
  local pat=$1
  local pids
  pids=$(pgrep -f -i "$pat" 2>/dev/null | sort -u || true)
  if [[ -z "$pids" ]]; then
    echo "no pids matched '$pat'; falling back to broad ps" >&2
    pids=$(ps -eo pid,args --no-headers | awk '{print $1}' | tr '\n' ' ')
  fi
  local p
  for p in $pids; do dump_pid "$p"; done
}

ports_map() {
  echo "============================================================"
  echo "Listening ports (127.0.0.1)"
  echo "============================================================"
  ss -tlnp 2>/dev/null | awk '/127\.0\.0\.1/ {print "  "$4"  -> "$7}'
  echo
  echo "Established (remote) connections"
  ss -tnp 2>/dev/null | awk 'NR>1 {print "  "$4" <-> "$5"  -> "$7}'
}

log_signal_sweep() {
  echo "============================================================"
  echo "Recent log signal (last 30 min, user home)"
  echo "============================================================"
  now_epoch=$(date +%s)
  find "$HOME" -maxdepth 6 -type f -newermt "@$((now_epoch - 1800))" \
       \( -name '*.log' -o -path '*/logs/*' \) 2>/dev/null | head -60 | while read -r f; do
    hits=$(grep -aoiE 'https?://[a-z0-9./_?=-]+|listening on http[^ ]*|/v[0-9]+/[a-z_]+|nonce[=:"a-zA-Z0-9_-]{0,40}|"model":"[a-z0-9._-]+"' "$f" 2>/dev/null | sort -u | head -25)
    if [[ -n "$hits" ]]; then
      echo "### $f"
      echo "$hits" | sed 's/^/   /'
    fi
  done
}

case "${1:-}" in
  "" )
    echo "No args. Usage: bash $0 <PID>... | --family <pattern> | --ports" >&2
    exit 2
    ;;
  --family )
    [[ -n "${2:-}" ]] || { echo "need a pattern after --family"; exit 2; }
    auto_family "$2"
    ports_map
    log_signal_sweep
    ;;
  --ports )
    ports_map
    log_signal_sweep
    ;;
  --help|-h ) sed -E 's/^#( |$)/\1/' "$0" | head -50 ;;
  * )
    for p in "$@"; do dump_pid "$p"; done
    ;;
esac
