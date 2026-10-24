#!/usr/bin/env bash
set -euo pipefail

# add-tailscale-provider.sh — register a Tailscale IP as an OpenAI-Compatible
# provider in OmniRoute, then wire one of its models into the auto-fastest combo.
#
# What it does (mirrors the OmniRoute "Add OpenAI Compatible" flow, verified
# against the live server):
#   1. Create (find-or-create) the provider NODE named `tailscale`,
#      type openai-compatible, base URL        http://<host:port>/v1
#      chatPath/modelsPath left to the server's defaults (NOT set),
#      → POST /api/provider-nodes
#   2. Add a CONNECTION on that node. No real key is needed, so a dummy
#      credential is stored (OmniRoute rejects keyless OpenAI-compatible
#      connections, and the backend ignores the key).
#      → POST /api/providers
#   3. Activate the connection (it is created inactive).
#      → PUT /api/providers/<id>
#   4. Import the requested model into the provider's model list.
#      → POST /api/provider-models
#   5. Add that provider's model to the existing `auto-fastest` combo
#      (appended, never duplicated).
#      → GET /api/combos + PUT /api/combos/<id>
#
# Every step is idempotent: re-running with the same IP is a no-op / update.
#
# Usage:
#   ./scripts/add-tailscale-provider.sh <ip-address>
#   PROVIDER_NAME=tailscale MODEL_NAME=qwen3.8:27b \
#       ./scripts/add-tailscale-provider.sh 100.79.117.84
#
# Environment:
#   TSC_IP              (alt to the positional arg) IP or host[:port] of the peer
#   TSC_PORT            port for a bare-host arg (default: 11434)
#   MODEL_NAME          model id to import + combo-ify (default: qwen3.8:27b)
#   PROVIDER_NAME       provider/node/connection name (default: tailscale)
#   OMNIROUTE_BASE_URL  OmniRoute server (default: http://127.0.0.1:20128)
#   OMNIROUTE_API_KEY   (optional) management key, only if the server requires one
#   TSC_DUMMY_KEY       credential stored on the connection (default: sk-noauth-tailscale)
#   TSC_TIMEOUT         per-request timeout seconds (default: 10)
#
# Flags:
#   --dry-run           print the plan (reads only) without writing anything
#
# Exit codes: 0 = ok, 1 = error (server / network / validation), 2 = usage.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
cd "$ROOT_DIR"

DRY_RUN=0
ARGS=()
for a in "$@"; do
    case "$a" in
        --dry-run|-n) DRY_RUN=1 ;;
        --help|-h)
            sed -n '4,44p' "$0" | sed -e 's/^# //' -e 's/^#//'
            exit 0 ;;
        -*) echo "ERROR: unknown flag: $a" >&2; exit 2 ;;
        *) ARGS+=("$a") ;;
    esac
done
if ((${#ARGS[@]} >= 1)); then
    TSC_IP="${TSC_IP:-${ARGS[0]}}"
fi
TSC_IP="${TSC_IP:-}"
TSC_PORT="${TSC_PORT:-11434}"

MODEL_NAME="${MODEL_NAME:-qwen3.8:27b}"
PROVIDER_NAME="${PROVIDER_NAME:-tailscale}"
OMNIROUTE_BASE_URL="${OMNIROUTE_BASE_URL:-http://127.0.0.1:20128}"
TSC_DUMMY_KEY="${TSC_DUMMY_KEY:-sk-noauth-tailscale}"
TSC_TIMEOUT="${TSC_TIMEOUT:-10}"

if [[ -z "$TSC_IP" ]]; then
    echo "ERROR: no IP address given. Usage: $0 <ip-address>" >&2
    exit 2
fi
# Validate the token looks like a host or host:port (no spaces / no scheme).
if [[ "$TSC_IP" =~ [[:space:]] || "$TSC_IP" == *://* ]]; then
    echo "ERROR: '$TSC_IP' looks like a URL, not a bare host or host:port." >&2
    echo "Hint: pass the host (e.g. 100.XX.XXX.XX or 100.XX.XXX.XX:11434)." >&2
    exit 2
fi
# Accept host or host:port; default the port when a bare host is given,
# then build the OpenAI-compatible base URL (baseUrl ends in /v1).
if [[ "$TSC_IP" == *:* ]]; then
    TSC_HOSTPORT="$TSC_IP"
else
    TSC_HOSTPORT="${TSC_IP}:${TSC_PORT}"
fi
TSC_BASE="http://${TSC_HOSTPORT}/v1"

if [[ "${TSC_DRY_VERBOSE:-0}" == "1" ]]; then
    echo "provider  = ${PROVIDER_NAME}"
    echo "base url  = ${TSC_BASE}"
    echo "model     = ${MODEL_NAME}"
    echo "omni base = ${OMNIROUTE_BASE_URL}"
fi

if [[ -z "${OMNIROUTE_API_KEY:-}" ]]; then
    : # server may be open locally; nothing to set
fi

python3 - "$DRY_RUN" "$PROVIDER_NAME" "$TSC_BASE" "$MODEL_NAME" \
        "$OMNIROUTE_BASE_URL" "${OMNIROUTE_API_KEY:-}" "$TSC_DUMMY_KEY" "$TSC_TIMEOUT" <<'PYEOF'
import json, sys, os, urllib.request, urllib.parse

(DRY, NAME, TSC_BASE, MODEL, OMNI_BASE, API_KEY, DUMMY_KEY, TIMEOUT_S) = sys.argv[1:9]
DRY = (DRY == "1")
OMNI_BASE = OMNI_BASE.rstrip("/")
TIMEOUT = int(TIMEOUT_S)

def req(method, path, body=None, expect_json=True):
    url = OMNI_BASE + path
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if API_KEY:
        headers["Authorization"] = "Bearer " + API_KEY
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=TIMEOUT) as resp:
            raw = resp.read().decode("utf-8", "replace")
            code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace") if e.fp else ""
        code = e.code
        return None, code, raw
    if not expect_json:
        return (raw if raw else None), code, raw
    try:
        return json.loads(raw) if raw else None, code, raw
    except json.JSONDecodeError:
        return raw, code, raw

def step(n, title, body=None, **_kw):
    print(f"[{n}] {title}" + ("  (dry-run)" if DRY else ""))

# ---------------------------------------------------------------------------
# 0. liveness
# ---------------------------------------------------------------------------
_, code, raw = req("GET", "/v1/models")
if code not in (200, 404):
    print(f"FAIL: OmniRoute not reachable at {OMNI_BASE} (HTTP {code}): {raw[:200]}")
    sys.exit(1)
print(f"OmniRoute reachable: {OMNI_BASE}")

# ---------------------------------------------------------------------------
# 1. provider NODE (find-or-create by name)
# ---------------------------------------------------------------------------
node_id = None
nodes, ncode, _ = req("GET", "/api/provider-nodes")
if ncode == 200 and isinstance(nodes, dict):
    for nd in nodes.get("nodes", []):
        if nd.get("name") == NAME:
            node_id = nd.get("id")

node_body = {
    "name": NAME,
    "type": "openai-compatible",
    "baseUrl": TSC_BASE,
    "prefix": NAME,
    "apiType": "chat",
    # chatPath/modelsPath intentionally omitted -> OmniRoute uses its own
    # defaults (setting them to null is a 400, and non-null /v1 strings
    # double the /v1 that baseUrl already carries).
}

# In dry-run we don't create, so give a readable placeholder for the display.
found_existing_node = node_id is not None
if DRY and node_id is None:
    node_id = f"<new:{NAME}-node>"

if DRY:
    step(1, f"node: {'reuse ' + str(node_id) if found_existing_node else 'create ' + NAME}",
         json.dumps(node_body))
else:
    if node_id is None:
        step(1, f"create node '{NAME}' -> {TSC_BASE}")
        res, code, raw = req("POST", "/api/provider-nodes", node_body)
        if code not in (200, 201):
            print(f"FAIL step 1 (HTTP {code}): {raw[:400]}"); sys.exit(1)
        node = res.get("node", res) if isinstance(res, dict) else {}
        node_id = node.get("id")
        if not node_id:
            print(f"FAIL step 1: no node id in response: {raw[:300]}"); sys.exit(1)
    else:
        print(f"[1] node '{NAME}' already exists -> {node_id}")

# ---------------------------------------------------------------------------
# 2. CONNECTION on the node (find-or-reuse by name) with dummy credential
# ---------------------------------------------------------------------------
psd = {"prefix": NAME, "apiType": "chat", "baseUrl": TSC_BASE, "nodeName": NAME}
conn_body = {
    "provider": node_id,
    "name": NAME,
    "apiKey": DUMMY_KEY,
    "priority": 100,
    "providerSpecificData": psd,
}
conn_id = None
conns, ccode, _ = req("GET", "/api/providers")
if ccode == 200 and isinstance(conns, dict):
    for c in (conns.get("connections") or conns.get("providers") or []):
        if c.get("name") == NAME and c.get("provider") == node_id:
            conn_id = c.get("id")

if DRY:
    step(2, f"connection: {'reuse ' + conn_id if conn_id else 'create on ' + str(node_id)}", json.dumps(conn_body))
else:
    if conn_id is None:
        step(2, f"add connection '{NAME}' on node {node_id} (dummy credential)")
        res, code, raw = req("POST", "/api/providers", conn_body)
        if code not in (200, 201):
            print(f"FAIL step 2 (HTTP {code}): {raw[:400]}"); sys.exit(1)
        conn = res.get("connection", res) if isinstance(res, dict) else {}
        conn_id = conn.get("id")
        if not conn_id:
            print(f"FAIL step 2: no connection id: {raw[:300]}"); sys.exit(1)
    else:
        print(f"[2] connection '{NAME}' already exists -> {conn_id}")

# Dry-run placeholder so step 3/4/5 don't print None.
if DRY and conn_id is None:
    conn_id = "<new:connection>"

# ---------------------------------------------------------------------------
# 3. ACTIVATE the connection
# ---------------------------------------------------------------------------
if DRY:
    step(3, f"activate connection {conn_id}", json.dumps({"isActive": True}))
else:
    step(3, f"activate connection {conn_id}")
    res, code, raw = req("PUT", f"/api/providers/{conn_id}", {"isActive": True})
    if code not in (200, 201):
        print(f"FAIL step 3 (HTTP {code}): {raw[:400]}"); sys.exit(1)
    active = (res or {}).get("connection", {}).get("isActive", True) if isinstance(res, dict) else True
    print(f"    active={active}")

# ---------------------------------------------------------------------------
# 4. IMPORT the model into the provider's model list
# ---------------------------------------------------------------------------
model_body = {"provider": node_id, "modelId": MODEL}
if DRY:
    step(4, f"import model '{MODEL}' into provider '{NAME}'", json.dumps(model_body))
else:
    step(4, f"import model '{MODEL}' into provider '{NAME}'")
    res, code, raw = req("POST", "/api/provider-models", model_body)
    if code not in (200, 201):
        print(f"FAIL step 4 (HTTP {code}): {raw[:400]}"); sys.exit(1)
    print(f"    imported: {json.dumps(res)[:200] if res else 'ok'}")

# ---------------------------------------------------------------------------
# 5. ADD the model to the existing auto-fastest combo (append, no duplicate)
# ---------------------------------------------------------------------------
COMBO = "auto-fastest"
full = f"{NAME}/{MODEL}"
combo_entry = {
    "id": f"{COMBO}-model-{NAME}-{MODEL}".replace(":", "-").replace(" ", "-"),
    "kind": "model",
    "model": full,
    "providerId": node_id,
    "weight": 0,
}
combinations, gcode, _ = req("GET", "/api/combos")
combo = None
if gcode == 200 and isinstance(combinations, dict):
    for c in combinations.get("combos", []):
        if c.get("name") == COMBO:
            combo = c
            break
if combo is None:
    if DRY:
        step(5, f"combo '{COMBO}' not found — would CREATE it with [{full}]")
    else:
        print(f"FAIL: combo '{COMBO}' does not exist; refusing to create a new one."); sys.exit(1)
else:
    existing = combo.get("models", [])
    if any((m.get("providerId") == node_id and m.get("model") == full) for m in existing):
        action, new_models = "already-in-combo (no-op)", existing
    else:
        action, new_models = "appending", existing + [combo_entry]
    payload = {
        "name": combo.get("name", COMBO),
        "strategy": combo.get("strategy", "priority"),
        "enabled": combo.get("enabled", True),
        "config": combo.get("config", {}),
        "models": new_models,
    }
    if DRY:
        step(5, f"combo '{COMBO}': {action} -> {len(new_models)} models",
             json.dumps(payload)[:400])
    else:
        steps_count = len(new_models)
        step(5, f"combo '{COMBO}': {action} -> {steps_count} models")
        cid = combo.get("id")
        url = f"/api/combos/{cid}" if cid else "/api/combos"
        res, code, raw = req("PUT", url, payload) if cid else req("POST", url, payload)
        if code not in (200, 201):
            print(f"FAIL step 5 (HTTP {code}): {raw[:400]}"); sys.exit(1)

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------
if DRY:
    print("\n[dry-run would end here. Nothing was written.]")
else:
    print(f"\nOK  provider '{NAME}' -> {full}  wired into combo '{COMBO}'  (node={node_id}, conn={conn_id})")
PYEOF
