---
name: codespace-service-discovery
description: "Use when asked to find out HOW a service inside this Codespace reaches its backend — how an in-house LLM/copilot provider is called, where a token/endpoint lives, or whether an endpoint can be reused/proxied — by inspecting processes, /proc env, ports, logs, and bundled code, then probing live."
version: 0.1.0
tags: [codespace, discovery, llm, copilot, processes, /proc, endpoints]
related_skills:
  - codespace-gh-auth
  - minions-llm-proxy-ops
---

# Codespace Service Discovery

Goal: given a question like *"how does X here call its LLM/provider backend, and can we reuse or proxy it"*, produce an **evidence-backed** answer — not a guess. Apply this method whenever you must reverse-engineer *how* a runtime component reaches an external service (LLM, API, token issuance), or locate a credential/endpoint/URL that isn't in the shell env.

The single rule that makes or breaks this: **separate what you verified by real output this session from what you inferred.** Report them in two buckets, always. Inference is fine and expected — but label it, and name the one experiment that would turn it into fact.

## The 8-step method

Work top-to-bottom. Each step's output feeds the next. Batch independent steps into one terminal call.

### 1. Frame the question (10 seconds, do it before any cmd)
Write out: (a) the target behavior (which feature/process am I hunting), (b) what "reusable" concretely means (a portable key? a URL I can curl? a client I can point at?), (c) what success looks like. If (b) is ambiguous it usually has two answers — "extractable token" vs "a live proxy I can attach to" — and those need different evidence. Name both.

### 2. Find the process family
Identify candidate processes and their roles. Never assume — read real output.

```bash
# Broad: anything LLM/provider/vendor related
ps aux | grep -iE "copilot|llm|anthropic|claude|codex|openai|extension-host|server-main|runtime" | grep -v grep

# Enumerate ALL pids and dump cmdline (survives truncated ps)
for pid in $(ls /proc/*/cmdline 2>/dev/null | cut -d/ -f3); do
  cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
  echo "PID=$pid COMM=$(cat /proc/$pid/comm 2>/dev/null) :: $cmd"
done

# Role hints from comm: copilot-runtime / node / MainThread / extensionHost
```
Build the **PID map** first: launcher (`sh ... code-server`), server (`server-main.js`), extension host (`node .../extension.js`), agent host (`bootstrap-fork --type=agentHost`), native runtime (`copilot-runtime`). Knowing which PID hosts which job tells you whose env/logs/binary to read.

### 3. Read `/proc/PID/environ` for credentials & URLs
The shell does NOT inherit the process's env. This is where live tokens, base URLs, feature flags, provider names, and model names hide.

```bash
PID=<pid>
grep -iE "token|key|secret|copilot|anthropic|claude|openai|model|provider|base_url|endpoint|proxy|auth|bearer|license|plan|tier" \
  /proc/$PID/environ 2>/dev/null | tr '\0' '\n' | sort

# When grep is too aggressive, dump full env to a file and grep it interactively
cat /proc/$PID/environ | tr '\0' '\n' > /tmp/env_$PID.txt
grep -inE "proxy|auth|key|base_url|header|anthropic|claude|model|api|127\.0\.0\.1|port" /tmp/env_$PID.txt
```
Read the *negative* evidence too: `ANTHROPIC_ADVISOR=false`, no `ANTHROPIC_BASE_URL`, no `OPENAI_API_KEY` → the provider is **not** keyed by a classic API key. That's a real finding, not a gap.

### 4. Map ports to PIDs
```bash
ss -tlnp        # listening sockets -> owning PID; correlate to the PID map
ss -tnp         # established connections (which remote host each pid talks to)
```
A local `LISTEN` that a chat/agent feature depends on is usually the LLM proxy. Note the exact `127.0.0.1:PORT` — that's the thing to probe in step 7.

### 5. Read the logs (fastest path to the *real* endpoint)
Bundled runtimes and VS Code write rich logs. Log content beats `strings` because it is the *actual* behavior.
```bash
# Find log roots
find /proc/<pid>/fd -lname '*log*' 2>/dev/null      # which files this pid has open
find ~ -maxdepth 4 \( -name '*.log' -o -path '*/logs/*' \) 2>/dev/null | xargs ls -lad | grep -vE '\.git'

# Pull endpoint/auth/model signal from them
LOG=<path>; grep -aoiE "https?://[a-z0-9./_?=-]+|listening on http[^ ]*|/v[0-9]+/[a-z_]+|model[\"':=][a-z0-9._-]*|nonce|token" "$LOG" | sort | uniq -c | sort -rn | head -40
```
"listening on http://127.0.0.1:PORT" is a proxy. A provider/model name in the log tells you which model is active.

### 6. Read the bundled code (definitive for *logic*: auth rules, upstream URL)
Native binaries: `strings -a <bin> | grep -iE "https?://|baseURL|endpoint|nonce|/v1/"`. Bundled JS (VS Code `out/`, extension `*.js`): minified, so grep with context windows, not plain `grep -w`.
```bash
F=<bundle.js>
grep -aoE '.{0,160}<needle>.{0,200}' "$F" | head        # context window around a word
grep -aoE 'https://[a-z0-9.-]+/[a-zA-Z0-9/_.-]*<ns>[a-zA-Z0-9/_.-]*' "$F" | sort -u   # real URLs
grep -aoE '"/v[0-9]+/[a-z_]+"' "$F" | sort -u           # routes
```
`<needle>` examples: the service name from step 5 (e.g. `ClaudeProxyService`, `nonce`, `Invalid authentication`), `Bearer`, `x-api-key`. The line that **validates** the request shows exactly what auth is required. The line that **forwards** it shows the upstream.

> Pitfall: `strings -a` on a large JS bundle can be slow/empty for the URLs you want — JS constants live as string literals, so use `grep -aoF '<url-fragment>'` (count) to confirm presence, then the context-window form to extract.

### 7. Probe live, and read what each status *means* (with the right path shape)
Test the endpoint with whatever token you have. Interpret:
- `200` + data → works, token valid.
- `401 Invalid authentication` → the gate is a *different* credential (a nonce, an SSO token, a per-session key) than the one you passed. This is the most common finding and is itself the answer — it proves the endpoint is **gated, not open**.
- `404` → the path exists in code but is not exposed over this auth surface (needs an internal SSO/OAuth service), or the URL is wrong.
- `400` + `model_not_supported` / `no_available_model_endpoints` → **the endpoint is fine, the token is fine, the model is not for this tier.** Not a gate — the model list is what to test from.
- `404 page not found` on the *obvious* path (e.g. `/v1/chat/completions`) → **try the path without the `/v1`** (`/chat/completions`). Vendor LLM endpoints often drop the OpenAI-style `/v1` prefix. A 404 on the obvious shape is *usually* a path mismatch, not an auth block. Probe 2–3 variants (`/v1/…`, `/…`, `/api/…`) before concluding "not the public path."
- `405 Method Not Allowed` → the *verb* is wrong; `GET /models` may need `POST`.
- Vendor errors that name a feature flag (e.g. *"To enable this API, set `COPILOT_ALLOW_GET_PROVIDER_ENDPOINT=true`"*) are **flags, not walls** — set the env var on the spawned child, retry, and the method becomes callable.

```bash
B=https://… # or http://127.0.0.1:PORT
# try path variants, not just one
for p in /v1/chat/completions /chat/completions /chat /completions /v1/completions; do
  printf '%s ' "$p"
  curl -s -m 5 -X POST "$B$p" -H "Authorization: Bearer $TOK" \
       -H 'content-type: application/json' \
       -d '{"model":"gpt-4o-mini","max_tokens":8,"stream":false,"messages":[{"role":"user","content":"ping"}]}' \
       | head -c 100
  echo
done
```
The **error envelope shape** identifies the protocol: `{"type":"error","error":{"type":"authentication_error"...}}` = Anthropic; `{"message":"Not Found","documentation_url":"…"}` = GitHub REST. Knowing the wire protocol half-answers "can OmniRoute/9Router attach to it."

### 8. (The step that ends most dead-ends) Reverse-engineer the SDK's wire protocol

Steps 5–7 can leave you at "gated local proxy + a client that obviously works (the panel/CLI/agent)". When that happens, **the working client is a better oracle than the proxy**: it already holds every credential, path, and header. Most vendor SDKs ship TypeScript `.d.ts` typings next to the minified bundle, and those typings are a map of the RPC surface.

```bash
SDK=node_modules/@github/copilot-sdk-linux-x64/copilot-sdk
# (a) experimental/hidden RPC methods
grep -rnoE "@experimental|getEndpoint|get[A-Z][A-Za-z]+Request" "$SDK"/*.d.ts "$SDK"/generated/*.d.ts | sort -u | head -40
# (b) the WIRE method names — what the client actually sends over the transport
grep -oE 'sendRequest\("[a-zA-Z/_.]+"' "$SDK/index.js" | sort -u
# (c) response shapes (baseUrl/apiKey/headers/sessionToken fields live here)
grep -n "ProviderEndpoint\b" "$SDK"/generated/*.d.ts | head
```

Then drive the SDK from Node. **The session's `.connection` object is the wire** — a JSON-RPC `MessageConnection` — so any wire method from (b) is callable:

```js
import { CopilotClient } from '/abs/path/copilot-sdk/index.js';
const c = new CopilotClient(); await c.start();                    // auth from GITHUB_TOKEN env
const s = await c.createSession({ name: 'probe' });
const ep = await s.connection.sendRequest('session.provider.getEndpoint',
                                          { sessionId: s.sessionId });
// => { baseUrl, apiKey, headers, wireApi }  ← the FULL upstream contract, no packet capture
```

Rules learned the hard way:
1. **Feature-flag errors are flags, not walls.** "To enable this API, set `X_ALLOW_Y=true`" → put the var in the *client process* env (the one spawning the runtime), retry, done.
2. **`wireApi: completions` does NOT mean `/v1/chat/completions`.** In the Copilot case the server 404s every `/v1/...` path and serves `/chat/completions` (no `v1`). Always probe 2–3 path shapes after you get `baseUrl`.
3. **`400 model_not_supported` is a tier constraint, not a gate.** The endpoint, token, and path are all correct — pull the model catalog and test the free-eligible entries (Copilot: `gpt-4o-mini`, `gpt-4o`, `gpt-4.1`, `text-embedding-3-small` work standalone; `gpt-*-luna`, claude models 400).
4. **Minimality check is the last probe:** once you have one working call, strip headers until it breaks. Copilot needed *zero* extra headers — bare `Bearer <ghu_>` + `/chat/completions` returns 200. That's the difference between "needs the SDK" and "registerable in 6 lines of proxy config."
5. Introspection shortcuts when typings hide the surface: `Object.getOwnPropertyNames(s)` on the session, `Object.getOwnPropertyNames(c._rpc)`, etc. Symbols and private fields show up there.

## Decision rubric: "can we reuse / proxy this?"
| You find | Reuse verdict |
|---|---|
| A real API key/token in env that returns `200` + data | **Reusable** as a portable credential. |
| A token that authenticates metadata (`/user`) but **not** the LLM path | Metadata reusable; LLM path is **gated separately**. |
| A local proxy that requires a per-session nonce / SSO upstream | The **proxy** is not reusable standalone — but run step 8: the SDK often has a `getEndpoint`-style RPC that returns the real upstream `baseUrl`+`apiKey`. In the Copilot case that upstream was a plain OpenAI-style REST API callable with Bearer auth alone. Solve for the upstream before declaring "not extractable". |
| `404` everywhere with the available token | Two different causes: (a) wrong path shape — probe `/v1/...` vs `...` vs `/api/...` variants; (b) genuinely an internal OAuth/SSO surface — only then is it **not extractable**. |

Free/limited tier is a real constraint to surface: `access_type_sku: free_limited_copilot`, `copilot_plan: individual` mean bounded models + rate limits even in the happy path.

## Close the loop (turn inference into fact)
When the upstream domain / real token is still "inferred", offer the user the one experiment that proves it: `strace -p <runtime>,<host> -e trace=network` or `tcpdump -i lo port <PORT>` while a real request fires (e.g. user types one message in the panel). That reveals the true backend + auth flow.

## Pitfalls (learned)
- **Shell env ≠ process env.** Tokens for these services are almost always in the *server/runtime* process, not the interactive shell. Check `/proc/PID/environ`.
- **Truncated output hides the answer.** `ps aux` and `cat /proc/PID/environ` truncate in tool output. Dump to a file, then grep the file.
- **"Nonce-gated local proxy" is usually not the endpoint.** The proxy is an internal hop; the SDK's `getEndpoint`-style RPC (step 8) reveals the real upstream, which in the Copilot case was a plain public REST API taking Bearer auth. Solve for the upstream before declaring "not extractable".
- **`404` and `400` are different news.** `404` = wrong path/method (try the other path shapes first); `400 model_not_supported` = path+token+auth all correct, model just not entitled for this tier. Never report `400 model_not_supported` as "gated/404" — it's a model-tier finding.
- **`wireApi: completions` ≠ OpenAI `/v1/...`.** Copilot's `api.individual.githubcopilot.com` serves `/chat/completions` (no `v1`); every `/v1/...` variant 404s. Probe 2–3 path shapes before concluding.
- **Vendor feature-flag errors are flags, not walls.** "set `X_ALLOW_Y=true`" → set the env var on the client process and retry.
- **Metadata vs LLM auth are different gates.** A token that reads `/user` (plan/access) needs separate testing against the completion endpoint — though here the *same* `ghu_` token opened the LLM path.
- **GitHub App token (`ghu_`) is scope-limited** to Codespace-installed repos and returns "Bad credentials" on raw REST (`/user`, push works) — but it *is* a valid Copilot LLM credential via the Copilot endpoint. Don't let the REST rejection make you skip the LLM surface. See `codespace-gh-auth`.
- **Report buckets honestly.** "Verified this session" vs "inferred (strong)" vs "the one experiment that would confirm it." Never present inference as tested.

## Reference
- `references/playbook-copilot-llm.md` — the worked example (finding the GitHub Copilot LLM path in a 2026-10 Codespace + what each step returned), plus the concrete verdict.
- `scripts/probe-service.sh` — generic env+port+log+endpoint dumper for a given PID set.
- `scripts/copilot-bridge.sh` — drives the standalone Copilot CLI as a scriptable LLM/agent: `github` backend (free-tier token) or `byok` backend (local OpenAI-compatible provider URL).
