# Worked example — GitHub Copilot LLM path in a GitHub Codespace

Date: 2026-10-30. Objective: *"How does this Codespace's chat panel call GitHub's LLM
provider — can we reuse that token, or proxy it into OmniRoute?"*

Everything below is either **VERIFIED** (real exit code / body captured this session) or
marked **INFERRED** (strong, from source) with the confirming experiment named.

## PID map (step 2) — the Copilot family

| PID | Role | Evidence |
|-----|------|----------|
| 1361 | launcher `sh code-server --install-extension anthropic.claude-code` | cmdline |
| 1370 | VS Code server `server-main.js` | cmdline |
| 1399 | Node extension host `--dns-result-order=ipv4first` | cmdline |
| 1413 | `bootstrap-fork --type=agentHost` — the **agent host**, also hosts proxy :42049 | cmdline + `ss -tlnp` |
| 2238 | `@github/copilot-sdk-linux-x64/copilot-runtime --headless --no-auto-update --stdio --no-auto-login` | cmdline |

## Environment (step 3)

copilot-runtime (2238) carries:
- `GITHUB_TOKEN=ghu_…` (40 chars, GitHub App user-to-server token)
- `GITHUB_COPILOT_INTEGRATION_ID=vscode-chat`
- `COPILOT_EXP_COPilot_CLI_EXECUTION_SUBAGENT_MODEL=gpt-5.6-luna` (model name leaks)
- `ANTHROPIC_ADVISOR=false`, `COPILOT_OTEL_EXPORTER_TYPE=otlp-http`
- COPILOT **has no** `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` / `OPENAI_API_KEY` → not a classic-key provider (VERIFIED: absent from 100-line env dump).

## Ports (step 4)
`ss -tlnp` → `127.0.0.1:42049` owned by **PID 1413** (agent host). (VERIFIED)

## Logs (step 5)
`agenthost.log`: `[ClaudeProxyService] listening on http://127.0.0.1:42049` (VERIFIED from log).
`copilot/logs/*.log`: policy fetch `https://github.com`, version `1.0.105`, one-way host RPC `lifecycle_server_shutdown_finalize` (context only).

## Bundled source (step 6) — the decisive evidence
File: `…/out/vs/platform/agentHost/node/agentHostMain.js` (~5.0 MB).
- Service identity: `ClaudeProxyService`; provider set `new Set(["anthropic"])`; routes
  `/v1/messages`, `/v1/models`, `/v1/messages/count_tokens`, `/v1/responses`, plus
  `"openai"` providers with `wireApi:"responses"` and `wireApi:"completions"` (INFERRED-protocol, VERIFIED-strings).
- **Nonce gate (the answer):** request handler builds `l=`Bearer ${n.nonce}`` and rejects
  with `401 authentication_error / "Invalid authentication"` unless `e.headers.authorization === l`.
  `nonce` is generated per-session via `crypto.getRandomValues(new Uint8Array(16))` and returned
  to the SDK client over the JSON-RPC/stdio channel — **not** readable from the shell. (VERIFIED-source)
- Upstream hint: `tokenEntitlementUrl:"https://api.github.com/copilot_internal/v2/token"`,
  `managedSettingsUrl:"…/copilot_internal/managed_settings"`, `mcpRegistryDataUrl:"…/copilot/mcp_registry"`
  — the proxy mints an entitlement token against GitHub and forwards the Anthropic/OpenAI body
  to the Copilot backend. (VERIFIED-source; forwarding target behind `_continuationScope`/`_handleResponses`, not fully read)

## Live probes (step 7) — what each returned
| Call | Result (VERIFIED) | Meaning |
|------|-------------------|---------|
| `GET :42049/` | `ok` (200) | liveness + proxy present |
| `GET :42049/v1/models` (no auth / ghu_ / x-api-key / query / Bearer+integrations) | `401 …authentication_error "Invalid authentication"` | gate is the nonce, not the ghu_ token |
| `POST :42049/v1/messages` (all token variants) | `401` same | LLM path nonce-gated |
| `GET api.github.com/copilot_internal/user` (ghu_) | **200** account JSON | ghu_ IS a valid Copilot credential |
| `…/copilot_internal/v2/token`, `/v2/completions`, `/v2/chat/completions`, `/v1/messages` (ghu_) | **404** GitHub REST | LLM/completion endpoints require the internal SSO/OAuth surface, not the ghu_ token |
| `GET /copilot/models`, `/copilot/chat/completions`, `/copilot/responses` (ghu_) | **404** | not the public path |

## Live capture correction (2026-10-31)

**See `playbook-copilot-llm-live-capture.md` for the full notebook.**

Short version: the panel's "hi, u there" call did **not** route through the
local `:42049` proxy — **zero** loopback packets in the pcap. It spoke
directly to GitHub's IAD Copilot LB front (`lb-140-82-112-2{i}
iad.github.com`, i=1,2). So :42049/ClaudeProxyService is a *separate*
provider for the agent-host's built-in Claude Code SDK — not the chat
panel's backend. All LLM traffic is end-to-end TLS; the Bearer nonce /
model name are not visible from the pcap (SNI + IP only).

The "reuse it" story is therefore:
- For the chat panel path: **no local endpoint to attach to**; needs a real
  Copilot credential (only mintable by a legitimate Copilot-SDK client).
- For a portable OmniRoute backend on the free tier: **`gh copilot` (or a
  similar SDK client)** is the credential holder; that is the only viable
  adapter path.

## Verdict (per the decision rubric)
- **No portable reusable LLM token exists.** The usable credential (`ghu_`) authenticates
  metadata (`/user`) but is rejected by every LLM surface tested. The LLM path is
  **nonce-gated + SSO-OAuth upstream**.
- **Proxy to OmniRoute by raw HTTP: no** — a valid per-session nonce is required, and only an
  in-process Copilot-SDK client can mint it.
- **Reuse as a client: yes** — that's how the panel already works. A legitimate SDK client
  (Claude Code / the chat host / `gh copilot`) acquires the nonce; OmniRoute could attach to
  :42049 as an `anthropic` backend *if handed* a valid nonce, and would still be capped to the
  **free limited tier** (`access_type_sku: free_limited_copilot`, `copilot_plan: individual`, VERIFIED).

## The one experiment that would turn the last piece into fact
`strace -p 2238,1413 -e trace=network` (or `tcpdump -i lo port 42049`) while the user sends one
message in the panel → reveals the real upstream domain and the exact auth header the proxy sends.

## Reuse this notebook as a template
Same 7 steps, swap the target. The invariant: find the process that HOSTS the feature, read its
env + its listening port + its bundle, then probe — and bucket every claim as verified vs inferred.
