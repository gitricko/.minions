#!/usr/bin/env sh
# lib/pi.sh - Pi-Agent installation and configuration

# Install Pi-Agent via npm
# Usage: install_pi <version> <install_dir>
install_pi() {
    version=$1
    install_dir=$2

    echo "Installing Pi-Agent ${version} via npm..."

    # Use npm with custom prefix (like OmniRoute/ModelRelay)
    npm_prefix="${install_dir}/npm"
    mkdir -p "${npm_prefix}/bin" "${npm_prefix}/lib/node_modules"

    # Set npm config to use our prefix (avoids writing to global node_modules)
    npm install "@earendil-works/pi-coding-agent@${version}" \
        --prefix "${npm_prefix}" \
        --no-audit \
        --no-fund \
        --loglevel error \
        --no-save || {
        # Fallback: try with --global-style in the prefix dir
        (cd "${npm_prefix}" && npm install "@earendil-works/pi-coding-agent@${version}" --no-audit --no-fund --loglevel error) || {
            echo "ERROR: Pi-Agent npm install failed" >&2
            return 1
        }
    }

    # Find the pi binary (symlink in .bin directory)
    pi_binary=$(find "${npm_prefix}" -name "pi" -path "*/node_modules/.bin/*" 2>/dev/null | head -1)
    if [ -z "${pi_binary}" ]; then
        pi_binary=$(find "${npm_prefix}" -name "pi" -path "*/bin/*" 2>/dev/null | head -1)
    fi
    if [ -z "${pi_binary}" ]; then
        pi_binary=$(find "${npm_prefix}" -name "pi" 2>/dev/null | head -1)
    fi

    if [ -z "${pi_binary}" ]; then
        echo "ERROR: Pi-Agent binary not found after npm install" >&2
        return 1
    fi

    # Fix macOS quarantine on the bin directory
    fix_macos_quarantine "${npm_prefix}/bin"

    # Create wrapper script that sets up the right environment
    cat > "${install_dir}/pi" << EOF
#!/usr/bin/env sh
export PATH="${npm_prefix}/bin:\${PATH}"
export NODE_PATH="${npm_prefix}/lib/node_modules"
exec "${pi_binary}" "\$@"
EOF
    make_executable "${install_dir}/pi"

    # Verify the binary works
    if "${install_dir}/pi" --version >/dev/null 2>&1; then
        echo "Pi-Agent ${version} installed (npm) and linked to ${install_dir}/pi"
    else
        echo "WARNING: Pi-Agent installed but binary verification failed" >&2
    fi
}

# Install pi-failover extension
# Usage: install_pi_failover_ext <install_dir>
install_pi_failover_ext() {
    install_dir=$1

    echo "Installing pi-failover extension..."

    # Use pi to install the extension
    if "${install_dir}/pi" install git:github.com/gitricko/pi-failover@hermes-impl 2>/dev/null; then
        echo "pi-failover extension installed"
    else
        echo "WARNING: pi-failover extension install failed (may not exist yet)" >&2
    fi
}

# Setup Mnemon Pi plugin
# Usage: setup_mnemon_pi
setup_mnemon_pi() {
    echo "Setting up Mnemon Pi plugin..."

    # Check if mnemon is available
    if ! command -v mnemon >/dev/null 2>&1; then
        echo "Mnemon not found, skipping Pi plugin setup" >&2
        return 0
    fi

    # Run mnemon setup for pi target
    if mnemon setup --target pi --global --yes 2>/dev/null; then
        echo "Mnemon Pi plugin setup complete"
    else
        echo "WARNING: Mnemon Pi plugin setup failed" >&2
    fi
}

# Create Pi config symlinks
# Usage: create_pi_symlinks <minions_home>
create_pi_symlinks() {
    minions_home=$1

    echo "Creating Pi config symlinks..."

    # Ensure ~/.pi directory exists
    mkdir -p "${HOME}/.pi"

    # Symlink pi.toml
    if [ -f "${minions_home}/etc/pi.toml" ]; then
        ln -sf "${minions_home}/etc/pi.toml" "${HOME}/.pi/pi.toml"
        echo "Symlinked pi.toml"
    else
        echo "WARNING: ${minions_home}/etc/pi.toml not found" >&2
    fi

    # Symlink models.json if it exists
    if [ -f "${minions_home}/etc/models.json" ]; then
        ln -sf "${minions_home}/etc/models.json" "${HOME}/.pi/models.json"
        echo "Symlinked models.json"
    fi

    # Symlink settings.json if it exists
    if [ -f "${minions_home}/etc/settings.json" ]; then
        ln -sf "${minions_home}/etc/settings.json" "${HOME}/.pi/settings.json"
        echo "Symlinked settings.json"
    fi
}

# Ensure Pi-Agent is available
ensure_pi() {
    # shellcheck disable=SC2153
    if [ -x "${MINIONS_HOME}/lib/pi/pi" ]; then
        echo "Pi-Agent found at ${MINIONS_HOME}/lib/pi/pi"
        return 0
    fi

    echo "Pi-Agent not found, installing via npm..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/pi"
    install_pi "${PI_VERSION}" "${MINIONS_HOME}/lib/pi"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/pi/pi" "${MINIONS_HOME}/bin/pi"

    # Run config steps
    install_pi_failover_ext "${MINIONS_HOME}/lib/pi"
    setup_mnemon_pi
    create_pi_symlinks "${MINIONS_HOME}"
}