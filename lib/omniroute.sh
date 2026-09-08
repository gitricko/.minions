#!/usr/bin/env sh
# lib/omniroute.sh - OmniRoute preconfiguration

# Preconfigure OmniRoute after it's healthy
# Usage: omniroute_preconfigure <host> <port>
omniroute_preconfigure() {
    host=$1
    port=$2
    base_url="http://${host}:${port}"

    echo "OmniRoute preconfig: disabling login requirement..."
    # Disable login (sqlite)
    sqlite3 "${HOME}/.omniroute/storage.sqlite" \
        "UPDATE key_value SET value='false' WHERE key='requireLogin';" || \
        curl -s -X PATCH "${base_url}/api/settings" \
            -H "Content-Type: application/json" \
            -d '{"requireLogin": false}' >/dev/null || true

    echo "OmniRoute preconfig: creating auto-fastest combo..."
    # OmniRoute 3.8.x: combo create is a CLI client command (server must be up).
    # Requires --models (comma-separated or JSON array) — old REST /api/combos form
    # is deprecated. Retry-loop because the server may still be warming up.
    while ! omniroute combo create auto-fastest --strategy auto --models '["oc/deepseek-v4-flash-free","oc/big-pickle","opencode-zen/deepseek-v4-flash-free","opencode-zen/hy3-free","opencode-zen/mimo-v2.5-free","opencode-zen/north-mini-code-free","opencode-zen/nemotron-3-ultra-free","opencode-zen/big-pickle"]' >/dev/null 2>&1; do
        echo "omniroute still not ready yet, retrying..."
        sleep 3
    done

    echo "OmniRoute preconfig complete"
}