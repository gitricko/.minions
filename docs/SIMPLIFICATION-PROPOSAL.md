# Simplification Proposal: .minions Install & Boot

**Date:** September 8, 2026  
**Status:** Draft — awaiting review  
**Goal:** Remove multi-instance complexity now that DTS provides clean test isolation

---

## Executive Summary

The current architecture supports **multiple concurrent instances** via `MINIONS_HOME`, `OMNIROUTE_PORT`, `MODELRELAY_PORT` overrides — originally for dev-testing alongside a host stack. **DTS (Docker Test Shell) eliminates this need** by providing clean, isolated containers. We can simplify dramatically by:

1. **Removing multi-instance support** — single install at `~/.minions` (no `MINIONS_HOME` override, no `--minions-home` flag)
2. **Keeping port env vars with defaults** — `OMNIROUTE_PORT=20128`, `MODELRELAY_PORT=7352` as env-overridable defaults (users can set in `~/.bashrc` before install)
3. **Using default config locations** — no custom `etc/` directory, no symlinks
4. **Consolidating preconfiguration** — move all config to install-time, boot only starts services
5. **Reducing wrapper/script indirection** — fewer files, simpler logic

---

## Current Complexity (What to Remove)

| Area | Current | Problem |
|------|---------|---------|
| **Multi-instance** | `MINIONS_HOME`, `OMNIROUTE_PORT`, `MODELRELAY_PORT` env vars everywhere | `MINIONS_HOME` override obsolete (DTS); ports keep as env-overridable defaults |
| **Config location** | `${MINIONS_HOME}/etc/` + symlinks to `~/.pi/agent/` + `${HERMES_HOME}/config.yaml` | 3 different config locations, fragile |
| **Install-time config** | `install.sh` copies templates, then `boot.sh` updates them again | Two-phase config, race conditions |
| **Wrapper scripts** | `lib/hermes.sh` + `lib/pi.sh` create wrappers setting env vars | Indirection, path bugs (see DTS learnings) |
| **Port propagation** | Ports passed through install → minions.env → boot → hermes_update_config → pi_update_config | 5+ hops for port values |

---

## Proposed Simplified Architecture

### 1. Single Install Location, Env-Configurable Ports

```bash
# Default port configuration (env-overridable)
# Users can set these in ~/.bashrc BEFORE running install.sh
OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"
MODELRELAY_PORT="${MODELRELAY_PORT:-7352}"
```

```
~/.minions/                    # Fixed, no MINIONS_HOME override
├── install.sh                 # One-time bootstrap (reads OMNIROUTE_PORT, MODELRELAY_PORT)
├── boot.sh                    # Start services only (reads same ports)
├── stop.sh                    # Stop services
├── bin/                       # Direct symlinks to component binaries
├── lib/                       # Helper libs only (no wrappers)
│   ├── detect.sh
│   ├── download.sh
│   ├── node.sh
│   ├── uv.sh
│   ├── npm_packages.sh        # OmniRoute, ModelRelay install
│   ├── omniroute.sh           # Preconfig only (idempotent)
│   ├── mnemon.sh
│   └── process.sh
├── etc/                       # Config templates (copied at install)
│   ├── versions.env           # Version lockfile
│   ├── pi.toml                # Pi-Agent config template
│   ├── models.json            # Pi-Agent models template
│   ├── settings.json          # Pi-Agent settings template
│   ├── mnemon-seed-hermes.json
│   └── mnemon-seed-pi.json
├── var/
│   ├── run/                   # PID files
│   └── log/
└── workspace/
```

### 2. Config at Standard Locations (Install Copies Templates)

| Component | Config Location | How Set |
|-----------|----------------|---------|
| **OmniRoute** | SQLite at `~/.config/omniroute/omniroute.db` | `omniroute_preconfigure()` at install |
| **ModelRelay** | None needed (flags only) | Started with `--port ${MODELRELAY_PORT}` |
| **Hermes** | `~/.hermes/config.yaml` | `hermes_preconfigure()` at install |
| **Pi-Agent** | `~/.pi/agent/{pi.toml,models.json,settings.json}` | Install copies from `etc/` + interpolates ports |
| **Mnemon** | `~/.config/mnemon/` | Binary + seed import at install |

**No `minions.env` runtime config. No symlinks. No port interpolation at boot.** `etc/` holds templates only — install copies and interpolates ports once.

### 3. Install.sh Does Everything Once

```bash
# Simplified install.sh flow:
1. Create ~/.minions/{bin,lib,var/run,var/log,workspace}
2. Source etc/versions.env for pinned versions
3. Install vendored Node.js (if needed) + uv
4. Install Mnemon binary + seed import
5. Install Pi-Agent via npm → wrapper ~/.minions/bin/pi
6. Install OmniRoute + ModelRelay via npm → wrappers in bin/
7. Install Hermes via official script → symlink ~/.minions/bin/hermes → hermes binary
8. Install pi-failover extension (pipelines CLI commands, no proxy needed)
9. COPY + INTERPOLATE CONFIGS (using OMNIROUTE_PORT / MODELRELAY_PORT):
   - etc/pi.toml → ~/.pi/agent/pi.toml (sed ports)
   - etc/models.json → ~/.pi/agent/models.json (sed ports)
   - Create ~/.hermes/config.yaml with provider/ports
   - omniroute setup: set default password + disable requireLogin (writes sqlite, no server)
   - Mnemon seed import
10. Add PATH snippet to ~/.bashrc and ~/.zshrc
```

### 4. Boot.sh Only Starts Services (plus one OmniRoute combo)

```bash
# Simplified boot.sh flow:
1. Source ~/.minions/lib/process.sh
2. Read OMNIROUTE_PORT (default 20128), MODELRELAY_PORT (default 7352)
3. start_service omniroute → ~/.minions/bin/omniroute serve --port ${OMNIROUTE_PORT} --no-open
4. start_service modelrelay → ~/.minions/bin/modelrelay --port ${MODELRELAY_PORT}
5. wait_for_port + wait_for_health
6. omniroute_preconfigure (create auto-fastest combo — REQUIRES a running server)
7. Touch readiness marker
8. Print status
```

**No config updates. No hermes_update_config. No pi_update_config.**

`omniroute_preconfigure` runs **at boot, not install**, by design: it creates the
`auto-fastest` combo via the `combo create` CLI, which is a client command that needs
the OmniRoute server running. Login-off (`setup` + disable `requireLogin`) IS done at
install time because it writes sqlite directly and needs no server.

### 5. Wrappers Only Where npm Needs Vendored Node

- `~/.minions/bin/omniroute` → wrapper exec'ing the npm binary under vendored Node 22.22.2
- `~/.minions/bin/modelrelay` → wrapper exec'ing the npm binary under vendored Node 22.22.2
- `~/.minions/bin/hermes` → symlink to Hermes-installed binary
- `~/.minions/bin/pi` → wrapper exec'ing the Pi npm binary under vendored Node 22.22.2
- `~/.minions/bin/mnemon` → symlink to Mnemon binary

The npm packages (OmniRoute, ModelRelay, Pi) require Node **22.22.2** (they have
compatibility issues with Node 24+), so a **direct symlink is not sufficient** — a thin
wrapper sets `PATH`/`NODE_PATH` to the vendored Node prefix and exec's the real binary.
This is a deliberate deviation from "direct binaries only": those three need the runtime
bootstrap. Hermes and Mnemon (standalone binaries) are plain symlinks, no wrapper.

---

## Files to Delete / Simplify

| File | Action |
|------|--------|
| `etc/minions.env` | **Delete** — no runtime config file needed |
| `etc/pi.toml`, `etc/models.json`, `etc/settings.json` | **Keep as templates** — install copies + interpolates ports to `~/.pi/agent/` |
| `etc/versions.env` | **Keep** — version lockfile only |
| `etc/mnemon-seed-*.json` | **Keep** — seed templates |
| `lib/hermes.sh` | **Simplify** — remove `hermes_update_config`, `hermes_preconfigure` (move to install.sh) |
| `lib/pi.sh` | **Simplify** — remove `pi_update_config`, `create_pi_symlinks`, wrapper (install copies templates) |
| `lib/omniroute.sh` | **Keep** — `omniroute_preconfigure()` used at install |
| `lib/mnemon.sh` | **Keep** — used at install |
| `lib/process.sh` | **Keep** — used by boot/stop |
| `boot.sh` | **Simplify** — remove config update steps, remove omniroute_preconfigure |
| `install.sh` | **Simplify** — remove `--minions-home`, `--dry-run`, two-phase config; keep port env vars; copy templates |

---

## Concrete Changes

### install.sh — Remove:
- `--minions-home` argument
- `--dry-run` mode (test via DTS instead)
- `hermes_update_config` / `pi_update_config` calls at end
- PATH snippet using `${MINIONS_HOME}` variable → hardcode `~/.minions`

### install.sh — Keep (with defaults):
- `OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"`
- `MODELRELAY_PORT="${MODELRELAY_PORT:-7352}"`
- Read these env vars at start, use for all preconfiguration

### install.sh — Add:
- Copy config templates from `etc/` to `~/.pi/agent/` with port interpolation
- Create `~/.hermes/config.yaml` with provider/ports inline
- Install pi-failover extension (no proxy needed, just pipelines CLI)

### boot.sh — Remove:
- Lines 100-103 (source minions.env)
- Lines 106-108 (re-derive URLs)
- Lines 155-165 (omniroute_preconfigure)
- Lines 170-186 (hermes_update_config, pi_update_config, hermes_preconfigure)
- `INSTALL_HERMES` reference

### boot.sh — Keep (with defaults):
- `OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"`
- `MODELRELAY_PORT="${MODELRELAY_PORT:-7352}"`
- Use these for starting services only

### lib/hermes.sh — Remove:
- `hermes_update_config()` function
- `hermes_preconfigure()` function (move to install.sh)
- Keep: `install_hermes()`, `ensure_hermes()`

### lib/pi.sh — Remove:
- `pi_update_config()` function
- `create_pi_symlinks()` function
- `install_pi_failover_ext()` (move to install.sh)
- Wrapper script generation (use direct symlink)
- Keep: `install_pi()`, `ensure_pi()`

---

## Testing with DTS

The DTS skill makes this verifiable:

```bash
# From repo root
./scripts/dts.sh up
./scripts/dts.sh apt "curl git ca-certificates xz-utils g++ make sqlite3 python3 python3-yaml"
./scripts/dts.sh exec "bash /src/install.sh"
./scripts/dts.sh exec "bash /home/ubuntu/.minions/boot.sh"
./scripts/dts.sh exec "hermes --version && pi --version && mnemon --version"
./scripts/dts.sh exec "hermes chat -q 'Reply with exactly: OK'"
./scripts/dts.sh clean
```

**No more port/config env var juggling. DTS provides the isolation.**

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Breaks dev workflow (running alongside host stack) | Dev can use DTS containers instead |
| Hardcoded ports conflict with other tools | Ports are env-overridable (`OMNIROUTE_PORT=20129 ./install.sh`) |
| Hermes/Pi config at non-standard locations | Using their **default** locations (~/.hermes, ~/.pi/agent) |
| Mnemon seed import path | Standard `~/.config/mnemon/` |

---

## Test Changes

The existing tests (`test_install.sh`, `test_boot.sh`, `test_cli_integration.sh`) will need updates to match the simplified architecture.

### test_install.sh
- **Remove**: `--dry-run` mode test (DTS replaces this)
- **Remove**: `--minions-home` argument test
- **Remove**: Config file copy verification (`etc/minions.env`, `etc/pi.toml`, etc.)
- **Remove**: `MINIONS_HOME` env var test
- **Keep**: shellcheck test, script permissions test
- **Add**: Verify configs written to standard locations (`~/.hermes/config.yaml`, `~/.pi/agent/`, `~/.config/omniroute/`)
- **Add**: Verify direct symlinks in `~/.minions/bin/` (no wrappers)
- **Real install test**: Run `./install.sh` (no args), verify binaries work

### test_boot.sh
- **Remove**: Mock `minions.env` setup (no runtime config file)
- **Remove**: Port verification from `minions.env` (ports are env vars with defaults)
- **Remove**: OmniRoute preconfig dry-run test (preconfig now at install)
- **Keep**: PID file creation/removal for `omniroute`/`modelrelay`
- **Keep**: Readiness marker test
- **Keep**: `stop.sh` and `status.sh` tests
- **Simplify**: Boot test just starts services with env vars, checks ports

### test_cli_integration.sh
- **Remove**: `--minions-home` argument handling
- **Remove**: Config path checks for `${MINIONS_HOME}/etc/` and `${MINIONS_HOME}/lib/hermes/home/config.yaml`
- **Update**: Hermes config check → `~/.hermes/config.yaml`
- **Update**: Pi config check → `~/.pi/agent/{pi.toml,models.json}`
- **Update**: Port verification uses `OMNIROUTE_PORT`/`MODELRELAY_PORT` env vars (with defaults)
- **Simplify**: Fresh install just runs `./install.sh`, boot runs `./boot.sh`

### DTS as Primary Test Path

Add a new test target that runs the full stack in DTS:

```bash
# New: tests/test_dts.sh (or integrate into CI)
# Runs install → boot → CLI verification in fresh container
./scripts/dts.sh up
./scripts/dts.sh apt "curl git ca-certificates xz-utils g++ make sqlite3 python3 python3-yaml"
./scripts/dts.sh exec "bash /src/install.sh"
./scripts/dts.sh exec "bash /home/ubuntu/.minions/boot.sh"
./scripts/dts.sh exec "hermes --version && pi --version && mnemon --version"
./scripts/dts.sh exec "hermes chat -q 'Reply with exactly: OK'"
./scripts/dts.sh exec "pi -p 'Reply with exactly: OK' --provider omniroute --model omniroute/auto-fastest"
./scripts/dts.sh clean
```

This replaces the complex mock-based tests with real integration testing.

---

## Migration Path

1. **Branch** from main
2. **Simplify install.sh** (remove multi-instance, inline preconfig)
3. **Simplify lib/hermes.sh, lib/pi.sh** (remove update/preconfig functions)
4. **Simplify boot.sh** (remove config updates)
5. **Delete etc/minions.env, etc/pi.toml, etc/models.json, etc/settings.json**
6. **Test via DTS** (fresh container, full install → boot → verify)
7. **Verify** `hermes chat -q` and `pi -p` work keyless via OmniRoute

---

## Estimated Effort

- **~200 lines removed** from install.sh
- **~150 lines removed** from lib/hermes.sh + lib/pi.sh  
- **~30 lines removed** from boot.sh
- **4 config files deleted**
- **Net reduction: ~400 lines, 4 files, significant cognitive load**

---

## Open Questions for Review

1. **Boot-time OmniRoute preconfig:** RESOLVED — runs at boot, not install. `combo create auto-fastest` needs a running server (client command).
2. **Pi failover extension:** RESOLVED — installed at install.sh via `pi install git:...` (CLI only, no proxy).
3. **Dry-run removal:** RESOLVED — removed; DTS is the verification path.
4. **Config interpolation:** RESOLVED — install copies `etc/` templates to standard locations with port interpolation.
