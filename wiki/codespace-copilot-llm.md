# GitHub Copilot LLM in Codespaces — Architecture Findings (2026-10-30)

## Objective

Determine **how** the built-in Copilot chat panel in a GitHub Codespace calls
GitHub's LLM backend — the process, endpoint, protocol, auth model — and
assess whether the resulting credential or endpoint can be **reused**
directly, or **proxied** into OmniRoute (or 9Router) for use by Hermes Agent
and the rest of the `.minions` stack.

## Executive summary

| Question | Answer |
|---|---|
| What process serves LLM for the chat panel | **Agent host (PID ≈ 1413)** exposes a `ClaudeProxyService` on `127.0.0.1:42049` |
| What protocol | **Anthropic** (`/v1/messages`, `/v1/models`, `/v1/responses`) + OpenAI-style (`wireApi:"responses"`, `"completions"`) |
| What uplinks it | `https://api.github.com/copilot_internal/…` (entitlement-token mint path; actual LLM target gated behind internal SSO) |
| What auth does the proxy require | `Authorization: Bearer <nonce>` where the nonce is a **per-session value** generated in-process by the Copilot SDK (`crypto.getRandomValues(16 bytes)`) and distributed to SDK clients over the JSON-RPC channel — **not** the shell's `GITHUB_TOKEN` |
| Is the `GITHUB_TOKEN` (`ghu_…`) a reusable LLM credential? | **YES — directly** (corrected 2026-10-31). It authenticates `GET /copilot_internal/user` *and* the real LLM endpoint `https://api.individual.githubcopilot.com/chat/completions` with plain `Authorization: Bearer *** — no SDK, no nonce, no extra headers. The earlier "401/404 on every LLM surface" was testing the **wrong surfaces** (the local proxy and the github REST endpoints on api.github.com), which are not the panel's real backend. |
| Can we attach OmniRoute to :42049? | Not needed. :42049 is an internal hop for in-IDE consumers. The real upstream is a public OpenAI-compatible REST API (see below) — register it as a provider directly. |
| Tier / cap | `access_type_sku: free_limited_copilot`, `copilot_plan: individual` — **free limited tier**; expect bounded models and rate limits even in the working case. |
| Active model family (observed) | `gpt-5.6-luna` (from `COPILOT_EXP_COPILOT_CLI_EXECUTION_SUBAGENT_MODEL`); Anthropic providers register on the proxy but the free tier may only allow a subset. |

## PID map

| PID (session of 2026-10-30) | Role | Key command |
|---|---|---|
| 1361 | Shell launcher | `sh …/code-server --install-extension anthropic.claude-code …` |
| 1370 | VS Code server (Node, MainThread) | `/vscode/bin/linux-x64/<commit>/out/server-main.js …` |
| 1399 | Extension host | `node … node --dns-result-order=ipv4first …` |
| 1413 | **Agent host — owns :42049** | `node …/out/bootstrap-fork --type=agentHost …` |
| 2238 | **Copilot runtime (native)** | `copilot-sdk-linux-x64/prebuilds/linux-x64/copilot-runtime --headless --no-auto-update --stdio --no-auto-login` |

`VSCODE_AGENT_HOST_CLAUDE_AGENT_ENABLED=true`, `VSCODE_AGENT_HOST_CODEX_AGENT_ENABLED=false`, `COPILOT_CLI_ENABLED_FEATURE_FLAGS=SHELL_SPAWN_BACKEND,DYNAMIC_AUTO_TIERS` all live on 1413's env.

## The proxy (ClaudeProxyService)

- **Address:** `http://127.0.0.1:42049` (from `agenthost.log`: `[ClaudeProxyService] listening on …`)
- **Liveness (VERIFIED):** `GET /` → `ok`
- **Routes seen in bundle:** `/v1/messages`, `/v1/models`, `/v1/messages/count_tokens`, `/v1/responses`, `/v1/chat/completions`
- **Provider set (VERIFIED-source):** the proxy registers provider type `"anthropic"` for Claude, and also handles `"openai"` wire APIs `responses` and `completions`.
- **Auth check (VERIFIED-source):** the handler builds `` `Bearer ${n.nonce}` `` and returns `401 authentication_error / "Invalid authentication"` unless `e.headers.authorization === l`. `nonce` originates from `crypto.getRandomValues(16 bytes)` in a per-session object returned alongside `baseUrl` to the client via the JSON-RPC channel.

The nonce is a **session-bound opaque bearer**, not a persistent token. It is minted when the Copilot-SDK client (the panel host) initializes its proxy session and handed out over stdio. No shell environment variable holds it; it does not persist on disk in a form we can grep.

## The `ghu_…` token — what it can and cannot do

`GET api.github.com/copilot_internal/user` with the extracted `ghu_…` token
(VERIFIED 2026-10-30) returns real account metadata:

```
id: 283379899
login: benchewyy
access_type_sku: free_limited_copilot
copilot_plan: individual
chat_enabled: true
cli_enabled: true
is_mcp_enabled: true
can_signup_for_limited: false
```

The same token, presented to `https://api.github.com/copilot_*` chat/completions
paths (VERIFIED), returns **404** — GitHub does not expose the raw completion
endpoint on this surface for this token. The proxy (`:42049`) returns **401**
for every bearer variant (verified with x-api-key, Bearer, query param,
`x-github-copilot-integration-id`, `x-app-id`). The correct credential is the
nonce + the internal SSO context the SDK establishes.

## Bundle / source references (verbatim fragments, abridged)

From `…/out/vs/platform/agentHost/node/agentHostMain.js`:

```
… let l = '…Bearer ${n.nonce}'; if (typeof d!=='string' || d!==l) {
  return kO(t, 401, 'authentication_error', 'Invalid authentication') }
…
tokenEntitlementUrl: 'https://api.github.com/copilot_internal/v2/token'
managedSettingsUrl:  'https://api.github.com/copilot_internal/managed_settings'
mcpRegistryDataUrl:  'https://api.github.com/copilot/mcp_registry'
```

The `Eq()` validator (session-key path) similarly checks `authorization === \`Bearer ${nonce}\``.

## Decision rubric applied here (superseded by the ✅✅ FINAL section below)

| Candidate | Verdict at the time (2026-10-30) | Current status (2026-10-31) |
|---|---|---|
| Extract a portable API key to hand to OmniRoute | "No — nonce non-extractable" | ✅ **YES** — the real upstream is `https://api.individual.githubcopilot.com` accepting the `ghu_` token directly; found via SDK `getEndpoint` RPC (skill step 8) |
| Point OmniRoute at `http://127.0.0.1:42049` | "Only with a valid nonce" | Unnecessary — the local proxy was an internal hop, not the endpoint |
| Use the panel/Claude-Codex extension as the client | **Yes** — that is how it works today | cap: free tier (`free_limited_copilot`) |
| Bypass via a fresh OAuth user token (`gho_…`/`ghp_…`) scoped to `copilot` | Untested | possible if the account has a personal token with the `copilot_api` scope; same free-tier access, portable |

## Live capture (2026-10-31) — what we actually saw on the wire

Objective test: send one panel message while capturing loopback + egress with
tcpdump. See `skills/codespace-service-discovery/references/playbook-copilot-llm-live-capture.md`
for the full notebook (flow table, SNI decode, bytes per destination).

**Verdict, corrected:**

- **The panel's "hi, u there" call did NOT go through the local
  `127.0.0.1:42049` proxy.** Zero packets on the loopback in a 52-second,
  2.3 MB capture. So :42049/ClaudeProxyService is **not** the panel's LLM
  gateway *for this traffic path*. (It exists and is a real Anthropic-speaking
  proxy — from logs + bundle source — but it serves a *different* client,
  most likely the agent-host's built-in Claude Code SDK provider.)
- **The real upstream is GitHub's IAD-region Copilot LB**, reachable by
  hostname:
  - `lb-140-82-112-21-iad.github.com` (28 packets)
  - `lb-140-82-112-22-iad.github.com` (149 packets)
  Both are Azure load-balancer pool domains (`lb-*` = GitHub's in-house LB
  naming; `iad` = Ashburn region) fronting the Copilot LLM service. The
  egress IP is `140.82.112.21/22` inside the pool; the reverse-DNS also
  shows as `<uuid>.internal.cloudapp.net` on some frames (Azure internal
  view).
- **All LLM legs are TLS** — no plaintext HTTP captured on `lo:443`,
  `lo:42049`, `eth0:80`, or `eth0:443`. The auth header + model name
  are inside TLS records and *not* readable from the pcap. The one plaintext
  thing I can say: the SNI at the client_hello tells me the LB pool.
- **A secondary large flow** (1.26 MB to `20.120.56.11:443`, a different
  Azure/GitHub IP) is likely the chat SSE/streaming channel for the response
  stream. Its SNI wasn't surfaced in the grep window; to close that:
  decode the ClientHello of the first packet of that flow via `tshark`
  (not installed; ~1 GB package, deferred for later pass).

**So the "can we reuse it" question — RESOLVED (see below):** the panel's path
has no local endpoint to attach to, but there IS a reusable client — the
preinstalled standalone Copilot CLI.

## **Helper script:** `add-ghcodespace-provider.sh`

Automates finding/verifying all usable LLM models at `https://api.individual.githubcopilot.com`:

- **Discovers models:** GET `/models` with `ghu_` Bearer token, parses IDs
- **Probes models:** 1 real `/chat/completions` call/model (polite delay), keeping `200+content` + transient `429`
- **Wires models:** Creates the `ghcodespace` node (bare host, no `/v1`), connection with `AuthorizationType: Bearer` + the `ghu_` token as `apiKey`, imports the surviving models → appends all to `auto-fastest` (dedup on id, idempotent).

Result: `auto-fastest` gains the working Copilot chat models; full model list + probe rules live in the script (`DRY_RUN=1 add-ghcodespace-provider.sh` previews without mutating).
SSE streaming verified (200). Header-minimality verified: every combo of
`Openai-Intent`, `X-Initiator`, `X-GitHub-Api-Version`, `User-Agent` tested —
**Bearer-only alone is sufficient** (all combos returned identical 200s).

**Free-tier model roster (from `GET /models`):**
- ✅ works standalone: `gpt-4o-mini-2024-07-18`, `gpt-4o-2024-08-06`,
  `gpt-4o-2024-11-20`, `gpt-4.1-2025-04-14`, `text-embedding-3-small`
- ❌ 400 `model_not_supported` on this tier: `gpt-5.6-luna`, `gpt-6-luna`,
  `claude-haiku-4.5` (listed in catalog incl. `free` but server rejects)

**Implication for the objective:** Hermes/OmniRoute can consume Path A with
no CLI, no agent loop, no BYOK shim — just a provider block:
`baseUrl=https://api.individual.githubcopilot.com`, `api=openai-completions`
(path: `/chat/completions`), `apiKey=$GHU`, models as above, wired into the
fallback chain as the last resort.

### (Earlier, still valid) CLI reuse paths — `copilot` v1.0.105

**Path A — reuse GitHub Copilot (the ghu_ token, via the CLI's entitlement flow):**
```bash
export GITHUB_TOKEN=$(cat /proc/$(pgrep -f server-main.js|head -1)/environ | tr '\0' '\n' | grep '^GITHUB_TOKEN=' | cut -d= -f2-)
copilot -p "Reply with exactly: OK" -s --no-auto-update   # -> OK   (AI Credits 0.18)
```
Reproducible (2 separate runs). The CLI is *accepted* with the `ghu_` App token
even though the raw REST `api.github.com/copilot*` paths 404 — different
credential surface. **Tier cap (VERIFIED):** `free_limited_copilot`; only
`--model auto` works (`gpt-5.6-luna`, `gpt-5-luna` rejected), auto-picked
**"GPT-6 Luna"**, credit-metered. Token dies on Codespace rebuild — not a
durable key.

**Path B — BYOK: the Copilot agent on OUR models (the real "proxy to OmniRoute"):**
```bash
COPILOT_PROVIDER_BASE_URL=http://127.0.0.1:20128/v1 COPILOT_PROVIDER_TYPE=openai \
COPILOT_MODEL=auto/best-coding copilot -p "Reply with exactly: OR-OK" -s --no-auto-update   # -> OR-OK
```
Both **OmniRoute (:20128)** and **9Router (:7352, model `auto-fastest`,
`BYOK-OK`)** verified live this session. GitHub auth not required in BYOK mode.
Key: the CLI is the *agent/client*, our local stack is the LLM — a genuine
proxy, with tools/plan/autopilot on top.

**Revised verdict:**
| Goal | Status |
|---|---|
| Reuse GitHub Copilot LLM | ✅ **direct REST: `POST https://api.individual.githubcopilot.com/chat/completions` + Bearer `ghu_`** — free-tier models (gpt-4o family, gpt-4.1), streaming OK. Also via `copilot -p` CLI (any auto model, credit-metered) |
| Proxy to OmniRoute | ✅ BYOK `COPILOT_PROVIDER_BASE_URL=…` runs the Copilot **agent** on our models; alternatively register githubcopilot.com as a fallback provider |
| Stable headless LLM | 9Router/OmniRoute backends (BYOK) are the durable one; GitHub path is the bonus + fallback |

**How we found the direct API (method, for future agents):** SDK `.d.ts` →
`ProviderEndpoint {baseUrl, apiKey, headers, wireApi}`; wire method
`session.provider.getEndpoint` on the session JSON-RPC `connection`; flag
`COPILOT_ALLOW_GET_PROVIDER_ENDPOINT=true`; then path-shape probing
(`/v1/` → 404, `/chat/completions` → 200). Full playbook: skill step 8.

> Helper: `skills/codespace-service-discovery/scripts/copilot-bridge.sh`.

## Next steps (re-ordered after resolution)
1. ✅ **Capture the wire.** Upstream = GitHub IAD LB; local `:42049` NOT in the panel path.
2. ✅ **Reusable client found (`/usr/local/bin/copilot`)** + both paths verified.
3. Wrap into `scripts/copilot-bridge.sh` (done) and add a tiny OmniRoute `provider`
   shim if you want `auto-fastest`/combos to route through the Copilot agent.
- (Optional, low value) name the 1.26 MB `20.120.56.11:443` streaming flow via
   `tshark`/`pyshark` — destination already known (`lb-* -iad.github.com` family).

## Pitfalls recorded

- **Do not trust `ps aux` output** — it truncates and misses the interesting
  env vars. Use `/proc/PID/environ`.
- **`pgrep -f` self-matches** the current shell when the pattern matches the
  command line. Use `pgrep -f -x` on the parent process or `ps -eo pid,comm,args`
  filtered.
- **`strings -a` on a 5 MB JS bundle is slow and noisy.** Use narrow
  `grep -aoE '.{0,N}<needle>.{0,N}'` with bounded windows instead.
- **Do not present inference as verified.** Keep `VERIFIED` / `INFERRED` /
  `UNKNOWN` buckets explicit in any notebook.
- **The free tier is a real cap**, not just a UI concern. Any "reuse" story
  must account for bounded models and rate limits.

## Related artifacts

- **Skill:** `skills/codespace-service-discovery/` — generic method + a reusable `probe-service.sh` and a worked reference (`references/playbook-copilot-llm.md`).
- **Precedent for the same discipline on auth:** `skills/codespace-gh-auth/` + `wiki/codespace-gh-auth.md` (ghu_ extraction, GitHub App scope, git-credential-store workaround).
- **Related proposal:** `docs/PROPOSAL-github-token-export.md` (durable ghu_ export via `boot.sh` — DRAFT, not implemented).
