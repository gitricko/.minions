#!/usr/bin/env sh
# lib/hermes.sh - Hermes Agent installation
#
# Install Hermes using their official install script (git-based, mirrors hermes-codespace)
# Usage: install_hermes <version> <install_dir>
install_hermes() {
    version=$1
    install_dir=$2

    # Pin to exact version tag (e.g. v2026.8.13)
    hermes_install_uri="https://raw.githubusercontent.com/NousResearch/hermes-agent/${version}/scripts/install.sh"
    hermes_fallback_uri="https://hermes-agent.nousresearch.com/install.sh"

    echo "Installing Hermes ${version} via official install script..."

    # Download install script
    tmp_script=$(mktemp)
    if ! curl -fsSL "${hermes_install_uri}" -o "${tmp_script}" 2>/dev/null; then
        echo "Primary URI failed, trying fallback..."
        curl -fsSL "${hermes_fallback_uri}" -o "${tmp_script}" || {
            echo "ERROR: could not download Hermes install script" >&2
            return 1
        }
    fi

    # The installer uses bash-specific syntax; run with bash not sh.
    # Install into the REAL ~/.hermes (standard location). Hermes resolves config
    # via get_hermes_home() = $HERMES_HOME or $HOME/.hermes, so installing with a
    # fake HOME (~/.minions/lib/hermes/home) would orphan the config we write at
    # $HOME/.hermes/config.yaml. No HOME override = one source of truth.
    bash "${tmp_script}" --skip-setup || {
        echo "ERROR: Hermes install script failed" >&2
        rm -f "${tmp_script}"
        return 1
    }
    rm -f "${tmp_script}"

    # Find the installed hermes binary. Prefer the venv entrypoint (its shebang
    # points at the venv python, which has all deps incl. python-dotenv). The
    # source-tree `hermes` launcher uses `#!/usr/bin/env python3` and would pick
    # the system python (which lacks dotenv) -> ModuleNotFoundError.
    hermes_bin=$(find "${HOME}/.hermes/hermes-agent/venv/bin" -type f -name "hermes" 2>/dev/null | head -1)
    if [ -z "${hermes_bin}" ]; then
        hermes_bin=$(find "${HOME}/.hermes" "${HOME}/.local/bin" -type f -name "hermes" 2>/dev/null | head -1)
    fi
    if [ -z "${hermes_bin}" ]; then
        hermes_bin=$(command -v hermes 2>/dev/null || true)
    fi

    if [ -z "${hermes_bin}" ]; then
        echo "ERROR: Hermes binary not found after install" >&2
        return 1
    fi

    # Create direct symlink (no wrapper - config is at ~/.hermes/config.yaml)
    ln -sf "${hermes_bin}" "${install_dir}/hermes"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}"

    # Verify the binary works (bounded timeout)
    if timeout 30 "${install_dir}/hermes" --version >/dev/null 2>&1; then
        echo "Hermes ${version} installed and verified at ${install_dir}"
    else
        echo "WARNING: Hermes installed but binary verification (--version) failed or timed out" >&2
    fi
}

# Ensure Hermes is available
ensure_hermes() {
    if [ -x "${MINIONS_HOME}/lib/hermes/hermes" ]; then
        echo "Hermes found at ${MINIONS_HOME}/lib/hermes/hermes"
        return 0
    fi

    echo "Hermes not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/hermes"
    install_hermes "${HERMES_VERSION}" "${MINIONS_HOME}/lib/hermes"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/hermes/hermes" "${MINIONS_HOME}/bin/hermes"
}