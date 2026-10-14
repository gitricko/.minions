#!/usr/bin/env sh
# lib/mnemon.sh - Mnemon installation and seed import

# Source versions.env for single source of truth (set by install.sh)
# MINIONS_HOME must already be set; versions.env provides MNEMON_VERSION
# shellcheck disable=SC1091,SC2153
if [ -f "${MINIONS_HOME}/etc/versions.env" ]; then
    . "${MINIONS_HOME}/etc/versions.env"
fi

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
    platform=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "${arch}" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac

    mnemon_version="${MNEMON_VERSION:-0.2.9}"
    mnemon_version="${mnemon_version#v}"

    mnemon_url="https://github.com/mnemon-dev/mnemon/releases/latest/download/mnemon_${mnemon_version}_${platform}_${arch}.tar.gz"
    echo "Attempting to download Mnemon from ${mnemon_url}..."
    if curl -fsSL "${mnemon_url}" | tar -xz -C "${install_dir}" mnemon 2>/dev/null; then
        chmod +x "${install_dir}/mnemon"
        fix_macos_quarantine "${install_dir}/mnemon"
        echo "Mnemon installed via prebuilt binary"
        return 0
    fi

    mnemon_url="https://github.com/mnemon-dev/mnemon/releases/download/v${mnemon_version}/mnemon_${mnemon_version}_${platform}_${arch}.tar.gz"
    echo "Attempting to download Mnemon from ${mnemon_url}..."
    if curl -fsSL "${mnemon_url}" | tar -xz -C "${install_dir}" mnemon 2>/dev/null; then
        chmod +x "${install_dir}/mnemon"
        fix_macos_quarantine "${install_dir}/mnemon"
        echo "Mnemon installed via prebuilt binary (v${mnemon_version})"
        return 0
    fi

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

ensure_mnemon() {
    minions_home=$1

    if [ -x "${minions_home}/lib/mnemon/mnemon" ]; then
        echo "Mnemon found at ${minions_home}/lib/mnemon/mnemon"
        return 0
    fi

    echo "Mnemon not found, installing..."
    mkdir -p "${minions_home}/lib/mnemon"
    install_mnemon "${minions_home}/lib/mnemon"

    if [ -x "${minions_home}/lib/mnemon/mnemon" ]; then
        ln -sf "${minions_home}/lib/mnemon/mnemon" "${minions_home}/bin/mnemon"
    fi
}

# Import Mnemon seed — dry-run validates, real import is deduped + non-fatal
# Usage: import_mnemon_seed <seed_file>
import_mnemon_seed() {
    seed_file=$1
    if [ ! -f "${seed_file}" ]; then
        echo "Seed file not found: ${seed_file}" >&2
        return 1
    fi
    if [ -x "${MINIONS_HOME}/bin/mnemon" ]; then
        MNEMON_BIN="${MINIONS_HOME}/bin/mnemon"
    elif command -v mnemon >/dev/null 2>&1; then
        MNEMON_BIN="$(command -v mnemon)"
    else
        echo "mnemon not found, skipping seed import" >&2
        return 0
    fi
    echo "Validating Mnemon seed ${seed_file}..."
    if ! "${MNEMON_BIN}" import --dry-run "${seed_file}" >/dev/null 2>&1; then
        echo "WARNING: mnemon import --dry-run failed for ${seed_file} (skipping)" >&2
        return 0
    fi
    echo "Importing Mnemon seed from ${seed_file}..."
    if "${MNEMON_BIN}" import "${seed_file}" 2>&1 | head -20; then
        echo "Mnemon seed imported"
    else
        echo "WARNING: mnemon seed import failed (non-fatal)" >&2
    fi
    # Surface embedding coverage (degraded mode is ok — Ollama may still be pulling)
    "${MNEMON_BIN}" embed --status 2>/dev/null | head -5 || true
    return 0
}

# Setup Mnemon for all targets — now seeds default knowledge (non-fatal)
# Usage: setup_mnemon_all <minions_home>
setup_mnemon_all() {
    _minions_home="${1:-${MINIONS_HOME}}"
    # Resolve seed via MODE (dev -> repo, standalone -> MINIONS_HOME)
    # MODE is set by detect_knowledge_mode (sourced by install.sh/boot.sh)
    if [ "${MODE:-standalone}" = "dev" ] && [ -n "${MINIONS_REPO_ROOT:-}" ] && [ -f "${MINIONS_REPO_ROOT}/mnemon/seed.json" ]; then
        _seed="${MINIONS_REPO_ROOT}/mnemon/seed.json"
    elif [ -f "${_minions_home}/mnemon/seed.json" ]; then
        _seed="${_minions_home}/mnemon/seed.json"
    elif [ -f "${MINIONS_HOME}/mnemon/seed.json" ]; then
        _seed="${MINIONS_HOME}/mnemon/seed.json"
    else
        echo "No mnemon seed found, skipping import"
        return 0
    fi
    # Never abort install/boot on seed failure
    set +e
    import_mnemon_seed "${_seed}"
    _rc=$?
    set -e
    return 0
}
