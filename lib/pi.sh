#!/usr/bin/env sh
# lib/pi.sh - Pi-Agent installation

# Install Pi-Agent standalone binary
# Usage: install_pi <version> <install_dir>
install_pi() {
    version=$1
    install_dir=$2

    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/detect.sh"
    detect_platform

    url=$(get_download_url pi "${version}")
    sha256=$(get_sha256 pi "${version}")

    binary_path="${install_dir}/pi"

    echo "Downloading Pi-Agent ${version} for ${PLATFORM}..."
    download_file "${url}" "${binary_path}" "${sha256}"

    make_executable "${binary_path}"

    # Fix macOS quarantine
    fix_macos_quarantine "${binary_path}"

    echo "Pi-Agent ${version} installed to ${binary_path}"
}

# Ensure Pi-Agent is available
ensure_pi() {
    if [ -x "${MINIONS_HOME}/lib/pi/pi" ]; then
        echo "Pi-Agent found at ${MINIONS_HOME}/lib/pi/pi"
        return 0
    fi

    echo "Pi-Agent not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/pi"
    install_pi "${PI_VERSION}" "${MINIONS_HOME}/lib/pi"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/pi/pi" "${MINIONS_HOME}/bin/pi"
}