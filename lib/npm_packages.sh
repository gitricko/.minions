#!/usr/bin/env sh
# lib/npm_packages.sh - npm package installation (OmniRoute, ModelRelay)

# Install npm package globally into our vendored location
# Usage: install_npm_package <package_name> <version> <install_dir> <bin_name> [bin_path_in_package]
install_npm_package() {
    pkg_name=$1
    pkg_version=$2
    pkg_install_dir=$3
    bin_name=$4
    bin_path_in_package=${5:-"bin/${bin_name}"}

    # Capture system npm FULL PATH BEFORE ensure_node_v22 prepends vendored node to PATH
    # Use absolute path to avoid any PATH resolution issues
    if [ -x "/home/codespace/nvm/current/bin/npm" ]; then
        system_npm="/home/codespace/nvm/current/bin/npm"
    elif [ -x "/usr/bin/npm" ]; then
        system_npm="/usr/bin/npm"
    else
        system_npm="npm"
    fi

    # Suppress interactive prompts from postinstall scripts (playwright, etc.)
    export CI=true
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export PUPPETEER_SKIP_DOWNLOAD=1

    # Use vendored node for runtime
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/node.sh"
    ensure_node_v22

    # Use npm with custom prefix (NO -g flag - causes EACCES in newer npm)
    npm_prefix="${pkg_install_dir}/npm"
    mkdir -p "${npm_prefix}/lib/node_modules"

    echo "Installing ${pkg_name}@${pkg_version}..."
    "${system_npm}" install "${pkg_name}@${pkg_version}" \
        --prefix "${npm_prefix}" \
        --no-audit \
        --no-fund \
        --loglevel error \
        --no-save \
        --legacy-peer-deps

    # Fix macOS quarantine
    fix_macos_quarantine "${npm_prefix}/lib/node_modules/.bin"

    # Find the actual binary path (npm 9+ hoists to prefix root)
    actual_binary=""
    for candidate in \
        "${npm_prefix}/${bin_path_in_package}" \
        "${npm_prefix}/node_modules/${pkg_name}/${bin_path_in_package}" \
        "${npm_prefix}/lib/node_modules/${pkg_name}/${bin_path_in_package}"; do
        if [ -f "${candidate}" ]; then
            actual_binary="${candidate}"
            break
        fi
    done

    if [ -z "${actual_binary}" ]; then
        echo "ERROR: Could not find binary at ${bin_path_in_package} for ${pkg_name}" >&2
        return 1
    fi

    echo "Found ${pkg_name} binary at: ${actual_binary}"

    # Create wrapper that calls the actual binary with vendored Node
    # Special case: omniroute CLI entry has a top-level-await bug (SyntaxError
    # on Node 22/24); bypass it and run the Next.js standalone server directly.
    # server.js reads PORT/HOSTNAME env vars, so translate --host/--port args.
    if [ "${pkg_name}" = "omniroute" ]; then
        cat > "${pkg_install_dir}/${bin_name}" << EOF
#!/usr/bin/env sh
export PATH="${MINIONS_HOME}/lib/node/bin:${npm_prefix}/lib/node_modules/.bin:\${PATH}"
export NODE_PATH="${npm_prefix}/lib/node_modules"
# Translate --host/--port CLI args into PORT/HOSTNAME env vars for server.js
host=""
port=""
for arg in "\$@"; do
    case "\$arg" in
        --version|-V) echo "${pkg_version}"; exit 0 ;;
    esac
done
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        --host) host="\$2"; shift 2 ;;
        --host=*) host="\${1#*=}"; shift ;;
        --port) port="\$2"; shift 2 ;;
        --port=*) port="\${1#*=}"; shift ;;
        *) shift ;;
    esac
done
[ -n "\$host" ] && export HOSTNAME="\$host"
[ -n "\$port" ] && export PORT="\$port"
exec "${MINIONS_HOME}/lib/node/bin/node" "${npm_prefix}/node_modules/omniroute/dist/server.js"
EOF
    else
        cat > "${pkg_install_dir}/${bin_name}" << EOF
#!/usr/bin/env sh
export PATH="${MINIONS_HOME}/lib/node/bin:${npm_prefix}/lib/node_modules/.bin:\${PATH}"
export NODE_PATH="${npm_prefix}/lib/node_modules"
exec "${actual_binary}" "\$@"
EOF
    fi
    make_executable "${pkg_install_dir}/${bin_name}"

    # Verify the binary works (bounded timeout — some bins hang on --version)
    if timeout 30 "${pkg_install_dir}/${bin_name}" --version >/dev/null 2>&1; then
        echo "${pkg_name}@${pkg_version} installed and verified at ${pkg_install_dir}"
    else
        echo "WARNING: ${pkg_name} installed but binary verification (--version) failed or timed out" >&2
    fi
}

# Ensure OmniRoute is available
ensure_omniroute() {
    if [ -x "${MINIONS_HOME}/lib/omniroute/omniroute" ]; then
        echo "OmniRoute found at ${MINIONS_HOME}/lib/omniroute/omniroute"
        return 0
    fi

    echo "OmniRoute not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/omniroute"
    install_npm_package "omniroute" "${OMNIROUTE_VERSION}" "${MINIONS_HOME}/lib/omniroute" "omniroute" "bin/omniroute.mjs"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/omniroute/omniroute" "${MINIONS_HOME}/bin/omniroute"
}

# Ensure ModelRelay is available
ensure_modelrelay() {
    if [ -x "${MINIONS_HOME}/lib/modelrelay/modelrelay" ]; then
        echo "ModelRelay found at ${MINIONS_HOME}/lib/modelrelay/modelrelay"
        return 0
    fi

    echo "ModelRelay not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/modelrelay"
    install_npm_package "modelrelay" "${MODELRELAY_VERSION}" "${MINIONS_HOME}/lib/modelrelay" "modelrelay" "bin/modelrelay.js"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/modelrelay/modelrelay" "${MINIONS_HOME}/bin/modelrelay"
}