# .minions

**Portable, oh-my-zsh-style bootstrap for a self-contained AI coding stack at `~/.minions`.**

First iteration targets **Linux (x86_64 + arm64)** — Codespace and GitHub Actions runners. macOS (Intel / Apple Silicon) is explicitly **later**.

```text
firstmate ──dispatch──►  boot.sh  ──►  Pi-Agent (CLI, invoked by user/automation)
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
               OmniRoute        ModelRelay       Hermes (CLI, opt-in)
            :20128/v1         :7352/v1         preinstalled
```

---

## Quick Start

```bash
# One-liner install (from minions.sh when published)
curl -fsSL https://minions.sh/install.sh | bash

# Or from this repo
./install.sh
```

Then start the stack:

```bash
~/.minions/boot.sh
```

You'll see:

```text
==============================================
  .minions stack is UP

  ✅ omniroute    http://localhost:20128/v1
  ✅ modelrelay   http://localhost:7352/v1
  ✅ pi-agent     CLI ready (invoked on demand)
  ✅ hermes       CLI ready (preinstalled)
  ✅ mnemon       memory layer ready

  READY FOR FIRSTMATE DISPATCH
==============================================
```

---

## Components

| Component | Kind | Runs How | v1 Status |
|-----------|------|----------|-----------|
| **OmniRoute** | persistent service | `setsid omniroute --no-open &` + preconfig | ✅ npm OK |
| **ModelRelay** | persistent service | `setsid modelrelay &` | ✅ npm OK |
| **Pi-Agent** | CLI tool | invoked by **user or automation** (GitHub runner / firstmate) | ✅ npm OK |
| **Hermes** | CLI tool | preinstalled; used as CLI | ✅ git install OK |
| **Mnemon** | memory layer | binary + seed import + extensions | ✅ available |

> **Note:** Pi & Hermes are **not servers unless launched**. Only the two LLM proxies are persistent.  
> **Gateway + Dashboard dropped from v1** — you never use them; deferred to future work.

---

## Usage

### Start the stack
```bash
~/.minions/boot.sh              # Backgrounds proxies, preconfigures them, touches readiness marker, returns
~/.minions/boot.sh --doctor     # Optional: repair a broken component
```

### Stop the stack
```bash
~/.minions/stop.sh
```

### Check status
```bash
~/.minions/status.sh
```

### Switch LLM proxy
```bash
# Use ModelRelay instead of OmniRoute
export MINIONS_LLM_BASE_URL=http://localhost:7352/v1
~/.minions/boot.sh
```

### Custom install location (with port isolation for dev)
```bash
MINIONS_HOME=/tmp/minions-dev \
OMNIROUTE_PORT=20129 \
MODELRELAY_PORT=7353 \
./install.sh
```

---

## Configuration

All configuration lives in `~/.minions/etc/`:

| File | Purpose |
|------|---------|
| `versions.env` | Pinned component versions (lockfile) + real SHA256 checksums |
| `minions.env` | Runtime config (ports, proxy choice, log level) |
| `pi/` | Pi-Agent config (symlinked to `~/.pi/`) — `models.json`, `settings.json` |
| `omniroute/` | OmniRoute preconfig state (sqlite, combo) |
| `mnemon-seed-pi.json` | Mnemon seed data for Pi-Agent |
| `mnemon-seed-hermes.json` | Mnemon seed data for Hermes |

Key environment variables (in `minions.env` / shell):

```bash
MINIONS_HOME=~/.minions              # Relocatable root
OMNIROUTE_PORT=20128                 # OmniRoute port (env-overridable)
MODELRELAY_PORT=7352                 # ModelRelay port (env-overridable)
MINIONS_LLM_BASE_URL=http://localhost:20128/v1  # Default proxy for Pi/Hermes
MINIONS_HERMES=off                   # Gateway disabled in v1 (future work)
```

---

## Architecture

```text
~/.minions/
├── install.sh          # One-time bootstrap (≈ post-create-cmd.sh)
├── boot.sh             # Runtime start (≈ start-hermes.sh) + --doctor
├── stop.sh             # Stop the stack
├── status.sh           # Health check + readiness marker
├── bin/                # Symlinks to component CLIs (on PATH)
├── lib/                # Helper scripts + vendored runtimes
│   ├── detect.sh       # OS/arch + download URLs + SHA256
│   ├── download.sh     # curl/wget + sha256 verify + extract
│   ├── node.sh         # Node.js ≥22.22.2 vendoring
│   ├── uv.sh           # uv vendoring (Rust triple mapping)
│   ├── pi.sh           # Pi-Agent install (npm @earendil-works/pi-coding-agent)
│   ├── hermes.sh       # Hermes install (official git install script)
│   ├── npm_packages.sh # OmniRoute + ModelRelay (npm -g --prefix)
│   ├── omniroute.sh    # OmniRoute preconfig (login off, combo, MCP)
│   ├── mnemon.sh       # Mnemon binary + seed import
│   └── process.sh      # start/stop/wait_for_port/wait_for_health
├── etc/                # Configuration templates
├── var/
│   ├── run/            # .pid files + ready marker
│   ├── log/            # Service logs
│   └── cache/          # Downloaded tarballs
└── workspace/          # Scratch dir for agents
```

---

## Requirements

- **Linux** (x86_64, arm64) — Codespace / GitHub runner
- **curl** or **wget** for downloads
- **bash** for PATH integration (optional)

The installer handles everything else:
- Vendors Node.js ≥22.22.2 if system version is too old (for OmniRoute/ModelRelay)
- Installs uv for Hermes (Python 3.11+ managed by uv)
- Installs Pi-Agent via npm: `@earendil-works/pi-coding-agent` (not a standalone binary)
- Preconfigures OmniRoute (login off, `auto-fastest` combo, MCP, hermes mcp add)
- Configures Hermes (`hermes config set` block: provider=omniroute, fallback=modelrelay, mnemon, approvals off)
- Installs Mnemon binary + seed import + Pi mnemon extension (skill + TypeScript extension)

---

## Preconfiguration (The Real Work)

`install.sh` + `boot.sh` mirror the `hermes-codespace` reference:

| Component | Preconfiguration |
|-----------|------------------|
| **OmniRoute** | wait `/v1/models`→200; sqlite `requireLogin=false`; create combo `auto-fastest` (strategy auto); PUT models + retry config; enable MCP; `hermes mcp add omniroute` |
| **Hermes** | `hermes config set`: model.default=auto-fastest, provider=omniroute, base_url `localhost:${OR_PORT}/v1`, modelrelay base_url `localhost:${MR_PORT}/v1`, fallback=modelrelay, approvals off, memory=mnemon, agent.max_turns=120, kanban.failure_limit=3 |
| **Pi** | install `pi-failover` ext; symlink tracked `etc/pi/{models,settings}.json` → `~/.pi/` (`defaultProvider: omniroute`, `modelrelay` fallback); install mnemon Pi extension (skill + TypeScript extension) |
| **Mnemon** | install binary; seed import from `etc/mnemon-seed-*.json` (dry-run validate → import) |

All preconfiguration reads `OMNIROUTE_PORT` / `MODELRELAY_PORT` / `MINIONS_HOME` so it targets the right instance.

---

## Port Configurability (Critical Dev Safety)

You are developing .minions **INSIDE hermes-codespace** where omniroute `:20128` and modelrelay `:7352` are **already running**.

| Env var | Default | Dev override |
|---------|---------|--------------|
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

Two full stacks coexist. Preconfiguration reads these vars.

---

## Process Safety (Critical Dev Safety)

**Not just port clash.** When running `hermes` / `pi` CLI during dev:
- They might connect to the *dev instance* (different ports/config)
- Must avoid commands that kill the **host** hermes/pi processes that run the dev environment

**Rules:**
- Never `pkill -f hermes` or `pkill -f pi` — use targeted PID or port-specific checks
- Dev instance processes are under `MINIONS_HOME=/tmp/minions-dev` — identify by cwd/env
- Host stack = `MINIONS_HOME=~/.minions` (or unset), ports 20128/7352
- CI/test scripts must scope kills to dev ports only

---

## Development

Run tests:

```bash
# Install shellcheck
# Ubuntu/Debian: apt-get install shellcheck
# macOS: brew install shellcheck

./tests/test_install.sh
./tests/test_boot.sh
```

---

## Implementation Phases

| Phase | Scope | Test Gate | Status |
|-------|-------|-----------|--------|
| **0** | Fix blockers B1–B7 in `lib/detect.sh` + `etc/versions.env` | real install dry-run | ✅ **DONE** |
| **1** | LLM Proxies: `install.sh` installs OmniRoute + ModelRelay via npm; `boot.sh` backgrounds + preconfigures them; readiness marker | `boot.sh` → status.sh ✅ | ✅ **DONE** |
| **2** | Hermes CLI: preinstall via official git install script; `install.sh` runs `hermes config set` block; `boot.sh` does NOT start gateway | `hermes --version` + `hermes config get` ✅ | ✅ **DONE** |
| **3** | Pi-Agent: npm install + `pi-failover` ext + mnemon Pi extension + config symlinks | `pi --version` + `pi config` ✅ | ✅ **DONE** |
| **4** | Mnemon: binary + seed import (both Hermes + Pi) | `mnemon status` ✅ | ✅ **DONE** |
| **5** | Full integration test + CI + docs | CI green | 🔄 **IN PROGRESS** |

---

## License

MIT