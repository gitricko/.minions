#!/usr/bin/env sh
# lib/hermes.sh - Hermes Agent installation

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

    # Run installer with custom HOME so it doesn't touch the host's ~/.hermes
    HERMES_HOME_OVERRIDE="${install_dir}/home"
    mkdir -p "${HERMES_HOME_OVERRIDE}"

    # The installer uses bash-specific syntax; run with bash not sh
    HOME="${HERMES_HOME_OVERRIDE}" bash "${tmp_script}" --skip-setup || {
        echo "ERROR: Hermes install script failed" >&2
        rm -f "${tmp_script}"
        return 1
    }
    rm -f "${tmp_script}"

    # Find the installed hermes binary
    hermes_bin=$(find "${HERMES_HOME_OVERRIDE}" -type f -name "hermes" 2>/dev/null | head -1)
    if [ -z "${hermes_bin}" ]; then
        # Fallback: installer may have used standard ~/.hermes
        hermes_bin=$(command -v hermes 2>/dev/null || true)
    fi

    if [ -z "${hermes_bin}" ]; then
        echo "ERROR: Hermes binary not found after install" >&2
        return 1
    fi

    # Create wrapper script in our install_dir
    cat > "${install_dir}/hermes" << EOF
#!/usr/bin/env sh
export HERMES_HOME="${HERMES_HOME_OVERRIDE}"
exec "${hermes_bin}" "\$@"
EOF
    make_executable "${install_dir}/hermes"

    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}"

    # Verify the binary works (bounded timeout)
    if timeout 30 "${install_dir}/hermes" --version >/dev/null 2>&1; then
        echo "Hermes ${version} installed and verified at ${install_dir}"
    else
        echo "WARNING: Hermes installed but binary verification (--version) failed or timed out" >&2
    fi

    # Install python-dotenv in Hermes managed venv (required for hermes_cli)
    # The managed uv is at ${HERMES_HOME_OVERRIDE}/.hermes/bin/uv
    if [ -x "${HERMES_HOME_OVERRIDE}/.hermes/bin/uv" ]; then
        "${HERMES_HOME_OVERRIDE}/.hermes/bin/uv" pip install python-dotenv >/dev/null 2>&1 || true
    fi

    # Preconfigure Hermes (if requested)
    if [ "${MINIONS_HERMES_PRECONFIG:-0}" -eq 1 ]; then
        hermes_preconfigure
    fi
}

# Preconfigure Hermes after install
# Sets up: auto-fastest model combo, omniroute login off (no MCP integration)
hermes_preconfigure() {
    echo "Preconfiguring Hermes..."

    # Ensure HERMES config dir exists
    mkdir -p "${HOME}/.hermes"

    # Set auto-fastest model combo (uses OmniRoute by default)
    hermes config set model.provider auto-fastest 2>/dev/null || true

    # Disable OmniRoute login requirement (mirrors start-hermes.sh)
    hermes config set omniroute.login_required false 2>/dev/null || true

    echo "Hermes preconfig complete"
}

# Update Hermes config.yaml with current ports
# Usage: hermes_update_config [omniroute_port] [modelrelay_port]
# If ports not provided, reads from OMNIROUTE_PORT/MODELRELAY_PORT env vars
hermes_update_config() {
    omniroute_port="${1:-${OMNIROUTE_PORT:-20128}}"
    modelrelay_port="${2:-${MODELRELAY_PORT:-7352}}"
    omniroute_url="http://127.0.0.1:${omniroute_port}/v1"
    modelrelay_url="http://127.0.0.1:${modelrelay_port}/v1"

    # Determine Hermes config file path
    config_file=""
    if [ -n "${HERMES_CONFIG_FILE:-}" ] && [ -f "${HERMES_CONFIG_FILE}" ]; then
        config_file="${HERMES_CONFIG_FILE}"
    elif [ -n "${HERMES_HOME:-}" ] && [ -f "${HERMES_HOME}/config.yaml" ]; then
        config_file="${HERMES_HOME}/config.yaml"
    elif [ -n "${HERMES_HOME:-}" ] && [ -f "${HERMES_HOME}/.hermes/config.yaml" ]; then
        config_file="${HERMES_HOME}/.hermes/config.yaml"
    elif [ -f "${HOME}/.hermes/config.yaml" ]; then
        config_file="${HOME}/.hermes/config.yaml"
    else
        # Config doesn't exist yet; nothing to update
        return 0
    fi

    # Use Python for reliable YAML manipulation
    python3 -c "
import yaml
import sys

config_file = '${config_file}'
omniroute_url = '${omniroute_url}'
modelrelay_url = '${modelrelay_url}'

with open(config_file, 'r') as f:
    config = yaml.safe_load(f) or {}

if 'custom_providers' not in config:
    config['custom_providers'] = {}

config['custom_providers']['omniroute'] = {'base_url': omniroute_url}
config['custom_providers']['modelrelay'] = {'base_url': modelrelay_url}

with open(config_file, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print('Hermes config updated: omniroute -> {} , modelrelay -> {}'.format(omniroute_url, modelrelay_url))
" 2>/dev/null || {
        echo "WARNING: Python YAML update failed, trying sed fallback..." >&2
        # Fallback sed approach (original logic)
        if ! grep -q "^custom_providers:" "${config_file}" 2>/dev/null; then
            sed -i "/^[^#]/i\\\ncustom_providers:\\\n  omniroute:\\\n    base_url: ${omniroute_url}\\\n  modelrelay:\\\n    base_url: ${modelrelay_url}\\\n" "${config_file}" 2>/dev/null || true
        else
            sed -i \
                -e "/^[[:space:]]*omniroute:/,/^[[:space:]]*[a-z]*:/ s|base_url:.*|base_url: ${omniroute_url}|" \
                -e "/^[[:space:]]*modelrelay:/,/^[[:space:]]*[a-z]*:/ s|base_url:.*|base_url: ${modelrelay_url}|" \
                "${config_file}" 2>/dev/null || true
            if ! grep -q "omniroute:" "${config_file}" 2>/dev/null; then
                sed -i "/^custom_providers:/a\\\n  omniroute:\\\n    base_url: ${omniroute_url}" "${config_file}" 2>/dev/null || true
            fi
            if ! grep -q "modelrelay:" "${config_file}" 2>/dev/null; then
                sed -i "/^custom_providers:/a\\\n  modelrelay:\\\n    base_url: ${modelrelay_url}" "${config_file}" 2>/dev/null || true
            fi
        fi
    }
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