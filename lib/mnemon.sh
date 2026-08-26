#!/usr/bin/env sh
# lib/mnemon.sh - Mnemon installation and seed import

# Install Mnemon binary (if not present)
# Usage: install_mnemon <install_dir>
install_mnemon() {
    install_dir=$1

    # Check if mnemon is already available
    if command -v mnemon >/dev/null 2>&1; then
        mnemon_binary=$(command -v mnemon)
        echo "Mnemon found at ${mnemon_binary}"
        mkdir -p "${install_dir}"
        ln -sf "${mnemon_binary}" "${install_dir}/mnemon"
        fix_macos_quarantine "${install_dir}/mnemon"
        return 0
    fi

    echo "Installing Mnemon..."
    # Try to download prebuilt binary first (faster than cargo)
    platform=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "${arch}" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
    esac

    # Try latest release download
    mnemon_url="https://github.com/mnemon-dev/mnemon/releases/latest/download/mnemon-${platform}-${arch}.tar.gz"
    echo "Attempting to download Mnemon from ${mnemon_url}..."
    if curl -fsSL "${mnemon_url}" | tar -xz -C "${install_dir}" mnemon 2>/dev/null; then
        chmod +x "${install_dir}/mnemon"
        fix_macos_quarantine "${install_dir}/mnemon"
        echo "Mnemon installed via prebuilt binary"
        return 0
    fi

    # Fallback: try specific version from releases
    mnemon_version="v0.2.5"
    mnemon_url="https://github.com/mnemon-dev/mnemon/releases/download/${mnemon_version}/mnemon-${platform}-${arch}.tar.gz"
    echo "Attempting to download Mnemon from ${mnemon_url}..."
    if curl -fsSL "${mnemon_url}" | tar -xz -C "${install_dir}" mnemon 2>/dev/null; then
        chmod +x "${install_dir}/mnemon"
        fix_macos_quarantine "${install_dir}/mnemon"
        echo "Mnemon installed via prebuilt binary (${mnemon_version})"
        return 0
    fi

    # Fallback to cargo if available
    if command -v cargo >/dev/null 2>&1; then
        cargo install mnemon --root "${install_dir}/mnemon-cargo" 2>/dev/null || true
        if [ -x "${install_dir}/mnemon-cargo/bin/mnemon" ]; then
            mkdir -p "${install_dir}"
            ln -sf "${install_dir}/mnemon-cargo/bin/mnemon" "${install_dir}/mnemon"
            fix_macos_quarantine "${install_dir}/mnemon"
            echo "Mnemon installed via cargo"
            return 0
        fi
    fi

    echo "ERROR: Mnemon not installed (no prebuilt binary or cargo available)" >&2
    return 1
}

# Ensure Mnemon is available
ensure_mnemon() {
    minions_home=$1

    if [ -x "${minions_home}/lib/mnemon/mnemon" ]; then
        echo "Mnemon found at ${minions_home}/lib/mnemon/mnemon"
        return 0
    fi

    echo "Mnemon not found, installing..."
    mkdir -p "${minions_home}/lib/mnemon"
    install_mnemon "${minions_home}/lib/mnemon"

    # Create symlink in bin
    if [ -x "${minions_home}/lib/mnemon/mnemon" ]; then
        ln -sf "${minions_home}/lib/mnemon/mnemon" "${minions_home}/bin/mnemon"
    fi
}

# Import Mnemon seed for a target (hermes, pi, or both)
# Usage: import_mnemon_seed <target> <seed_file> [store_name]
import_mnemon_seed() {
    target=$1
    seed_file=$2
    store_name=${3:-default}

    if [ ! -f "${seed_file}" ]; then
        echo "Seed file not found: ${seed_file}" >&2
        return 1
    fi

    echo "Importing Mnemon seed for ${target} from ${seed_file}..."

    if mnemon import "${seed_file}" --data-dir "${HOME}/.mnemon" --store "${store_name}" 2>/dev/null; then
        echo "Mnemon seed imported for ${target}"
    else
        echo "WARNING: Mnemon seed import failed for ${target}" >&2
        return 1
    fi
}

# Setup Mnemon for all targets (hermes, pi, etc.)
# Usage: setup_mnemon_all <minions_home>
setup_mnemon_all() {
    minions_home=$1

    echo "Setting up Mnemon for all targets..."

    # Ensure mnemon is available
    if ! command -v mnemon >/dev/null 2>&1; then
        # Check if we have a stub
        if [ -x "${minions_home}/bin/mnemon" ]; then
            echo "Using Mnemon stub (not fully installed)"
        else
            echo "Mnemon not in PATH, skipping setup" >&2
            return 0
        fi
    fi

    # Setup for Pi
    mnemon setup --target pi --global --yes 2>/dev/null || echo "WARNING: Mnemon Pi setup failed" >&2

    # Setup for Hermes
    mnemon setup --target hermes --global --yes 2>/dev/null || echo "WARNING: Mnemon Hermes setup failed" >&2

    # Import seeds if they exist
    for target in pi hermes; do
        seed_file="${minions_home}/etc/mnemon-seed-${target}.json"
        if [ -f "${seed_file}" ]; then
            import_mnemon_seed "${target}" "${seed_file}" "default"
        fi
    done
}