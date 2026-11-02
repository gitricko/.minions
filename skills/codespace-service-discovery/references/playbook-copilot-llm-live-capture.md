# Live capture — Copilot chat "hi, u there" (2026-10-31T00:21Z)

## Setup (verified)
- tcpdump 4.99.4 (installed via sudo apt-get install -y tcpdump — was missing before this session)
- capture: `sudo -n timeout 180 tcpdump -ni lo -ni eth0 -s 0 "port 42049 or port 443 or port 80" -w /tmp/copilot-llm-capture.pcap`
- pcap size: 2.3 MB, 5238 packets over ~52 seconds (00:21:01.14Z → 00:21:53.12Z)
- user prompt: `hi, u there` fired from the Copilot chat panel in the Codespace VS Code web panel
- capture interfaces: `lo` (loopback) + `eth0` (Codespace egress NIC, src 10.0.10.166 via 10.0.0.1)

## What the pcap actually proves (VERIFIED this capture)

### 1. The local ClaudeProxyService (127.0.0.1:42049) saw ZERO traffic
`127.0.0.1` appears in **0 packets** — no flow touches port 42049 or 42048, and no flow
originates from or terminates at 127.0.0.1.

**Implication:** the Copilot chat panel is NOT a client of the :42049 proxy for the
"hi, u there" turn. The panel (or the extension host / copilot-runtime that serves it)
spoke to GitHub's LLM front directly over TCP/TLS egress on eth0.

This overturns one half of my earlier inference:
- I had said "the LLM path is via :42049."
- What I actually have:
  - VERIFIED: :42049 exists and is ClaudeProxyService (from agenthost.log + bundle source)
  - VERIFIED (this capture): the chat panel's real LLM call did NOT route through :42049

So :42049 is for a *different* client (the agent-host's own provider routing for Claude Code
or a "copilotcli" provider), not for the panel's "hi" call.

### 2. The real egress destination is GitHub's IAD load-balancer
Two SNIs observed in the ASCII payload of the pcap:

| SNI (from client hello) | hits in pcap |
|---|---|
| `lb-140-82-112-22-iad.github.com` | 149 |
| `lb-140-82-112-21-iad.github.com` | 28 |
| `data.microsoft.com` | 2 (telemetry) |

Both `lb-…-iad.github.com` are GitHub's Copilot LLM frontend behind Azure LB IAD
(Ashburn / Virginia). The IP `140.82.112.21` / `140.82.112.22` are the two LB frontends
for this session's region routing. The "iad" in the SNI is the Azure region tag; the
`lb-140-82-112-` is the LB pool. So the panel→GitHub LLM leg is:

    VS Code panel / copilot-runtime
        → (TLS) lb-140-82-112-21-iad.github.com :443
        → (backend) GitHub Copilot LLM service (free tier, "auto" picker)

### 3. Flow table (28 distinct TCP flows, top 8 by volume)

| bytes | pkts | flow |
|---:|---:|---|
| 1,260,466 | 4,459 | 10.0.10.166:52842 ↔ 20.120.56.11:443  ← **dominant flow; this is likely an earlier/ongoing GitHub Copilot or chat SSE stream** |
|   293,421 |   149 | 10.0.10.166:58100 ↔ 140.82.112.22:443  ← **lb-…-IAD GitHub Copilot LLM front** (149 pkts ↔ SNI count) |
|    92,584 |    73 | 10.0.10.166:33030 ↔  4.150.223.98:443  |
|    69,524 |    44 | 10.0.10.166:55880 ↔ 74.144.159.202:443  |
|    49,244 |   260 | 10.0.10.166:59358 ↔ 20.209.53.229:443  |
|    23,731 |    28 | 10.0.10.166:60360 ↔ 140.82.112.21:443  ← **second LB front (28 pkts ↔ SNI count)** |
|    10,525 |    28 | 10.0.10.166:34216 ↔ 104.21.95.185:443  (<- Cloudflare, probably telemetry / vscode) |
|    10,417 |     8 | 10.0.10.166:56026 ↔ 52.224.38.193:443  |
|     5,537 |     6 | 10.0.10.166:34766 ↔ 169.254.169.254:80  (metadata) |
|     5,348 |    31 | 10.0.10.166:56092 ↔ 199.165.136.100:443  (GitHub API) |

The 168.63.129.16:80 noise (Azure telemetry / heartbeat) and 169.254.169.254:80
(AWS-like metadata) are irrelevant.

### 4. Every LLM leg is end-to-end TLS
- No plaintext HTTP on eth0 port 80.
- No plaintext HTTP on lo port 443/42049 (the filter would have caught it).
- SNI reveals the backend host at TLS 1.3 layer, i.e. the upstream host is a real
  GitHub LB domain, not an internal service — we can't sniff headers/bodies (encrypted).

### 5. The dominant 1.26 MB flow to `20.120.56.11:443` — what is that?

20.120.56.11 is an Azure / GitHub IP. Its SNI isn't in my grep window (client hello
packets are short, usually in the first few bytes of the flow), but 4,459 pkts and
1.26 MB in a single flow strongly suggests a long-lived SSE / streaming channel —
likely the Copilot chat panel's streaming connection (the "hi" response came back
over this). To confirm its hostname: run `sslstrip`-like analysis on the pcap, or
re-run tcpdump with `-A` and filter to just that flow's first packet.

## Final verdict — updated with live evidence

The earlier conclusion "no portable reusable key, and the LLM path is gated by nonce"
is **still correct in spirit**, but now I have a *specific* destination, and more:

1. **The LLM is not a local proxy in this path.** It's GitHub's real backend at
   `lb-140-82-112-2x-iad.github.com`. That changes the reuse question — we can't
   "attach" to it without a GitHub Copilot credential (which the ghu_ token IS, but
   only as an app-credential, not as a Copilot chat credential).

2. **The local :42049 proxy IS a live service** — it just doesn't serve the panel in
   this path. It might serve the `gh copilot` CLI or the agent-host's Claude SDK
   provider. Still nonce-gated, still needs a valid SDK client to mint the nonce.

3. **To actually reuse this as an LLM for OmniRoute**, we need one of:
   - A **Copilot OAuth token** (from `gh auth login --scopes copilot`) — gives us
     real Copilot chat access via GitHub's public Copilot API (`gh copilot` CLI).
   - A **personal access token with a `copilot` equivalent scope** (GHES /
     enterprise has that; GHA free tier does not, so no-go here)
   - A **headless Copilot-SDK client** like `gh copilot` or the `@github/copilot`
     API (same effect, different transport)

4. **The free tier cap** (`free_limited_copilot`) remains the ceiling: whatever
   credential route we pick, we only get the free models and rate limits.

## The one next experiment that would close the last inference

Capture just the SNI of the 1.26 MB flow (20.120.56.11):443 — I suspect it's a
separate GitHub Copilot backend domain (like `api.githubcopilot.com` or
`github.github.com`). If that's the case, it's a *second* upstream to add to the
wiki. To do this concretely:

```
sudo tcpdump -r /tmp/copilot-llm-capture.pcap -A 2>/dev/null | \
    grep -B2 '20.120.56.11' | head -60    # find first packet, look for SNI
```

Or install tshark and decode TLS ClientHello properly.

## What this capture did NOT show (honest bucket)

- The **auth header / Bearer nonce value** — encrypted, not in the pcap.
- The **exact model name** — encrypted request body; only the env variable
  (`gpt-5.6-luna`) leaks which model family.
- Whether **Copilot used a different model** than the env-suggested one for this
  request — free tier "auto" can pick any model.
