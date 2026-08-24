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

    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/uv.sh"
    ensure_uv

    # Use uv to create a venv and install hermes-agent
    hermes_venv="${install_dir}/venv"
    
    echo "Creating Hermes virtual environment..."
    uv venv "${hermes_venv}" --python 3.11

    echo "Installing hermes-agent ${version}..."
    # Use uv pip to install from GitHub (exact version)
    "${hermes_venv}/bin/uv" pip install "hermes-agent==${version}" --index-url https://pypi.org/simple

    # Create a wrapper script
    cat > "${install_dir}/hermes" << 'EOF'
#!/usr/bin/env sh
HERMES_VENV="${MINIONS_HOME}/lib/hermes/venv"
exec "${HERMES_VENV}/bin/hermes" "$@"
EOF
    make_executable "${install_dir}/hermes"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}"

    echo "Hermes ${version} installed to ${install_dir}"
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