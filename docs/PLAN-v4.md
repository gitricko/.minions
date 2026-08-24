# .minions — Plan v4 (Markdown Export)

**Portable, oh-my-zsh-style bootstrap for a self-contained AI coding stack at `~/.minions`.**  
v4 folds in all captain feedback: Linux-first scope, CLI-only components, preconfiguration as core work, env-configurable ports for dev-safety, `--doctor` optional, **mnemon provider for Pi**, and **process isolation safety**.

---

## 1 · Scope (v1)

| Target | Status |
|--------|--------|
| Codespace Linux (x86_64 + arm64) | ✅ Primary |
| GitHub Actions runner Linux | ✅ Primary |
| macOS (Intel / Apple Silicon) | 🔜 **Later** — explicitly deferred |

**Don't overfit to Codespace.** Keep it portable bash. Linux-only assertions in CI.

---

## 2 · Component Model

| Component | Kind | Runs How | v1 Status |
|-----------|------|----------|-----------|
| OmniRoute | persistent service | `setsid omniroute --no-open &` + preconfig | ✅ npm OK |
| ModelRelay | persistent service | `setsid modelrelay &` | ✅ npm OK |
| Pi-Agent | CLI tool | invoked by **user or automation** (GitHub runner / firstmate) | ⚠ npm (B1) |
| Hermes | CLI tool | preinstalled; used as CLI | ⚠ checksum (B4) |

> **Note:** Pi & Hermes are **not servers unless launched**. Only the two LLM proxies are persistent.  
> **Gateway + Dashboard dropped from v1** — you never use them; deferred to future work.

---

## 3 · Decisions — RESOLVED

| Decision | Resolution |
|----------|------------|
| D1 · Pi transport | **DROPPED** — Pi is a CLI; no RPC server. |
| D2 · Proxy default | **DROPPED** — both always up; chosen per-component in config files. |
| D3 · Hermes | **RESOLVED** — always preinstall Hermes **CLI**. Gateway/Dashboard = **FUTURE WORK**. |
| D4 · Pi delivery | **RESOLVED** — npm: `@earendil-works/pi-coding-agent` (not the broken Bun URL). |

---

## 4 · The Real Work = Preconfiguration

Mirroring `post-create-cmd.sh` + `start-hermes.sh`, **install + boot must preconfigure each component** after it starts. This is the portability payload.

| Component | Preconfiguration (from reference) | .minions Location |
|-----------|-----------------------------------|-------------------|
| **OmniRoute** | wait `/v1/models`→200; set `requireLogin=false` (sqlite); create combo `auto-fastest` (strategy auto); PUT models + retry config; enable MCP; `hermes mcp add omniroute` | `boot.sh` + `lib/omniroute.sh` |
| **Hermes** | `hermes config set`: model.default=auto-fastest, provider=omniroute, base_url `localhost:${OR_PORT}/v1`, modelrelay base_url `localhost:${MR_PORT}/v1`, fallback=modelrelay, approvals off, memory=mnemon, agent.max_turns=120, kanban.failure_limit=3 | `install.sh` (first-run only) |
| **Pi** | install `pi-failover@hermes-impl` ext; symlink tracked `etc/pi/{models,settings}.json` → `~/.pi/agent/` (`defaultProvider: omniroute`, `modelrelay` fallback) | `install.sh` + `boot.sh` (repair guard) |
| **Mnemon (Hermes)** | install binary; seed import from `etc/seed.json` (dry-run validate → import); **install hermes-plugin-mnemon** → gives Hermes `mnemon_remember`/`mnemon_recall` tools | `install.sh` + `start-hermes.sh` pattern |
| **Mnemon (Pi)** | **NEW:** figure out Pi-agent mnemon integration — likely a Pi extension or direct mnemon CLI usage in Pi's config/hooks. Mirror Hermes pattern where possible. | `install.sh` (Pi section) |

> All preconfiguration must read ports from env (§5) so it targets the right instance.

---

## 5 · Port Configurability (CRITICAL dev-safety)

> ⚠ **You are developing .minions INSIDE hermes-codespace where omniroute :20128 and modelrelay :7352 are ALREADY running.**

Every port MUST be env-overridable so a parallel dev instance does not collide with the host:

| Env var | Default | Dev Override (example) |
|---------|---------|------------------------|
| `OMNIROUTE_PORT` | 20128 | 20129 |
| `MODELRELAY_PORT` | 7352 | 7353 |
| `MINIONS_HOME` | `~/.minions` | `/tmp/minions-dev` |

**Dev command:**
```bash
MINIONS_HOME=/tmp/minions-dev \
OMNIROUTE_PORT=20129 \
MODELRELAY_PORT=7353 \
./install.sh && ./boot.sh
```

Two full stacks coexist. Preconfiguration (§4) reads these vars.

---

## 6 · Process Safety (NEW)

**Not just port clash.** When running `hermes` / `pi` CLI during dev:
- They might connect to the *dev instance* (different ports/config)
- Must avoid commands that kill the **host** hermes/pi processes that run the dev environment

**Rules:**
- Never `pkill -f hermes` or `pkill -f pi` — use targeted PID or port-specific checks
- Dev instance processes are under `MINIONS_HOME=/tmp/minions-dev` — identify by cwd/env
- Host stack = `MINIONS_HOME=~/.minions` (or unset), ports 20128/7352
- CI/test scripts must scope kills to dev ports only

---

## 7 · install.sh ≈ post-create-cmd.sh (one-time)

```mermaid
flowchart LR
    A[install.sh] --> B[detect node+npm+uv (B2)\ninstall if missing]
    A --> C[omniroute + modelrelay\nnpm -g --prefix (ports via env)]
    A --> D[pi-agent (npm, B1)\n+ pi-failover ext]
    A --> E[preinstall hermes CLI\nD3: no gateway in v1]
    A --> F[hermes config set block\n§4 preconfig (ports via env)]
    A --> G[wire pi + mnemon cfg\nsymlinks + seed import\n+ Pi mnemon provider]
```

---

## 8 · boot.sh ≈ start-hermes.sh (runtime) + optional `--doctor`

```mermaid
flowchart LR
    A[boot.sh] --> B[bg omniroute\npreconfig: login off, combo\nMCP + hermes mcp add]
    A --> C[bg modelrelay\nsetsid … &]
    A --> D[wait healthy + ready\nB5: var/run/ready]
    A --> E[status.sh + return\nno --daemon (B6 dropped)]
    A -.-> F[boot.sh --doctor (opt)\nrepair broken component]
```

---

## 9 · Blockers — REVISED (B1–B7)

| # | Blocker | Fix |
|---|---------|-----|
| B1 | Pi URL 404 (Bun) | `lib/detect.sh:69` → `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` |
| B2 | node/npm/uv prereq | `install.sh` detect + vendor/install if missing |
| B3 | uv URL 404 | `lib/detect.sh:54-64` Rust triple (uv-x86_64-unknown-linux-gnu.tar.gz) |
| B4 | placeholder checksums | `etc/versions.env` pin: Hermes v2026.8.13, OmniRoute 3.8.49, ModelRelay 1.18.0, Pi 0.84.2 |
| B5 | readiness marker | `boot.sh`: `touch $MINIONS_HOME/var/run/ready` after healthy |
| B6 | --daemon | **DROPPED** — setsid + return |
| B7 | get_sha256 case | `lib/detect.sh:96` uppercase before eval |

---

## 10 · CI + Next Steps

- **CI:** install + retest on Codespace Linux + GitHub runner Linux. Portable bash, Linux-only assertions. Use env ports (§5) so CI doesn't clobber host stack.
- **Future work (explicitly deferred):** macOS support, Hermes gateway/dashboard, Telegram.

**Implementation order:**
1. **install.sh** = mirror post-create (prereqs, npm installs, hermes config set, pi/mnemon symlinks+seed, **Pi mnemon provider**)
2. **boot.sh** = mirror start-hermes (bg proxies + omniroute preconfig, readiness marker, return; optional `--doctor`)
3. **lib/detect.sh** fixes B1/B3/B7
4. **etc/versions.env** pin real (B4)
5. Real install test (network-mocked) + open PR

---

## 11 · Open Questions

1. **Pi-agent mnemon provider** — Hermes uses `hermes-plugin-mnemon` (gitricko/hermes-plugin-mnemon) which exposes `mnemon_remember`/`mnemon_recall` as tools. What's the Pi equivalent?
   - Option A: Pi extension that wraps mnemon CLI
   - Option B: Direct mnemon CLI calls in Pi's config/hooks
   - Option C: Pi uses Hermes as mnemon provider via RPC (if Hermes gateway runs)
   - Need to research / prototype

2. **Seed.json content** — what goes in `.minions/etc/seed.json`? Mirror hermes-codespace's `.devcontainer/mnemon/seed.json` but for the .minions stack.

---

*Captain: v4 reflects all feedback. Review in VS Code — adjust here or say "sync to README + scout report".*