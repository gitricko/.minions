#!/usr/bin/env sh
# lib/hermes.sh - Hermes Agent installation

# Install Hermes using their installer script but with our own paths
# Usage: install_hermes <version> <install_dir>
install_hermes() {
    version=$1
    install_dir=$2

    # Hermes installer is a shell script that we need to run
    # We'll download and run it with custom HOME to isolate it
    # But their installer writes to ~/.hermes and modifies shell rc files
    # Better approach: use uv to install hermes-agent into our own venv

    # Ensure uv is available (system or vendored)
    if ! command -v uv >/dev/null 2>&1; then
        # shellcheck disable=SC1091
        . "${MINIONS_HOME}/lib/uv.sh"
        ensure_uv
        export PATH="${MINIONS_HOME}/lib/uv:${PATH}"
    fi

    # Use uv to create a venv and install hermes-agent
    hermes_venv="${install_dir}/venv"

    echo "Creating Hermes virtual environment..."
    uv venv "${hermes_venv}" --python 3.11

    echo "Installing hermes-agent ${version}..."
    # Use uv pip to install into the venv we just created
    uv pip install --python "${hermes_venv}/bin/python" "hermes-agent==${version}" --index-url https://pypi.org/simple

    # Create a wrapper script
    cat > "${install_dir}/hermes" << 'EOF'
#!/usr/bin/env sh
HERMES_VENV="${MINIONS_HOME}/lib/hermes/venv"
exec "${HERMES_VENV}/bin/hermes" "$@"
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