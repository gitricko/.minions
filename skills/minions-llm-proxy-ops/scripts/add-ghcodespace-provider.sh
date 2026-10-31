#!/usr/bin/env bash
set -euo pipefail

# add-ghcodespace-provider.sh — register GitHub Copilot (Individual) as an
# OpenAI-compatible provider in OmniRoute, then wire every model that actually
# responds into the auto-fastest combo.
#
# Mirrors add-tailscale-provider.sh (same req/step helpers, same 5 REST steps,
# same find-or-create logic), with two differences that make this correct for a
# Copilot token instead of a keyless Ollama peer:
#
#   * The endpoint is https://api.individual.githubcopilot.com and has NO /v1
#     (verified: /chat/completions=200, /v1/chat/completions=404). So the node
#     baseUrl is the bare domain and chatPath/modelsPath are left to defaults.
#   * The connection credential is the REAL Codespace GITHUB_TOKEN (ghu_), which
#     OmniRoute sends as `Authorization: Bearer <ghu_>` — the exact auth the
#     panel uses. There is no dummy-key fallback: this endpoint *requires* it.
#
# What it does:
#   [0] OmniRoute liveness.
#   [1] Discover the model roster: GET <base>/models (Bearer ghu_).
#   [2] Probe every model with a real completion POST <base>/chat/completions.
#       Classification (mirrors lib/9router.sh + the 9router-models skill):
#         200 + non-empty content  -> KEEP
#         429 (rate limit)         -> KEEP (not broken; free-tier throttle)
#         400 / 404 / 410          -> DROP (model_not_supported / wrong shape)
#         5xx                      -> retry xN, then DROP if it never recovers
#   [3] Create provider NODE `gh-pilot` -> bare domain.   POST /api/provider-nodes
#   [4] Add CONNECTION on the node with the REAL ghu_ credential. POST /api/providers
#   [5] Activate the connection (created inactive).          PUT /api/providers/<id>
#   [6] Import each KEEP model.                             POST /api/provider-models
#   [7] Append each KEEP model to the existing auto-fastest combo. POST /api/combos/<id>
#
# Every REST step is idempotent: re-running is a no-op/update. The model *probe*
# does no writes.
#
# Usage:
#   skills/minions-llm-proxy-ops/scripts/add-ghcodespace-provider.sh
#   DRY_RUN=1  .../add-ghcodespace-provider.sh        # discover+probe, print plan,
#                                                   #   write nothing
#   PROBE_DRY_VERBOSE=1  .../add-ghcodespace-provider.sh --dry-run
#
# Environment (all optional):
#   GHPILOT_BASEURL      endpoint (default https://api.individual.githubcopilot.com)
#   PROVIDER_NAME        node/conn/model prefix (default gh-pilot)
#   GITHUB_TOKEN         pre-existing token; if unset, extracted via codespace-gh-auth
#   OMNIROUTE_BASE_URL   OmniRoute server (default http://127.0.0.1:20128)
#   OMNIROUTE_API_KEY    OmniRoute auth (omit for the open local server)
#   PROBE_MAX_TOKENS     completion budget per probe (default 8)
#   PROBE_TIMEOUT        per-probe timeout, s (default 25)
#   PROBE_RETRY          retries for 429/5xx (default 3)
#   PROBE_DELAY_S        polite delay between probes, s (default 0.4)
#   DRY_RUN=1            discover+probe, print the plan, write nothing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SKILLS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# --- token source: prefer the codespace-gh-auth skill, else inline fallback ---
GH_AUTH_SH=""
for cand in \
    "${REPO_SKILLS_DIR}/codespace-gh-auth/scripts/codespace-gh-auth.sh" \
    "${HOME}/.hermes/skills/minions/codespace-gh-auth/scripts/codespace-gh-auth.sh" \
    "${HOME}/.minions/skills/codespace-gh-auth/scripts/codespace-gh-auth.sh"; do
    [[ -f "${cand}" ]] && { GH_AUTH_SH="${cand}"; break; }
done

if [[ -n "${GH_AUTH_SH}" ]]; then
    # shellcheck disable=SC1090
    source "${GH_AUTH_SH}"
    echo "token source: codespace-gh-auth skill (${GH_AUTH_SH})"
else
    # Inline fallback, byte-for-byte the skill's get_github_token.
    get_github_token() {
        local vscode_pid; vscode_pid=$(pgrep -f "server-main.js" | head -1)
        [[ -z "${vscode_pid}" ]] && { echo "ERROR: VS Code server (server-main.js) not found" >&2; return 1; }
        local token
        token=$(cat "/proc/${vscode_pid}/environ" 2>/dev/null | tr '\0' '\n' | grep '^GITHUB_TOKEN=' | cut -d= -f2-)
        [[ -z "${token}" ]] && { echo "ERROR: GITHUB_TOKEN not found in VS Code server env" >&2; return 1; }
        export GITHUB_TOKEN="${token}"
        return 0
    }
    echo "token source: inline fallback (codespace-gh-auth skill not found)"
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    if ! get_github_token >/dev/null; then
        echo "ERROR: could not obtain a GITHUB_TOKEN. Pass GITHUB_TOKEN=ghu_… explicitly." >&2
        exit 2
    fi
fi

# Redact the token for any human-facing output: `ghu_****(len=NN)`.
_TL=${#GITHUB_TOKEN}
_TOK_REDACTED="${GITHUB_TOKEN:0:4}****(len=${_TL})"

PROVIDER_NAME="${PROVIDER_NAME:-gh-pilot}"
OMNIROUTE_BASE_URL="${OMNIROUTE_BASE_URL:-http://127.0.0.1:20128}"
GHPILOT_BASEURL="${GHPILOT_BASEURL:-https://api.individual.githubcopilot.com}"

DRY_RUN="${DRY_RUN:-0}"
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ "${PROBE_DRY_VERBOSE:-0}" == "1" || "${DRY_RUN}" == "1" ]]; then
    echo "provider  = ${PROVIDER_NAME}"
    echo "endpoint  = ${GHPILOT_BASEURL}   (no /v1; /chat/completions, /models)"
    echo "token     = ${_TOK_REDACTED}"
    echo "omni base = ${OMNIROUTE_BASE_URL}"
    echo "mode      = ${DRY_RUN:0:1} (dry-run=no writes)"
fi

# Token travels in the environment, not argv (avoids ps exposure).
GHPILOT_TOKEN="${GITHUB_TOKEN}" GHPILOT_BASEURL="${GHPILOT_BASEURL}" \
PROVIDER_NAME="${PROVIDER_NAME}" OMNIROUTE_BASE_URL="${OMNIROUTE_BASE_URL}" \
DRY_RUN="${DRY_RUN}" OMNIROUTE_API_KEY="${OMNIROUTE_API_KEY:-}" \
PROBE_MAX_TOKENS="${PROBE_MAX_TOKENS:-8}" PROBE_TIMEOUT="${PROBE_TIMEOUT:-25}" \
PROBE_RETRY="${PROBE_RETRY:-3}" PROBE_DELAY_S="${PROBE_DELAY_S:-0.4}" \
python3 - <<'PYEOF'
import json, os, sys, time, urllib.request, urllib.error

DRY        = (os.environ.get("DRY_RUN") == "1")
TOKEN      = os.environ["GHPILOT_TOKEN"]
API_BASE   = os.environ["GHPILOT_BASEURL"].rstrip("/")
NAME       = os.environ.get("PROVIDER_NAME") or "gh-pilot"
OMNI       = (os.environ.get("OMNIROUTE_BASE_URL") or "http://127.0.0.1:20128").rstrip("/")
OMNI_KEY   = os.environ.get("OMNIROUTE_API_KEY") or ""
MAX_TOKENS = int(os.environ.get("PROBE_MAX_TOKENS") or 8)
TIMEOUT    = int(os.environ.get("PROBE_TIMEOUT") or 25)
RETRY      = int(os.environ.get("PROBE_RETRY") or 3)
DELAY      = float(os.environ.get("PROBE_DELAY_S") or 0.4)

# --- generic JSON request against an arbitrary base URL ----------------------
def http(base, path, method="GET", body=None, auth_token=None, timeout=TIMEOUT):
    url = base + path
    data = None
    headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if auth_token:
        headers["Authorization"] = "Bearer " + auth_token
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace"); code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace") if e.fp else ""; code = e.code
    except Exception as e:
        return None, 0, str(e)
    try:    return json.loads(raw) if raw else None, code, raw
    except json.JSONDecodeError: return raw, code, raw

def step(n, title, extra=""):
    print(f"[{n}] {title}" + ("  (dry-run)" if DRY else "") + (f"  {extra}" if extra else ""))

# --- OmniRoute requests (with optional local auth key) ----------------------
def req_auth(method, path, body=None):
    url = OMNI + path
    data = None; headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode(); headers["Content-Type"] = "application/json"
    if OMNI_KEY: headers["Authorization"] = "Bearer " + OMNI_KEY
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=TIMEOUT) as resp:
            raw = resp.read().decode("utf-8","replace"); code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8","replace") if e.fp else ""; code = e.code
    except Exception as e:
        return None, 0, str(e)
    try: return json.loads(raw) if raw else None, code, raw
    except json.JSONDecodeError: return raw, code, raw

# --- direct-endpoint request (Bearer ghu_; real API, not OmniRoute) ----------
def http_ep(path, method="GET", body=None, timeout=TIMEOUT):
    url = API_BASE + path
    data = None; headers = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode(); headers["Content-Type"] = "application/json"
    headers["Authorization"] = "Bearer " + TOKEN
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8","replace"); code = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8","replace") if e.fp else ""; code = e.code
    except Exception as e:
        return None, 0, str(e)
    try: return json.loads(raw) if raw else None, code, raw
    except json.JSONDecodeError: return raw, code, raw

# -----------------------------------------------------------------------------
# 0. OmniRoute liveness
# -----------------------------------------------------------------------------
_, code, raw = http(OMNI, "/api/health")
if code not in (200, 404):
    print(f"FAIL: OmniRoute not reachable at {OMNI} (HTTP {code}): {raw[:200]}"); sys.exit(1)
print(f"OmniRoute reachable: {OMNI}")

# -----------------------------------------------------------------------------
# 1. Discover the model roster from the real endpoint
# -----------------------------------------------------------------------------
step(1, f"discover models: GET {API_BASE}/models",
     f"token={TOKEN[:4]}****(len={len(TOKEN)})")
mdata, mcode, mraw = http(API_BASE, "/models", auth_token=TOKEN)
ids = []
def _ids_from(obj):
    out = []
    if isinstance(obj, list):
        for it in obj:
            if isinstance(it, str): out.append(it)
            elif isinstance(it, dict):
                v = it.get("id") or it.get("model") or it.get("name")
                if v: out.append(v)
    elif isinstance(obj, dict):
        for k in ("data", "models", "items"):
            if k in obj and obj[k] is not None:
                got = _ids_from(obj[k])
                if got: return got
        if obj.get("object") == "list" and isinstance(obj.get("data"), list):
            out = _ids_from(obj["data"])
    return out
ids = sorted(_ids_from(mdata) or [])
if mcode != 200 or not ids:
    print(f"  WARNING: /models returned {mcode} or no parsable ids; "
          f"falling back to known-good free-tier roster.")
    ids = ["gpt-4o-mini-2024-07-18", "gpt-4o-2024-11-20", "gpt-4o-2024-08-06",
           "gpt-4.1-2025-04-14", "text-embedding-3-small"]
for i in ids: print(f"    {i}")

# -----------------------------------------------------------------------------
# 2. Probe every model with a real completion; classify keep vs drop
# -----------------------------------------------------------------------------
step(2, f"probe {len(ids)} models with real completions "
        f"(keep=200+content or 429; drop=400/404/410/5xx)")

def probe(model):
    global LAST_RAW
    body = {"model": model, "max_tokens": MAX_TOKENS,
            "messages": [{"role": "user", "content": "Reply with the single word: ok"}]}
    code, content, raw = 0, "", ""
    for attempt in range(RETRY + 1):
        d, code, raw = http_ep("/chat/completions", method="POST", body=body)
        if code == 200:
            try:
                content = (d.get("choices", [{}])[0].get("message", {})
                           .get("content", "") if isinstance(d, dict) else "")
            except Exception: content = ""
            if content and content.strip():
                return "ok", 200, content.strip()[:40]
            break  # 200 but empty -> project invariant: non-empty = pass
        if code in (429, 500, 502, 503, 504):
            if attempt < RETRY:
                time.sleep(1.2 * (attempt + 1)); continue
            return ("rate_limited" if code == 429 else "drop"), code, raw[:80]
        return "drop", code, raw[:80]  # definitive non-retryable (400/401/404/410/403)
    return "drop", code, raw[:80]

keep, dropped = [], []
# Exclude non-chat auxiliaries (embeddings, search-aux) that don't belong in
# a chat-completions combo. The endpoint happily serves them for a "ping" but
# they're not LLMs — adding them to auto-fastest would confuse routing.
EXCLUDE_PREFIX = ("text-embedding-", "copilot-search-")
for i, model in enumerate(ids):
    if model.startswith(EXCLUDE_PREFIX):
        dropped.append(model)
        print(f"    EXCL  {model:34} (non-chat auxiliary: embeddings / search-aux)")
        continue
    if i: time.sleep(DELAY)
    state, code, hint = probe(model)
    tag = "KEEP" if state in ("ok", "rate_limited") else "drop"
    if state in ("ok", "rate_limited"): keep.append(model)
    else: dropped.append(model)
    print(f"    {tag:4}  {model:34} {state:12} (http {code}) {hint}")

print(f"\n    -> {len(keep)} keep, {len(dropped)} drop")
if DRY and not keep:
    print("\n[dry-run] no models to keep — nothing would be registered. Stopping.")
    sys.exit(0)

# -----------------------------------------------------------------------------
# 3. OmniRoute NODE (find-or-create by name). baseUrl = bare domain, NO /v1.
# -----------------------------------------------------------------------------
node_id = None
nodes, ncode, _ = http(OMNI, "/api/provider-nodes")
if ncode == 200 and isinstance(nodes, dict):
    for nd in nodes.get("nodes", []):
        if nd.get("name") == NAME: node_id = nd.get("id")

node_body = {
    "name": NAME, "type": "openai-compatible", "baseUrl": API_BASE,
    "prefix": NAME, "apiType": "chat",
    # chatPath/modelsPath intentionally omitted -> defaults. githubcopilot has
    # no /v1, so we must NOT inject /v1 the way the tailscale peer expects.
}
if DRY:
    step(3, f"node: {'reuse %s' % node_id if node_id else 'create %s' % NAME}",
         json.dumps(node_body))
else:
    if node_id is None:
        step(3, f"create node '{NAME}' -> {API_BASE}")
        res, code, raw = req_auth("POST", "/api/provider-nodes", node_body)
        if code not in (200, 201):
            print(f"FAIL step 3 (HTTP {code}): {raw[:400]}"); sys.exit(1)
        node = res.get("node", res) if isinstance(res, dict) else {}
        node_id = node.get("id")
        if not node_id: print(f"FAIL step 3: no node id: {raw[:300]}"); sys.exit(1)
    else:
        print(f"[3] node '{NAME}' already exists -> {node_id}")

# -----------------------------------------------------------------------------
# 4. CONNECTION on the node with the REAL ghu_ credential
# -----------------------------------------------------------------------------
psd = {"prefix": NAME, "apiType": "chat", "baseUrl": API_BASE, "nodeName": NAME}
conn_body = {"provider": node_id, "name": NAME, "apiKey": TOKEN,
             "priority": 100, "providerSpecificData": psd}
conn_id = None
conns, ccode, _ = req_auth("GET", "/api/providers")
if ccode == 200 and isinstance(conns, dict):
    for c in (conns.get("connections") or conns.get("providers") or []):
        if c.get("name") == NAME and c.get("provider") == node_id:
            conn_id = c.get("id")

if DRY:
    step(4, f"connection: {'reuse %s' % conn_id if conn_id else 'create on %s' % node_id}",
         json.dumps({**conn_body, "apiKey": TOKEN[:4] + "****"}))
else:
    if conn_id is None:
        step(4, f"add connection '{NAME}' on node {node_id} (real ghu_ credential)")
        res, code, raw = req_auth("POST", "/api/providers", conn_body)
        if code not in (200, 201):
            print(f"FAIL step 4 (HTTP {code}): {raw[:400]}"); sys.exit(1)
        conn = res.get("connection", res) if isinstance(res, dict) else {}
        conn_id = conn.get("id")
        if not conn_id: print(f"FAIL step 4: no connection id: {raw[:300]}"); sys.exit(1)
    else:
        print(f"[4] connection '{NAME}' already exists -> {conn_id}")

if DRY and conn_id is None:
    conn_id = "<new:connection>"

# -----------------------------------------------------------------------------
# 5. ACTIVATE the connection
# -----------------------------------------------------------------------------
if DRY:
    step(5, f"activate connection {conn_id}", json.dumps({"isActive": True}))
else:
    step(5, f"activate connection {conn_id}")
    res, code, raw = req_auth("PUT", f"/api/providers/{conn_id}", {"isActive": True})
    if code not in (200, 201):
        print(f"FAIL step 5 (HTTP {code}): {raw[:400]}"); sys.exit(1)
    active = (res or {}).get("connection", {}).get("isActive", True) if isinstance(res, dict) else True
    print(f"    active={active}")

# -----------------------------------------------------------------------------
# 6. IMPORT each KEEP model into the provider's model list
# -----------------------------------------------------------------------------
for i, model in enumerate(keep):
    model_body = {"provider": node_id, "modelId": model}
    if DRY:
        step(6, f"import model '{model}'", json.dumps(model_body))
    else:
        step(6, f"import model '{model}'")
        res, code, raw = req_auth("POST", "/api/provider-models", model_body)
        if code not in (200, 201):
            print(f"FAIL step 6 (HTTP {code}) for {model}: {raw[:300]}"); sys.exit(1)

# -----------------------------------------------------------------------------
# 7. APPEND each KEEP model to the existing auto-fastest combo
# -----------------------------------------------------------------------------
COMBO = "auto-fastest"
combinations, gcode, _ = req_auth("GET", "/api/combos")
combo = None
if gcode == 200 and isinstance(combinations, dict):
    for c in combinations.get("combos", []):
        if c.get("name") == COMBO: combo = c; break
if combo is None:
    print(f"[7] combo '{COMBO}' not found — would create it with "
          f"{[f'{NAME}/{m}' for m in keep]}")
    if not DRY:
        print("FAIL: combo does not exist and refusing to create a new one."); sys.exit(1)
else:
    existing = combo.get("models", [])
    entries = []
    for model in keep:
        full = f"{NAME}/{model}"
        if any(m.get("providerId") == node_id and m.get("model") == full for m in existing):
            continue  # already present -> preserve, don't duplicate
        entries.append({
            "id": f"{COMBO}-model-{NAME}-{model}".replace(":", "-"),
            "kind": "model", "model": full, "providerId": node_id, "weight": 0,
        })
    if entries:
        new_models = existing + entries
        payload = {"name": combo.get("name", COMBO),
                   "strategy": combo.get("strategy", "priority"),
                   "enabled": combo.get("enabled", True),
                   "config": combo.get("config", {}), "models": new_models}
        if DRY:
            step(7, f"combo '{COMBO}': append {len(entries)} -> {len(new_models)} models",
                 json.dumps(payload)[:400])
        else:
            step(7, f"combo '{COMBO}': append {len(entries)} -> {len(new_models)} models")
            cid = combo.get("id")
            res, code, raw = req_auth("PUT", f"/api/combos/{cid}", payload) if cid \
                else req_auth("POST", "/api/combos", payload)
            if code not in (200, 201):
                print(f"FAIL step 7 (HTTP {code}): {raw[:400]}"); sys.exit(1)
    else:
        print(f"[7] all keep-models already in combo '{COMBO}' — no-op")

# -----------------------------------------------------------------------------
print()
if DRY:
    print(f"[dry-run] would register '{NAME}' ({len(keep)} models) "
          f"and wire them into auto-fastest. Nothing written.")
else:
    print(f"OK  provider '{NAME}' -> {[(f'{NAME}/{m}') for m in keep]} "
          f"wired into auto-fastest  (node={node_id}, conn={conn_id})")
PYEOF
