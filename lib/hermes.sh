#!/usr/bin/env sh
# lib/hermes.sh - Hermes Agent installation

# Install Hermes using their official install script (git-based, mirrors hermes-codespace)
# Usage: install_hermes <version> <install_dir>
install_hermes() {
    version=$1
    install_dir=$2

    # Pin to exact version tag (e.g. v2026.8.13)
    hermes_install_uri="https://raw.githubusercontent.com/NousResearch/hermes-agent/${version}/scripts/install.sh"
    hermes_fallback_uri="https://hermes-agent.nousresearch.com/install.sh"

    echo "Installing Hermes ${version} via official install script..."

    # Download install script
    tmp_script=$(mktemp)
    if ! curl -fsSL "${hermes_install_uri}" -o "${tmp_script}" 2>/dev/null; then
        echo "Primary URI failed, trying fallback..."
        curl -fsSL "${hermes_fallback_uri}" -o "${tmp_script}" || {
            echo "ERROR: could not download Hermes install script" >&2
            return 1
        }
    fi

    # Run installer with custom HOME so it doesn't touch the host's ~/.hermes
    HERMES_HOME_OVERRIDE="${install_dir}/home"
    mkdir -p "${HERMES_HOME_OVERRIDE}"

    # The installer writes to ~/.hermes by default; we redirect via HOME
    HOME="${HERMES_HOME_OVERRIDE}" sh "${tmp_script}" || {
        echo "ERROR: Hermes install script failed" >&2
        rm -f "${tmp_script}"
        return 1
    }
    rm -f "${tmp_script}"

    # Find the installed hermes binary
    hermes_bin=$(find "${HERMES_HOME_OVERRIDE}" -type f -name "hermes" 2>/dev/null | head -1)
    if [ -z "${hermes_bin}" ]; then
        # Fallback: installer may have used standard ~/.hermes
        hermes_bin=$(command -v hermes 2>/dev/null || true)
    fi

    if [ -z "${hermes_bin}" ]; then
        echo "ERROR: Hermes binary not found after install" >&2
        return 1
    fi

    # Create wrapper script in our install_dir
    cat > "${install_dir}/hermes" << EOF
#!/usr/bin/env sh
export HERMES_HOME="${HERMES_HOME_OVERRIDE}"
exec "${hermes_bin}" "\$@"
EOF
    make_executable "${install_dir}/hermes"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}"

    # Verify the binary works
    if "${install_dir}/hermes" --version >/dev/null 2>&1; then
        echo "Hermes ${version} installed and verified at ${install_dir}"
    else
        echo "WARNING: Hermes installed but binary verification failed" >&2
    fi

    # Preconfigure Hermes (if requested)
    if [ "${MINIONS_HERMES_PRECONFIG:-0}" -eq 1 ]; then
        hermes_preconfigure
    fi
}

# Preconfigure Hermes after install
# Sets up: auto-fastest model combo, MCP, omniroute login off, gateway/dashboard
hermes_preconfigure() {
    echo "Preconfiguring Hermes..."

    # Ensure HERMES config dir exists
    mkdir -p "${HOME}/.hermes"

    # Set auto-fastest model combo (uses OmniRoute by default)
    hermes config set model.provider auto-fastest 2>/dev/null || true

    # Enable MCP
    hermes config set mcp.enabled true 2>/dev/null || true

    # Disable OmniRoute login requirement (mirrors start-hermes.sh)
    hermes config set omniroute.login_required false 2>/dev/null || true

    # Register OmniRoute as MCP server
    hermes mcp add omniroute --command omniroute --args --mcp 2>/dev/null || true

    echo "Hermes preconfig complete"
}

# Ensure Hermes is available
ensure_hermes() {
    if [ -x "${MINIONS_HOME}/lib/hermes/hermes" ]; then
        echo "Hermes found at ${MINIONS_HOME}/lib/hermes/hermes"
        return 0
    fi

    echo "Hermes not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/hermes"
    install_hermes "${HERMES_VERSION}" "${MINIONS_HOME}/lib/hermes"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/hermes/hermes" "${MINIONS_HOME}/bin/hermes"
}