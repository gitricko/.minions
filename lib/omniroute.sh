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
    sqlite3 "${MINIONS_HOME}/var/lib/omniroute/omniroute.db" \
        "UPDATE key_value SET value='false' WHERE key='requireLogin';" 2>/dev/null || \
        curl -s -X PATCH "${base_url}/api/settings" \
            -H "Content-Type: application/json" \
            -d '{"requireLogin": false}' >/dev/null || true

    echo "OmniRoute preconfig: creating auto-fastest combo..."
    # Create auto-fastest combo
    combo_id=$(curl -s -X POST "${base_url}/api/combos" \
        -H "Content-Type: application/json" \
        -d '{"name": "auto-fastest", "strategy": "auto"}' | \
        grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//; s/"//') || true

    if [ -n "${combo_id}" ]; then
        echo "OmniRoute preconfig: updating combo with FREE models (no API keys needed)..."
        # Update combo with free models that work without API keys
        # Model format: { "provider": "<provider>", "model": "<model>" }
        curl -s -X PUT "${base_url}/api/combos/${combo_id}" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "auto-fastest",
                "strategy": "auto",
                "models": [
                    {"provider": "opencode", "model": "deepseek-v4-flash-free"},
                    {"provider": "opencode", "model": "big-pickle"},
                    {"provider": "opencode-zen", "model": "deepseek-v4-flash-free"},
                    {"provider": "opencode-zen", "model": "hy3-free"},
                    {"provider": "opencode-zen", "model": "mimo-v2.5-free"},
                    {"provider": "opencode-zen", "model": "north-mini-code-free"},
                    {"provider": "opencode-zen", "model": "nemotron-3-ultra-free"},
                    {"provider": "opencode-zen", "model": "big-pickle"}
                ],
                "config": {
                    "maxRetries": 2,
                    "retryDelayMs": 1000,
                    "timeoutMs": 120000,
                    "healthCheckEnabled": true
                }
            }' >/dev/null || true
    fi

    echo "OmniRoute preconfig complete"
}