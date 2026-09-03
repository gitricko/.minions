#!/usr/bin/env sh
# lib/pi.sh - Pi-Agent installation and configuration

# Install Pi-Agent via npm
# Usage: install_pi <version> <install_dir>
install_pi() {
    version=$1
    install_dir=$2

    echo "Installing Pi-Agent ${version} via npm..."

    # Use npm with custom prefix (like OmniRoute/ModelRelay)
    npm_prefix="${install_dir}/npm"
    mkdir -p "${npm_prefix}/lib/node_modules"

    # Set npm config to use our prefix (avoids writing to global node_modules)
    npm install "@earendil-works/pi-coding-agent@${version}" \
        --prefix "${npm_prefix}" \
        --no-audit \
        --no-fund \
        --loglevel error \
        --no-save || {
        # Fallback: try with --global-style in the prefix dir
        (cd "${npm_prefix}" && npm install "@earendil-works/pi-coding-agent@${version}" --no-audit --no-fund --loglevel error) || {
            echo "ERROR: Pi-Agent npm install failed" >&2
            return 1
        }
    }

    # Find the pi binary in the package (try multiple locations)
        pi_binary=""
        # First check if package is hoisted to root of prefix (npm 9+ behavior)
        for candidate in \
            "${npm_prefix}/dist/cli.js" \
            "${npm_prefix}/dist/bun/cli.js" \
            "${npm_prefix}/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
            "${npm_prefix}/node_modules/@earendil-works/pi-coding-agent/dist/bun/cli.js" \
            "${npm_prefix}/node_modules/pi-coding-agent/dist/cli.js" \
            "${npm_prefix}/node_modules/pi-coding-agent/dist/bun/cli.js"; do
            if [ -f "${candidate}" ]; then
                pi_binary="${candidate}"
                break
            fi
        done

        if [ -z "${pi_binary}" ]; then
            # Fallback: use npm ls to find the package location
            echo "DEBUG: Using npm ls to find pi-coding-agent..." >&2
            cd "${npm_prefix}" && npm ls @earendil-works/pi-coding-agent --prefix "${npm_prefix}" 2>&1 | head -20 >&2
        
            # Also try finding via npm list --json
            pi_binary=$(cd "${npm_prefix}" && npm ls @earendil-works/pi-coding-agent --prefix "${npm_prefix}" --json 2>/dev/null | \
                grep -o '"path":"[^"]*"' | head -1 | sed 's/"path":"//;s/"//' 2>/dev/null)
            if [ -n "${pi_binary}" ] && [ -f "${pi_binary}/dist/cli.js" ]; then
                pi_binary="${pi_binary}/dist/cli.js"
            fi
        fi

        if [ -z "${pi_binary}" ]; then
            # Fallback: search for any cli.js
            echo "DEBUG: Searching for pi binary..." >&2
            echo "DEBUG: npm_prefix = ${npm_prefix}" >&2
            echo "DEBUG: prefix root contents:" >&2
            ls -la "${npm_prefix}/" 2>/dev/null >&2 || echo "DEBUG: prefix root not found" >&2
            echo "DEBUG: node_modules contents:" >&2
            ls -la "${npm_prefix}/node_modules/" 2>/dev/null >&2 || echo "DEBUG: node_modules not found" >&2
            echo "DEBUG: @earendil-works contents:" >&2
            ls -la "${npm_prefix}/node_modules/@earendil-works/" 2>/dev/null >&2 || echo "DEBUG: @earendil-works not found" >&2
            echo "DEBUG: Full find for cli.js:" >&2
            find "${npm_prefix}" -name "cli.js" 2>/dev/null | head -30 >&2
            echo "DEBUG: Full find for pi-coding-agent:" >&2
            find "${npm_prefix}" -name "pi-coding-agent" -type d 2>/dev/null | head -20 >&2
            pi_binary=$(find "${npm_prefix}" -name "cli.js" -path "*/pi-coding-agent/*" 2>/dev/null | head -1)
        fi

        if [ -z "${pi_binary}" ] || [ ! -f "${pi_binary}" ]; then
            echo "ERROR: Pi-Agent binary not found in ${npm_prefix}" >&2
            find "${npm_prefix}" -name "cli.js" 2>/dev/null | head -20 >&2
            return 1
        fi

        echo "Found Pi-Agent binary at: ${pi_binary}"

        # Fix macOS quarantine
        fix_macos_quarantine "${npm_prefix}/lib/node_modules/.bin"

        # Create wrapper script (use printf to avoid heredoc issues)
                # Use MINIONS_HOME-based paths so wrapper works regardless of install location
                printf '#!/usr/bin/env sh\n%s\n%s\n%s\n%s\n' \
                    "export PATH=\"\${MINIONS_HOME}/lib/pi/npm/lib/node_modules/.bin:\${PATH}\"" \
                    "export NODE_PATH=\"\${MINIONS_HOME}/lib/pi/npm/lib/node_modules\"" \
                    "cd \"\${MINIONS_HOME}/lib/pi/npm\"" \
                    "exec \"\${MINIONS_HOME}/lib/pi/npm/node_modules/.bin/pi\" \"\$@\"" \
                    > "${install_dir}/pi"
                make_executable "${install_dir}/pi"

    # Verify the binary works (bounded timeout)
    if timeout 30 "${install_dir}/pi" --version >/dev/null 2>&1; then
        echo "Pi-Agent ${version} installed (npm) and linked to ${install_dir}/pi"
    else
        echo "WARNING: Pi-Agent installed but binary verification (--version) failed or timed out" >&2
    fi
}

# Install pi-failover extension
# Usage: install_pi_failover_ext <install_dir>
install_pi_failover_ext() {
    install_dir=$1

    echo "Installing pi-failover extension..."

    # Use pi to install the extension
    if "${install_dir}/pi" install git:github.com/gitricko/pi-failover@hermes-impl 2>/dev/null; then
        echo "pi-failover extension installed"
    else
        echo "WARNING: pi-failover extension install failed (may not exist yet)" >&2
    fi
}

# Setup Mnemon Pi plugin
# Usage: setup_mnemon_pi <minions_home>
setup_mnemon_pi() {
    minions_home=$1
    echo "Setting up Mnemon Pi plugin..."

    # Use local mnemon if available, otherwise fall back to system
    if [ -x "${minions_home}/bin/mnemon" ]; then
        MNEMON_BIN="${minions_home}/bin/mnemon"
    elif command -v mnemon >/dev/null 2>&1; then
        MNEMON_BIN="mnemon"
    else
        echo "Mnemon not found, skipping Pi plugin setup" >&2
        return 0
    fi

    # Run mnemon setup for pi target
    if "${MNEMON_BIN}" setup --target pi --global --yes 2>/dev/null; then
        echo "Mnemon Pi plugin setup complete"
    else
        echo "WARNING: Mnemon Pi plugin setup failed" >&2
    fi
}

# Create Pi config symlinks
# Usage: create_pi_symlinks <minions_home>
create_pi_symlinks() {
    minions_home=$1

    echo "Creating Pi config symlinks..."

    # Ensure ~/.pi directory exists
    mkdir -p "${HOME}/.pi"

    # Symlink pi.toml
    if [ -f "${minions_home}/etc/pi.toml" ]; then
        ln -sf "${minions_home}/etc/pi.toml" "${HOME}/.pi/pi.toml"
        echo "Symlinked pi.toml"
    else
        echo "WARNING: ${minions_home}/etc/pi.toml not found" >&2
    fi

    # Symlink models.json if it exists
    if [ -f "${minions_home}/etc/models.json" ]; then
        ln -sf "${minions_home}/etc/models.json" "${HOME}/.pi/models.json"
        echo "Symlinked models.json"
    fi

    # Symlink settings.json if it exists
    if [ -f "${minions_home}/etc/settings.json" ]; then
        ln -sf "${minions_home}/etc/settings.json" "${HOME}/.pi/settings.json"
        echo "Symlinked settings.json"
    fi
}

# Ensure Pi-Agent is available
ensure_pi() {
    # shellcheck disable=SC2153
    if [ -x "${MINIONS_HOME}/lib/pi/pi" ]; then
        echo "Pi-Agent found at ${MINIONS_HOME}/lib/pi/pi"
        return 0
    fi

    echo "Pi-Agent not found, installing via npm..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/pi"
    install_pi "${PI_VERSION}" "${MINIONS_HOME}/lib/pi"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/pi/pi" "${MINIONS_HOME}/bin/pi"

    # Install pi-failover extension (needs proxies running, but we'll try during install too)
    # This will fail if proxies aren't running, but that's okay - we'll retry at boot
    if [ "${OMNIROUTE_PORT:-20128}" ] && [ "${MODELRELAY_PORT:-7352}" ]; then
        # Proxies might not be running yet during install, but let's try
        echo "Installing pi-failover extension..."
        if "${MINIONS_HOME}/bin/pi" install git:github.com/gitricko/pi-failover@hermes-impl 2>/dev/null; then
            echo "pi-failover extension installed"
        else
            echo "pi-failover extension install will retry at boot (proxies not running yet)"
        fi
    fi

    # Run config steps
    setup_mnemon_pi "${MINIONS_HOME}"
    create_pi_symlinks "${MINIONS_HOME}"
}

# Update Pi config with actual proxy ports
# Usage: pi_update_config <omniroute_port> <modelrelay_port>
# Updates both pi.toml and models.json in ~/.pi/ with actual running ports
pi_update_config() {
    omniroute_port="${1:-${OMNIROUTE_PORT:-20128}}"
    modelrelay_port="${2:-${MODELRELAY_PORT:-7352}}"
    omniroute_url="http://127.0.0.1:${omniroute_port}/v1"
    modelrelay_url="http://127.0.0.1:${modelrelay_port}/v1"

    echo "Updating Pi config with ports: omniroute=${omniroute_port}, modelrelay=${modelrelay_port}"

    # Update pi.toml
    if [ -f "${HOME}/.pi/pi.toml" ]; then
        sed -i "s|base_url = \".*\"|base_url = \"${omniroute_url}\"|" "${HOME}/.pi/pi.toml"
        # Add provider if not present
        if ! grep -q '^provider =' "${HOME}/.pi/pi.toml"; then
            sed -i '/^model = "auto"/a # Default provider to use (both omniroute and modelrelay have auto-fastest)\nprovider = "omniroute"' "${HOME}/.pi/pi.toml"
        else
            sed -i "s|provider = \".*\"|provider = \"omniroute\"|" "${HOME}/.pi/pi.toml"
        fi
        echo "Updated pi.toml base_url to ${omniroute_url}"
    fi

    # Update models.json (using Python for reliable JSON manipulation)
    if [ -f "${HOME}/.pi/models.json" ]; then
        python3 -c "
import json
with open('${HOME}/.pi/models.json', 'r') as f:
    cfg = json.load(f)
cfg['providers']['omniroute']['baseUrl'] = '${omniroute_url}'
cfg['providers']['modelrelay']['baseUrl'] = '${modelrelay_url}'
# Also update model-level baseUrl for both providers
if 'models' in cfg['providers']['omniroute']:
    for model in cfg['providers']['omniroute']['models']:
        model['baseUrl'] = '${omniroute_url}'
if 'models' in cfg['providers']['modelrelay']:
    for model in cfg['providers']['modelrelay']['models']:
        model['baseUrl'] = '${modelrelay_url}'
with open('${HOME}/.pi/models.json', 'w') as f:
    json.dump(cfg, f, indent=2)
"
        echo "Updated models.json baseUrl to omniroute=${omniroute_url}, modelrelay=${modelrelay_url}"
    fi
}