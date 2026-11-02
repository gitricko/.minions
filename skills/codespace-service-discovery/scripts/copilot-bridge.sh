#!/usr/bin/env bash
# copilot-bridge.sh — drive the standalone GitHub Copilot CLI (a full Copilot-SDK
# client) as a scriptable LLM / agent. Two backends:
#   A  github   — reuse GitHub's own Copilot via the Codespace ghu_ token (free tier)
#   B  byok     — run the Copilot agent against OUR local LLM (OmniRoute / 9Router)
#
# Requires: /usr/local/bin/copilot present. Backend A also needs the ghu_ token,
# which we extract from the VS Code server (see codespace-gh-auth skill).
#
# Usage:
#   copilot-bridge.sh <github|byok> "prompt text" [options]
#
#   Backend flags (env or per-call):
#     github : TOKEN=<ghu_...>            (auto-extracted if TOKEN unset)
#     byok   : BASE_URL=<url> MODEL=<id> (defaults below)
#
#   Common:
#     --model <m>          override model (github backend: only 'auto' works on free tier)
#     --auto-tier <t>      efficiency|balance|intelligence (github auto profile)
#     --context <tier>     default|long_context
#     --max-out <n>        --max-output-tokens
#     --stream / --no-stream   (default: no-stream)
#
# Examples:
#   copilot-bridge.sh github "explanatory one-liner of what GPT-7 is"
#   TOKEN=ghu_... copilot-bridge.sh github "reply 'ping' in lowercase" --max-out 40
#   copilot-bridge.sh byok "summarise this sentence: hi" \
#       BASE_URL=http://127.0.0.1:20128/v1 MODEL=auto/best-coding
#
set -uo pipefail

COPILOT_BIN="${COPILOT_BIN:-/usr/local/bin/copilot}"

[ -x "$COPILOT_BIN" ] || { echo "error: $COPILOT_BIN not found or not executable" >&2; exit 2; }

usage() {
    sed -E 's/^#( |$)/\1/' "$0" | head -60
    exit "${1:-2}"
}

BACKEND="${1:-}"
[ -n "$BACKEND" ] || usage
case "$BACKEND" in github|byok) ;; *) echo "unknown backend '$BACKEND' (need github|byok)"; exit 2;; esac

shift

PROMPT=""
MODEL=""
MAX_OUT=""
AUTO_TIER=""
CONTEXT=""
STREAM=0
BASE_URL=""
PROVIDER_TYPE="openai"
WIRE_API="completions"
TOKEN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --model) MODEL="$2"; shift 2;;
        --auto-tier) AUTO_TIER="$2"; shift 2;;
        --context) CONTEXT="$2"; shift 2;;
        --max-out) MAX_OUT="$2"; shift 2;;
        --stream) STREAM=1; shift;;
        --no-stream) STREAM=0; shift;;
        --base-url) BASE_URL="$2"; shift 2;;
        --provider-type) PROVIDER_TYPE="$2"; shift 2;;
        --wire-api) WIRE_API="$2"; shift 2;;
        --token) TOKEN="$2"; shift 2;;
        --help|-h) usage 0;;
        --*) echo "error: flag '$1' requires a value"; exit 2;;
        -*) [ "$1" = "--" ] && shift; continue;;
        --) shift; continue;;
        *)
            if [ -z "$PROMPT" ]; then PROMPT="$1"; shift; else
                # remaining args: append (space-separated) to prompt.
                PROMPT="$PROMPT $1"; shift
            fi;;
    esac
done

[ -n "$PROMPT" ] || { echo "error: no prompt given"; usage; }

# Extract ghu_ token from VS Code server if not given and backend needs it.
if [ -z "$TOKEN" ]; then
    VSCODE_PID=$(pgrep -f "server-main.js" 2>/dev/null | head -1 || true)
    if [ -n "${VSCODE_PID:-}" ]; then
        TOKEN=$(cat "/proc/$VSCODE_PID/environ" 2>/dev/null | tr '\0' '\n' | grep '^GITHUB_TOKEN=' | cut -d= -f2- || true)
    fi
fi

TMPDIR_LOCAL=$(mktemp -d)
OUT_FILE="$TMPDIR_LOCAL/out.txt"; ERR_FILE="$TMPDIR_LOCAL/err.txt"
if [ "$BACKEND" = "github" ]; then
    [ -n "$TOKEN" ] || { echo "error: need TOKEN=<ghu_...> or a running VS Code server (for extraction)" >&2; exit 2; }
    EXTRA=()
    [ -n "$MODEL" ]     && EXTRA+=(--model="$MODEL")
    [ -n "$AUTO_TIER" ] && EXTRA+=(--auto-tier="$AUTO_TIER")
    [ -n "$CONTEXT" ]   && EXTRA+=(--context="$CONTEXT")
    env -i HOME="${HOME:-/home/codespace}" \
        PATH="/usr/local/bin:/usr/bin:/bin" \
        COPILOT_AUTO_UPDATE=false \
        GITHUB_TOKEN="$TOKEN" \
        "$COPILOT_BIN" -p "$PROMPT" -s --no-auto-update \
        ${EXTRA[@]+"${EXTRA[@]}"} \
        >"$OUT_FILE" 2>"$ERR_FILE"
    RC=$?
elif [ "$BACKEND" = "byok" ]; then
    BASE_URL="${BASE_URL:-http://127.0.0.1:20128/v1}"
    env -i HOME="${HOME:-/home/codespace}" \
        PATH="/usr/local/bin:/usr/bin:/bin" \
        COPILOT_AUTO_UPDATE=false \
        COPILOT_PROVIDER_BASE_URL="$BASE_URL" \
        COPILOT_PROVIDER_TYPE="$PROVIDER_TYPE" \
        COPILOT_PROVIDER_WIRE_API="$WIRE_API" \
        COPILOT_MODEL="${MODEL:-auto/best-coding}" \
        "$COPILOT_BIN" -p "$PROMPT" -s --no-auto-update \
        >"$OUT_FILE" 2>"$ERR_FILE"
    RC=$?
else
    echo "error: unknown backend '$BACKEND'" >&2
    exit 2
fi
if [ $RC -ne 0 ]; then
    head -3 "$ERR_FILE" 2>/dev/null
    rm -rf "$TMPDIR_LOCAL"
    echo "exit=$RC" >&2
    exit $RC
fi
cat "$OUT_FILE"
rm -rf "$TMPDIR_LOCAL"
