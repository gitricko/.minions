#!/usr/bin/env sh
# lib/ollama.sh - Ollama installation and management

# Source versions.env for single source of truth (set by install.sh)
# MINIONS_HOME must already be set; versions.env provides OLLAMA_VERSION
# shellcheck disable=SC1091,SC2153
if [ -f "${MINIONS_HOME}/etc/versions.env" ]; then
    . "${MINIONS_HOME}/etc/versions.env"
fi

# Install Ollama binary (if not present)
# Usage: install_ollama <install_dir>
install_ollama() {
    install_dir=$1

    # Check if ollama is already available
    if command -v ollama >/dev/null 2>&1; then
        ollama_binary=$(command -v ollama)
        echo "Ollama found at ${ollama_binary}"
        mkdir -p "${install_dir}"
        ln -sf "${ollama_binary}" "${install_dir}/ollama"
        fix_macos_quarantine "${install_dir}/ollama"
        return 0
    fi

    echo "Installing Ollama..."
    platform=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "${arch}" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac

    ollama_version="${OLLAMA_VERSION:-0.40.0}"
    # Strip leading 'v' if present (versions.env stores v0.40.0)
    ollama_version="${ollama_version#v}"

    # Determine asset name and URL
    if [ "${platform}" = "darwin" ]; then
        # macOS universal binary
        asset="ollama-darwin.tgz"
        url="https://github.com/ollama/ollama/releases/download/v${ollama_version}/${asset}"
    else
        # Linux
        asset="ollama-${platform}-${arch}.tar.zst"
        url="https://github.com/ollama/ollama/releases/download/v${ollama_version}/${asset}"
    fi

    echo "Attempting to download Ollama from ${url}..."
    if curl -fsSL "${url}" -o "${install_dir}/${asset}"; then
        # Extract
        if extract_tarball "${install_dir}/${asset}" "${install_dir}"; then
            # Archive layout: bin/ollama + lib/ollama/* (handle both)
            if [ -f "${install_dir}/bin/ollama" ]; then
                mv "${install_dir}/bin/ollama" "${install_dir}/ollama"
                rmdir "${install_dir}/bin" 2>/dev/null || true
            fi
            if [ -f "${install_dir}/ollama" ]; then
                chmod +x "${install_dir}/ollama"
                fix_macos_quarantine "${install_dir}/ollama"
                echo "Ollama installed via prebuilt binary (v${ollama_version})"
                rm -f "${install_dir}/${asset}"
                return 0
            fi
        fi
        rm -f "${install_dir}/${asset}"
    fi

    # Fallback: try the official install script (unpinned, but works as last resort)
    echo "Prebuilt binary download failed; trying official install script..."
    if curl -fsSL https://ollama.com/install.sh | sh; then
        if command -v ollama >/dev/null 2>&1; then
            ollama_binary=$(command -v ollama)
            mkdir -p "${install_dir}"
            ln -sf "${ollama_binary}" "${install_dir}/ollama"
            fix_macos_quarantine "${install_dir}/ollama"
            echo "Ollama installed via official install script"
            return 0
        fi
    fi

    echo "ERROR: Ollama not installed (no prebuilt binary or install script available)" >&2
    return 1
}

# Ensure Ollama is available
# Usage: ensure_ollama <minions_home>
ensure_ollama() {
    minions_home=$1

    if [ -x "${minions_home}/lib/ollama/ollama" ]; then
        echo "Ollama found at ${minions_home}/lib/ollama/ollama"
        mkdir -p "${minions_home}/bin"
        ln -sf "${minions_home}/lib/ollama/ollama" "${minions_home}/bin/ollama"
        return 0
    fi

    echo "Ollama not found, installing..."
    mkdir -p "${minions_home}/lib/ollama"
    install_ollama "${minions_home}/lib/ollama"

    # Create symlink in bin
    if [ -x "${minions_home}/lib/ollama/ollama" ]; then
        ln -sf "${minions_home}/lib/ollama/ollama" "${minions_home}/bin/ollama"
    fi
}

# Start Ollama service
# Usage: start_ollama <minions_home>
start_ollama() {
    minions_home=$1

    if pgrep -f "ollama serve" >/dev/null; then
        echo "Ollama already running"
        return 0
    fi

    echo "Starting Ollama service..."
    mkdir -p "${minions_home}/var/log"
    setsid "${minions_home}/bin/ollama" serve >> "${minions_home}/var/log/ollama.log" 2>&1 &
    echo $! > "${minions_home}/var/run/ollama.pid"

    # Wait for server to be ready
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if curl -s --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
            echo "Ollama service ready"
            return 0
        fi
        sleep 1
    done

    echo "WARNING: Ollama service may not be ready yet" >&2
    return 1
}

# Stop Ollama service
# Usage: stop_ollama <minions_home>
stop_ollama() {
    minions_home=$1

    if [ -f "${minions_home}/var/run/ollama.pid" ]; then
        pid=$(cat "${minions_home}/var/run/ollama.pid" 2>/dev/null)
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            echo "Stopping Ollama (PID ${pid})..."
            kill "${pid}" 2>/dev/null
            sleep 2
            kill -9 "${pid}" 2>/dev/null
        fi
        rm -f "${minions_home}/var/run/ollama.pid"
    else
        # Fallback: pkill
        pkill -f "ollama serve" 2>/dev/null || true
    fi
}

# Pull required embedding model
# Usage: pull_ollama_model <model_name>
pull_ollama_model() {
    model="${1:-nomic-embed-text}"

    echo "Pulling Ollama model: ${model}..."
    if ollama pull "${model}" >> "${MINIONS_HOME}/var/log/ollama-pull.log" 2>&1; then
        echo "Model ${model} pulled successfully"
        return 0
    else
        echo "WARNING: Failed to pull model ${model}" >&2
        return 1
    fi
}