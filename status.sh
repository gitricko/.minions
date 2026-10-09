#!/usr/bin/env sh
# .minions status script - checks health of all services

set -e
set -u

MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"

# Port configuration (env-overridable with defaults)
# No runtime config file (etc/minions.env was removed) - ports come from env or defaults
OMNIROUTE_HOST="${OMNIROUTE_HOST:-127.0.0.1}"
OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"
NINEROUTER_HOST="${NINEROUTER_HOST:-127.0.0.1}"
NINEROUTER_PORT="${NINEROUTER_PORT:-7352}"

check_port() {
    host=$1
    port=$2
    # Use nc (netcat) if available, fallback to /dev/tcp for bash
    if command -v nc >/dev/null 2>&1; then
        nc -z "${host}" "${port}" 2>/dev/null
        return $?
    fi
    # Fallback: try /dev/tcp (bash-specific but widely available)
    # shellcheck disable=SC3025
    (echo > "/dev/tcp/${host}/${port}") 2>/dev/null
}

check_pid() {
    name=$1
    pid_file="${MINIONS_HOME}/var/run/${name}.pid"
    if [ -f "${pid_file}" ]; then
        pid=$(cat "${pid_file}" 2>/dev/null)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            echo "✅ (pid ${pid})"
            return 0
        fi
    fi
    echo "❌"
    return 1
}

# Tailscale is opt-in — presence-gated, guarded against set -e (tailscale status returns non-zero when logged out)
check_tailscale() {
    # Prefer managed socket if present
    _ts_socket="${MINIONS_HOME}/var/run/tailscaled.sock"
    _ts_cli=""
    if [ -x "${MINIONS_HOME}/bin/tailscale" ]; then
        _ts_cli="${MINIONS_HOME}/bin/tailscale"
    elif command -v tailscale >/dev/null 2>&1; then
        _ts_cli="$(command -v tailscale)"
    fi
    if [ -z "${_ts_cli}" ]; then
        echo "— not installed (install with install.sh --tailscale)"
        return 0
    fi
    # If pidfile exists and live, prefer it; else fall back to status probe (avoids EPERM lie for root daemon)
    if [ -f "${MINIONS_HOME}/var/run/tailscaled.pid" ]; then
        _ts_pid=$(cat "${MINIONS_HOME}/var/run/tailscaled.pid" 2>/dev/null || true)
        if [ -n "${_ts_pid:-}" ] && kill -0 "${_ts_pid}" 2>/dev/null; then
            echo "✅ (pid ${_ts_pid})"
            return 0
        fi
    fi
    # Fallback: pgrep or status (guarded) — use --socket for custom socket (TAILSCALE_SOCKET env is not honoured by v1.104.1)
    if command -v pgrep >/dev/null 2>&1 && pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
        echo "✅ (running)"
        return 0
    fi
    # Try status without failing the script (set -e guard)
    set +e
    if [ -n "${_ts_socket:-}" ] && [ -S "${_ts_socket}" ]; then
        "${_ts_cli}" --socket="${_ts_socket}" status >/dev/null 2>&1
        _rc=$?
    else
        "${_ts_cli}" status >/dev/null 2>&1
        _rc=$?
    fi
    set -e
    if [ "${_rc:-1}" -eq 0 ]; then
        echo "✅ (status ok)"
        return 0
    fi
    echo "❌"
    return 1
}

echo ".minions status:"
echo ""

# Check OmniRoute
echo "  omniroute   (${OMNIROUTE_HOST}:${OMNIROUTE_PORT})"
check_port "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" && echo "✅" || echo "❌"
check_pid "omniroute"

# Check 9Router
echo "  9router     (${NINEROUTER_HOST}:${NINEROUTER_PORT})"
check_port "${NINEROUTER_HOST}" "${NINEROUTER_PORT}" && echo "✅" || echo "❌"
check_pid "9router"

# Check Pi-Agent CLI
echo "  pi-agent    CLI"
if command -v pi >/dev/null 2>&1; then
    echo "✅ ($(pi --version 2>&1 | head -1))"
else
    echo "❌"
fi

# Check Hermes CLI
echo "  hermes      CLI"
if command -v hermes >/dev/null 2>&1; then
    echo "✅ ($(hermes --version 2>&1 | head -1))"
else
    echo "❌"
fi

# Check Tailscale (opt-in)
echo "  tailscale   (opt-in)"
# Guarded — check_tailscale returns non-zero when not running but status.sh must not abort
set +e
_tailscale_out=$(check_tailscale 2>&1)
_tailscale_rc=$?
set -e
echo "  ${_tailscale_out}"

# Check ready marker
echo ""
if [ -f "${MINIONS_HOME}/var/run/ready" ]; then
    echo "  READY FOR FIRSTMATE DISPATCH ✅"
else
    echo "  NOT READY ❌"
fi