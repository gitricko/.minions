#!/usr/bin/env sh
# .minions stop script - stops all services

set -e
set -u

MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"

# Source lib
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/process.sh"

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*"; }

# Stop in reverse order
for service in pi hermes modelrelay omniroute; do
    if [ -f "${MINIONS_HOME}/var/run/${service}.pid" ]; then
        stop_service "${service}"
    fi
done

# Remove ready marker
rm -f "${MINIONS_HOME}/var/run/ready"

log_info "All services stopped"