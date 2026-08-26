#!/usr/bin/env sh
# lib/node.sh - Node.js installation and management

# Check if system Node meets minimum version requirement
# Usage: check_node_version <min_version>
check_node_version() {
    min_version=$1

    if ! command -v node >/dev/null 2>&1; then
        return 1
    fi

    current_version=$(node --version | sed 's/^v//')
    # Compare versions: returns 0 if current >= min
    printf '%s\n%s\n' "${min_version}" "${current_version}" | sort -V | head -1 | grep -q "^${min_version}$"
}

# Install vendored Node.js
# Usage: install_vendored_node <version> <install_dir>
install_vendored_node() {
    version=$1
    install_dir=$2

    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/detect.sh"
    detect_platform

    url=$(get_download_url node "${version}")
    sha256=$(get_sha256 node "${version}")

    tarball="${MINIONS_HOME}/var/cache/node-v${version}-${PLATFORM}.tar.xz"

    echo "Downloading Node.js ${version} for ${PLATFORM}..."
    download_file "${url}" "${tarball}" "${sha256}"

    echo "Extracting Node.js..."
    # Extract to a temporary directory first
    tmp_dir=$(mktemp -d)
    extract_tarball "${tarball}" "${tmp_dir}"

    # The tarball extracts to node-vX.Y.Z-platform
    extracted_dir=$(find "${tmp_dir}" -maxdepth 1 -type d -name "node-v*" | head -1)

    # Move contents to install_dir
    mkdir -p "${install_dir}"
    cp -r "${extracted_dir}"/* "${install_dir}/"

    # Cleanup
    rm -rf "${tmp_dir}"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}"

    echo "Node.js ${version} installed to ${install_dir}"
}

# Ensure Node.js is available (system or vendored)
# Usage: ensure_node <min_version>
ensure_node() {
    min_version=$1

    if check_node_version "${min_version}"; then
        echo "System Node.js $(node --version) meets requirement (>= ${min_version})"
        return 0
    fi

    echo "System Node.js insufficient (need >= ${min_version}), installing vendored Node..."
    install_vendored_node "${NODE_VERSION}" "${MINIONS_HOME}/lib/node"

    # Prepend vendored node to PATH
    export PATH="${MINIONS_HOME}/lib/node/bin:${PATH}"
}

# Ensure Node.js 22.22.2 is available (vendored) for OmniRoute/ModelRelay/Pi
# These packages have compatibility issues with Node 24+
# Usage: ensure_node_v22
ensure_node_v22() {
    echo "Ensuring Node.js ${NODE_VERSION} (vendored) for npm packages..."
    install_vendored_node "${NODE_VERSION}" "${MINIONS_HOME}/lib/node"
    export PATH="${MINIONS_HOME}/lib/node/bin:${PATH}"
}