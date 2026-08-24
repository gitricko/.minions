#!/usr/bin/env sh
# .minions status script - checks health of all services

set -e
set -u

MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"

# Default config values (overridden by etc/minions.env)
OMNIROUTE_HOST="127.0.0.1"
OMNIROUTE_PORT="20128"
MODELRELAY_HOST="127.0.0.1"
MODELRELAY_PORT="7352"

# Source config
if [ -f "${MINIONS_HOME}/etc/minions.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${MINIONS_HOME}/etc/minions.env"
fi

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

echo ".minions status:"
echo ""

# Check OmniRoute
echo "  omniroute   (${OMNIROUTE_HOST}:${OMNIROUTE_PORT})"
check_port "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" && echo "✅" || echo "❌"
check_pid "omniroute"

# Check ModelRelay
echo "  modelrelay  (${MODELRELAY_HOST}:${MODELRELAY_PORT})"
check_port "${MODELRELAY_HOST}" "${MODELRELAY_PORT}" && echo "✅" || echo "❌"
check_pid "modelrelay"

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

# Check ready marker
echo ""
if [ -f "${MINIONS_HOME}/var/run/ready" ]; then
    echo "  READY FOR FIRSTMATE DISPATCH ✅"
else
    echo "  NOT READY ❌"
fi