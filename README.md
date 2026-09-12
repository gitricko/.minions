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

## Installing from a Specific Branch (for testing PRs / dev branches)

The standard one-liner installs from `main`. To install from a specific branch (e.g. to test a PR before merge), use the **`INSTALL_URL`** pattern:

```bash
# Export the raw install.sh URL from the branch you want to test
export INSTALL_URL="https://github.com/gitricko/.minions/raw/refs/heads/fix/dev-mode-hermes-wiring/install.sh"

# Run via bash -c "$(curl ...)" — this correctly propagates INSTALL_URL to the bootstrap
bash -c "$(curl -fsSL "$INSTALL_URL")"

# Or with a custom HOME (for isolated testing)
HOME=/custom/path bash -c "$(curl -fsSL "$INSTALL_URL")"
```

**Why `bash -c "$(curl ...)"` instead of `curl ... | bash`?**

| Pattern | Problem |
|---------|---------|
| `curl ... \| bash` | Env vars (`HOME`, `INSTALL_URL`) only apply to `curl`, not the piped `bash` — install goes to wrong location and branch detection fails |
| `bash -c "$(curl ...)"` | Parent shell env propagates; `HOME` set once; clean stdin; branch tarball auto-derived |

The bootstrap preamble detects `INSTALL_URL` and auto-derives the branch tarball URL:
```
/raw/ → /archive/     # GitHub raw → archive
/install.sh → .tar.gz # install.sh → tarball
```

So you only set the **install.sh** URL — the correct **branch tarball** is fetched automatically.

---

## Components

| Component | Kind | Runs How | v1 Status |
|-----------|------|----------|-----------|
| **OmniRoute** | persistent service | `setsid omniroute serve --no-open &` (vendored Node wrapper) + combo preconfig at boot | ✅ npm OK |
| **ModelRelay** | persistent service | `setsid modelrelay &` (vendored Node wrapper) | ✅ npm OK |
| **Pi-Agent** | CLI tool | invoked by **user or automation** (GitHub runner / firstmate) | ✅ npm OK |
| **Hermes** | CLI tool | preinstalled to `~/.hermes`; used as CLI | ✅ git install OK |
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

### Custom ports (in preference to defaults)
```bash
# Override default ports before running install.sh / boot.sh
export OMNIROUTE_PORT=20129
export MODELRELAY_PORT=7353
./install.sh
~/.minions/boot.sh
```

---

## Configuration

Config templates live in `~/.minions/etc/`; **install copies them to each component's
standard location** (no symlinks, no runtime config file).

| File | Purpose | Installed To |
|------|---------|--------------|
| `versions.env` | Pinned component versions (lockfile) | `~/.minions/etc/versions.env` |
| `pi.toml` | Pi-Agent config (port-interpolated) | `~/.pi/agent/pi.toml` |
| `models.json` | Pi-Agent models (port-interpolated) | `~/.pi/agent/models.json` |
| `mnemon-seed-pi.json` | Mnemon seed data for Pi-Agent | import at install |
| `mnemon-seed-hermes.json` | Mnemon seed data for Hermes | import at install |
| — | Hermes config (written inline w/ ports) | `~/.hermes/config.yaml` |
| — | OmniRoute setup (login off, password) | `~/.config/omniroute/` (sqlite) |

Key environment variables:

```bash
OMNIROUTE_PORT=20128                 # OmniRoute port (env-overridable)
MODELRELAY_PORT=7352                 # ModelRelay port (env-overridable)
MINIONS_LLM_BASE_URL=http://localhost:20128/v1  # Default proxy for Pi/Hermes
```

---

## Architecture

```text
~/.minions/
├── install.sh          # One-time bootstrap: installs binaries + copies/interpolates configs
├── boot.sh             # Starts the two services + OmniRoute combo, touches readiness marker
├── stop.sh             # Stop the stack
├── status.sh           # Health check + readiness marker
├── bin/                # Entries on PATH: wrappers (omniroute/modelrelay/pi) + symlinks (hermes/mnemon)
├── lib/                # Helper scripts + vendored runtimes
│   ├── detect.sh       # OS/arch + download URLs + SHA256
│   ├── download.sh     # curl/wget + sha256 verify + extract
│   ├── node.sh         # Node.js 22.22.2 vendoring
│   ├── uv.sh           # uv vendoring (Rust triple mapping)
│   ├── pi.sh           # Pi-Agent install (npm @earendil-works/pi-coding-agent)
│   ├── hermes.sh       # Hermes install (official git install script)
│   ├── npm_packages.sh # OmniRoute + ModelRelay (npm --prefix)
│   ├── omniroute.sh    # OmniRoute combo preconfig (at boot)
│   ├── mnemon.sh       # Mnemon binary + seed import
│   └── process.sh      # start/stop/wait_for_port/wait_for_health
├── etc/                # Configuration templates + versions.env lockfile
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
- Configures Hermes (`hermes config set` block: provider=custom:omniroute, fallback=modelrelay, mnemon, approvals off)
- Installs Mnemon binary + seed import + Pi mnemon extension (skill + TypeScript extension)

---

## Preconfiguration (The Real Work)

`install.sh` handles all config at install time; `boot.sh` only starts services and
creates the OmniRoute `auto-fastest` combo (which needs a running server).

| Component | Preconfiguration | When |
|-----------|------------------|------|
| **OmniRoute** | `setup --non-interactive --password`; disable `requireLogin` (sqlite) | install |
| **OmniRoute** | create combo `auto-fastest` (strategy auto) via `combo create` | boot (needs running server) |
| **Hermes** | write `~/.hermes/config.yaml`: provider omniroute, model auto-fastest, base_url `${OR_PORT}/v1`, modelrelay `${MR_PORT}/v1` | install |
| **Pi** | copy+interpolate `etc/{pi.toml,models.json}` → `~/.pi/agent/` (omniroute provider, modelrelay fallback); install `pi-failover` ext | install |
| **Mnemon** | install binary; seed import from `etc/mnemon-seed-*.json` | install |

All preconfiguration reads `OMNIROUTE_PORT` / `MODELRELAY_PORT` (env-overridable with
defaults) so it targets the right ports.

---

## Port Configurability

`OMNIROUTE_PORT` (default 20128) and `MODELRELAY_PORT` (default 7352) are env-overridable.
Set them in your shell before `install.sh` **and** `boot.sh` to use non-default ports:

```bash
export OMNIROUTE_PORT=20129
export MODELRELAY_PORT=7353
./install.sh && ~/.minions/boot.sh
```

There is **one install location (`~/.minions`)**. For isolated dev testing, use the
[DTS container](#development) instead of a second install — it provides clean isolation.

---

## Process Safety

`boot.sh`/`stop.sh`/`status.sh` use PID files in `~/.minions/var/run/` and targeted
`kill` by PID — they never `pkill -f hermes` or `pkill -f pi`. Use `stop.sh` to stop the
stack cleanly; the CLI tools (pi/hermes) are not daemons and are never killed.

---

## Development

Run tests:

```bash
# Install shellcheck
# Ubuntu/Debian: apt-get install shellcheck
# macOS: brew install shellcheck

./tests/test_install.sh          # shellcheck + permissions; real install if CI_REAL_INSTALL=1
./tests/test_boot.sh             # shellcheck + permissions; DTS if CI_DTS_TEST=1
./tests/test_cli_integration.sh  # real-stack CLI checks (CI_REAL_INSTALL=1)

# Full-stack end-to-end in a clean Docker container (DTS) - the primary test path
bash tests/test_dts.sh           # requires docker; runs install → boot → health → chat → stop
```

DTS (Docker Test Shell) is the recommended way to test: it runs install → boot → health
→ chat completion → stop in a **fresh** `ubuntu:24.04` container (`scripts/dts.sh`),
eliminating host state pollution. This is wired into CI via the `dts-integration` job.

---

## Implementation Phases

| Phase | Scope | Test Gate | Status |
|-------|-------|-----------|--------|
| **0** | Fix blockers B1–B7 in `lib/detect.sh` + `etc/versions.env` | real install dry-run | ✅ **DONE** (PR #3) |
| **1** | LLM Proxies: `install.sh` installs OmniRoute + ModelRelay via npm; `boot.sh` backgrounds + preconfigures them; readiness marker | `boot.sh` → status.sh ✅ | ✅ **DONE** (PR #4) |
| **2** | Hermes CLI: preinstall via official git install script; `install.sh` runs `hermes config set` block; `boot.sh` does NOT start gateway | `hermes --version` + `hermes config get` ✅ | ✅ **DONE** (PR #5, #16) |
| **3** | Pi-Agent: npm install + `pi-failover` ext + config symlinks + mnemon Pi extension | `pi --version` + `pi config` ✅ | ✅ **DONE** (PR #6, #17) |
| **4** | Mnemon: binary + seed import (both Hermes + Pi) | `mnemon status` ✅ | ✅ **DONE** (PR #7) |
| **5** | Full integration test + CI + docs | CI green | ✅ **DONE** (PR #8) |

---

## Problem History & Lessons Learned (Detailed)

### The Longest Debugging Sessions

#### 1. **Pi "Unknown provider omniroute" — Config Path Mismatch (Days)**
**Problem:** `pi -p 'hello'` returned `Unknown provider "omniroute"` in CI, but worked locally.
**Root Cause:** Pi reads config from `~/.pi/agent/` (via `getAgentDir()` in `pi-coding-agent/dist/config.js:417-428`), but our `lib/pi.sh` was writing symlinks/config to `~/.pi/`. The local Codespace had pre-existing hermes-codespace symlinks masking the bug.
**Fix:** Changed all symlink targets and config writes in `lib/pi.sh` (`create_pi_symlinks()`, `pi_update_config()`) from `~/.pi/` → `~/.pi/agent/`. Updated test paths accordingly.
**Commit:** `80e2c9c` (PR #17)
**Lesson:** Always verify the actual config directory of external tools — don't assume standard locations. The Pi source code was the definitive reference.

#### 2. **Hermes "No inference provider configured" — Wrong Provider Name (Hours)**
**Problem:** `hermes chat -q 'hello'` prompted "No inference provider is configured yet" even after preconfig.
**Root Cause:** We set `model.provider = auto-fastest` (a combo inside OmniRoute), but Hermes expects a provider name. Valid providers from `hermes doctor`: `custom:omniroute`, `custom:modelrelay`, `openai`, `anthropic`, etc. `auto-fastest` is a *model* within the `custom:omniroute` provider.
**Fix:** `lib/hermes.sh` `hermes_preconfigure()` now sets:
```bash
model.provider = custom:omniroute
model.default  = auto-fastest
```
And `hermes_update_config()` writes `custom_providers` as a YAML **list** (not dict):
```yaml
custom_providers:
  - name: omniroute
    base_url: http://127.0.0.1:20128/v1
  - name: modelrelay
    base_url: http://127.0.0.1:7352/v1
```
**Commits:** `88f3f4d`, `f23cb0e` (PR #16)
**Lesson:** Read the tool's own diagnostics (`hermes doctor`) instead of guessing. The config schema matters — dict vs list broke Hermes.

#### 3. **npm `--ignore-scripts` Prevented Binary Linking (Hours)**
**Problem:** OmniRoute/ModelRelay/Pi binaries weren't found after `npm install -g --prefix --ignore-scripts`.
**Root Cause:** `--ignore-scripts` skips `postinstall` scripts that create binary symlinks in `node_modules/.bin/`.
**Fix:** Removed `--ignore-scripts` in `lib/npm_packages.sh` and `lib/pi.sh`. Added CI env vars to suppress playwright postinstall prompt:
```bash
export CI=true
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
export PUPPETEER_SKIP_DOWNLOAD=1
```
**Commits:** `53d42c5`, various in PR #14

#### 4. **ModelRelay `--version` Hangs (Hours)**
**Problem:** `modelrelay --version` never returns, blocking install verification.
**Root Cause:** Upstream ModelRelay bug — `--version` waits for something.
**Fix:** Added `timeout 10s` in CI verification. The wrapper doesn't call `--version` at runtime.
**Lesson:** Always bound version checks with timeout.

#### 5. **Boot.sh Redundant Pi Extension Install (Minutes)**
**Problem:** `boot.sh` called `pi install pi-failover` every boot, causing timeout.
**Root Cause:** Extension was already installed in `install.sh`. Boot only needs to reload/verify.
**Fix:** `boot.sh` Step 5c trimmed to only `pi_update_config` (essential). Removed `extensions reload`, `extensions list`, `--list-models` calls.
**Commit:** `a7d4d40`

#### 6. **Hermes Config Directory Mismatch (Minutes)**
**Problem:** `hermes_preconfigure` wrote to `${HOME}/.hermes/` but Hermes installed to `HERMES_HOME_OVERRIDE`.
**Fix:** `hermes_preconfigure()` now uses same config-discovery logic as `hermes_update_config()` — checks `HERMES_HOME` first.
**Commit:** `3146873`

#### 7. **Stale Local Install Masking Bugs (Ongoing)**
**Problem:** User's `~/.minions` was from before fixes; `hermes` fell back to system hermes at `~/.local/bin/hermes`.
**Lesson:** Always test fresh install. CI is the truth — it installs fresh every run.

---

## Common Pitfalls (For Future Agents)

| Pitfall | Symptom | Prevention |
|---------|---------|------------|
| Config dir mismatch | Tool says "unknown provider" but config looks right | Verify tool's actual config dir (source code > docs) |
| YAML list vs dict | `hermes doctor` complains, chat fails | Match schema exactly — list with `name`/`base_url` |
| npm `--ignore-scripts` | Binaries missing after install | Don't use `--ignore-scripts` for tools needing postinstall |
| Port collision | Dev stack kills host stack | Always use `MINIONS_HOME` + env ports for dev |
| Stale local install | "It works in CI but not locally" | Reinstall fresh: `rm -rf ~/.minions && ./install.sh` |
| Provider name vs model | "No inference provider" prompt | Check `hermes doctor` for valid provider names |
| Extension not loaded | Pi can't use provider | Verify extension install + config `provider = "omniroute"` |

---

## License

MIT