---
name: minions-llm-proxy-ops
description: Use when operating or debugging the .minions LLM proxies.
version: 0.1.0
author: .minions maintainers
license: MIT
metadata:
  hermes:
    tags: [9router, omniroute, opencode, llm-proxy, free-tier, combos]
    related_skills: [docker-test-shell, version-single-source]
---

# .minions LLM proxy stack ops

## When to Use

- A model or combo through 9Router (:7352) or OmniRoute (:20128) errors,
  403s, rate-limits, or returns empty content.
- opencode.ai free tier (`oc/` models) breaks — FreeTierError, "Model is
  unavailable", or silent empty responses.
- The `auto-fastest` combo needs its model list refreshed or reordered.
- You need to change 9Router provider headers, combos, or settings so they
  survive reboots (i.e. via `lib/9router.sh`).

The stack (boot.sh) runs OmniRoute (:20128) and 9Router (:7352). 9Router routes
`auto-fastest` (a combo) to free OpenCode (`oc/`) models; OmniRoute is the
upstream LLM proxy for Hermes. `lib/9router.sh` (`ninerouter_preconfigure`)
re-applies 9Router config idempotently on every boot — edit it there so config
survives restarts, and use its API calls as the reference for ad-hoc changes.

## Always-on rules

- **Verify a proxy change with real completions, never HTTP status alone.**
  9Router's combo fallback counts an empty `finish_reason:"in_progress"` (or
  `finish_length` with 0 visible tokens) response as SUCCESS, so a combo whose
  first model is silently broken returns empty content forever without ever
  falling back. Pass signal = non-empty `choices[0].message.content`; empty
  content is a failure regardless of `finish_reason` (free models sometimes
  return correct content with `finish_reason:"length"`, so don't require
  `stop`). A 2xx with empty content is a failure.
- **Lead a combo with the known-good model.** Since fallback only fires on
  hard errors, put the model that actually produces content FIRST in the combo
  model list; put flaky/unverified models after.
- **Free-tier model lists rotate.** Query the live list before trusting any
  hardcoded model id: `curl -s https://opencode.ai/zen/v1/models` (only ids
  ending `-free` / `-contributor-free` are actually free). A stale id either
  hard-errors or silently returns empty — both degrade the combo.
- **9Router dashboard login**: default password `123456`; cookie session via
  `POST /api/auth/login`. All admin APIs need the cookie (`-b "$COOKIE"`).
  `requireLogin`/`requireApiKey` are disabled by preconfig.
- **9Router combo model list lives in `etc/9router-models.json` (single
  source). 9Router only — `lib/omniroute.sh` is NOT wired to it.**
  `lib/9router.sh` reads that file at boot — never duplicate the list inline
  in a shell script. `tests/test_9router_models.sh` (blocking CI) is an OFFLINE
  structural guard; `scripts/sync-9router-models.sh` owns upstream drift
  (`--check`/`--write`) and live probing (`--probe`, `--probe-write` need a
  running 9Router on :7352: keep 200/429, drop 400/410).

- **Config lives in 9Router's own DB, keyed by canonical provider id.**
  `PUT /api/providers/<id>/overrides` REPLACES the whole header map for that
  provider (idempotent; send the full map each time). `POST /api/combos` +
  DELETE-by-id is how combos are recreated (there is no PUT on combos).

## Standard procedure: audit/fix a provider's routing

1. Log in and save a cookie:
   `curl -s -c /tmp/nr.txt -X POST $BASE/api/auth/login -H 'Content-Type: application/json' -d '{"password":"123456"}'`
2. Inspect current state: `GET /api/combos`, `GET /api/settings`,
   `GET /api/providers/<id>/overrides` (shows `headers` + `builtinHeaders`).
3. If upstream 403s / rejects: set header overrides (see
   `references/opencode-free-tier.md` for the OpenCode-specific header set and
   session-id generator).
4. Fix the combo model list against the LIVE free list (step above), known-good
   model first.
5. Test with a real prompt at >=128 max_tokens (small budgets get eaten by
   reasoning tokens and look like empty failures):
   `POST /v1/chat/completions {"model":"auto-fastest","messages":[...],"stream":false,"max_tokens":128}`
   Assert non-empty content. To validate a combo's model list, test each
   member individually the same way — bare ids route directly
   (`model=oc/<id>`), so you can run them in parallel and prune dead ids
   before recreating the combo. If a model errors, read
   `~/.minions/var/log/9router.log` — it logs the upstream URL, status, and
   provider-side error body.
6. Any change must land in `lib/9router.sh` or it is lost: the boot
   preconfig deletes and recreates combos (and re-puts overrides) every boot,
   so live-only edits — dashboard or ad-hoc API — silently revert on next
   boot. Edit the script, then let boot apply it, or apply + edit together.

## Add an OpenAI-compatible provider (OmniRoute :20128), wire a model into `auto-fastest`

`scripts/add-tailscale-provider.sh <host[:port]>` does this idempotently
(`--dry-run` supported; `TSC_PORT` sets the port for a bare host (default
`11434`); `MODEL_NAME`/`PROVIDER_NAME` env, model defaults to `qwen3.8:27b`).
The five REST steps below are the verified sequence (OmniRoute 3.8.53) and how
the script works — use them as the manual/API reference for any new upstream
that only needs a base URL:

1. **Create the NODE** — `POST /api/provider-nodes` with
   `{name, type:"openai-compatible", baseUrl:"http://<host:port>/v1",
   prefix:name, apiType:"chat"}`. `baseUrl` MUST end in `/v1` (the base for the
   OpenAI-compatible endpoints) and OMIT `chatPath`/`modelsPath` entirely —
   the server stores them `null` (its own default), which is the correct shape.
   The **server generates** the concrete id `openai-compatible-chat-<uuid>` —
   that uuid IS the provider id used by `/api/providers` and combos. **Pitfalls
   (verified against OmniRoute 3.8.53):** explicit `null` → `400 Invalid input`
   (so omit the keys, don't null them); non-null strings like
   `"/v1/chat/completions"` → `201` but **wrong** — they double the `/v1`
   `baseUrl` already carries, producing `.../v1/v1/...`. If you ever DO set
   them, use bare `"/chat/completions"` or `"/models"` (no `/v1`).
2. **Create the CONNECTION** — `POST /api/providers` with
   `{provider:"<node-id>", name, apiKey:"<any non-empty string>", priority,
   providerSpecificData:{prefix, apiType:"chat", baseUrl, nodeName:name}}`.
   **Pitfall:** a keyless connection is rejected (`"API key is required"` /
   `"does not allow a connection without a credential"`). The key value is
   ignored by the upstream; a dummy credential is fine. `omniroute providers
   add openai-compatible …` fails with `Invalid provider` because the CLI will
   not accept the abstract type — the node must exist first and the concrete
   id must be passed.
3. **Activate** — `PUT /api/providers/<cid> {"isActive":true}`. The connection
   is created `isActive:false`; activation returns `testStatus:"active"`
   immediately when the upstream is reachable.
4. **Import the model** — `POST /api/provider-models {provider:"<node-id>",
   modelId}`. The alternate `validate-and-add` endpoint requires a real
   `Authorization` header on this deployment and 401s — use the plain one.
5. **Append to `auto-fastest`** — `GET /api/combos`, find `auto-fastest`, add
   `{id:"<combo>-model-<name>-<model>", kind:"model", model:"<name>/<model>",
   providerId:"<node-id>", weight:0}` to `models[]`, then `PUT /api/combos/<id>`
   with the FULL body `{name, strategy, enabled, config, models}`. **Pitfall:**
   `PUT` rejects a body that has only `models` (`COMBO_001 Invalid JSON body`).
   `POST /api/combos` upserts by name, so it works for both create and re-list.

**Teardown (safe):** `omniroute providers remove <name> --yes` does an exact
name match (no substrings) — verified in `resolveRemoteConnection` →
`findConnectionFromResponse`. `DELETE /api/provider-nodes/<node-id>` removes
the node. To strip a line from a combo: `PUT /api/combos/<id>` with the
filtered `models` (don't send `id`/`sortOrder`/`isHidden` in the body).

**Watch for server-side side effects:** the OmniRoute `ModelSync` job runs on a
timer and has been observed removing an existing duplicate connection on the
same provider node during an unrelated create/delete window (2026-10-23,
`main-2` on the `ollama` node vanished while adding/removing a *different*
node). Always snapshot `GET /api/providers` plus the `provider_nodes` /
`provider_connections` rows before and after, so collateral damage is caught
and reported, not hidden.

## Pitfalls

- Don't test with tiny max_tokens (16–32): free models spend the budget on
  reasoning tokens and return empty `finish_reason=length`, which looks like a
  routing bug but isn't.
- Don't assume `curl -f` passing means the combo works — a 2xx empty-body
  response passes `-f`. Parse the JSON body.
- Free-tier endpoints are flaky: a 429/"Endpoint is unavailable" on one model
  is usually transient per-model, not a config error — try the other combo
  members before changing config. The opposite case is a deterministic 400
  `Upstream request failed: Model is unavailable` that reproduces across
  retries and token budgets: that's a dead id — drop it from the combo and
  sync `lib/9router.sh`.
- Some model ids need a different protocol than openai chat completions and
  fail with `ModelProtocolUnsupported` — exclude them from the combo rather
  than trying to force them.

## OmniRoute (:20128) does NOT accept this fix

The OpenCode header override is 9Router-specific. Verified live against
OmniRoute 3.8.51 — do not waste time re-attempting it:

- OmniRoute has no `/api/providers/<id>/overrides` equivalent.
- Its open-sse build synthesizes OpenCode headers natively with `OPENCODE_CLIENT`
  / `OPENCODE_USER_AGENT` env knobs (in `~/.omniroute/.env`, loaded at startup).
  Setting `OPENCODE_CLIENT=cli` + the UA and restarting does NOT clear the 403.
- Passing the full `x-opencode-*` header set on the request itself changes the
  error from `FreeTierError` to `No active credentials for provider: opencode` —
  OmniRoute treats a valid CLI identity as a *keyed* account, not a bypass.
- `POST /api/providers/free-onboarding` returns "not eligible" for `opencode`
  and `opencode-zen` — a real account/credential is required.
- OmniRoute's combo also rots: `opencode-zen/mimo-v2.5-free` → 410 deprecated.
- If the OpenCode free tier must be used, route through 9Router (:7352) —
  it already has the working fix.