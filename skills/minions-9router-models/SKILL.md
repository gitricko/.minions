---
name: minions-9router-models
description: Manage 9Router model list via etc/9router-models.json.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [9router, models, json, free-tier, advisory-ci]
    related_skills: [version-single-source, ci-debugging, tdd]
---
# 9Router Model JSON Management

**Never hardcode `oc/...-free` / `-contributor-free` model ids in `lib/9router.sh`.**
Always source them from `etc/9router-models.json`, the single source of truth for the 9Router auto-fastest combo model list.

## JSON schema

| Field | Description |
|-------|-------------|
| `combo` | Combo name (e.g. `auto-fastest`) |
| `strategy` | Strategy name (e.g. `auto`) |
| `source` | Upstream model list URL |
| `filter` | Shell glob patterns to filter upstream models |
| `excluded` | Model ids preserved by design (with reasons) |
| `models` | Array of `oc/...-free` / `-contributor-free` ids consumed by `lib/9router.sh` |

## Adding/removing models

1. Edit `etc/9router-models.json` directly — add or remove ids in the `models` array.
2. Regenerate from upstream: `bash scripts/sync-9router-models.sh --dry-run`
3. Validate: `python3 -c "import json; json.load(open('etc/9router-models.json'))"`
4. Commit the updated JSON.

## Sync script (`scripts/sync-9router-models.sh`)

### Modes

| Mode | Flag | Behavior |
|------|------|----------|
| Dry-run | `--dry-run` | Fetch upstream, show what would change; exit 0 if file would differ |
| Check | `--check` | Same as dry-run but exits non-zero if file would change (advisory CI gate) |
| Probe | `--probe` | Probe each model in `models[]` against running 9Router. Gates on 7352 liveness first (exit 2 if down). | **Yes** |
| Write | `--write` | Regenerates `etc/9router-models.json` from upstream free-tier models (no probe). | No |
| Probe-write | `--probe-write` | Gate on 7352 alive → probe all upstream free candidates → keep 200/429, drop 400/410, record dropped in `excluded`, write JSON. Refuses to write an empty models list. | **Yes** |

### Probe / probe-write classification

| HTTP | Class | Action |
|------|-------|--------|
| 200 | OK | keep |
| 429 | RATED-LIMIT | keep (free-tier rate-limit, not broken) |
| 400/410 | HARD-FAIL | drop (deterministic ModelProtocolUnsupported / gone) |
| other | UNKNOWN | keep (fail-open, surfaced) |

`--probe` and `--probe-write` retry 429/5xx up to 3× with backoff, then classify.

### Exit codes (repo convention 0 ok / 1 warnings / 2 critical)

- **0** — ok; no failures / clean write / no drift
- **1** — some model HARD-FAILED (advisory, CI continues); `--check` drift detected
- **2** — 9Router unreachable at 7352 (probe and probe-write both bail before touching the JSON); `--probe-write` refusing an empty write

## Advisory CI model validity (`.github/workflows/ci.yml`)

`9router-model-check` runs `bash scripts/sync-9router-models.sh --check` — single implementation, no inline reparse. `continue-on-error: true`, gated on infrastructure-changes. The offline `tests/test_9router_models.sh` runs in the blocking `test` job. Probe is NOT in CI (GitHub runners don't have 9Router running); run `--probe` / `--probe-write` manually or on a schedule.

## Probe mode detail

Uses `POST /v1/chat/completions` with `model=<id>` and `max_tokens=16`. 4xx (400/410) are deterministic failures → drop the model. 429 is rate-limiting → keep. All probe code shares: `probe_gate(base_url)` (TCP connect with 3s timeout), `probe_one(base_url, model_id)` (retries transient errors), `classify(code)` (shared 200/400/410/other mapping).  `--probe-write` also records a newly-dropped model into the `excluded` array (idempotent by id) and preserves non-upstream custom models the user may have added.

## Runtime integration in `lib/9router.sh`

The `ninerouter_preconfigure()` function reads the model list dynamically from `etc/9router-models.json` using a Python one-liner, so editing the JSON file is the only change needed — no edits to `lib/9router.sh` required.

## Exclusion list

Model ids in the `excluded` array are preserved by design and excluded from the auto-fastest combo. Each has a `reason` field documenting why (e.g., Model is unavailable upstream, ModelProtocolUnsupported, Upstream 400 Model is unavailable).

## Related skills

- `version-single-source` — for the broader version/deps.yaml pattern
- `ci-debugging` — for debugging CI model-check failures
- `tdd` — for test-driven development of model list changes