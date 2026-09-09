#!/usr/bin/env sh
# lib/omniroute.sh - OmniRoute preconfiguration
#
# Login-off is handled at install time via omniroute setup + sqlite.
# This function only creates the auto-fastest combo (requires running server).
# Usage: omniroute_preconfigure
omniroute_preconfigure() {
    omniroute_bin="${MINIONS_HOME}/bin/omniroute"
    export PATH="${MINIONS_HOME}/lib/node/bin:${MINIONS_HOME}/lib/omniroute/npm/lib/node_modules/.bin:${PATH}"
    export NODE_PATH="${MINIONS_HOME}/lib/omniroute/npm/lib/node_modules"

    echo "OmniRoute preconfig: creating auto-fastest combo..."
    # OmniRoute 3.8.x: combo create is a CLI client command (server must be up).
    # Requires --models (comma-separated or JSON array) — old REST /api/combos form
    # is deprecated. Retry-loop because the server may still be warming up.
    retry_count=0
    while ! "${omniroute_bin}" combo create auto-fastest --strategy auto --models '["oc/deepseek-v4-flash-free","oc/big-pickle","opencode-zen/deepseek-v4-flash-free","opencode-zen/hy3-free","opencode-zen/mimo-v2.5-free","opencode-zen/north-mini-code-free","opencode-zen/nemotron-3-ultra-free","opencode-zen/big-pickle"]' >/dev/null 2>&1; do
        retry_count=$((retry_count + 1))
        if [ "${retry_count}" -gt 40 ]; then
            echo "WARNING: omniroute combo create timed out after 120s" >&2
            return 1
        fi
        echo "omniroute still not ready yet, retrying..."
        sleep 3
    done

    echo "OmniRoute preconfig complete"
}