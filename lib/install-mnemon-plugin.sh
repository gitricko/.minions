#!/usr/bin/env sh
# lib/install-mnemon-plugin.sh — idempotent mnemon plugin setup
# Sourced by install.sh and boot.sh. Installs gitricko/hermes-plugin-mnemon
# into ~/.hermes/plugins/mnemon and points Hermes' memory.provider at it.
#
# Non-fatal: network/plugin failures must never fail an install or boot.

install_mnemon_plugin() {
    local PLUGIN_DIR="${HOME}/.hermes/plugins/mnemon"
    if [ -d "$PLUGIN_DIR" ]; then
        log_info "mnemon plugin already installed"
        return 0
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git not found; skipping mnemon plugin install"
        return 0
    fi

    log_info "Installing mnemon plugin..."
    if ! git clone --depth 1 https://github.com/gitricko/hermes-plugin-mnemon.git /tmp/hermes-plugin-mnemon >/dev/null 2>&1; then
        log_warn "mnemon plugin clone failed; skipping"
        rm -rf /tmp/hermes-plugin-mnemon
        return 0
    fi
    mkdir -p "$PLUGIN_DIR"
    cp -r /tmp/hermes-plugin-mnemon/mnemon/* "$PLUGIN_DIR/" 2>/dev/null || true
    rm -rf /tmp/hermes-plugin-mnemon

    # Point Hermes at the mnemon provider (best-effort; PATH first, then bin)
    if command -v hermes >/dev/null 2>&1; then
        hermes config set memory.provider mnemon >/dev/null 2>&1 || true
    elif [ -x "${MINIONS_HOME}/bin/hermes" ]; then
        "${MINIONS_HOME}/bin/hermes" config set memory.provider mnemon >/dev/null 2>&1 || true
    fi
    log_info "mnemon plugin installed"
}