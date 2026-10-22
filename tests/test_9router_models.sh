#!/usr/bin/env bash
set -euo pipefail

# Test: 9Router model-list JSON — OFFLINE structural validation.
#
# This is a fast, no-network unit test that always runs in the `test` job:
# it guarantees the data file is well-formed and internally consistent, so a
# hand-edit can't silently break boot. What the file actually CONTAINS
# (drift vs. the live upstream) is checked by the advisory job via
# scripts/sync-9router-models.sh --check, and what works against a live
# stack is checked by --probe. Keep this test local/offline by design.
#
# Exit 0 = clean. Exit 1 = structural problem (should not be committed).

# Resolve the JSON relative to the repo root (this script lives in tests/).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
JSON_FILE="$ROOT_DIR/etc/9router-models.json"

echo "Validating $JSON_FILE (offline / structural) ..."

if [ ! -f "$JSON_FILE" ]; then
    echo "FAIL: $JSON_FILE not found"
    exit 1
fi

python3 - "$JSON_FILE" <<'PYEOF'
import json, sys

path = sys.argv[1]
errors = []

# 1. JSON parses
try:
    data = json.load(open(path))
except Exception as e:
    print(f"FAIL: not valid JSON: {e}")
    sys.exit(1)

if not isinstance(data, dict):
    print("FAIL: top level must be a JSON object")
    sys.exit(1)

# 2. Required scalar fields
combo = data.get("combo")
if combo != "auto-fastest":
    errors.append(f"combo must be 'auto-fastest', got {combo!r}")

strategy = data.get("strategy")
if not isinstance(strategy, str) or not strategy:
    errors.append(f"strategy must be a non-empty string, got {strategy!r}")

# 3. models: non-empty list of oc/-prefixed strings
models = data.get("models")
if not isinstance(models, list) or not models:
    errors.append("models must be a non-empty array")
    models = []
else:
    for m in models:
        if not isinstance(m, str) or not m.startswith("oc/"):
            errors.append(f"model {m!r} is not an 'oc/...' prefixed string")

# 4. excluded: list of {id, reason} objects (optional)
excluded = data.get("excluded", [])
if not isinstance(excluded, list):
    errors.append("excluded must be an array (if present)")
    excluded = []
else:
    for e in excluded:
        if not isinstance(e, dict) or "id" not in e:
            errors.append(f"excluded entry must be an object with 'id', got {e!r}")

# 5. Invariant: an excluded model must NOT also be in the active list.
#    This is the exact bug that shipped in 2026-10 (oc/jev-1.13-free was in
    # both) — catch any future recurrence.
models_set = set(models)
for e in excluded:
    if isinstance(e, dict) and e.get("id") in models_set:
        errors.append(f"{e['id']} is both in 'excluded' AND in 'models' (must be in one place only)")

if errors:
    print("FAIL: structural validation failed:")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print(f"OK: {len(models)} active model(s), "
       f"{len(excluded)} excluded, combo={combo!r}, strategy={strategy!r}")
sys.exit(0)
PYEOF
