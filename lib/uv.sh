#!/usr/bin/env sh
# lib/uv.sh - uv installation and management

# Check if uv is available
check_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    # Check vendored uv
    if [ -x "${MINIONS_HOME}/lib/uv/uv" ]; then
        return 0
    fi
    return 1
}

# Install vendored uv
# Usage: install_vendored_uv <version> <install_dir>
install_vendored_uv() {
    version=$1
    install_dir=$2

    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/detect.sh"
    detect_platform

    url=$(get_download_url uv "${version}")
    sha256=$(get_sha256 uv "${version}")

    tarball="${MINIONS_HOME}/var/cache/uv-${version}-${PLATFORM}.tar.gz"

    echo "Downloading uv ${version} for ${PLATFORM}..."
    download_file "${url}" "${tarball}" "${sha256}"

    echo "Extracting uv..."
    tmp_dir=$(mktemp -d)
    extract_tarball "${tarball}" "${tmp_dir}"

    # Find the uv binary
    uv_binary=$(find "${tmp_dir}" -type f -name "uv" | head -1)

    if [ -z "${uv_binary}" ]; then
        echo "uv binary not found in extracted archive" >&2
        rm -rf "${tmp_dir}"
        return 1
    fi

    mkdir -p "${install_dir}"
    cp "${uv_binary}" "${install_dir}/uv"
    make_executable "${install_dir}/uv"

    # Cleanup
    rm -rf "${tmp_dir}"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}/uv"

    echo "uv ${version} installed to ${install_dir}"
}

# Ensure uv is available
ensure_uv() {
    if check_uv; then
        if command -v uv >/dev/null 2>&1; then
            echo "System uv $(uv --version) found"
        else
            echo "Vendored uv found at ${MINIONS_HOME}/lib/uv/uv"
        fi
        return 0
    fi

    echo "uv not found, installing vendored uv..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    install_vendored_uv "${UV_VERSION}" "${MINIONS_HOME}/lib/uv"

    # Add to PATH
    export PATH="${MINIONS_HOME}/lib/uv:${PATH}"
}