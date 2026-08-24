#!/usr/bin/env sh
# lib/pi.sh - Pi-Agent installation (via npm)

# Install Pi-Agent via npm
# Usage: install_pi <version> <install_dir>
install_pi() {
    version=$1
    install_dir=$2

    echo "Installing Pi-Agent ${version} via npm..."

    # Use npm to install globally with --ignore-scripts
    # The binary will be in the npm global bin directory
    npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${version}"

    # Find where npm installed it
    pi_binary=$(command -v pi)
    if [ -z "${pi_binary}" ]; then
        echo "Pi-Agent binary not found after npm install" >&2
        return 1
    fi

    # Create symlink in our install_dir
    mkdir -p "${install_dir}"
    ln -sf "${pi_binary}" "${install_dir}/pi"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}/pi"

    echo "Pi-Agent ${version} installed (npm) and linked to ${install_dir}/pi"
}

# Ensure Pi-Agent is available
ensure_pi() {
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
}