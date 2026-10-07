#!/usr/bin/env bash
# uninstall.sh — remove .minions and its HOME state (issue #61)
# Flags: --keep-config --dry-run --verify --force -h/--help
set -euo pipefail

RED=''; GREEN=''; YELLOW=''; NC=''
if [ -t 1 ]; then RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'; fi
log_info()  { echo "${GREEN}[INFO]${NC}  $*" >&2; }
log_warn()  { echo "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo "${RED}[ERROR]${NC} $*" >&2; }

KEEP_CONFIG=0
DRY_RUN=0
VERIFY=0
FORCE=0

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--keep-config] [--dry-run] [--verify] [--force] [-h|--help]

  --keep-config  Preserve user config/data (see table). Default: purge all.
  --dry-run      Print planned actions, change nothing (exit 0).
  --verify       After (or instead of) removal, report CLEAN vs LEFT: <paths> and exit 1 if leftovers.
  --force        Skip "are you sure?" prompt (for CI).
  -h, --help     Show this help.

Flag interactions:
  --dry-run alone: prints WOULD REMOVE: / WOULD KEEP: per path, changes nothing, exit 0.
  --verify alone (no deletion): scans and prints CLEAN (exit 0) or LEFT: <abs-path> per line (exit 1).
  --dry-run --verify: valid — plans removal then verifies what would remain, without mutating.
  Default uninstall.sh --force --verify: deletes then verifies in one run.

Without --force on non-TTY, fails with hint: use --force instead of hanging.
--dry-run and --verify never prompt (dry-run implies no prompt).
EOF
}

ORIGINAL_ARGS=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-config) KEEP_CONFIG=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verify) VERIFY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) log_error "unknown option: $1"; usage >&2; exit 2 ;;
    *) log_error "unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

# Resolve MINIONS_HOME — mirrors install.sh: fixed ${HOME}/.minions, honor exported only if valid
DEFAULT_MINIONS_HOME="${HOME}/.minions"
# Helper: canonicalize path (realpath -m if available, else normalize)
_canonicalize() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$1" 2>/dev/null || echo "$1"
  elif command -v readlink >/dev/null 2>&1 && readlink -m / >/dev/null 2>&1; then
    readlink -m "$1" 2>/dev/null || echo "$1"
  else
    # Fallback: strip trailing slash, resolve . and .. crudely
    _c="$1"
    # remove trailing slashes except root
    while [ "${_c%/}" != "$_c" ] && [ "$_c" != "/" ]; do _c="${_c%/}"; done
    echo "$_c"
  fi
}
if [ -n "${MINIONS_HOME:-}" ]; then
  case "${MINIONS_HOME}" in
    ""|"/"|"$HOME"|"$HOME/") log_warn "MINIONS_HOME=${MINIONS_HOME} is unsafe, falling back to ${DEFAULT_MINIONS_HOME}"; MINIONS_HOME="$DEFAULT_MINIONS_HOME" ;;
    /*)
      # Must be strictly under HOME — reject traversal and outside-HOME paths
      _canon_home=$(_canonicalize "$HOME")
      _canon_target=$(_canonicalize "$MINIONS_HOME")
      case "$_canon_target" in
        "$_canon_home"/*) ;; # under HOME, honor
        *)
          log_warn "MINIONS_HOME=${MINIONS_HOME} is not under HOME (${HOME}), falling back to ${DEFAULT_MINIONS_HOME}"
          MINIONS_HOME="$DEFAULT_MINIONS_HOME"
          ;;
      esac
      unset _canon_home _canon_target
      ;;
    *) log_warn "MINIONS_HOME=${MINIONS_HOME} is not absolute, falling back to ${DEFAULT_MINIONS_HOME}"; MINIONS_HOME="$DEFAULT_MINIONS_HOME" ;;
  esac
else
  MINIONS_HOME="$DEFAULT_MINIONS_HOME"
fi

# Self-deletion safety: if running from inside MINIONS_HOME, re-exec via /tmp copy
# Must run BEFORE any other logic that consumes ORIGINAL_ARGS; use absolute $0 via realpath
if [ "${MINIONS_UNINSTALL_REEXEC:-}" != "1" ] && [ -n "${MINIONS_HOME:-}" ]; then
  _self_canonical=$(realpath -m "${0:-}" 2>/dev/null || readlink -m "${0:-}" 2>/dev/null || echo "${0:-}")
  _home_canonical=$(_canonicalize "${MINIONS_HOME}")
  case "${_self_canonical}" in
    "${_home_canonical}"/*)
      tmp_copy=$(mktemp /tmp/minions-uninstall.XXXXXX 2>/dev/null || echo "/tmp/minions-uninstall-$$")
      cp "$_self_canonical" "$tmp_copy" 2>/dev/null || cp "${BASH_SOURCE[0]:-$0}" "$tmp_copy" 2>/dev/null || true
      chmod +x "$tmp_copy" 2>/dev/null || true
      export MINIONS_UNINSTALL_REEXEC=1
      # shellcheck disable=SC2145
      exec bash "$tmp_copy" "${ORIGINAL_ARGS[@]}"
      ;;
  esac
  unset _self_canonical _home_canonical tmp_copy
fi

# Determine whether this invocation should delete (vs verify-only)
# --dry-run never deletes; --verify alone without --force is verify-only; otherwise delete
DO_DELETE=1
if [ "$DRY_RUN" = "1" ]; then
  DO_DELETE=0
elif [ "$VERIFY" = "1" ] && [ "$FORCE" = "0" ]; then
  # verify-only when no --force and no explicit keep-config delete intent
  # but if user passed no other flag besides --verify, it's verify-only
  # Detect: if only --verify was requested, don't delete
  # We need to know if FORCE was 0 and DRY_RUN 0 and command was just --verify => verify-only
  # Use heuristic: if VERIFY=1 and FORCE=0 and DRY_RUN=0 and no deletion trigger without prompt would be odd,
  # but spec says --verify alone is scan without deletion, so treat FORCE=0 + VERIFY=1 as verify-only
  DO_DELETE=0
fi
# However --keep-config --verify without --force should also be verify-only; --force --verify should delete
# Override: if FORCE=1, always delete (even with --verify)
if [ "$FORCE" = "1" ] && [ "$DRY_RUN" = "0" ]; then
  DO_DELETE=1
fi
# Plain uninstall without --verify and without --dry-run is deletion (needs confirmation if not --force)
if [ "$VERIFY" = "0" ] && [ "$DRY_RUN" = "0" ]; then
  DO_DELETE=1
fi

# Lists
DATA_DIRS=("$HOME/.hermes" "$HOME/.pi" "$HOME/.omniroute" "$HOME/.9router" "$HOME/.mnemon" "$HOME/.ollama")
RC_FILES=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")

is_safe_target() {
  t="$1"
  if [ -z "$t" ] || [ "$t" = "/" ] || [ "$t" = "$HOME" ] || [ "$t" = "$HOME/" ]; then return 1; fi
  # Also reject if canonical target is not under HOME (defense-in-depth)
  _ist_canon=$(_canonicalize "$t")
  _ist_home=$(_canonicalize "$HOME")
  case "$_ist_canon" in
    "$_ist_home"/*) _ist_rc=0 ;;
    *) _ist_rc=1 ;;
  esac
  unset _ist_canon _ist_home
  if [ "$_ist_rc" != "0" ]; then return 1; fi
  return 0
}

safe_rm_target() {
  t="$1"
  if [ -L "$t" ]; then
    rm -f "$t" 2>/dev/null || true
    echo "REMOVE: $t" >&2
    return 0
  fi
  if [ -e "$t" ]; then
    if ! is_safe_target "$t"; then
      log_warn "skip unsafe rm: $t"
      return 0
    fi
    # Retry + verify like MINIONS_HOME (Finding 6: don't lie with REMOVE on failure)
    for _srt_i in 1 2 3; do
      rm -rf "$t" 2>/dev/null && break
      [ "$_srt_i" -lt 3 ] && sleep 1
    done
    if [ -e "$t" ] || [ -L "$t" ]; then
      log_error "failed to remove $t after 3 attempts"
      return 1
    fi
    echo "REMOVE: $t" >&2
  fi
}

# Dry-run: print plan and exit
if [ "$DRY_RUN" = "1" ]; then
  # For dry-run, show WOULD REMOVE vs WOULD KEEP respecting --keep-config
  # MINIONS_HOME always would be removed
  if [ -e "$MINIONS_HOME" ] || [ -L "$MINIONS_HOME" ]; then
    echo "WOULD REMOVE: $MINIONS_HOME"
  else
    echo "WOULD KEEP: $MINIONS_HOME (absent)"
  fi
  for d in "${DATA_DIRS[@]}"; do
    if [ "$KEEP_CONFIG" = "1" ]; then
      # kept
      if [ -e "$d" ] || [ -L "$d" ]; then
        echo "WOULD KEEP: $d"
      else
        echo "WOULD KEEP: $d (absent)"
      fi
    else
      if [ -e "$d" ] || [ -L "$d" ]; then
        echo "WOULD REMOVE: $d"
      else
        echo "WOULD KEEP: $d (absent)"
      fi
    fi
  done
  for rc in "${RC_FILES[@]}"; do
    if [ "$KEEP_CONFIG" = "1" ]; then
      echo "WOULD KEEP: $rc"
    else
      if [ -f "$rc" ] && grep -q "# .minions - added by installer" "$rc" 2>/dev/null; then
        echo "WOULD REMOVE: $rc (installer block)"
      else
        echo "WOULD KEEP: $rc"
      fi
    fi
  done
  if [ "$VERIFY" = "1" ]; then
    # Simulate verification of what would remain after the planned removal.
    # MINIONS_HOME would be gone; data dirs remain only if --keep-config; rc blocks remain if --keep-config.
    _dry_left=0
    # DATA_DIRS would remain iff KEEP_CONFIG=1 — those are expected, not LEFT.
    # So only check for leftovers that should have been removed.
    # Since dry-run never deletes, we report LEFT only if a path that WOULD be removed is missing from plan
    # i.e. no filesystem change, so we scan current state for paths that the plan would leave behind incorrectly.
    # Correct simulation: after dry-run, remaining = current state minus WOULD REMOVE set.
    # For now, since MINIONS_HOME WOULD be removed and with --keep-config data dirs are kept,
    # the simulated remaining set is exactly do_verify with KEEP_CONFIG — which is CLEAN by definition.
    # To avoid lying, actually simulate: if a WOULD REMOVE target doesn't exist now, don't report LEFT.
    # So dry-run --verify is CLEAN iff do_verify would be CLEAN after performing WOULD REMOVE.
    # We implement by checking if any WOULD REMOVE target currently exists but would NOT be removed — none.
    # Thus CLEAN is correct for a consistent plan; but if plan is inconsistent (guard skips), we must detect.
    # Check: if MINIONS_HOME is under HOME and WOULD REMOVE but is_safe_target says skip, that's LEFT.
    if [ -e "$MINIONS_HOME" ] || [ -L "$MINIONS_HOME" ]; then
      if ! is_safe_target "$MINIONS_HOME"; then
        echo "LEFT: $MINIONS_HOME"
        _dry_left=1
      fi
    fi
    if [ "$KEEP_CONFIG" = "0" ]; then
      for d in "${DATA_DIRS[@]}"; do
        # WOULD REMOVE: if it exists but is_safe_target would skip, it would be LEFT
        if [ -e "$d" ] || [ -L "$d" ]; then
          if ! is_safe_target "$d"; then
            echo "LEFT: $d"
            _dry_left=1
          fi
        fi
      done
      for rc in "${RC_FILES[@]}"; do
        if [ -f "$rc" ] && grep -q "# .minions - added by installer" "$rc" 2>/dev/null; then
          # WOULD REMOVE block — check not applicable for safety
          :
        fi
      done
    fi
    if [ "$_dry_left" = "0" ]; then
      echo "CLEAN"
    fi
    unset _dry_left
  fi
  exit 0
fi

# Verify-only scan (no deletion)
do_verify() {
  left=0
  # Check MINIONS_HOME
  if [ -e "$MINIONS_HOME" ] || [ -L "$MINIONS_HOME" ]; then
    echo "LEFT: $MINIONS_HOME"
    left=1
  fi
  for d in "${DATA_DIRS[@]}"; do
    if [ "$KEEP_CONFIG" = "1" ]; then
      continue
    fi
    if [ -e "$d" ] || [ -L "$d" ]; then
      echo "LEFT: $d"
      left=1
    fi
  done
  if [ "$KEEP_CONFIG" = "0" ]; then
    for rc in "${RC_FILES[@]}"; do
      if [ -f "$rc" ] && grep -q "# .minions - added by installer" "$rc" 2>/dev/null; then
        echo "LEFT: $rc"
        left=1
      fi
    done
  fi
  if [ "$left" = "0" ]; then
    echo "CLEAN"
    return 0
  else
    return 1
  fi
}

if [ "$DO_DELETE" = "0" ] && [ "$VERIFY" = "1" ]; then
  # verify-only
  if do_verify; then exit 0; else exit 1; fi
fi

# Deletion path: confirmation if not --force
if [ "$FORCE" = "0" ] && [ "$DO_DELETE" = "1" ]; then
  # --dry-run and --verify-only already returned, so we are about to delete
  if [ ! -t 0 ]; then
    log_error "refusing to uninstall without --force on non-TTY (hint: use --force)"
    exit 2
  fi
  # Build list for prompt
  prompt_list="$MINIONS_HOME"
  if [ "$KEEP_CONFIG" = "0" ]; then
    for d in "${DATA_DIRS[@]}"; do prompt_list="$prompt_list, $d"; done
    prompt_list="$prompt_list, rc MINIONS_HOME blocks"
  else
    prompt_list="$prompt_list (keeping ~/.hermes, ~/.pi, ~/.omniroute, ~/.9router, ~/.mnemon, ~/.ollama)"
  fi
  echo "Will remove: $prompt_list" >&2
  printf "Are you sure? [y/N] " >&2
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES) ;;
    *) log_info "aborted"; exit 1 ;;
  esac
fi

# Operation order: 1) stop services, 2) data folders, 3) MINIONS_HOME last, then rc
# 1) stop services — stdout reserved for CLEAN/LEFT, so redirect service chatter to stderr
if [ "$DO_DELETE" = "1" ]; then
  # try lib/process.sh stop_service if available — guard against set -u abort inside sourced file
  _stop_one() {
    _svc="$1"
    if command -v stop_service >/dev/null 2>&1; then
      # stop_service may print "not running" to stdout — redirect to stderr so verify stays pure
      set +e
      stop_service "$_svc" >&2 2>&1 || log_warn "stop $_svc failed or not running" >&2
      set -e
    fi
  }
  if [ -f "${MINIONS_HOME}/lib/process.sh" ]; then
    # shellcheck disable=SC1090
    set +u; . "${MINIONS_HOME}/lib/process.sh" 2>/dev/null || true; set -u
    for svc in omniroute 9router ollama; do _stop_one "$svc"; done
  elif [ -f "$(dirname -- "$0")/lib/process.sh" ]; then
    # shellcheck disable=SC1090
    set +u; . "$(dirname -- "$0")/lib/process.sh" 2>/dev/null || true; set -u
    for svc in omniroute 9router ollama; do _stop_one "$svc"; done
  fi
  unset -f _stop_one
  # Kill only pidfile-recorded PIDs — never blanket pkill -f ollama/omniroute/9router (Finding 3)
  for _pidf in "${MINIONS_HOME}/var/run/"*.pid; do
    [ -f "$_pidf" ] || continue
    _pid=$(cat "$_pidf" 2>/dev/null || true)
    if [ -n "${_pid:-}" ] && kill -0 "$_pid" 2>/dev/null; then
      kill "$_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$_pid" 2>/dev/null || true
    fi
  done
  unset _pid _pidf
  # remove pidfiles/logs regardless
  rm -f "${MINIONS_HOME}/var/run/"*.pid "${MINIONS_HOME}/var/run/ready" 2>/dev/null || true
  rm -rf "${MINIONS_HOME}/var/log" 2>/dev/null || true
  # give processes time to fully exit and release file handles
  sleep 1
fi

# 2) data folders (after services stopped)
if [ "$DO_DELETE" = "1" ] && [ "$KEEP_CONFIG" = "0" ]; then
  for d in "${DATA_DIRS[@]}"; do
    safe_rm_target "$d"
  done
fi

# 3) MINIONS_HOME last
if [ "$DO_DELETE" = "1" ]; then
  # For MINIONS_HOME, don't swallow errors - we need to know if it fails
  if [ -L "$MINIONS_HOME" ]; then
    rm -f "$MINIONS_HOME" 2>/dev/null || true
    log_info "removed symlink $MINIONS_HOME"
  elif [ -e "$MINIONS_HOME" ]; then
    if ! is_safe_target "$MINIONS_HOME"; then
      log_warn "skip unsafe rm: $MINIONS_HOME"
    else
      # Unmount any Docker volume mounts under MINIONS_HOME (DTS mounts host
      # ollama cache at $MINIONS_HOME/lib/ollama - rm -rf fails on mountpoints).
      # DTS runs as uid 1000 so umount needs sudo when available; try both.
      _try_umount() {
        for _u in "umount -l" "umount" "sudo umount -l" "sudo umount" "sudo -n umount -l"; do
          $_u "$1" 2>/dev/null && return 0
        done
        return 1
      }
      if command -v mountpoint >/dev/null 2>&1; then
        for mp in "$MINIONS_HOME/lib/ollama" "$MINIONS_HOME"; do
          if mountpoint -q "$mp" 2>/dev/null; then
            _try_umount "$mp" || true
            log_info "unmounted $mp"
          fi
        done
      fi
      # Fallback: parse mount table for any mount under MINIONS_HOME
      for mp in $(mount 2>/dev/null | awk -v home="${MINIONS_HOME}" 'length(home) && ($3==home || index($3, home"/")==1) {print $3}' | sort -r); do
        _try_umount "$mp" || true
        log_info "unmounted $mp (via mount table)"
      done
      unset -f _try_umount
      # Try removal with retries (handles transient file locks + mount release)
      for attempt in 1 2 3 4 5; do
        rm -rf "$MINIONS_HOME" 2>/dev/null && break
        [ "$attempt" -lt 5 ] && sleep 2
      done
      if [ -e "$MINIONS_HOME" ] || [ -L "$MINIONS_HOME" ]; then
        # Diagnostic: show what's left
        log_error "failed to remove $MINIONS_HOME after 5 attempts"
        ls -la "$MINIONS_HOME" 2>/dev/null | head -20 >&2 || true
        find "$MINIONS_HOME" -type f 2>/dev/null | head -30 >&2 || true
        mount 2>/dev/null | grep "$MINIONS_HOME" >&2 || true
        exit 1
      fi
      log_info "removed $MINIONS_HOME"
    fi
  fi
fi

# rc blocks (after MINIONS_HOME)
if [ "$DO_DELETE" = "1" ] && [ "$KEEP_CONFIG" = "0" ]; then
  for rc in "${RC_FILES[@]}"; do
    if [ -f "$rc" ] && grep -q "# .minions - added by installer" "$rc" 2>/dev/null; then
      # remove exact 3-line block: comment, export MINIONS_HOME, export PATH
      tmpf="$(mktemp)"
      awk '
        /# \.minions - added by installer/ { skip=2; next }
        skip>0 { skip--; next }
        { print }
      ' "$rc" > "$tmpf" 2>/dev/null && cat "$tmpf" > "$rc" 2>/dev/null || true
      rm -f "$tmpf" 2>/dev/null || true
      log_info "cleaned $rc"
    fi
  done
fi

# Final verify if requested
if [ "$VERIFY" = "1" ] && [ "$DO_DELETE" = "1" ]; then
  if do_verify; then exit 0; else exit 1; fi
fi

exit 0
