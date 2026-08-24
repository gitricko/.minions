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
        echo "OmniRoute preconfig: updating combo with models..."
        # Update combo with model config
        curl -s -X PUT "${base_url}/api/combos/${combo_id}" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "auto-fastest",
                "strategy": "auto",
                "models": [
                    {"provider": "anthropic", "model": "claude-3-5-sonnet-20241022"},
                    {"provider": "openai", "model": "gpt-4o"},
                    {"provider": "google", "model": "gemini-1.5-pro"}
                ],
                "retry": {"maxAttempts": 3, "backoffMs": 1000}
            }' >/dev/null || true
    fi

    echo "OmniRoute preconfig: enabling MCP..."
    curl -s -X PATCH "${base_url}/api/settings" \
        -H "Content-Type: application/json" \
        -d '{"mcpEnabled": true}' >/dev/null || true

    echo "OmniRoute preconfig: registering with Hermes..."
    # Only if Hermes is installed
    if command -v hermes >/dev/null 2>&1; then
        hermes mcp add omniroute --command omniroute --args --mcp 2>/dev/null || true
    fi

    echo "OmniRoute preconfig complete"
}