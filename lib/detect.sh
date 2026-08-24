#!/usr/bin/env sh
# lib/detect.sh - OS/Arch detection helpers

# Detect OS and architecture
# Sets: OS, ARCH, PLATFORM
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "${OS}" in
        linux)
            OS="linux"
            ;;
        darwin)
            OS="macos"
            ;;
        *)
            echo "Unsupported OS: ${OS}" >&2
            return 1
            ;;
    esac

    case "${ARCH}" in
        x86_64|amd64)
            ARCH="x64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            echo "Unsupported architecture: ${ARCH}" >&2
            return 1
            ;;
    esac

    PLATFORM="${OS}-${ARCH}"
    export OS ARCH PLATFORM
}

# Get the appropriate download URL for a component given platform
# Usage: get_download_url <component> <version>
get_download_url() {
    component=$1
    version=$2

    case "${component}" in
        node)
            echo "https://nodejs.org/dist/v${version}/node-v${version}-${PLATFORM}.tar.xz"
            ;;
        uv)
            # uv uses different naming
            case "${PLATFORM}" in
                linux-x64)
                    echo "https://github.com/astral-sh/uv/releases/download/${version}/uv-${PLATFORM}.tar.gz"
                    ;;
                linux-arm64)
                    echo "https://github.com/astral-sh/uv/releases/download/${version}/uv-${PLATFORM}.tar.gz"
                    ;;
                macos-x64)
                    echo "https://github.com/astral-sh/uv/releases/download/${version}/uv-${PLATFORM}.tar.gz"
                    ;;
                macos-arm64)
                    echo "https://github.com/astral-sh/uv/releases/download/${version}/uv-${PLATFORM}.tar.gz"
                    ;;
            esac
            ;;
        pi)
            # Pi-Agent standalone binary from GitHub releases
            echo "https://github.com/earendil-works/pi/releases/download/pi-coding-agent%40${version}/pi-${PLATFORM}"
            ;;
        hermes)
            # Hermes installer - we don't download directly, we use their installer script
            echo "https://hermes-agent.nousresearch.com/install.sh"
            ;;
        *)
            echo "Unknown component: ${component}" >&2
            return 1
            ;;
    esac
}

# Get expected SHA256 for a component/platform/version
# Usage: get_sha256 <component> <version>
get_sha256() {
    component=$1
    version=$2

    # Source versions.env for checksums
    if [ -f "${MINIONS_HOME}/etc/versions.env" ]; then
        # shellcheck disable=SC1090,SC1091
        . "${MINIONS_HOME}/etc/versions.env"
    fi

    # Convert platform to variable format (e.g., linux-x64 -> LINUX_X64)
    platform_upper=$(echo "${PLATFORM}" | tr '[:lower:]-' '[:upper:]_')
    var_name="${component}_SHA256_${platform_upper}"
    # shellcheck disable=SC2086
    eval "echo \${${var_name}}"
}