---
title: "GitHub Copilot Sidebar MITM — Findings & Dead-End Report"
type: article
status: reference
last-updated: 2026-11-01
author: hermes
tags: [copilot, mitm, github, codespace, mai, auto, entitlement]
related:
  - codespace-copilot-llm.md
  - codespace-gh-auth.md
  - codespace-playbook.md
---

**Last updated:** 2026-11-01 (auto-resolution + MAI-variant sweep + script-fit review)

## TL;DR

- **MITM proven end-to-end.** TLS terminated on `127.0.0.1:443`, real GitHub
  responses captured with full request + response text, all three lanes.
- **`auto` resolves to MAI for this account.** Two independent proofs:
  GitHub's A/B header on every `auto` request
  (`x-copilot-api-exp-assignment-context: …autov2_mai_prod_ci815668…`) and
  81/81 probes across 3 lanes × 27 integration ids returning
  `400 model_not_supported`.
- **MAI-Code-1.1-Flash is not reachable from this Codespace PAT** on any
  lane, any integration id, any variant (`1.1-flash`, `1-flash-4th`,
  `1-flash-secondary`, `1-flash-tertiary`). Catalog shows
  `policy.state=enabled`, but every probe returns `model_not_supported`.
  Server-side entitlement gate tied to the sidebar's OAuth session, not
  the `ghu_` codespace PAT.
- **`gpt-4o`, `gpt-4o-mini`, `gpt-4.1` work** — real 200 with content on
  `/chat/completions`. The free-tier workhorses.
- **Do NOT register `auto` as a `ghcodespace` model.** It's a router alias,
  not a model id, and it 100% fails on this account. Registering it would
  rot the `auto-fastest` fallback tier.

## Architecture (verified)

```
Codespace sidebar (webview)
   │  webview ⇢ agentHost ⇢ copilot-runtime (Rust, headless)
   │  base URL compiled in; OS cert store NOT used by this client
   ▼
api.githubcopilot.com / api.individual.githubcopilot.com
   (GitHub IAD LB pool 140.82.112.21/22 glb-db52c2cf8be544.github.com)
   │
   ├─ GET  /models?api=chat          → 47-model account catalog
   ├─ POST /chat/completions         → OpenAI-shape (GPT family works)
   ├─ POST /v1/messages              → Anthropic-shape
   └─ POST /responses (+ ws:)       → OpenAI-shape (MAI cataloged here)
```

## Error-code dictionary (empirical)

| HTTP | Code / text | Meaning |
|---|---|---|
| 400 | `{code:"model_not_supported", param:"model"}` | Dispatch table has no lane for this model+account |
| 400 | `"no model endpoints available given user constraints"` | Model recognized, zero allocation for this account |
| 400 | `model_not_available_for_integrator` | Model exists; gated for this `Copilot-Integration-Id` |
| 404 | `page not found` (on `/meta`) | `/meta` resolver not exposed for `ghu_` scope |
| 200 | non-empty `content` in body | Real assistant reply |

## Catalog (47 models, this PAT, 2026-11-01)

`GET https://api.githubcopilot.com/models?api=chat` with
`Bearer ghu_…` + `Copilot-Integration-Id: vscode-chat`.

| Policy | Model id(s) | Endpoint(s) |
|---|---|---|
| enabled | `mai-code-1.1-flash` | `/responses`, `ws:/responses` |
| enabled | `mai-code-1-flash-{4th,secondary,tertiary}` | `/chat/completions`, `/responses` |
| enabled | `gpt-4.1`, `gpt-4o-mini-2024-07-18`, `gpt-4o-2024-11-20`, `gpt-4o-2024-08-06`, `gpt-4.1-2025-04-14` | `/chat/completions` |
| enabled | `claude-haiku-4.5` | `/v1/messages` |
| enabled | `kimi-k3-base`, `kimi-k3-copilot` | `/chat/completions` |
| disabled | `claude-fable-5{,.1}`, `claude-{opus,sonnet,haiku}-5*` | — |
| disabled | `gpt-5.4-nano`, `gpt-5.6-{sol,terra}`, `gpt-6-*` | — |
| disabled | `gemini-{3.8-flash,4-argon}` | — |

**`policy.state=enabled` ≠ entitlement.** The dispatch table is the real
gate. `enabled` + 400 is the classic free-tier Codespace state.

## Probes and verdicts (2026-11-01)

### `auto` resolution — conclusive

Probes: `auto` × 3 lanes × 27 integration ids = 81 requests, all `ghu_`.
- All 81: `400 model_not_supported`.
- All responses carry `x-copilot-api-exp-assignment-context: …autov2_mai_prod_ci815668…`
  — GitHub's A/B is assigning this account to the MAI-Prod cell.
- `GET /meta` → `404 page not found`.

**Verdict:** `auto` → MAI for this bucket. MAI not dispatchable on the
`ghu_` PAT. No client-side path (integration id, lane, WS) flips it.

### MAI variants — conclusive

| Model id | Lane | Verdict |
|---|---|---|
| `mai-code-1.1-flash` | `/responses`, `/chat/completions` | 400 `model_not_supported` |
| `mai-code-1-flash-4th` | both | 400 `model_not_supported` |
| `mai-code-1-flash-secondary` | both | 400 `model_not_supported` |
| `mai-code-1-flash-tertiary` | both | 400 `model_not_supported` |

Controls (sanity):
- `gpt-4o` on `/chat/completions` → 200 OK with content
- `gpt-4.1` on `/chat/completions` → 200 OK with content
- `claude-haiku-4.5` on `/v1/messages` → 200 OK with content

### Working request (proven)

```http
POST https://api.githubcopilot.com/chat/completions
Authorization: Bearer ghu_…
Copilot-Integration-Id: vscode-chat
Content-Type: application/json

{"model":"gpt-4.1","messages":[{"role":"user","content":"hi"}],
 "max_tokens":64,"stream":false}
→ 200 (~921ms) {"choices":[{"finish_reason":"length",
   "message":{"content":"Pong! How can I assist you…"}}]}
```

### `copilot` CLI

With `SSL_CERT_FILE=<our CA>`:
- TLS handshake through MITM succeeded.
- `GET /models` returned `200 OK` from GitHub (server `iad`).
- Then `copilot` exited with `Cannot invoke native session after
  disposal` — refuses to drive a completion over a bare `ghu_` PAT.
  Same entitlement gate, just in the client.

## What does NOT work (and why)

1. **OS-store CA injection against the sidebar.** `copilot-runtime`
   (Rust, headless) bundles webpki roots and does not read
   `/etc/ssl/certs` despite OpenSSL-shaped error strings. Even with the c_rehash symlink
   present, this client will not use it.
2. **`auto` as a provider model.** Resolves to MAI for this account.
   MAI is a hard 400 here. Registering would be a 100%-fail entry
   that rots `auto-fastest`.
3. **Any MAI variant via `ghu_` PAT.** 8/8 failures.
4. **Capturing the sidebar's real Copilot OAuth bearer.** The client
   is the wall, not the server. Not worth further pursuit on this
   account.

## MITM restart / revert (playbook)

### Restart

```bash
# 1. hosts (backup first if missing)
sudo -n bash -c '
  grep -vE "^\s*127\.0\.0\.1\s+api\.githubcopilot\.com" /etc/hosts |
    grep -vE "^\s*127\.0\.0\.1\s+api\.individual\.githubcopilot\.com" > /tmp/hosts.new
  echo "127.0.0.1 api.githubcopilot.com"      >> /tmp/hosts.new
  echo "127.0.0.1 api.individual.githubcopilot.com" >> /tmp/hosts.new
  [[ -f /etc/hosts.bak-cx ]] || cp /etc/hosts /etc/hosts.bak-cx
  cp /tmp/hosts.new /etc/hosts'

# 2. CA (only if not already installed + hashed)
sudo -n cp /tmp/cx/ca.crt /etc/ssl/certs/minions-mitm-ca.crt
sudo -n c_rehash /etc/ssl/certs

# 3. Start
sudo -n python3 -u /home/codespace/.hermes/cache/scratch/cx/mitm.py &

# 4. Verify
ss -tlnp | grep -E ':443\s'
getent hosts api.githubcopilot.com   # 127.0.0.1
```

### Revert

```bash
pid=$(sudo -n ss -tlnp | grep ':443' | sed -nE "s/.*pid=([0-9]+).*/\1/p")
[ -n "$pid" ] && sudo -n kill "$pid"
sudo -n cp /etc/hosts.bak-cx /etc/hosts
sudo -n rm /etc/ssl/certs/minions-mitm-ca.crt
sudo -n c_rehash /etc/ssl/certs
getent hosts api.githubcopilot.com   # real GH IP
timeout 15 curl -sS -o /dev/null -w "HTTP %{http_code} via %{remote_ip}\n" \
  "https://api.individual.githubcopilot.com/models?api=chat"
```

### Pitfalls (learned this session)

- Auth is `Bearer ghu_…`, not `token ghu_…`.
- `Copilot-Integration-Id` is required for dispatch. Common values:
  `vscode-chat`, `copilot-developer-cli`, `opencode`, `hermes-agent`,
  `openclaw`, `agentic-workflows`, `litellm`, `clawde-agent`.
- `pkill -f 'mitm.py'` matches our own shell command line — kill by
  socket instead.
- Hermes context compressor mangles long inline payloads: write probe
  scripts to files, execute via short `terminal` commands.
- `dict.min(...)` doesn't exist in Python 3 stdlib — use explicit
  min/max.
- MITM response-write bug (fixed in scratch copy): send the status
  line, the headers, then a blank line, before the body. For chunked or
  keep-alive responses use a recv idle timeout (~2s) rather than blocking
  on upstream EOF.

## Related scripts

- `skills/minions-llm-proxy-ops/scripts/add-ghcodespace-provider.sh`
  — registers the provider in OmniRoute and probes every model via
  `/chat/completions`. **The existing script is already correct for
  the findings above**: it will (a) see `auto` is not in the roster
  (47 models, no `auto` id), (b) DROP all MAI variants via the existing
  400 classification, (c) KEEP the working gpt-4o family via the
  200-with-content rule, (d) append the survivors to `auto-fastest`. No
  code change needed to encode today's findings.
  - Optional future polish (not required for the finding to be encoded):
    add `Copilot-Integration-Id: vscode-chat` to probe headers and a
    `/responses` probe, so the log distinguishes "wrong lane" from
    "no entitlement". Today's probes confirm both return the same
    verdict, so it is a diagnostic-quality improvement only.
- Probe archives (this session, `/tmp/cx/`): `autoresolve.py`,
  `autoiid.py`, `mai-variants.py`, `modelsweep.py`, `idsweep.py`,
  `catchg.py`, `catalog-api.json`.

## See also

- [codespace-copilot-llm.md](codespace-copilot-llm.md) — how the
  sidebar reaches GitHub's LLM backend; endpoint discovery method.
- [codespace-gh-auth.md](codespace-gh-auth.md) — extracting the
  `ghu_` token from the VS Code server process env.
- [codespace-playbook.md](codespace-playbook.md) — general Codespace ops.