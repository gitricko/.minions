# Implementation Plan: .minions Bootstrap v1

**Version:** v4 (aligned with Lavish board v4)  
**Branch:** `main` (all phases merged)  
**Reference:** `hermes-codespace/.devcontainer/post-create-cmd.sh` + `start-hermes.sh` + `pi-config/`  

---

## Overview

Portable, oh-my-zsh-style bootstrap for a self-contained AI coding stack at `~/.minions`.  
First iteration: Linux (x86_64 + arm64) — Codespace + GitHub runner. macOS later.

---

## Phased Implementation — **ALL COMPLETE**

Each phase had a clear test gate. Next phase only started after previous phase's gate passed.

### Phase 0: Blocker Fixes (Prerequisite) ✅ **DONE** (PR #3)
**Files:** `lib/detect.sh`, `etc/versions.env`, `lib/uv.sh`, `lib/pi.sh`

| Task | Details | Status |
|------|---------|--------|
| B1: Pi URL | `lib/pi.sh` → `npm i -g @earendil-works/pi-coding-agent` (no `--ignore-scripts`) | ✅ |
| B2: Prereqs | `install.sh` → detect Node≥22.22.2 + npm + uv; vendor if missing | ✅ |
| B3: uv URL | `lib/uv.sh` → map platform → Rust triple | ✅ |
| B4: Checksums | `etc/versions.env` → pin real SHA256 for all components | ✅ |
| B5: Ready marker | `boot.sh` → `touch $MINIONS_HOME/var/run/ready` after healthy | ✅ |
| B6: --daemon | **DROPPED** — remove from arg parse, `boot.sh` returns after bg | ✅ |
| B7: get_sha256 case | `lib/detect.sh:96` → uppercase component before `eval` | ✅ |

**Gate:** `install.sh --dry-run` passes + real install in sandbox completes without 404/unbound errors. ✅

---

### Phase 1: LLM Proxies (OmniRoute + ModelRelay) ✅ **DONE** (PR #4)
**Files:** `install.sh`, `boot.sh`, `lib/npm_packages.sh`, `lib/omniroute.sh`, `lib/process.sh`, `etc/minions.env`

#### install.sh
- [x] Detect Node.js ≥22.22.2 + npm (vendor if missing)
- [x] `npm install -g --prefix $MINIONS_HOME/lib/omniroute omniroute@3.8.49`
- [x] `npm install -g --prefix $MINIONS_HOME/lib/modelrelay modelrelay@1.18.0`
- [x] Symlink `bin/omniroute` → `$MINIONS_HOME/lib/omniroute/bin/omniroute`
- [x] Symlink `bin/modelrelay` → `$MINIONS_HOME/lib/modelrelay/bin/modelrelay`
- [x] Copy `etc/minions.env.template` → `etc/minions.env` with port defaults

#### boot.sh
- [x] Background OmniRoute: `setsid $MINIONS_HOME/bin/omniroute --no-open >> $MINIONS_HOME/var/log/omniroute.log 2>&1 &`
- [x] Background ModelRelay: `setsid $MINIONS_HOME/bin/modelrelay >> $MINIONS_HOME/var/log/modelrelay.log 2>&1 &`
- [x] Wait for health: `wait_for_port $OMNIROUTE_PORT` + `wait_for_health http://localhost:$OMNIROUTE_PORT/v1/models`
- [x] Wait for health: `wait_for_port $MODELRELAY_PORT` + `wait_for_health http://localhost:$MODELRELAY_PORT/v1/models`
- [x] **OmniRoute preconfig** (via `lib/omniroute.sh`):
  - [x] sqlite: `UPDATE key_value SET value='false' WHERE key='requireLogin'`
  - [x] `omniroute combo create auto-fastest --strategy auto`
  - [x] PUT `/api/combos/<id>` with models + retry config
  - [x] Enable MCP: `curl -X PATCH /api/settings -d '{"mcpEnabled":true}'`
  - [x] `hermes mcp add omniroute --command omniroute --args --mcp` (if Hermes installed)
- [x] `touch $MINIONS_HOME/var/run/ready`
- [x] Print READY banner, **return** (no --daemon)

#### stop.sh
- [x] Kill by PID file, clean `var/run/ready`

#### status.sh
- [x] Check `var/run/ready` + port health → ✅/❌

**Gate:** `./boot.sh && ./status.sh` → both proxies ✅, readiness marker exists. ✅

---

### Phase 2: Hermes CLI ✅ **DONE** (PR #5)
**Files:** `install.sh`, `lib/hermes.sh`, `lib/uv.sh`, `lib/mnemon.sh`

#### install.sh
- [x] Install uv (via `lib/uv.sh` — Rust triple, real checksum) — **replaced by official git install**
- [x] Official git install script: `https://raw.githubusercontent.com/NousResearch/hermes-agent/v2026.8.13/scripts/install.sh`
- [x] Runs with `bash` (not `sh`), HOME isolation
- [x] Symlink `bin/hermes` → install location
- [x] **Hermes config set block** (reads `$OMNIROUTE_PORT`, `$MODELRELAY_PORT`):
  ```bash
  hermes config set model.default auto-fastest
  hermes config set model.provider omniroute
  hermes config set providers.omniroute.base_url http://localhost:${OMNIROUTE_PORT}/v1
  hermes config set providers.omniroute.api_key no-key-needed
  hermes config set providers.modelrelay.base_url http://localhost:${MODELRELAY_PORT}/v1
  hermes config set providers.modelrelay.api_key no-key-needed
  hermes config set fallback_providers.provider modelrelay
  hermes config set fallback_providers.model auto-fastest
  hermes config set auxiliary.title_generation.model auto-fastest
  hermes config set auxiliary.title_generation.provider modelrelay
  hermes config set auxiliary.vision.model auto-fastest
  hermes config set auxiliary.vision.provider modelrelay
  hermes config set auxiliary.compression.model auto-fastest
  hermes config set auxiliary.compression.provider modelrelay
  hermes config set approvals.mode off
  hermes config set memory.memory_enabled true
  hermes config set memory.user_profile_enabled true
  hermes config set memory.provider mnemon
  hermes config set agent.max_turns 120
  hermes config set kanban.failure_limit 3
  ```

**Gate:** `hermes --version` → v2026.8.13; `hermes config get model.provider` → omniroute; `hermes config get fallback_providers.provider` → modelrelay. ✅

---

### Phase 3: Pi-Agent ✅ **DONE** (PR #6)
**Files:** `install.sh`, `lib/pi.sh`, `lib/mnemon.sh`, `etc/pi/`

#### install.sh
- [x] `npm install -g @earendil-works/pi-coding-agent@0.84.2` (no `--ignore-scripts`)
- [x] Symlink `bin/pi` → npm global bin
- [x] `pi install pi-failover` (extension for model failover)
- [x] **Config symlinks:** `etc/pi/{models,settings}.json` → `~/.pi/`
  - `models.json`: `defaultProvider: omniroute`, `modelrelay` fallback
  - `settings.json`: `defaultProvider: omniroute`, `defaultModel: auto-fastest`
- [x] **Mnemon Pi extension:** `mnemon setup --target pi --global --yes`
  - Skill: `~/.pi/skills/mnemon/SKILL.md`
  - Extension: `~/.pi/extensions/mnemon.ts`

**Gate:** `pi --version` → 0.84.2; `pi config` shows omniroute + modelrelay; mnemon skill/extension present in `~/.pi/`. ✅

---

### Phase 4: Mnemon (Both Hermes + Pi) ✅ **DONE** (PR #7)
**Files:** `install.sh`, `lib/mnemon.sh`, `etc/mnemon-seed-pi.json`, `etc/mnemon-seed-hermes.json`

#### install.sh
- [x] Uses system `mnemon` if available (installed via cargo or pre-installed)
- [x] Falls back to stub binary that warns if not installed
- [x] `mnemon setup --target pi --global --yes`
- [x] `mnemon setup --target hermes --global --yes`
- [x] Seed import from `etc/mnemon-seed-pi.json` and `etc/mnemon-seed-hermes.json`

#### etc/mnemon-seed-pi.json
- [x] Architecture facts
- [x] Version pins
- [x] Key decisions
- [x] Blocker list + fixes
- [x] Port configurability rules

#### etc/mnemon-seed-hermes.json
- [x] Architecture facts
- [x] Version pins
- [x] Key decisions
- [x] Blocker list + fixes
- [x] Port configurability rules

**Gate:** `mnemon status` shows insights imported; `mnemon recall "minions"` returns relevant facts. ✅

---

### Phase 5: Full Integration + CI + Docs ✅ **DONE** (this PR)
**Files:** `install.sh`, `boot.sh`, `stop.sh`, `status.sh`, `tests/`, `.github/workflows/ci.yml`, `README.md`, `docs/`

#### Integration test
- [x] `MINIONS_HOME=/tmp/integration-test OMNIROUTE_PORT=20129 MODELRELAY_PORT=7353 ./install.sh`
- [x] `./boot.sh`
- [x] `./status.sh` → all ✅
- [x] `./stop.sh` → clean
- [x] `mnemon recall "minions"` works

#### CI (`.github/workflows/ci.yml`)
- [x] Codespace Linux runner: full install+boot+status (env ports)
- [x] GitHub ubuntu-latest: same, with vendored Node/uv
- [x] Path-filter: full build for `install.sh`/`boot.sh`/`lib/`/`etc/`; lint for docs
- [x] Shellcheck on all scripts

**Gate:** CI green on both runners. ✅

#### Docs
- [x] `README.md` — complete rewrite with vision, objectives, architecture, quickstart, config
- [x] `docs/scout-report-minions-v1.md` — updated to reflect actual implementation
- [x] `docs/IMPLEMENTATION-PLAN.md` — this file, updated with phase status
- [x] `docs/PLAN-v4.md` — current

---

## Port Configurability (All Phases)

Every script reads:
```bash
MINIONS_HOME=${MINIONS_HOME:-~/.minions}
OMNIROUTE_PORT=${OMNIROUTE_PORT:-20128}
MODELRELAY_PORT=${MODELRELAY_PORT:-7352}
MINIONS_LLM_BASE_URL=${MINIONS_LLM_BASE_URL:-http://localhost:${OMNIROUTE_PORT}/v1}
```

Dev command (parallel stack, no host collision):
```bash
MINIONS_HOME=/tmp/minions-dev \
OMNIROUTE_PORT=20129 \
MODELRELAY_PORT=7353 \
./install.sh && ./boot.sh
```

---

## Process Safety Rules (All Phases)

- Never `pkill -f hermes` or `pkill -f pi` — use PID files or port-specific checks
- Dev instance = `MINIONS_HOME=/tmp/minions-dev`, ports 20129/7353
- Host stack = `MINIONS_HOME=~/.minions`, ports 20128/7352
- CI/test scripts scope kills to dev ports only

---

## Deliverables (Docs) — **ALL COMPLETE**

| File | Status |
|------|--------|
| `README.md` | ✅ Updated (Phase 5) |
| `docs/scout-report-minions-v1.md` | ✅ Updated (Phase 5) |
| `docs/IMPLEMENTATION-PLAN.md` | ✅ This file |
| `docs/PLAN-v4.md` | ✅ Markdown export from Lavish |
| `etc/versions.env` | ✅ Real pins + checksums (Phase 0) |
| `lib/detect.sh` | ✅ B1/B3/B7 fixes (Phase 0) |

---

## Handoff Checklist

- [x] Phase 0 blockers fixed
- [x] Phase 1: OmniRoute + ModelRelay install + boot + preconfig + readiness
- [x] Phase 2: Hermes CLI preinstall + config block
- [x] Phase 3: Pi-Agent npm + extensions + config symlinks
- [x] Phase 4: Mnemon binary + seed import (both)
- [x] Phase 5: Full integration test + CI green
- [x] All docs updated
- [x] PRs opened against `main` with squash commits per phase

---

*Captain: v4 implementation is complete. All phases merged to main. CI green. Ready for production use.*