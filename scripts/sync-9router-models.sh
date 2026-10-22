#!/usr/bin/env bash
set -euo pipefail

# Sync: Regenerate etc/9router-models.json from live upstream model list
# Mirrors the pattern of sync-versions.sh / sync-readme-badges.sh
#
# Modes:
#   bash scripts/sync-9router-models.sh              # --check (default, advisory)
#   bash scripts/sync-9router-models.sh --dry-run    # show diff, don't write
#   bash scripts/sync-9router-models.sh --check      # exit non-zero if drift
#   bash scripts/sync-9router-models.sh --write      # regenerate from upstream (no probe)
#   bash scripts/sync-9router-models.sh --probe      # probe each model; no write
#   bash scripts/sync-9router-models.sh --probe-write
#       Fetch upstream -> probe all free-tier candidates against a running
#       9Router -> keep 200 (OK) and 429 (RATED-LIMIT) -> drop 400/404/410
#       (HARD-FAIL) -> write the surviving models back into the JSON.
#       Requires running 9Router at NINEROUTER_BASE_URL (default 127.0.0.1:7352).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Run from repo root so etc/ paths resolve correctly
cd "$SCRIPT_DIR/.."

JSON_FILE="etc/9router-models.json"
UPSTREAM_URL="https://opencode.ai/zen/v1/models"

# Use curl to fetch upstream model list (urllib hits 403 in this env)
TMPFILE="$(mktemp /tmp/9router-upstream-ids.XXXXXX)"
trap 'rm -f "$TMPFILE"' EXIT

if curl -fsS "$UPSTREAM_URL" -o "$TMPFILE" 2>/dev/null; then
    FETCHED=1
else
    FETCHED=0
    echo "WARNING: Could not fetch upstream model list via curl" >&2
fi

read_json_and_check() {
    local json_file="$1" tmpfile="$2" mode="$3"
    python3 - "$json_file" "$tmpfile" "$mode" <<'PYEOF'
import json, sys, hashlib, os
import urllib.request, urllib.error, urllib.parse, socket, time

json_file = sys.argv[1]
tmpfile   = sys.argv[2]
mode      = sys.argv[3] if len(sys.argv) > 3 else "check"

with open(json_file) as f:
    current_data  = json.load(f)
with open(tmpfile) as f:
    upstream_data = json.load(f)

upstream_ids = [
    m['id'] for m in upstream_data.get('data', [])
    if m['id'].endswith('-free') or m['id'].endswith('-contributor-free')
]

excluded_ids = set(e['id'] for e in current_data.get('excluded', []))
# Upstream ids are bare (jev-1.13-free); our JSON lists/excludes them with
# the oc/ prefix. Match on both forms so an exclusion is honored whether it
# was written bare or prefixed.
def _excluded(bare_id):
    return bare_id in excluded_ids or ('oc/' + bare_id) in excluded_ids

new_models_list = ['oc/' + id_ for id_ in upstream_ids if not _excluded(id_)]

# ---------------------------------------------------------------------------
# Classification shared by --probe and --probe-write
#   200     -> OK           (model serves cleanly; keep)
#   429     -> RATED-LIMIT  (exists, free-quota only; keep — deliberately NOT a failure; rate-limit ≠ broken)
#   400/404/410 -> HARD-FAIL (deterministic unsupported/gone/unknown; drop)
#   other   -> UNKNOWN      (surfaced; keep — safer to fail open)
# ---------------------------------------------------------------------------
def classify(code):
    if code == 200:            return 'OK'
    # 429 = free-tier quota. Deliberate: rate-limited means the model EXISTS.
    # Do not "fix" this to drop — that discards every model during a burst.
    if code == 429:            return 'RATED-LIMIT'
    if code in (400, 404, 410): return 'HARD-FAIL'
    return 'UNKNOWN'

# ---------------------------------------------------------------------------
# 7352 liveness gate. Returns (host, port, err); err=='' on success.
# ---------------------------------------------------------------------------
def probe_gate(base_url):
    p    = urllib.parse.urlparse(base_url if '://' in base_url else 'http://' + base_url)
    host = p.hostname
    port = p.port or 80
    try:
        s = socket.create_connection((host, port), timeout=3)
        s.close()
        return (host, port, '')
    except OSError as e:
        return (host, port, f'{e.__class__.__name__}: {e}')

# ---------------------------------------------------------------------------
def probe_one(base_url, model_id):
    """One LM request; returns (final_code, detail).

    Retries 429/5xx transient errors up to 3 times with backoff.
    400/404/410 are deterministic - return immediately.
    """
    last_code, last_detail = -1, ''
    for attempt in range(3):
        try:
            req = urllib.request.Request(
                f'{base_url}/v1/chat/completions',
                data=json.dumps({
                    "model": model_id,
                    "messages": [{"role": "user", "content": "OK"}],
                    "max_tokens": 16,
                }).encode(),
                headers={'Content-Type': 'application/json'},
                method='POST',
            )
            with urllib.request.urlopen(req, timeout=20) as resp:
                return (int(resp.status), '')
        except urllib.error.HTTPError as e:
            body = e.read().decode()[:120]
            last_code, last_detail = e.code, body[:80]
            if e.code in (400, 404, 410):
                return (last_code, last_detail)
            if e.code == 429 or e.code >= 500:
                time.sleep(1.5 * (attempt + 1))
                continue
            return (last_code, last_detail)
        except Exception as e:
            last_code, last_detail = -1, f'{type(e).__name__}: {str(e)[:40]}'
            time.sleep(1.5 * (attempt + 1))
    return (last_code, last_detail)

# ---------------------------------------------------------------------------
if mode == "dry-run":
    print(f'Current model count:    {len(current_data.get("models", []))}')
    print(f'Upstream free models:   {len(upstream_ids)}')
    print(f'Excluded (deliberate):  {len(excluded_ids)}')
    print()
    print('Current models (first 5):')
    for m in current_data.get('models', [])[:5]:
        print(f'  {m}')
    print()
    print('New models (first 5):')
    for m in new_models_list[:5]:
        print(f'  {m}')
    print()
    print('New models (last 5):')
    for m in new_models_list[-5:]:
        print(f'  {m}')
    print()
    print('Excluded models preserved:')
    for e in current_data.get('excluded', []):
        print(f'  {e["id"]}: {e.get("reason", "")}')

elif mode == "check":
    current_models = current_data.get('models', [])
    current_set    = set(current_models)
    new_set        = set(new_models_list)
    dead    = [m for m in current_models if m not in new_set]
    missing = [m for m in new_models_list if m not in current_set and m not in excluded_ids]
    if not dead and not missing:
        print(f'OK: etc/9router-models.json is in sync with upstream '
              f'({len(current_models)} models, {len(excluded_ids)} excluded)')
        sys.exit(0)
    print(f'DRIFT DETECTED vs upstream: '
          f'{len(current_models)} listed -> {len(new_models_list)} currently valid')
    if dead:
        print(f'  {len(dead)} model(s) in our list NO LONGER valid upstream (remove):')
        for m in dead:
            print(f'    - {m}')
    if missing:
        print(f'  {len(missing)} upstream free model(s) not yet listed, not excluded (optional):')
        for m in missing:
            print(f'    + {m}')
    print('Advisory: to apply, run  bash scripts/sync-9router-models.sh --write')
    sys.exit(1)

elif mode == "probe":
    base_url = os.environ.get('NINEROUTER_BASE_URL', 'http://127.0.0.1:7352')
    host, port, err = probe_gate(base_url)
    if err:
        print(f'ERROR: 9Router not reachable at {host}:{port} ({err})')
        print('Probe requires a running 9Router. Start the stack (boot.sh) or set NINEROUTER_BASE_URL.')
        sys.exit(2)

    models = current_data.get('models', [])
    if not models:
        print('No models to probe.')
        sys.exit(0)

    counts = {'OK': 0, 'RATED-LIMIT': 0, 'HARD-FAIL': 0, 'UNKNOWN': 0}
    for model_id in models:
        code, detail = probe_one(base_url, model_id)
        cls = classify(code)
        counts[cls] = counts.get(cls, 0) + 1
        line = f'{cls:11s} {model_id}'
        if detail:
            line += f'  (HTTP {code}: {detail})'
        print(line)
    print()
    hard = counts.get('HARD-FAIL', 0)
    if hard:
        print(f'{hard} model(s) hard-failed (400/404/410). Run --probe-write to drop them.')
        sys.exit(1)
    if counts.get('UNKNOWN'):
        print(f'{counts["UNKNOWN"]} model(s) unknown-status; kept. See lines above.')
    print(f'OK={counts["OK"]}  RATED-LIMIT={counts["RATED-LIMIT"]}  '
          f'HARD-FAIL={hard}  UNKNOWN={counts.get("UNKNOWN", 0)}')
    sys.exit(0)

elif mode == "probe-write":
    base_url = os.environ.get('NINEROUTER_BASE_URL', 'http://127.0.0.1:7352')
    host, port, err = probe_gate(base_url)
    if err:
        print(f'ERROR: 9Router not reachable at {host}:{port} ({err})')
        print('--probe-write requires a running 9Router to classify models.')
        sys.exit(2)

    candidates = new_models_list   # upstream-derived, already excludes `excluded`
    if not candidates:
        print('No candidates to probe (upstream returned empty free-tier list?).')
        sys.exit(0)

    print(f'Probing {len(candidates)} upstream free candidates at {host}:{port} ...')
    print('Keep: 200 / 429    Drop: 400 / 410    (other codes: keep, reported)')
    print()

    kept, dropped, unknown = [], [], []
    for model_id in candidates:
        code, detail = probe_one(base_url, model_id)
        cls = classify(code)
        line = f'{cls:11s} {model_id}'
        if detail:
            line += f'  (HTTP {code}: {detail})'
        print(line)
        if cls in ('OK', 'RATED-LIMIT'):
            kept.append(model_id)
        elif cls == 'HARD-FAIL':
            dropped.append((model_id, code, detail))
        else:
            unknown.append((model_id, code, detail))

    print()
    print(f'Probed: {len(candidates)}   kept: {len(kept)}   '
          f'dropped: {len(dropped)}   unknown-kept: {len(unknown)}')

    # Preserve any models already in the current file that are NOT in the
    # upstream free-tier candidate set (e.g. a user-added custom model).
    # --probe-write only manages the free-tier list; custom entries pass
    # through untouched.
    existing  = current_data.get('models', [])
    upstreams = set(new_models_list)
    preserved = [m for m in existing if m not in upstreams]

    final_models = list(kept) + preserved

    # Record any newly-dropped candidate into the `excluded` block (idempotent
    # by id) so the reason is discoverable and a later --write does not
    # accidentally resurrect it.
    excluded_block        = list(current_data.get('excluded', []))
    existing_excluded_ids = {e['id'] for e in excluded_block}
    for model_id, code, detail in dropped:
        if model_id not in existing_excluded_ids:
            reason = f'probe-write: HTTP {code} {detail}'.strip()
            excluded_block.append({'id': model_id, 'reason': reason})

    # Safety: refuse to write an empty models list - that would be a silent
    # catastrophic update if the free tier happened to hard-fail everything.
    if not final_models:
        print()
        print('ERROR: final models list would be empty. Refusing to write.')
        print('All upstream free-tier models hard-failed or came back unknown.')
        print('Re-run later, or inspect manually. (Use --probe to see per-model status.)')
        sys.exit(1)

    new_data = dict(current_data)
    new_data['models']   = final_models
    new_data['excluded'] = excluded_block
    with open(json_file, 'w') as f:
        json.dump(new_data, f, indent=2)
        f.write('\n')

    print()
    print(f'OK: {json_file} updated via --probe-write')
    print(f'  models: {len(final_models)} (kept={len(kept)} + preserved={len(preserved)})')
    print(f'  excluded: {len(excluded_block)}')
    if dropped:
        print('  dropped this run:')
        for m, code, detail in dropped:
            print(f'    - {m}  (HTTP {code})')

    sys.exit(0)
PYEOF
}

case "${1:-check}" in
    --dry-run)
        echo "=== Dry run: showing what would change ==="
        read_json_and_check "etc/9router-models.json" "$TMPFILE" "dry-run"
        echo ""
        echo "(Upstream fetch status: $FETCHED)"
        ;;

    --check)
        echo "Checking if etc/9router-models.json is in sync with upstream..."
        read_json_and_check "etc/9router-models.json" "$TMPFILE" "check"
        ;;

    --probe)
        echo "Probing models against running 9Router instance..."
        read_json_and_check "etc/9router-models.json" "$TMPFILE" "probe"
        ;;

    --probe-write)
        echo "Probing upstream free-tier candidates and writing etc/9router-models.json..."
        read_json_and_check "etc/9router-models.json" "$TMPFILE" "probe-write"
        echo ""
        echo "(Upstream fetch status: $FETCHED)"
        ;;

    --write)
        echo "Writing etc/9router-models.json from upstream (no probe)..."
        python3 - "$JSON_FILE" "$TMPFILE" <<'PYEOF'
import json, sys

json_file = sys.argv[1]
tmpfile   = sys.argv[2]

with open(json_file) as f:
    current_data  = json.load(f)
with open(tmpfile) as f:
    upstream_data = json.load(f)

upstream_ids = [
    m['id'] for m in upstream_data.get('data', [])
    if m['id'].endswith('-free') or m['id'].endswith('-contributor-free')
]

excluded_ids = set(e['id'] for e in current_data.get('excluded', []))
def _excluded(bare_id):
    return bare_id in excluded_ids or ('oc/' + bare_id) in excluded_ids

new_models_list = ['oc/' + id_ for id_ in upstream_ids if not _excluded(id_)]

# Preserve any models already in the current file that are NOT in the
# upstream free-tier set (e.g. a user-added custom model) — same semantics
# as --probe-write, so hand-edited entries survive --write regeneration.
existing  = current_data.get('models', [])
upstreams = set(new_models_list)
preserved = [m for m in existing if m not in upstreams]
final_models = list(new_models_list) + preserved

# Safety: refuse to write an empty models list (broken upstream shape /
# all free models excluded) — see the identical guard in --probe-write.
if not final_models:
    print()
    print('ERROR: final models list would be empty. Refusing to write.')
    print('Either upstream returned nothing or every candidate is excluded.')
    sys.exit(1)

new_data = dict(current_data)
new_data['models'] = final_models

with open(json_file, 'w') as f:
    json.dump(new_data, f, indent=2)
    f.write('\n')

print(f'OK: {json_file} regenerated from upstream')
print(f'  models: {len(final_models)} (upstream={len(new_models_list)} + preserved={len(preserved)})')
print(f'  combo:  {new_data.get("combo")}')
print(f'  strategy: {new_data.get("strategy")}')
for e in new_data.get('excluded', []):
    print(f'    excluded: {e["id"]} - {e.get("reason", "")}')
PYEOF
        ;;

    *)
        echo "ERROR: unknown argument: ${1}" >&2
        echo "" >&2
        echo "Usage: bash scripts/sync-9router-models.sh [--dry-run | --check | --write | --probe | --probe-write]" >&2
        echo "  (no argument = --check)" >&2
        exit 2
        ;;
esac
