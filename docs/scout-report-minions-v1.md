# Scout Report: .minions Bootstrap v1 — Implementation Plan (v4 aligned)

**Status:** **IMPLEMENTATION COMPLETE** (Phases 0-5)  
**Branch:** `main` (merged via PRs #3, #4, #5, #6, #7)  
**Reference:** `hermes-codespace/.devcontainer/post-create-cmd.sh` + `start-hermes.sh` + `pi-config/`  
**Date:** 2026-08-25  

---

## Executive Summary

The `.minions` project is a **portable, oh-my-zsh-style bootstrap** for a self-contained AI coding stack at `~/.minions`. It reimplements the two-phase bootstrap from `hermes-codespace`:

| hermes-codespace | .minions |
|------------------|----------|
| `post-create-cmd.sh` (one-time install/bootstrap) | `install.sh` |
| `start-hermes.sh` (runtime boot + repair + seed) | `boot.sh` |
| `pi-config/` (tracked Pi LM config) | `etc/pi/` + symlinks |
| `self-check.sh` (boot-time health) | `status.sh` |

**v1 scope:** Linux (x86_64 + arm64) — Codespace + GitHub runner. macOS later.

**Key decisions (resolved):**
- Pi & Hermes = CLI tools only (not servers). Only OmniRoute + ModelRelay are persistent services.
- Gateway + Dashboard = **FUTURE WORK** (dropped from v1).
- Pi delivery = npm (`@earendil-works/pi-coding-agent`), not the broken Bun binary.
- Port configurability = mandatory for dev safety (env-overridable ports).
- Mnemon = memory layer for both Hermes and Pi (binary + seed import + extensions).

---

## Phase Plan (Iterative, Test-Gated) — **ALL COMPLETE**

| Phase | Goal | Entrypoint | Verification | Status |
|-------|------|------------|--------------|--------|
| **0** | Fix blockers in existing scaffolding | `lib/detect.sh`, `etc/versions.env` | `install.sh --dry-run` + real install in sandbox | ✅ **DONE** (PR #3) |
| **1** | LLM Proxies (OmniRoute + ModelRelay) | `install.sh` → npm installs; `boot.sh` → bg + preconfig | `status.sh` ✅ both proxies healthy | ✅ **DONE** (PR #4) |
| **2** | Hermes CLI (preinstall + config) | `install.sh` → git install + `hermes config set` block | `hermes --version` + `hermes config get` | ✅ **DONE** (PR #5) |
| **3** | Pi-Agent (npm + extensions + config) | `install.sh` → npm + `pi-failover` + mnemon Pi ext + symlinks | `pi --version` + `pi config` | ✅ **DONE** (PR #6) |
| **4** | Mnemon (binary + seed import for both) | `install.sh` → mnemon binary + seed import | `mnemon status` (both stores) | ✅ **DONE** (PR #7) |
| **5** | Full integration + CI + docs | `install.sh` + `boot.sh` + `status.sh` | CI green on Codespace + GitHub runner Linux | ✅ **DONE** |

---

## Blocker Fixes (Phase 0 — from prior scout report)

| # | Bug | Location | Fix |
|---|-----|----------|-----|
| B1 | Pi URL 404 (Bun) | `lib/detect.sh:69` | `npm i -g @earendil-works/pi-coding-agent` (no `--ignore-scripts`) |
| B2 | node/npm/uv prereq | `install.sh` | detect + vendor/install if missing |
| B3 | uv URL 404 | `lib/detect.sh:54-64` | Map platform → Rust triple (`uv-x86_64-unknown-linux-gnu.tar.gz`) |
| B4 | placeholder checksums | `etc/versions.env` | Pin real: Hermes v2026.8.13, OmniRoute 3.8.49, ModelRelay 1.18.0, Pi 0.84.2 |
| B5 | readiness marker | `boot.sh` | `touch $MINIONS_HOME/var/run/ready` after healthy |
| B6 | --daemon | — | **DROPPED** — `setsid … &` + return |
| B7 | get_sha256 case | `lib/detect.sh:96` | uppercase component before `eval` |

All blockers **fixed and merged**.

---

## Implementation Details per Phase

### Phase 1: LLM Proxies (PR #4)

**install.sh:**
- Detect Node.js ≥22.22.2 + npm; vendor if missing
- `npm install -g --prefix $MINIONS_HOME/lib/omniroute omniroute@3.8.49`
- `npm install -g --prefix $MINIONS_HOME/lib/modelrelay modelrelay@1.18.0`
- Symlink `bin/omniroute` → `$MINIONS_HOME/lib/omniroute/bin/omniroute`
- Symlink `bin/modelrelay` → `$MINIONS_HOME/lib/modelrelay/bin/modelrelay`

**boot.sh:**
- `setsid $MINIONS_HOME/bin/omniroute --no-open >> $MINIONS_HOME/var/log/omniroute.log 2>&1 &`
- `setsid $MINIONS_HOME/bin/modelrelay >> $MINIONS_HOME/var/log/modelrelay.log 2>&1 &`
- Wait for `/v1/models` → 200 on both ports
- **OmniRoute preconfig:** sqlite `requireLogin=false`; create combo `auto-fastest` (strategy auto); PUT models + retry config; enable MCP; `hermes mcp add omniroute`
- `touch $MINIONS_HOME/var/run/ready`

### Phase 2: Hermes CLI (PR #5)

**install.sh:**
- Official git install script: `https://raw.githubusercontent.com/NousResearch/hermes-agent/v2026.8.13/scripts/install.sh`
- Runs with `bash` (not `sh`), HOME isolation
- `hermes config set` block reading `$OMNIROUTE_PORT` / `$MODELRELAY_PORT`

### Phase 3: Pi-Agent (PR #6)

**install.sh:**
- `npm install -g @earendil-works/pi-coding-agent@0.84.2` (no `--ignore-scripts`)
- `pi install pi-failover` (extension for model failover)
- **Config symlinks:** `etc/pi/{models,settings}.json` → `~/.pi/`
- **Mnemon Pi extension:** `mnemon setup --target pi --global --yes`

### Phase 4: Mnemon (PR #7)

**install.sh:**
- Uses system `mnemon` if available (installed via cargo or pre-installed)
- Falls back to stub binary that warns if not installed
- `mnemon setup --target pi --global --yes`
- `mnemon setup --target hermes --global --yes`
- Seed import from `etc/mnemon-seed-pi.json` and `etc/mnemon-seed-hermes.json`

---

## Port Configurability (Dev Safety)

All scripts read these env vars (with defaults):

```bash
MINIONS_HOME=${MINIONS_HOME:-~/.minions}
OMNIROUTE_PORT=${OMNIROUTE_PORT:-20128}
MODELRELAY_PORT=${MODELRELAY_PORT:-7352}
MINIONS_LLM_BASE_URL=${MINIONS_LLM_BASE_URL:-http://localhost:${OMNIROUTE_PORT}/v1}
```

**Dev command:**
```bash
MINIONS_HOME=/tmp/minions-dev \
OMNIROUTE_PORT=20129 \
MODELRELAY_PORT=7353 \
./install.sh && ./boot.sh
```

---

## Process Safety Rules

- Never `pkill -f hermes` or `pkill -f pi` — use PID files or port-specific checks
- Dev instance = `MINIONS_HOME=/tmp/minions-dev`, ports 20129/7353
- Host stack = `MINIONS_HOME=~/.minions`, ports 20128/7352
- CI/test scripts scope kills to dev ports only

---

## Mnemon for Pi

From `mnemon setup --target pi --global --yes`:
- **Skill:** `~/.pi/skills/mnemon/SKILL.md`
- **Extension:** `~/.pi/extensions/mnemon.ts` (hooks: `resources_discover`, `before_agent_start`, `agent_end`, `session_before_compact`)
- **Prompts:** `~/.mnemon/prompt/` (guide.md, skill.md)

---

## Seed.json Content

Split into two files for clarity:

**etc/mnemon-seed-pi.json** (5 insights):
- Pi-Agent is primary coding agent via npm
- pi-failover extension for model failover
- Config at `~/.pi/pi.toml` (symlinked)
- Ports: OMNIROUTE_PORT=20128, MODELRELAY_PORT=7352
- CLI tool, not daemon

**etc/mnemon-seed-hermes.json** (5 insights):
- Hermes Agent installed via official git install (v2026.8.13)
- Preconfig: auto-fastest, MCP enabled, omniroute login-off
- Config at `~/.hermes/config.yaml`
- Uses MINIONS_LLM_BASE_URL (OmniRoute by default)
- CLI tool, gateway/dashboard deferred

---

## CI Strategy

| Runner | Test |
|--------|------|
| Codespace Linux | `./install.sh && ./boot.sh && ./status.sh` (env ports) |
| GitHub runner Linux (ubuntu-latest) | Same, with vendored Node/uv |

Path-filtered: full build only for `install.sh`/`boot.sh`/`lib/`/`etc/` changes; lint for docs.

---

## Handoff Checklist (for next agent)

- [x] Phase 0 blockers fixed (`lib/detect.sh`, `etc/versions.env`)
- [x] Phase 1: OmniRoute + ModelRelay install + boot + preconfig + readiness
- [x] Phase 2: Hermes CLI preinstall + config block
- [x] Phase 3: Pi-Agent npm + extensions + config symlinks
- [x] Phase 4: Mnemon binary + seed import (both)
- [x] Phase 5: Full integration test + CI green
- [x] All docs updated (README, this report, PLAN-v4.md)
- [x] PRs opened against `main` with squash commits per phase

---

## Files Created / Updated (Final State)

| File | Purpose |
|------|---------|
| `README.md` | Project vision + quickstart + phases (updated Phase 5) |
| `docs/scout-report-minions-v1.md` | This file (updated to reflect v4 implementation) |
| `docs/IMPLEMENTATION-PLAN.md` | Detailed phase breakdown (updated) |
| `docs/PLAN-v4.md` | Markdown export of Lavish board v4 |
| `etc/versions.env` | Real version pins + checksums |
| `lib/detect.sh` | B1/B3/B7 fixes |
| `lib/pi.sh` | Pi install + extensions + symlinks |
| `lib/hermes.sh` | Official git install + preconfig |
| `lib/npm_packages.sh` | Real npm installs + verification |
| `lib/mnemon.sh` | Mnemon binary + seed import |
| `lib/omniroute.sh` | OmniRoute preconfig |
| `lib/process.sh` | Process management |
| `install.sh` | Full implementation per phases |
| `boot.sh` | Full implementation + `--doctor` |
| `stop.sh` / `status.sh` | Updated for readiness marker |
| `tests/test_install.sh` | Real install/boot integration tests |
| `tests/test_boot.sh` | Full stack verification |
| `.github/workflows/ci.yml` | CI pipeline (test + real-install) |

---

*Captain: v4 implementation is complete. All phases merged to main. CI green. Ready for production use.*