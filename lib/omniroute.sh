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

    # Enable prompt compression (master toggle) + CCR & headroom engines +
    # Caveman LLM-output compression. Idempotent PUT; safe on every boot.
    OMNI_BASE="http://${OMNIROUTE_HOST:-127.0.0.1}:${OMNIROUTE_PORT:-20128}"
    if curl -fsS -X PUT "${OMNI_BASE}/api/settings/compression" \
        -H "Content-Type: application/json" \
        -d '{"enabled":true,"engines":{"ccr":{"enabled":true},"headroom":{"enabled":true}},"cavemanOutputMode":{"enabled":true,"intensity":"full","autoClarity":true}}' >/dev/null 2>&1; then
        echo "OmniRoute preconfig: compression (CCR+headroom+caveman) enabled"
    else
        echo "WARNING: omniroute compression settings failed" >&2
    fi

    echo "OmniRoute preconfig: checking auto-fastest combo..."
    # Check if combo already exists (avoids "already exists" error on retry)
    if "${omniroute_bin}" combo list --json 2>/dev/null | grep -q '"name": "auto-fastest"'; then
        echo "OmniRoute preconfig: auto-fastest combo already exists"
        return 0
    fi

    echo "OmniRoute preconfig: creating auto-fastest combo..."
    # OmniRoute 3.8.x: combo create is a CLI client command (server must be up).
    # Requires --models (comma-separated or JSON array) — old REST /api/combos form
    # is deprecated. Retry-loop because the server may still be warming up.
    retry_count=0
    while ! "${omniroute_bin}" combo create auto-fastest --strategy auto --models '[{"model":"oc/deepseek-v4-flash-free","providerId":"oc","weight":0},{"model":"oc/big-pickle","providerId":"oc","weight":0},{"model":"opencode-zen/deepseek-v4-flash-free","providerId":"opencode-zen","weight":0},{"model":"opencode-zen/hy3-free","providerId":"opencode-zen","weight":0},{"model":"opencode-zen/mimo-v2.5-free","providerId":"opencode-zen","weight":0},{"model":"opencode-zen/north-mini-code-free","providerId":"opencode-zen","weight":0},{"model":"opencode-zen/nemotron-3-ultra-free","providerId":"opencode-zen","weight":0},{"model":"opencode-zen/big-pickle","providerId":"opencode-zen","weight":0}]' >/dev/null 2>&1; do
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