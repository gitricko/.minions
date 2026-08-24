# Portable `.minions` Bootstrap System — Design Proposal

**Task ID:** `create-a-design-proposal-for-a-portable-minions`
**Author:** crewmate (autonomous agent)
**Status:** proposal / design (scout deliverable — report only, no PR)
**Date:** 2026-08-24

---

## 1. Executive Summary

This document proposes a self-contained, one-liner-installable bootstrap system rooted at
`~/.minions`. A single command:

```bash
curl -fsSL https://minions.sh/install.sh | bash
```

installs and wires together four components into a single, runnable stack:

| Component | Role | Upstream |
|-----------|------|----------|
| **Hermes Agent** | Self-improving conversational/generalist agent (Nous Research) | `github.com/NousResearch/hermes-agent` |
| **Pi-Agent** (`@earendil-works/pi-coding-agent`) | Coding-agent CLI / firstmate crewmate harness | `github.com/earendil-works/pi` |
| **OmniRoute** | LLM proxy/gateway, 350+ providers, 90+ free, quota-aware fallback | `github.com/diegosouzapw/OmniRoute` |
| **ModelRelay** | Lightweight OpenAI-compatible router over free coding models | `github.com/ellipticmarketing/modelrelay` |

The install produces `~/.minions/boot.sh`, which on invocation starts the full stack
(Hermes + OmniRoute + ModelRelay + Pi-agent) and leaves Pi-agent ready for firstmate
dispatch.

The proposal is grounded in the **actual** install/run mechanics of each upstream project,
derived from their `package.json` / `pyproject.toml` and READMEs (evidence cited inline).
The key design tension is that these four projects have **different runtime substrates**
(Python/uv vs. Node ≥22.19/≥22.22) and **different port defaults** — so the bootstrap
must (a) provision a compatible Node, (b) isolate each service, and (c) aggregate their
health into a single boot façade.

---

## 2. Component Analysis (grounded in upstream)

### 2.1 Hermes Agent  (`github.com/NousResearch/hermes-agent`)

- **Language / runtime:** Python 3.11–3.13 (`requires-python = ">=3.11,<3.14"` in `pyproject.toml`).
  Managed via **`uv`** (Astral). The official installer downloads its own `uv` into the
  Hermes bin dir rather than relying on a system Python.
- **Install (upstream one-liner):**
  ```bash
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  ```
  Installs under `~/.hermes` on Linux/macOS/WSL2; `%LOCALAPPDATA%\hermes` on native Windows.
  Bundles: `uv`, Python 3.11, Node.js, ripgrep, ffmpeg, and (Windows) a portable Git Bash.
- **Run:**
  ```bash
  hermes            # TUI chat
  hermes gateway    # messaging gateway (Telegram/Discord/Slack/...)
  hermes doctor     # diagnostics
  ```
- **Key constraint:** Heavy Python dependency tree (pydantic, httpx, rich, prompt_toolkit,
  croniter, etc.), exact-pinned. Needs its **own** venv; should not share Pi/OmniRoute's Node.
- **Evidence:** `pyproject.toml` (lines for `requires-python`, `uv` install model);
  README "Quick Install" section (`curl ... install.sh`).

### 2.2 Pi-Agent / Pi Coding Agent  (`github.com/earendil-works/pi`)

- **Language / runtime:** TypeScript monorepo, **Node ≥ 22.19.0** (`engines.node` in root
  `package.json`). The coding-agent subpackage is published as
  `@earendil-works/pi-coding-agent` (currently `0.84.2`).
- **Bin:** `pi` → `dist/bundle/cli.js`.
- **Two relevant run modes:**
  - **Interactive/TUI coding agent:** `pi` (CLI).
  - **RPC/crewmate mode:** the package exposes `./dist/bundle/rpc-entry.js` (export
    `"./rpc-entry"`) — a headless RPC entrypoint that is exactly the *firstmate crewmate
    harness* surface referenced in the task. firstmate dispatches work to this RPC endpoint.
- **Install options:**
  1. **npm global:** `npm i -g @earendil-works/pi-coding-agent` then `pi`.
  2. **Bun standalone binary:** `build:binary` target compiles a single `dist/pi` executable
     (`bun build --compile ... ./src/bun/cli.ts`). This is the most portable/self-contained
     form (no Node on PATH needed) — recommended for `.minions`.
  3. **Source build** from monorepo (heavy: needs `tsgo`, `biome`, esbuild, workspace build order).
- **Supply-chain note:** published CLI ships `npm-shrinkwrap.json`; upstream installs use
  `--ignore-scripts`. The bootstrap should prefer the prebuilt binary or the npm package with
  `--ignore-scripts` to avoid arbitrary postinstall network access.
- **Evidence:** `package.json` (root `engines.node >=22.19.0`);
  `packages/coding-agent/package.json` (`bin.pi`, `exports["./rpc-entry"]`, `build:binary`);
  README ("Building standalone binaries from release source").

### 2.3 OmniRoute  (`github.com/diegosouzapw/OmniRoute`)

- **Language / runtime:** TypeScript, **Node ≥ 22.22.2 <23 || ≥ 24** (`engines.node` in
  `package.json`). Published as `omniroute` on npm (currently `3.8.50`).
- **Bin:** `omniroute` → `bin/omniroute.mjs`; also `omniroute-reset-password`.
- **Default port:** `localhost:20128` (OpenAI-compatible `/v1`). **Zero-config out of the
  box** — `model: "auto"` answers with no API key via keyless free providers.
- **Install:** `npm i -g omniroute` (also Docker `diegosouzapw/omniroute`).
- **Nuance:** OmniRoute's `postinstall` script (`scripts/postinstall.mjs`) does setup work
  and may try to fetch optional native bits; it has many workspaces and a large install. The
  bootstrap should pin a version and run with `--ignore-scripts` where feasible, then run the
  runtime env assemble step explicitly if needed.
- **Evidence:** `package.json` (`engines.node`, `bin.omniroute`, default port `20128` in README
  quick-start; `files` lists `scripts/postinstall.mjs`).

### 2.4 ModelRelay  (`github.com/ellipticmarketing/modelrelay`)

- **Language / runtime:** Node.js, **Node ≥ 18** (`engines.node`). Published as `modelrelay`
  (currently `1.12.0`). Lightweight (deps: `chalk`, `express`).
- **Bin:** `modelrelay` → `bin/modelrelay.js`.
- **Default port:** `http://127.0.0.1:7352/v1` (OpenAI-compatible). Model `auto-fastest`
  benchmarks free models and routes to best QoS.
- **Install:** `npm i -g modelrelay`, then `modelrelay`. Also Docker compose.
- **Convenience:** `modelrelay install --autostart`, `modelrelay onboard` (configures
  OpenClaw/OpenCode). The bootstrap should **not** use `--autostart` (we manage lifecycle
  ourselves via `boot.sh`) but can reuse `modelrelay`'s config-export/import token for portable
  config.
- **Evidence:** `package.json` (`engines.node >=18`, `bin.modelrelay`, `express`/`chalk`);
  README ("Install via NPM", port `7352`, `auto-fastest`).

### 2.5 Runtime substrate summary

| Component | Substrate | Hard requirement | Default port |
|-----------|-----------|----------------|--------------|
| Hermes | Python + uv | Python 3.11–3.13 | (gateway configurable; CLI none) |
| Pi-Agent | Node 22.19+ (or Bun binary) | Node ≥22.19 **or** standalone binary | RPC/stdio (firstmate-managed) |
| OmniRoute | Node 22.22+ | Node ≥22.22.2 | `20128` |
| ModelRelay | Node 18+ | Node ≥18 | `7352` |

**Critical:** OmniRoute requires **≥22.22.2**, which is *newer* than Pi-Agent's ≥22.19. The
bootstrap must provision Node ≥22.22.2 (covers both), or run Pi-Agent as a **Bun-compiled
standalone binary** (no Node needed) and OmniRoute/ModelRelay on Node ≥22.22.2. The latter is
recommended: it decouples the heaviest Node requirement (OmniRoute) from Pi-Agent entirely and
removes Node from Pi-Agent's attack/version surface.

---

## 3. Architecture

### 3.1 High-level topology

```
                        ┌──────────────────────────────────────────┐
                        │            ~/.minions  (hidden)          │
                        │                                            │
   firstmate ──dispatch──►  boot.sh  (orchestrator / health façade)  │
                        │        │                                   │
          ┌─────────────┼────────┼───────────────┬──────────────────┤
          ▼             ▼        ▼               ▼                  │
     [Pi-Agent]    [OmniRoute]  [ModelRelay]   [Hermes]            │
     rpc-entry    :20128/v1     :7352/v1      (uv venv)            │
     (crewmate)   OpenAI-compat OpenAI-compat  TUI / gateway       │
          │             ▲             ▲                             │
          │             │             │                             │
          └──── points BASE_URL at one of the proxies ──────────────┘
                        │
                        ▼
                  free LLM providers (90+ free tiers)
```

- **Pi-Agent** is the *worker*. firstmate dispatches tasks to its `rpc-entry`. Pi's own LLM
  calls are pointed (via env/config) at either OmniRoute (`localhost:20128/v1`) or
  ModelRelay (`localhost:7352/v1`).
- **OmniRoute** and **ModelRelay** are *competing/complementary proxies*. Both expose an
  OpenAI-compatible `/v1`; we run both and let the user/agent pick (OmniRoute for breadth +
  quota-aware fallback, ModelRelay for "fastest free coding model" routing). They can even be
  chained (Pi → ModelRelay → OmniRoute) but that adds latency; keep them side-by-side.
- **Hermes** is a *separate* generalist agent with its own model config; it can also be pointed
  at a proxy if the user wants free routing, but by default uses its own provider selection.
- **boot.sh** is the single entrypoint: it brings up the proxies + Hermes, then launches
  Pi-Agent in RPC mode and prints a "ready for firstmate dispatch" line.

### 3.2 Isolation & process model

- Each component runs as an **independent supervised process** with its own log file under
  `~/.minions/var/log/`.
- Proxies (OmniRoute, ModelRelay) are long-running servers; Hermes gateway (optional) and
  Pi-Agent RPC are long-running too.
- The bootstrap uses a tiny **process supervisor** (a POSIX `sh` loop or `systemd --user` where
  available) so `boot.sh` can start all and `boot.sh stop` can stop all. On macOS, prefer
  `launchd` plist or a plain background loop; keep it dependency-free (no Docker required).

### 3.3 Why not Docker-only?

Docker *could* bundle everything, but the task says "work on fresh Linux/macOS" and "self-
contained." Docker is an extra install step that fails on many fresh macOS/Windows laptops and
on restricted CI. The proposal therefore makes **Docker optional** (a `boot.sh --docker`
variant) and the default path is **native** (Node + uv, both vendored into `~/.minions`).

---

## 4. Install Flow

### 4.1 One-liner

```bash
curl -fsSL https://minions.sh/install.sh | bash
```

`install.sh` is a **minimal, auditable POSIX sh** script (like oh-my-zsh / Hermes installers).
It must:

1. **Detect OS/arch** (Linux x64/arm64, macOS intel/apple-silicon) and `uname`.
2. **Create `~/.minions`** and subdirs (`bin/`, `lib/`, `var/log/`, `var/run/`, `etc/`,
   `cache/`).
3. **Provision a pinned Node** (≥22.22.2) into `~/.minions/lib/node/` only if the system Node
   is missing or too old. Use `nodejs.org/dist` tarballs (no apt/brew needed). This satisfies
   OmniRoute and ModelRelay.
   - *Alternatively*, skip Node for Pi-Agent by downloading the **Bun-compiled standalone
     `pi` binary** (see §2.2) — recommended to keep Pi-Agent isolated from Node version churn.
4. **Provision `uv`** into `~/.minions/lib/uv/` (Hermes' own installer already does this; we
   reuse the pattern, or call Hermes' installer non-interactively).
5. **Fetch pinned component archives** (npm tarballs or prebuilt binaries) into
   `~/.minions/lib/<component>/`. Pin exact versions (e.g. `omniroute@3.8.50`,
   `modelrelay@1.12.0`, `pi-coding-agent` binary `0.84.2`, `hermes-agent` `0.20.5`) and
   checksum-verify each download.
6. **Generate `boot.sh`**, `stop.sh`, config templates in `~/.minions/etc/`, and symlink the
   four CLIs into `~/.minions/bin/` (which gets prepended to `PATH` via a shell snippet the
   installer offers to add to `~/.bashrc`/`~/.zshrc`).
7. **Print a summary** and the next step: `~/.minions/boot.sh`.

### 4.2 Idempotency & updates

- Re-running `install.sh` upgrades in place (or `boot.sh update` shells out to each component's
  own updater: `hermes update`, `omniroute`/`modelrelay` via `npm -g`, Pi binary re-download).
- Keep a `~/.minions/etc/versions.env` lockfile so installs are reproducible.

### 4.3 Offline / air-gapped variant (stretch)

Because all four publish versioned tarballs, a `minions-bundle.tar.gz` can ship the pinned
artifacts for fully offline install. Not required for v1 but the directory layout supports it.

---

## 5. Directory Structure

```
~/.minions/
├── README.md                 # what this is + quickstart
├── install.sh                # (also lives at minions.sh/install.sh) bootstrap entry
├── boot.sh                   # START the full stack (the deliverable entrypoint)
├── stop.sh                   # STOP the full stack
├── status.sh                 # health check / port probe
├── update.sh                 # upgrade components in place
├── bin/                      # symlinks / shims on PATH
│   ├── pi -> ../lib/pi/pi            (standalone binary) 
│   ├── hermes -> ../lib/hermes/...    (uv-shim)
│   ├── omniroute -> ../lib/omniroute/bin/omniroute.mjs
│   └── modelrelay -> ../lib/modelrelay/bin/modelrelay.js
├── lib/
│   ├── node/                 # vendored Node ≥22.22.2 (only if system Node too old)
│   ├── uv/                   # vendored uv + Hermes Python toolchain
│   ├── pi/                   # @earendil-works/pi-coding-agent (standalone binary or npm)
│   ├── hermes/               # hermes-agent (uv venv + sources)
│   ├── omniroute/            # omniroute npm package
│   └── modelrelay/           # modelrelay npm package
├── etc/
│   ├── versions.env          # pinned component versions (lockfile)
│   ├── minions.env           # MINIONS_* config (ports, proxy choice, log levels)
│   ├── pi.toml / pi.json     # pi-agent config: BASE_URL -> proxy, model, rpc port
│   ├── omniroute.env         # omniroute overrides (port 20128, bind)
│   ├── modelrelay.env        # modelrelay overrides (port 7352)
│   └── hermes.env            # hermes provider/model config
├── var/
│   ├── run/                  # .pid files for each service
│   ├── log/                  # <component>.log
│   └── cache/                # downloaded tarballs / npm cache
└── workspace/                # optional scratch dir Pi-Agent / Hermes operate in
```

All paths are referenced relative to `$MINIONS_HOME` (defaults to `~/.minions`) so the whole
tree is relocatable (e.g. for tests or multi-user).

---

## 6. Boot Sequence

`boot.sh` (POSIX sh, `set -euo pipefail`-light, logs to `var/log/boot.log`):

```
1. export MINIONS_HOME, prepend $MINIONS_HOME/bin to PATH
2. source etc/minions.env, etc/versions.env
3. ensure Node/uv on PATH (use vendored lib/node, lib/uv if present)
4. for each service in order [omniroute, modelrelay, hermes?, pi]:
     a. if pid file exists & process alive -> skip (already up)
     b. start in background, redirect to var/log/<svc>.log, write pid to var/run/<svc>.pid
     c. wait-for-port loop (max ~15s) probing the service's port
5. OmniRoute (20128) and ModelRelay (7352) must be UP before Pi-Agent.
6. Launch Pi-Agent in RPC/crewmate mode:
     pi --rpc --base-url http://localhost:20128/v1   (or 7352)
   (configurable via etc/pi.toml; this is the "ready for firstmate dispatch" process)
7. Print status block:
     ✅ omniroute   http://localhost:20128/v1
     ✅ modelrelay  http://localhost:7352/v1
     ✅ hermes      (tui/gateway)
     ✅ pi-agent    rpc-entry up — READY FOR FIRSTMATE DISPATCH
8. If run interactively (no args), `exec`/attach; if `--daemon`, return 0 and detach.
```

`stop.sh` walks `var/run/*.pid`, TERM then KILL after grace, removes pid files.

`status.sh` probes each port and prints ✅/❌; used by firstmate health checks.

**Ordering rationale:** proxies first (they're what Pi-Agent talks to); Hermes is
independent so it can start in parallel; Pi-Agent last because firstmate dispatches to it and
it depends on a proxy being live.

---

## 7. Pitfalls & Risks

1. **Node version split (HIGH).** OmniRoute needs Node ≥22.22.2 but Pi-Agent only ≥22.19. A
   system Node of, say, 20.x satisfies neither. *Mitigation:* vendor a single Node ≥22.22.2,
   **or** run Pi-Agent as a Bun standalone binary (no Node). The binary path is preferred.
2. **macOS Gatekeeper / unsigned binaries (MED).** `uv` and the Pi Bun binary are unsigned
   Rust/compiled binaries; macOS will quarantine them ("cannot be opened"). *Mitigation:*
   `xattr -dr com.apple.quarantine` the vendored binaries during install; document the
   "allow in Security & Privacy" step.
3. **Hermes installer side-effects (MED).** The Hermes `install.sh` writes to `~/.bashrc` and
   installs a *portable Git Bash* on Windows; running it non-interactively inside our
   installer can clobber user shell config. *Mitigation:* call Hermes installer with its
   non-interactive flags (or replicate its uv-venv setup ourselves under `lib/hermes` and avoid
   its shell hacks), and never let it edit the user's rc files — we manage `PATH` via our own
   `minions.sh` snippet.
4. **Postinstall network access (MED / supply-chain).** OmniRoute and Hermes run install-time
   scripts that touch the network. *Mitigation:* `npm i --ignore-scripts` for the Node
   packages; verify checksums of every tarball before extraction; pin exact versions.
5. **Port collisions (LOW/MED).** `20128` (OmniRoute) and `7352` (ModelRelay) may be taken.
   *Mitigation:* `status.sh`/boot probes the port; if busy, look for a free port in a small
   range and rewrite the relevant `etc/*.env`; print the actual port.
6. **Two competing proxies confusion (LOW).** Users/agents may not know which `/v1` to point
   Pi at. *Mitigation:* `etc/minions.env` has a single `MINIONS_LLM_BASE_URL` default
   (OmniRoute) and `boot.sh` prints both endpoints; Pi config references the var, not a literal.
7. **Firstmate dispatch contract (MED).** The exact transport firstmate uses to talk to Pi-
   Agent's `rpc-entry` (stdio vs HTTP port vs unix socket) must be nailed down before shipping
   the boot "ready" line. *Mitigation:* boot.sh should poll Pi's actual RPC readiness
   (e.g. a health file `var/run/pi.rpc-ready` written by the agent) rather than just "process
   started," so firstmate only dispatches when truly ready. **This is the #1 open decision
   (see §8).**
8. **Hermes TUI vs gateway (LOW).** `hermes` (TUI) needs a terminal; in a headless server boot
   it should run `hermes gateway` (or be skipped unless requested). *Mitigation:* boot.sh
   starts Hermes gateway only when `MINIONS_HERMES=on` (default off in daemon mode).
9. **Disk / bandwidth (LOW).** OmniRoute's npm tree is large; Hermes pulls many wheels.
   *Mitigation:* cache tarballs in `var/cache`; support the offline bundle.
10. **No shared daemon interference (OPERATIONAL).** The shared `no-mistakes` daemon is
    out of scope for `.minions` but the bootstrap must **never** stop/restart it. boot.sh only
    manages the four components it owns.

---

## 8. Open Decisions for the Captain (unresolved)

These are genuine product/architecture choices that belong to a human, not this scout report:

- **[D1] Pi-Agent dispatch transport.** Should `.minions` expose Pi-Agent's RPC to firstmate
  over (a) stdio, (b) a localhost HTTP port, or (c) a unix socket? This determines what
  "ready for firstmate dispatch" concretely means and how firstmate connects. *Recommendation:*
  a localhost HTTP RPC port (simplest cross-process, easy health probe), with the port in
  `etc/pi.toml`.
- **[D2] Proxy default.** Ship OmniRoute as the default Pi base-URL, ModelRelay, or let the
  user pick at install? *Recommendation:* OmniRoute default (broadest free coverage +
  quota-aware fallback), ModelRelay side-by-side.
- **[D3] Hermes default mode.** Start Hermes gateway by default in daemon boot, or leave it
  opt-in (`MINIONS_HERMES=on`)? *Recommendation:* opt-in to avoid a stray Telegram/Discord
  gateway binding on a server.
- **[D4] Pi-Agent delivery form.** Bun standalone binary (recommended, no Node dep) vs npm
  global (simpler, needs Node). *Recommendation:* standalone binary.

(These map to decision-holds registered via `bin/fm-decision-hold.sh` per the
decision-hold-lifecycle skill; see §9.)

---

## 9. Completion Gate (decision-hold-lifecycle)

Per `/home/codespace/Documents/firstmate/.agents/skills/decision-hold-lifecycle/SKILL.md`,
this scout report surfaces unresolved captain decisions. Before marking the task done:

1. Inventory genuine captain choices → the four in §8 (D1–D4).
2. Register each with `bin/fm-decision-hold.sh hold` using stable keys
   `minions-pi-transport`, `minions-proxy-default`, `minions-hermes-mode`, `minions-pi-delivery`.
3. Run `bin/fm-decision-hold.sh complete` with those keys.
4. Surface them to the captain as "Captain's Call" items (not using the word "hold").
5. On the captain's answers, route any follow-up work and close the holds via
   `bin/fm-decision-hold.sh resolve`/`answer`/`decline`.

Because this is a **scout/report-only** task, the report itself is the deliverable; the holds
ensure D1–D4 are not lost when the report is archived.

---

## 10. Recommendations

1. **Adopt the vendored-binary layout** in §5 with `MINIONS_HOME` indirection — it makes the
   tree relocatable and testable.
2. **Run Pi-Agent as the Bun standalone binary** (§2.2) to drop the Node ≥22.19 requirement
   for the worker, leaving only OmniRoute's ≥22.22.2 for the proxies. This is the cleanest
   version-isolation story.
3. **Use `--ignore-scripts` + checksum pinning** for all Node/Python fetches (§7.4) — matches
   upstream Pi supply-chain hardening and avoids surprise network egress during install.
4. **Make `boot.sh` readiness-based, not just process-based** — Pi-Agent should write
   `var/run/pi.rpc-ready` (or expose a health endpoint) before boot.sh declares "ready for
   firstmate dispatch" (§7.7/D1).
5. **Default OmniRoute as the Pi base-URL, ModelRelay side-by-side, Hermes opt-in** (§8 D2/D3).
6. **Keep Docker as an optional `boot.sh --docker` variant**, not the default (§3.3).
7. **Resolve D1–D4 with the captain** before any implementation/promotion of this design into
   a shipped installer.

---

## 11. Evidence Index

| Claim | Source |
|-------|--------|
| Hermes Python 3.11–3.13, uv-managed, `~/.hermes`, one-liner installer | `github.com/NousResearch/hermes-agent` → `pyproject.toml` (`requires-python`), README "Quick Install" |
| Pi-Agent Node ≥22.19, `pi` bin, `rpc-entry` export, Bun `build:binary` | `github.com/earendil-works/pi` → root `package.json` (`engines.node`), `packages/coding-agent/package.json` (`bin`, `exports["./rpc-entry"]`, `build:binary`) |
| OmniRoute Node ≥22.22.2, `omniroute` bin, port `20128`, zero-config `auto` | `github.com/diegosouzapw/OmniRoute` → `package.json` (`engines.node`, `bin`), README quick-start |
| ModelRelay Node ≥18, `modelrelay` bin, port `7352`, `auto-fastest` | `github.com/ellipticmarketing/modelrelay` → `package.json` (`engines.node`), README |
| Pi supply-chain: shrinkwrap, `--ignore-scripts`, pinned deps | `earendil-works/pi` README "Supply-chain hardening" |
| Hermes exact-pin + `uv` supply-chain rationale | `hermes-agent/pyproject.toml` dependency comments |

**Environment probed during research (this agent's host):**
`curl 8.5.0`, `wget 1.21.4`, `git 2.53.0`, `python3 3.12.1`, `node v24.14.0`, `npm 11.9.0`,
`docker 29.3.0`. Node v24.14.0 already satisfies both Pi (≥22.19) and OmniRoute (≥22.22.2),
so on a host like this the vendored-Node step can be skipped — but the installer must still
handle the fresh-system (old/missing Node) case.

---

*End of proposal. This is a design document only; no code was committed to the upstream repo
and no installer was published. The four open decisions (§8) are registered as decision-holds
per the lifecycle skill before this task is marked done.*
