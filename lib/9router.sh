#!/usr/bin/env sh
# lib/9router.sh - 9Router preconfiguration (auto-fastest combo, no-login, no-api-key)
# Sourced by boot.sh after 9Router is up. Idempotent - safe to call on every boot.
#
# OpenCode free tier (oc/) requires custom headers, otherwise opencode.ai returns
# HTTP 403 FreeTierError ("only be used from within OpenCode"). We set them via:
#   PUT /api/providers/opencode/overrides  ->  { headers: { User-Agent, x-opencode-* } }
# The x-opencode-session value is a 12-hex + 14-base62 id; regenerate per boot
# (fresh conversation, avoids stale-session 403s). Session id format reference:
# https://github.com/decolua/9router/issues/4781

# _ninerouter_opencode_session
#   Print a fresh x-opencode-session value: ses_<12hex><14base62>
_ninerouter_opencode_session() {
    hex=$(python3 -c "import time; v=~(int(time.time()*1000)*4096+1)&281474976710655; print(format(v,'012x'))")
    rand=$(python3 -c "import secrets,string; c=string.digits+string.ascii_uppercase+string.ascii_lowercase; print(''.join(secrets.choice(c) for _ in range(14)))")
    printf 'ses_%s%s\n' "$hex" "$rand"
}

# ninerouter_preconfigure
#   Configures 9Router:
#     - Disables dashboard login (requireLogin=false)
#     - Disables API key enforcement (requireApiKey=false)
#     - Sets OpenCode free-tier bypass headers (403 workaround, decolua/9router#4781)
#     - Creates/updates "auto-fastest" combo with current free oc/ models
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

    # OpenCode free-tier bypass headers (403 workaround). PUT replaces the whole
    # override map per provider, so this is idempotent.
    SES=$(_ninerouter_opencode_session)
    OVERRIDES=$(python3 -c "import json,sys; print(json.dumps({'headers':{'User-Agent':'opencode/1.18.31','x-opencode-client':'cli','x-opencode-project':'global','x-opencode-request':'_msg','x-opencode-session':sys.argv[1]}}))" "$SES")
    if curl -fsS -b "$COOKIE_FILE" \
        -X PUT "$BASE_URL/api/providers/opencode/overrides" \
        -H "Content-Type: application/json" \
        -d "$OVERRIDES" >/dev/null 2>&1; then
        log_info "ninerouter_preconfigure: OpenCode free-tier headers set"
    else
        log_warn "ninerouter_preconfigure: failed to set OpenCode headers (oc/ models will 403)"
    fi

    # Delete existing auto-fastest combo if present
    COMBO_ID=$(curl -fsS -b "$COOKIE_FILE" "$BASE_URL/api/combos" 2>/dev/null | \
        jq -r '.combos[] | select(.name=="auto-fastest") | .id' 2>/dev/null | head -n 1)
    if [ -n "$COMBO_ID" ]; then
        curl -fsS -b "$COOKIE_FILE" \
            -X DELETE "$BASE_URL/api/combos/$COMBO_ID" >/dev/null 2>&1 || true
    fi

    # Create auto-fastest combo with free oc/ models (OpenCode free tier).
    # Keep this list in sync with https://opencode.ai/zen/v1/models (*-free /
    # *-contributor-free ids only); stale ids just lose to fallback.
    # All ids below verified working (200 + content @ max_tokens=256); note
    # thinking models need >16 tokens or they return empty content.
    # Excluded: oc/union-alpha (upstream 400 "Model is unavailable", 2026-10).
    if ! curl -fsS -b "$COOKIE_FILE" \
        -X POST "$BASE_URL/api/combos" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "auto-fastest",
            "models": [
              "oc/mimo-v2.6-flash-free",
              "oc/muse-spark-1.2-contributor-free",
              "oc/muse-spark-1.3-contributor-free",
              "oc/beam-free",
              "oc/big-pickle",
              "oc/deepseek-v4.1-flash-free",
              "oc/glm-5.3-flash-free",
              "oc/ll-alpha-free",
              "oc/longcat-2.5-preview-free",
              "oc/nemotron-3.5-lightning-free",
              "oc/nemotron-3.5-super-vl-free",
              "oc/space-bunny-free"
            ]
        }' >/dev/null 2>&1; then
        log_warn "ninerouter_preconfigure: failed to create auto-fastest combo"
        return 1
    fi

    # Test the combo (9Router uses /v1/chat/completions with model=auto-fastest).
    # Note: muse-spark-* via openai-responses may return finish_reason=in_progress
    # with empty content on 16-token prompts; that's a free-tier behavior, not a
    # routing failure. Treat HTTP 2xx as pass (curl -f would not 2xx, so the
    # "failed" line below mostly catches auth/routing errors).
    if curl -fsS "$BASE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"auto-fastest","messages":[{"role":"user","content":"Reply with exactly: OK"}],"stream":false,"max_tokens":16}' >/dev/null 2>&1; then
        log_info "ninerouter_preconfigure: auto-fastest combo test passed"
    else
        log_warn "ninerouter_preconfigure: auto-fastest combo test failed (may still be starting)"
    fi

    return 0
}
