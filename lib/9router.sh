#!/usr/bin/env sh
# lib/9router.sh - 9Router preconfiguration (auto-fastest combo, no-login, no-api-key)
# Sourced by boot.sh after 9Router is up. Idempotent - safe to call on every boot.

# ninerouter_preconfigure
#   Configures 9Router:
#     - Disables dashboard login (requireLogin=false)
#     - Disables API key enforcement (requireApiKey=false)
#     - Creates/updates "auto-fastest" combo with free models
#     - Sets auto-fastest combo strategy to round-robin
#   Returns 0 on success, non-zero on failure (but non-fatal to boot)
ninerouter_preconfigure() {
    BASE_URL="http://${NINEROUTER_HOST:-127.0.0.1}:${NINEROUTER_PORT:-7352}"
    COOKIE_FILE=$(mktemp)
    trap 'rm -f "$COOKIE_FILE"' EXIT

    # Log in and save the session cookie (default password: 123456)
    if ! curl -fsS -c "$COOKIE_FILE" \
        -X POST "$BASE_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"password":"123456"}' >/dev/null 2>&1; then
        log_warn "ninerouter_preconfigure: login failed"
        return 1
    fi

    # Disable dashboard login and API-key enforcement
    if ! curl -fsS -b "$COOKIE_FILE" \
        -X PATCH "$BASE_URL/api/settings" \
        -H "Content-Type: application/json" \
        -d '{"requireLogin":false,"requireApiKey":false}' >/dev/null 2>&1; then
        log_warn "ninerouter_preconfigure: failed to disable login/api-key"
        return 1
    fi

    # Delete existing auto-fastest combo if present
    COMBO_ID=$(curl -fsS -b "$COOKIE_FILE" "$BASE_URL/api/combos" 2>/dev/null | \
        jq -r '.combos[] | select(.name=="auto-fastest") | .id' 2>/dev/null | head -n 1)
    if [ -n "$COMBO_ID" ]; then
        curl -fsS -b "$COOKIE_FILE" \
            -X DELETE "$BASE_URL/api/combos/$COMBO_ID" >/dev/null 2>&1 || true
    fi

    # Create auto-fastest combo with free oc/ models (OpenCode free tier)
    if ! curl -fsS -b "$COOKIE_FILE" \
        -X POST "$BASE_URL/api/combos" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "auto-fastest",
            "models": [
              "oc/muse-spark-1.2-contributor-free",
              "oc/muse-spark-1.3-contributor-free",
              "oc/union-alpha",
              "oc/big-pickle",
              "oc/mimo-v2.5-free",
              "oc/ling-3.0-flash-fin-free",
              "oc/nemotron-3-ultra-free",
              "oc/nemotron-3.5-lightning-free"
            ]
        }' >/dev/null 2>&1; then
        log_warn "ninerouter_preconfigure: failed to create auto-fastest combo"
        return 1
    fi

    # Set auto-fastest combo strategy to round-robin
    STRATEGIES=$(
        curl -fsS -b "$COOKIE_FILE" "$BASE_URL/api/settings" 2>/dev/null | \
        jq -c '
            (.comboStrategies // {})
            | .["auto-fastest"] = ((.["auto-fastest"] // {}) + {fallbackStrategy: "round-robin"})
        ' 2>/dev/null
    )
    if ! curl -fsS -b "$COOKIE_FILE" \
        -X PATCH "$BASE_URL/api/settings" \
        -H "Content-Type: application/json" \
        -d "{\"comboStrategies\":$STRATEGIES}" >/dev/null 2>&1; then
        log_warn "ninerouter_preconfigure: failed to set combo strategy"
        return 1
    fi

    # Test the combo (9Router uses /v1/chat/completions with model=auto-fastest)
    if curl -fsS "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto-fastest","messages":[{"role":"user","content":"Reply with exactly: OK"}],"stream":false,"max_tokens":16}' >/dev/null 2>&1; then
        log_info "ninerouter_preconfigure: auto-fastest combo test passed"
    else
        log_warn "ninerouter_preconfigure: auto-fastest combo test failed (may still be starting)"
    fi

    return 0
}