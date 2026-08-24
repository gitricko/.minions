#!/usr/bin/env sh
# lib/download.sh - Download and verify helpers

# Download a file with retries
# Usage: download_file <url> <output_path> [expected_sha256]
download_file() {
    url=$1
    output=$2
    expected_sha256=$3

    # Create parent directory
    mkdir -p "$(dirname "${output}")"

    # Download with curl (or wget as fallback)
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 2 -o "${output}.tmp" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --waitretry=2 -O "${output}.tmp" "${url}"
    else
        echo "Neither curl nor wget found" >&2
        return 1
    fi

    # Verify checksum if provided
    if [ -n "${expected_sha256}" ]; then
        case ${expected_sha256} in
            PLACEHOLDER*)
                # Skip placeholder checksums
                ;;
            *)
                actual_sha256=$(sha256sum "${output}.tmp" 2>/dev/null | awk '{print $1}') || actual_sha256=$(shasum -a 256 "${output}.tmp" 2>/dev/null | awk '{print $1}')
                if [ "${actual_sha256}" != "${expected_sha256}" ]; then
                    echo "Checksum mismatch for ${url}" >&2
                    echo "Expected: ${expected_sha256}" >&2
                    echo "Actual:   ${actual_sha256}" >&2
                    rm -f "${output}.tmp"
                    return 1
                fi
                ;;
        esac
    fi

    mv "${output}.tmp" "${output}"
}

# Extract tarball
# Usage: extract_tarball <tarball_path> <destination_dir>
extract_tarball() {
    tarball=$1
    dest=$2

    mkdir -p "${dest}"

    case "${tarball}" in
        *.tar.gz|*.tgz)
            tar -xzf "${tarball}" -C "${dest}"
            ;;
        *.tar.xz)
            tar -xJf "${tarball}" -C "${dest}"
            ;;
        *.tar)
            tar -xf "${tarball}" -C "${dest}"
            ;;
        *.zip)
            unzip -q "${tarball}" -d "${dest}"
            ;;
        *)
            echo "Unknown archive format: ${tarball}" >&2
            return 1
            ;;
    esac
}

# Fix macOS quarantine on a file or directory
# Usage: fix_macos_quarantine <path>
fix_macos_quarantine() {
    path=$1
    if [ "$(uname -s)" = "Darwin" ]; then
        xattr -dr com.apple.quarantine "${path}" 2>/dev/null || true
    fi
}

# Make a file executable
# Usage: make_executable <path>
make_executable() {
    chmod +x "$1"
}