#!/usr/bin/env sh
# lib/process.sh - Process management helpers

# Start a service in background
# Usage: start_service <name> <command> [args...]
start_service() {
    name=$1
    shift
    cmd=$1
    shift

    pid_file="${MINIONS_HOME}/var/run/${name}.pid"
    log_file="${MINIONS_HOME}/var/log/${name}.log"

    # Check if already running
    if [ -f "${pid_file}" ]; then
        existing_pid=$(cat "${pid_file}" 2>/dev/null)
        if [ -n "${existing_pid}" ] && kill -0 "${existing_pid}" 2>/dev/null; then
            echo "${name} already running (pid ${existing_pid})"
            return 0
        fi
    fi

    echo "Starting ${name}..."
    # Run detached in a new session via setsid + nohup so the service survives the
    # boot shell exiting AND ignores SIGHUP when its parent shell/step terminates.
    # setsid alone creates a new session, but on GitHub Actions/CI a background
    # child is still killed when the invoking step's shell exits; nohup makes it
    # ignore the SIGHUP delivered on process-group teardown.
    nohup setsid "${cmd}" "$@" >>"${log_file}" 2>&1 </dev/null &
    pid=$!

    # Write PID file
    echo "${pid}" > "${pid_file}"

    # Give it a moment to start
    sleep 0.5

    # Check if process is still alive
    if kill -0 "${pid}" 2>/dev/null; then
        echo "${name} started (pid ${pid})"
        return 0
    else
        echo "Failed to start ${name}" >&2
        rm -f "${pid_file}"
        return 1
    fi
}

# Stop a service
# Usage: stop_service <name>
stop_service() {
    name=$1
    pid_file="${MINIONS_HOME}/var/run/${name}.pid"

    if [ ! -f "${pid_file}" ]; then
        echo "${name} not running (no pid file)"
        return 0
    fi

    pid=$(cat "${pid_file}" 2>/dev/null)
    if [ -z "${pid}" ]; then
        rm -f "${pid_file}"
        return 0
    fi

    echo "Stopping ${name} (pid ${pid})..."
    if ! kill "${pid}" 2>/dev/null; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo -n kill "${pid}" 2>/dev/null || true; fi
    fi

    # Wait for graceful shutdown (check both user and sudo)
    # shellcheck disable=SC2034
    for _ in 1 2 3 4 5; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n kill -0 "${pid}" 2>/dev/null; then sleep 1; continue; fi
            break
        fi
        sleep 1
    done

    # Force kill if still alive
    _still=0
    if kill -0 "${pid}" 2>/dev/null; then _still=1; fi
    if [ "$_still" = 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n kill -0 "${pid}" 2>/dev/null; then _still=1; fi
    if [ "$_still" = 1 ]; then
        echo "Force killing ${name}..."
        kill -9 "${pid}" 2>/dev/null || true
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo -n kill -9 "${pid}" 2>/dev/null || true; fi
        sleep 0.5
    fi
    unset _still

    rm -f "${pid_file}" 2>/dev/null || true
    if [ -f "${pid_file}" ]; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo -n rm -f "${pid_file}" 2>/dev/null || true; fi
    fi
    echo "${name} stopped"
}

# Start tailscaled with optional sudo (kernel mode runs as root).
# Usage: _ts_start_daemon <daemon_path> [args...]
# Writes pidfile var/run/tailscaled.pid (root-owned when sudo used).
_ts_start_daemon() {
    _tsd_bin=$1; shift
    pid_file="${MINIONS_HOME}/var/run/tailscaled.pid"
    log_file="${MINIONS_HOME}/var/log/tailscaled.log"
    if [ -f "${pid_file}" ]; then
        existing_pid=$(cat "${pid_file}" 2>/dev/null || true)
        if [ -n "${existing_pid:-}" ]; then
            if kill -0 "${existing_pid}" 2>/dev/null; then echo "tailscaled already running (pid ${existing_pid})"; unset _tsd_bin existing_pid; return 0; fi
            if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n kill -0 "${existing_pid}" 2>/dev/null; then echo "tailscaled already running (pid ${existing_pid}, root)"; unset _tsd_bin existing_pid; return 0; fi
        fi
    fi
    echo "Starting tailscaled..."
    if [ "${_TS_MODE:-userspace}" = "kernel" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        # shellcheck disable=SC2086,SC2024
        # SC2024: redirect intentionally by user shell (log under $HOME, not root-owned) — sudo is for the daemon
        sudo -n nohup setsid "${_tsd_bin}" "$@" >>"${log_file}" 2>&1 </dev/null &
        pid=$!
        # sudo pid is the daemon's parent; give kernel time to fork
        sleep 0.5
        # find actual tailscaled pid if sudo pid died quickly (sudo forks)
        if ! sudo -n kill -0 "$pid" 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then
            # try pgrep for fallback pid
            pid=$(pgrep -f "[t]ailscaled.*${TAILSCALE_SOCKET:-}" 2>/dev/null | head -1)
            [ -n "${pid:-}" ] || pid=$(pgrep -f "[t]ailscaled" 2>/dev/null | head -1)
        fi
        if [ -n "${pid:-}" ]; then
            # pidfile will be root-owned; use sudo to write if needed (6102925874 #4)
            if ! echo "${pid}" > "${pid_file}" 2>/dev/null; then
                sudo -n sh -c "echo ${pid} > ${pid_file}" 2>/dev/null || echo "${pid}" > "${pid_file}" 2>/dev/null || true
            fi
        fi
    else
        nohup setsid "${_tsd_bin}" "$@" >>"${log_file}" 2>&1 </dev/null &
        pid=$!
        echo "${pid}" > "${pid_file}"
        sleep 0.5
    fi
    if [ -n "${pid:-}" ] && (kill -0 "${pid}" 2>/dev/null || sudo -n kill -0 "${pid}" 2>/dev/null 2>&1); then
        echo "tailscaled started (pid ${pid}, mode=${_TS_MODE:-userspace})"
        unset _tsd_bin pid existing_pid
        return 0
    else
        echo "Failed to start tailscaled" >&2
        rm -f "${pid_file}" 2>/dev/null; sudo -n rm -f "${pid_file}" 2>/dev/null || true
        unset _tsd_bin pid existing_pid
        return 1
    fi
}

# Check if a service is running
# Usage: is_service_running <name>
is_service_running() {
    name=$1
    pid_file="${MINIONS_HOME}/var/run/${name}.pid"

    if [ ! -f "${pid_file}" ]; then
        return 1
    fi

    pid=$(cat "${pid_file}" 2>/dev/null)
    if [ -z "${pid}" ]; then
        return 1
    fi

    if kill -0 "${pid}" 2>/dev/null; then return 0; fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n kill -0 "${pid}" 2>/dev/null; then return 0; fi
    return 1
}

# Wait for a port to become available
# Usage: wait_for_port <host> <port> <timeout_seconds> <service_name>
# No hard dependency on nc: prefer nc if present, else fall back to a
# Bash /dev/tcp probe (nc is NOT installed by default on many distros).
wait_for_port() {
    host=$1
    port=$2
    timeout=$3
    name=$4

    # Pick a port-checker once: nc if available, else bash /dev/tcp.
    # The bash /dev/tcp probe works even when this script runs under dash,
    # because we invoke bash explicitly via `bash -c`.
    if command -v nc >/dev/null 2>&1; then
        port_check() { nc -z "$1" "$2" 2>/dev/null; }
    elif command -v bash >/dev/null 2>&1; then
        port_check() { bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }
    else
        echo "WARNING: neither nc nor bash available to probe ${name} port" >&2
        port_check() { return 1; }
    fi

    echo "Waiting for ${name} on ${host}:${port}..."
    start_time=$(date +%s)

    while [ $(($(date +%s) - start_time)) -lt "${timeout}" ]; do
        if port_check "${host}" "${port}"; then
            echo "${name} is up on ${host}:${port}"
            return 0
        fi
        sleep 1
    done

    echo "Timeout waiting for ${name} on ${host}:${port}" >&2
    return 1
}

# Wait for HTTP health endpoint
# Usage: wait_for_health <url> <timeout_seconds> <service_name>
wait_for_health() {
    url=$1
    timeout=$2
    name=$3

    echo "Waiting for ${name} health at ${url}..."
    start_time=$(date +%s)

    while [ $(($(date +%s) - start_time)) -lt "${timeout}" ]; do
        if curl -fsS "${url}" >/dev/null 2>&1; then
            echo "${name} health check passed"
            return 0
        fi
        sleep 1
    done

    echo "Timeout waiting for ${name} health" >&2
    return 1
}