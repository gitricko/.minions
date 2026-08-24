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
    # Run detached in a new session via setsid so the service survives the
    # boot shell exiting and is not killed when boot.sh returns.
    setsid "${cmd}" "$@" >>"${log_file}" 2>&1 </dev/null &
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
    kill "${pid}" 2>/dev/null || true

    # Wait for graceful shutdown
    # shellcheck disable=SC2034
    for _ in 1 2 3 4 5; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Force kill if still alive
    if kill -0 "${pid}" 2>/dev/null; then
        echo "Force killing ${name}..."
        kill -9 "${pid}" 2>/dev/null || true
        sleep 0.5
    fi

    rm -f "${pid_file}"
    echo "${name} stopped"
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

    kill -0 "${pid}" 2>/dev/null
}

# Wait for a port to become available
# Usage: wait_for_port <host> <port> <timeout_seconds> <service_name>
wait_for_port() {
    host=$1
    port=$2
    timeout=$3
    name=$4

    echo "Waiting for ${name} on ${host}:${port}..."
    start_time=$(date +%s)

    while [ $(($(date +%s) - start_time)) -lt "${timeout}" ]; do
        if nc -z "${host}" "${port}" 2>/dev/null; then
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