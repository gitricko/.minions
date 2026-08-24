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
            # uv uses Rust triple naming (not PLATFORM)
            # Map PLATFORM to Rust target triple
            case "${PLATFORM}" in
                linux-x64)
                    uv_target="x86_64-unknown-linux-gnu"
                    ;;
                linux-arm64)
                    uv_target="aarch64-unknown-linux-gnu"
                    ;;
                macos-x64)
                    uv_target="x86_64-apple-darwin"
                    ;;
                macos-arm64)
                    uv_target="aarch64-apple-darwin"
                    ;;
                *)
                    echo "Unsupported platform for uv: ${PLATFORM}" >&2
                    return 1
                    ;;
            esac
            echo "https://github.com/astral-sh/uv/releases/download/${version}/uv-${uv_target}.tar.gz"
            ;;
        pi)
            # Pi-Agent is now installed via npm (not standalone binary)
            # This function is kept for compatibility but returns empty for pi
            # Actual install is in lib/pi.sh using npm
            echo ""
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
    # Uppercase component to match versions.env naming (UV_SHA256_, NODE_SHA256_, etc.)
    component_upper=$(echo "${component}" | tr '[:lower:]' '[:upper:]')
    var_name="${component_upper}_SHA256_${platform_upper}"
    # shellcheck disable=SC2086
    eval "echo \${${var_name}}"
}