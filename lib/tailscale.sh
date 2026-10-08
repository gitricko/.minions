#!/usr/bin/env sh
# lib/tailscale.sh - Tailscale installation (managed static tarball, opt-in, userspace default)
# Pinned via etc/deps.yaml -> etc/versions.env (TAILSCALE_VERSION).
# Installs into ${MINIONS_HOME}/lib/tailscale and symlinks into bin/ so
# uninstall --verify can be honestly CLEAN and boot can presence-gate on bin/.

# Source versions.env for single source of truth (set by install.sh)
# MINIONS_HOME must already be set; versions.env provides TAILSCALE_VERSION
# shellcheck disable=SC1091,SC2153
if [ -f "${MINIONS_HOME}/etc/versions.env" ]; then
    . "${MINIONS_HOME}/etc/versions.env"
fi

# Install Tailscale binaries (if not present)
# Usage: install_tailscale <install_dir>
install_tailscale() {
    install_dir=$1

    # Host-cache fast-path for DTS: /tmp/tailscale-cache is host's
    # pre-downloaded binaries (ro mount), same pattern as ollama/uv.
    # Cache dir should contain both `tailscale` and `tailscaled`.
    if [ -f "/tmp/tailscale-cache/tailscale" ] && [ -f "/tmp/tailscale-cache/tailscaled" ]; then
        mkdir -p "${install_dir}"
        cp -f "/tmp/tailscale-cache/tailscale" "${install_dir}/tailscale" 2>/dev/null || true
        cp -f "/tmp/tailscale-cache/tailscaled" "${install_dir}/tailscaled" 2>/dev/null || true
        if [ -x "${install_dir}/tailscale" ] && [ -x "${install_dir}/tailscaled" ]; then
            chmod +x "${install_dir}/tailscale" "${install_dir}/tailscaled"
            fix_macos_quarantine "${install_dir}/tailscale" 2>/dev/null || true
            fix_macos_quarantine "${install_dir}/tailscaled" 2>/dev/null || true
            echo "Tailscale installed from DTS host cache (/tmp/tailscale-cache)"
            return 0
        fi
    fi
    # Single-file cache fallback: some fixtures only provide `tailscale` binary
    if [ -f "/tmp/tailscale-cache/tailscale" ] && [ ! -f "/tmp/tailscale-cache/tailscaled" ]; then
        mkdir -p "${install_dir}"
        cp -f "/tmp/tailscale-cache/tailscale" "${install_dir}/tailscale" 2>/dev/null || true
        if [ -x "${install_dir}/tailscale" ]; then
            chmod +x "${install_dir}/tailscale"
            fix_macos_quarantine "${install_dir}/tailscale" 2>/dev/null || true
            echo "Tailscale installed from DTS host cache (/tmp/tailscale-cache) — single binary"
            return 0
        fi
    fi

    tailscale_version="${TAILSCALE_VERSION:-v1.104.1}"
    # Strip leading 'v' for pkgs URL (pkgs uses bare 1.104.1, deps.yaml stores v1.104.1)
    tailscale_version="${tailscale_version#v}"

    os=$(uname -s)
    if [ "${os}" != "Linux" ]; then
        echo "Tailscale managed install is Linux-only (pkgs host has no Darwin tarball; use brew on macOS)" >&2
        return 1
    fi
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo "Unsupported architecture for Tailscale: ${arch} (managed install supports amd64/arm64 only)" >&2; return 1 ;;
    esac

    # pkgs.tailscale.com stable tarballs are the versioned distribution.
    # Verified: Linux only — pkgs has no Darwin tarball for 1.104.1 (see above guard).
    # Asset pattern: tailscale_<version>_<arch>.tgz  (e.g. tailscale_1.104.1_amd64.tgz)
    asset="tailscale_${tailscale_version}_${arch}.tgz"
    url="https://pkgs.tailscale.com/stable/${asset}"

    echo "Installing Tailscale v${tailscale_version} (${arch}) from ${url}..."

    # Resolve per-platform sha256 from versions.env (populated via deps.yaml)
    tailscale_sha=""
    case "${arch}" in
        amd64) tailscale_sha="${TAILSCALE_SHA256_LINUX_X64:-}" ;;
        arm64) tailscale_sha="${TAILSCALE_SHA256_LINUX_ARM64:-}" ;;
    esac

    # Download to install_dir (use download_file helper if available, else curl)
    tarball="${install_dir}/${asset}"
    mkdir -p "${install_dir}"

    if command -v download_file >/dev/null 2>&1; then
        if ! download_file "${url}" "${tarball}" "${tailscale_sha}"; then
            echo "Failed to download Tailscale from ${url}" >&2
            return 1
        fi
    else
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL --retry 3 --retry-delay 2 -o "${tarball}.tmp" "${url}"; then
                echo "Failed to download Tailscale from ${url}" >&2
                return 1
            fi
            if [ -n "${tailscale_sha}" ]; then
                _actual=$(sha256sum "${tarball}.tmp" 2>/dev/null | awk '{print $1}') || _actual=$(shasum -a 256 "${tarball}.tmp" 2>/dev/null | awk '{print $1}')
                if [ "${_actual}" != "${tailscale_sha}" ]; then
                    echo "Checksum mismatch for ${url} (expected ${tailscale_sha}, got ${_actual})" >&2
                    rm -f "${tarball}.tmp"
                    return 1
                fi
            fi
            mv "${tarball}.tmp" "${tarball}"
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -q --tries=3 -O "${tarball}.tmp" "${url}"; then
                echo "Failed to download Tailscale from ${url}" >&2
                return 1
            fi
            if [ -n "${tailscale_sha}" ]; then
                _actual=$(sha256sum "${tarball}.tmp" 2>/dev/null | awk '{print $1}') || _actual=$(shasum -a 256 "${tarball}.tmp" 2>/dev/null | awk '{print $1}')
                if [ "${_actual}" != "${tailscale_sha}" ]; then
                    echo "Checksum mismatch for ${url} (expected ${tailscale_sha}, got ${_actual})" >&2
                    rm -f "${tarball}.tmp"
                    return 1
                fi
            fi
            mv "${tarball}.tmp" "${tarball}"
        else
            echo "Neither curl nor wget found for Tailscale download" >&2
            return 1
        fi
        unset _actual
    fi

    # Extract
    tmp_dir=$(mktemp -d -t tailscale.XXXXXX)
    if command -v extract_tarball >/dev/null 2>&1; then
        if ! extract_tarball "${tarball}" "${tmp_dir}"; then
            echo "Failed to extract ${tarball}" >&2
            rm -rf "${tmp_dir}" "${tarball}"
            return 1
        fi
    else
        if ! tar -xzf "${tarball}" -C "${tmp_dir}"; then
            echo "Failed to extract ${tarball}" >&2
            rm -rf "${tmp_dir}" "${tarball}"
            return 1
        fi
    fi
    rm -f "${tarball}"

    # Archive layout: top-level dir or flat binaries
    tailscale_bin=$(find "${tmp_dir}" -type f -name "tailscale" | head -1)
    tailscaled_bin=$(find "${tmp_dir}" -type f -name "tailscaled" | head -1)

    if [ -z "${tailscale_bin}" ]; then
        echo "ERROR: tailscale binary not found in ${asset}" >&2
        rm -rf "${tmp_dir}"
        return 1
    fi

    cp -f "${tailscale_bin}" "${install_dir}/tailscale"
    chmod +x "${install_dir}/tailscale"
    fix_macos_quarantine "${install_dir}/tailscale" 2>/dev/null || true

    if [ -n "${tailscaled_bin}" ]; then
        cp -f "${tailscaled_bin}" "${install_dir}/tailscaled"
        chmod +x "${install_dir}/tailscaled"
        fix_macos_quarantine "${install_dir}/tailscaled" 2>/dev/null || true
        echo "Tailscale v${tailscale_version} installed to ${install_dir} (tailscale + tailscaled)"
    else
        echo "Tailscale v${tailscale_version} installed to ${install_dir} (tailscale only; tailscaled not in archive)"
    fi

    rm -rf "${tmp_dir}"
    return 0
}

# Ensure Tailscale is available (opt-in)
# Usage: ensure_tailscale <minions_home>
ensure_tailscale() {
    minions_home=$1

    if [ -x "${minions_home}/lib/tailscale/tailscale" ]; then
        echo "Tailscale found at ${minions_home}/lib/tailscale/tailscale"
        mkdir -p "${minions_home}/bin"
        ln -sf "${minions_home}/lib/tailscale/tailscale" "${minions_home}/bin/tailscale"
        if [ -x "${minions_home}/lib/tailscale/tailscaled" ]; then
            ln -sf "${minions_home}/lib/tailscale/tailscaled" "${minions_home}/bin/tailscaled"
        fi
        return 0
    fi

    echo "Tailscale not found, installing..."
    mkdir -p "${minions_home}/lib/tailscale"
    if ! install_tailscale "${minions_home}/lib/tailscale"; then
        echo "WARNING: Tailscale install failed (opt-in, non-fatal)" >&2
        return 1
    fi

    # Create symlinks in bin
    mkdir -p "${minions_home}/bin"
    if [ -x "${minions_home}/lib/tailscale/tailscale" ]; then
        ln -sf "${minions_home}/lib/tailscale/tailscale" "${minions_home}/bin/tailscale"
    fi
    if [ -x "${minions_home}/lib/tailscale/tailscaled" ]; then
        ln -sf "${minions_home}/lib/tailscale/tailscaled" "${minions_home}/bin/tailscaled"
    fi
    return 0
}
