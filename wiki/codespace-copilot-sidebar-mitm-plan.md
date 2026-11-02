---
title: "Copilot Sidebar Chat MITM — Plan (Option A)"
type: article
status: archived
superseded-by: codespace-copilot-mitm-handoff.md
last-updated: 2026-11-01
author: hermes
tags: [copilot, mitm, github, codespace, plan]
related:
  - codespace-copilot-mitm-handoff.md
  - codespace-copilot-llm.md
---

**Goal:** intercept the Codespace sidebar Copilot chat wire traffic (TLS + WebSocket)
from inside the container, capture the exact requests GitHub's front-door receives —
headers, model names, entitlement context — and determine how `Auto` routes
(MAI-Code-1.1-Flash vs gpt-4o) on this account.

## Topology (observed via ps/ss)

```
6152 sh code-server launch
 └─ 6161 node server-main.js            ← VS Code server in-container
     ├─ 6191 extensionHost              ← copilot extension JS (webview bridge)
     ├─ 6232 agentHost  (127.0.0.1:40175)
     │   └─ 6374 copilot-runtime --headless   ← OWNS the egress socket
     └─ 6233 fileWatcher
```

- `ss -tnp`: `10.0.x.x:*** → 140.82.112.2x:443 users:"copilot-runtime",pid=6374`
- Sidebar chat = webview ⇢ agentHost ⇢ copilot-runtime ⇢ **direct TLS** to
  `api.individual.githubcopilot.com` / `api.githubcopilot.com` (GitHub IAD LB
  pool `140.82.112.21/22`). No local proxy in the path (prior pcap: zero 127.0.0.1
  packets from the panel).
- Transport mix: `gpt-4o*` → HTTP chat completions; MAI / gpt-6-astra →
  **WebSocket** `ws(s):/responses` (per `supported_endpoints` in extension.js).
  So the interceptor MUST handle WebSocket upgrades, not just HTTP.

## Method (Option A): DNS redirect + local TLS terminator

1. **Resolve real upstream IPs first** (`getent hosts` / DNS) and save to a
   map file. Then rewrite `/etc/hosts`:
   - `api.individual.githubcopilot.com → 127.0.0.1`
   - `api.githubcopilot.com → 127.0.0.1`
   (backup original file first; restore at end)
2. **TLS-terminating relay on 127.0.0.1:443** (Python stdlib `ssl` + threads):
   - server-side: present a leaf cert (SAN = the API hostnames) signed by our CA
   - client-side: dial the real IP (from map file) for the Host header,
     SNI set to the original host, forward decrypted bytes
   - **log everything**: req line, headers (redact Bearer/nonce values to
     first 8 chars + `…`), body (cap ~64 KB), response status + body
   - **WebSocket-aware**: on `101 Switching Protocols`, enter raw-bidirectional
     relay, tee both frame streams to a hex log (frame decode after the fact)
   - handles SSE streaming responses (plain byte copy both directions)
3. **Node CA trust ladder** (pick the first that works, in order):
   a. If the bundled `node` links **dynamic system libssl** (`ldd node | grep ssl`):
      drop our CA into `/etc/ssl/certs/` + `c_rehash` → trusted with **no env
      change and no process restart**. (Best case: zero disruption.)
   b. If `/proc/<pid>/environ` already carries `SSL_CERT_FILE` pointing at an
      editable file: append our CA to that file.
   c. `LD_PRELOAD` shim (C constructor `putenv("NODE_EXTRA_CA_CERTS=…")`) +
      kill `copilot-runtime`; agentHost respawns it. Works **only if** the
      respawner's env carries the shim — verify, don't assume.
   d. Last resort: restart the VS Code server tree (kills the user's editor
      session — only with explicit OK).
4. **Probes through the interceptor:**
   - `copilot` CLI (Path A token `ghu_`, extracted from `/proc/6374/environ`):
     `-p "…" --model auto` and `--model mai-code-1.1-flash` → capture the
     full real wire: auth headers, model field, entitlement responses.
   - Ask user to send one sidebar message in `Auto` → capture the
     **extension-minted** version (Integration-Id, Traversal, Request-Id headers)
     — that's the delta that decides whether the sidebar channel itself
     unlocks MAI.
5. **Rubbish-in check:** verify a known-good call (gpt-4o) still completes
   end-to-end through the MITM, so we're logging success not just failures.

## Deliverable

- `caps/<timestamp>/*.log` — every request/response body, redacted
- WS frame log decoded to the `{"type":…}` protocol frames
- Verdict: exact endpoint + model + headers GitHub receives for sidebar
  `Auto`, and whether MAI is granted on the sidebar channel

## Risks & rollback

| Risk | Mitigation |
|---|---|
| Sidebar broken during test | restore `/etc/hosts.bak`, kill mitm → instant recovery |
| Bearer tokens leaked into logs | values truncated to 8 chars at write time; scrub before sharing |
| Node not trusting CA (static bundle) | ladder (b)→(c)→(d); every rung testable without user involvement except (d) |
| WS relay drops framing | pure byte-relay after 101; decode offline |

## Exit criteria

- [ ] gpt-4o completion succeeds THROUGH the MITM (log shows 200 + body)
- [ ] MAI request captured with full headers + exact rejection payload
- [ ] WS frame capture decoded (if Auto takes the WS path)
- [ ] /etc/hosts restored, mitm stopped, logs redacted
- [ ] verdict section filled in below

## Verdict (fill after capture)

_TBD_
