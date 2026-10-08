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
for service in tailscaled ollama pi hermes 9router omniroute; do
    if [ -f "${MINIONS_HOME}/var/run/${service}.pid" ]; then
        stop_service "${service}"
    fi
done
# Tailscale pgrep fallback (userspace daemon may not have pidfile if started elsewhere)
if command -v pgrep >/dev/null 2>&1 && pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
    # Only try graceful kill via pidfile; don't blanket kill system daemon in root mode
    if [ -f "${MINIONS_HOME}/var/run/tailscaled.pid" ]; then
        pgrep -f "[t]ailscaled" >/dev/null 2>&1 || true
    fi
fi

# Remove ready marker
rm -f "${MINIONS_HOME}/var/run/ready"

log_info "All services stopped"