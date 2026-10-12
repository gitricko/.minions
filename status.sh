#!/usr/bin/env sh
# .minions status — health of all services (thin wrapper over lib/status-lib.sh)
# No set -e: reporter must not abort when degraded.

set -u

MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"

# Resolve lib location: prefer installed lib, fall back to repo lib
if [ -f "${MINIONS_HOME}/lib/status-lib.sh" ]; then
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/status-lib.sh"
else
    _status_script_dir=$(cd "$(dirname "$0")" && pwd)
    if [ -f "${_status_script_dir}/lib/status-lib.sh" ]; then
        # shellcheck disable=SC1091
        . "${_status_script_dir}/lib/status-lib.sh"
    elif [ -f "${_status_script_dir}/../lib/status-lib.sh" ]; then
        # shellcheck disable=SC1091
        . "${_status_script_dir}/../lib/status-lib.sh"
    else
        echo "status.sh: lib/status-lib.sh not found" >&2
        exit 2
    fi
    unset _status_script_dir
fi

# Parse args
case "${1:-}" in
    --help|-h)
        echo "Usage: status.sh [--help]"
        echo "  No args   Human report (one row per service, exit 0/1/2)"
        echo "  --help    Show this help"
        exit 0
        ;;
    --json)
        echo "status.sh: --json deferred to follow-up (use self-check.sh for JSON)" >&2
        exit 2
        ;;
    "")
        ;;
    *)
        echo "Unknown option: $1 (try --help)" >&2
        exit 2
        ;;
esac

status_collect
status_render_human
_rc=$(status_exit_code)
exit "${_rc}"
