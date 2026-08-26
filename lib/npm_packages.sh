#!/usr/bin/env sh
# lib/npm_packages.sh - npm package installation (OmniRoute, ModelRelay)

# Install npm package globally into our vendored location
# Usage: install_npm_package <package_name> <version> <install_dir> <bin_name>
install_npm_package() {
    package=$1
    version=$2
    install_dir=$3
    bin_name=$4

    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/node.sh"
    ensure_node "22.22.2"

    # Use npm with custom prefix (NO -g flag - causes EACCES in newer npm)
    npm_prefix="${install_dir}/npm"
    mkdir -p "${npm_prefix}/lib/node_modules"

    echo "Installing ${package}@${version}..."
    npm install "${package}@${version}" \
        --prefix "${npm_prefix}" \
        --no-audit \
        --no-fund \
        --loglevel error \
        --no-save \
        --legacy-peer-deps

    # Fix macOS quarantine on the bin directory
    fix_macos_quarantine "${npm_prefix}/lib/node_modules/.bin"

    # Create wrapper script that calls the binary from node_modules/.bin
    cat > "${install_dir}/${bin_name}" << EOF
#!/usr/bin/env sh
export PATH="${npm_prefix}/lib/node_modules/.bin:\${PATH}"
export NODE_PATH="${npm_prefix}/lib/node_modules"
exec "${npm_prefix}/lib/node_modules/.bin/${bin_name}" "\$@"
EOF
    make_executable "${install_dir}/${bin_name}"

    # Verify the binary works
    if "${install_dir}/${bin_name}" --version >/dev/null 2>&1; then
        echo "${package}@${version} installed and verified at ${install_dir}"
    else
        echo "WARNING: ${package} installed but binary verification failed" >&2
    fi
}

# Ensure OmniRoute is available
ensure_omniroute() {
    if [ -x "${MINIONS_HOME}/lib/omniroute/omniroute" ]; then
        echo "OmniRoute found at ${MINIONS_HOME}/lib/omniroute/omniroute"
        return 0
    fi

    echo "OmniRoute not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/omniroute"
    install_npm_package "omniroute" "${OMNIROUTE_VERSION}" "${MINIONS_HOME}/lib/omniroute" "omniroute"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/omniroute/omniroute" "${MINIONS_HOME}/bin/omniroute"
}

# Ensure ModelRelay is available
ensure_modelrelay() {
    if [ -x "${MINIONS_HOME}/lib/modelrelay/modelrelay" ]; then
        echo "ModelRelay found at ${MINIONS_HOME}/lib/modelrelay/modelrelay"
        return 0
    fi

    echo "ModelRelay not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/modelrelay"
    install_npm_package "modelrelay" "${MODELRELAY_VERSION}" "${MINIONS_HOME}/lib/modelrelay" "modelrelay"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/modelrelay/modelrelay" "${MINIONS_HOME}/bin/modelrelay"
}