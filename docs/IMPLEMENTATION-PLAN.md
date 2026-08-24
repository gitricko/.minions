# Implementation Plan: .minions Bootstrap v1

**Version:** v4 (aligned with Lavish board v4)  
**Branch:** `fm/save-minions-v1-implementation`  
**Reference:** `hermes-codespace/.devcontainer/post-create-cmd.sh` + `start-hermes.sh` + `pi-config/`  

---

## Overview

Portable, oh-my-zsh-style bootstrap for a self-contained AI coding stack at `~/.minions`.  
First iteration: Linux (x86_64 + arm64) — Codespace + GitHub runner. macOS later.

---

## Phased Implementation

Each phase has a clear test gate. Next phase only starts after previous phase's gate passes.

### Phase 0: Blocker Fixes (Prerequisite)
**Files:** `lib/detect.sh`, `etc/versions.env`, `lib/uv.sh`, `lib/pi.sh`

| Task | Details |
|------|---------|
| B1: Pi URL | `lib/pi.sh` → `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` |
| B2: Prereqs | `install.sh` → detect Node≥22.22.2 + npm + uv; vendor if missing |
| B3: uv URL | `lib/uv.sh` → map platform → Rust triple (`uv-x86_64-unknown-linux-gnu.tar.gz`) |
| B4: Checksums | `etc/versions.env` → pin real SHA256 for all components |
| B5: Ready marker | `boot.sh` → `touch $MINIONS_HOME/var/run/ready` after healthy |
| B6: --daemon | **DROPPED** — remove from arg parse, `boot.sh` returns after bg |
| B7: get_sha256 case | `lib/detect.sh:96` → uppercase component before `eval` |

**Gate:** `install.sh --dry-run` passes + real install in sandbox (`HOME=/tmp/test MINIONS_HOME=/tmp/test/.minions ./install.sh`) completes without 404/unbound errors.

---

### Phase 1: LLM Proxies (OmniRoute + ModelRelay)
**Files:** `install.sh`, `boot.sh`, `lib/npm_packages.sh`, `lib/omniroute.sh`, `lib/process.sh`, `etc/minions.env`

#### install.sh
- [ ] Detect Node.js ≥22.22.2 + npm (vendor if missing)
- [ ] `npm install -g --prefix $MINIONS_HOME/lib/omniroute omniroute@3.8.49`
- [ ] `npm install -g --prefix $MINIONS_HOME/lib/modelrelay modelrelay@1.18.0`
- [ ] Symlink `bin/omniroute` → `$MINIONS_HOME/lib/omniroute/bin/omniroute`
- [ ] Symlink `bin/modelrelay` → `$MINIONS_HOME/lib/modelrelay/bin/modelrelay`
- [ ] Copy `etc/minions.env.template` → `etc/minions.env` with port defaults

#### boot.sh
- [ ] Background OmniRoute: `setsid $MINIONS_HOME/bin/omniroute --no-open >> $MINIONS_HOME/var/log/omniroute.log 2>&1 &`
- [ ] Background ModelRelay: `setsid $MINIONS_HOME/bin/modelrelay >> $MINIONS_HOME/var/log/modelrelay.log 2>&1 &`
- [ ] Wait for health: `wait_for_port $OMNIROUTE_PORT` + `wait_for_health http://localhost:$OMNIROUTE_PORT/v1/models`
- [ ] Wait for health: `wait_for_port $MODELRELAY_PORT` + `wait_for_health http://localhost:$MODELRELAY_PORT/v1/models`
- [ ] **OmniRoute preconfig** (via `lib/omniroute.sh`):
  - [ ] sqlite: `UPDATE key_value SET value='false' WHERE key='requireLogin'`
  - [ ] `omniroute combo create auto-fastest --strategy auto`
  - [ ] PUT `/api/combos/<id>` with models + retry config
  - [ ] Enable MCP: `curl -X PATCH /api/settings -d '{"mcpEnabled":true}'`
  - [ ] `hermes mcp add omniroute --command omniroute --args --mcp` (if Hermes installed)
- [ ] `touch $MINIONS_HOME/var/run/ready`
- [ ] Print READY banner, **return** (no --daemon)

#### stop.sh
- [ ] Kill by PID file, clean `var/run/ready`

#### status.sh
- [ ] Check `var/run/ready` + port health → ✅/❌

**Gate:** `./boot.sh && ./status.sh` → both proxies ✅, readiness marker exists.

---

### Phase 2: Hermes CLI
**Files:** `install.sh`, `lib/hermes.sh`, `lib/uv.sh`, `lib/mnemon.sh`

#### install.sh
- [ ] Install uv (via `lib/uv.sh` — Rust triple, real checksum)
- [ ] `uv venv $MINIONS_HOME/lib/hermes/venv --python 3.11`
- [ ] `uv pip install --python $MINIONS_HOME/lib/hermes/venv/bin/python hermes-agent@v2026.8.13`
- [ ] Symlink `bin/hermes` → `$MINIONS_HOME/lib/hermes/venv/bin/hermes`
- [ ] **Hermes config set block** (reads `$OMNIROUTE_PORT`, `$MODELRELAY_PORT`):
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

**Gate:** `hermes --version` → v2026.8.13; `hermes config get model.provider` → omniroute; `hermes config get fallback_providers.provider` → modelrelay.

---

### Phase 3: Pi-Agent
**Files:** `install.sh`, `lib/pi.sh`, `lib/mnemon.sh`, `etc/pi/`

#### install.sh
- [ ] `npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.2`
- [ ] Symlink `bin/pi` → npm global bin (or `$MINIONS_HOME/lib/pi/bin/pi`)
- [ ] `pi install git:github.com/gitricko/pi-failover@hermes-impl`
- [ ] **Config symlinks:** `etc/pi/{models,settings}.json` → `~/.pi/agent/`
  - `models.json`: `defaultProvider: omniroute`, `modelrelay` fallback
  - `settings.json`: `defaultProvider: omniroute`, `defaultModel: auto-fastest`
- [ ] **Mnemon Pi extension:** `mnemon setup --target pi --global --yes`
  - Skill: `~/.pi/agent/skills/mnemon/SKILL.md`
  - Extension: `~/.pi/agent/extensions/mnemon.ts`

**Gate:** `pi --version` → 0.84.2; `pi config` shows omniroute + modelrelay; mnemon skill/extension present in `~/.pi/agent/`.

---

### Phase 4: Mnemon (Both Hermes + Pi)
**Files:** `install.sh`, `lib/mnemon.sh`, `etc/seed.json`

#### install.sh
- [ ] Download mnemon binary (GitHub releases, real checksum) → `$MINIONS_HOME/bin/mnemon`
- [ ] `mnemon import --dry-run $MINIONS_HOME/etc/seed.json` → validate
- [ ] `mnemon import $MINIONS_HOME/etc/seed.json`
- [ ] Pi mnemon already done in Phase 3

#### etc/seed.json
- [ ] Architecture facts (this plan)
- [ ] Version pins
- [ ] Key decisions (D1–D4 resolved)
- [ ] Blocker list + fixes
- [ ] Port configurability rules
- [ ] Process safety rules

**Gate:** `mnemon status` shows insights imported; `mnemon recall "minions"` returns relevant facts.

---

### Phase 5: Full Integration + CI
**Files:** `install.sh`, `boot.sh`, `stop.sh`, `status.sh`, `tests/`, `.github/workflows/ci.yml`

#### Integration test
- [ ] `MINIONS_HOME=/tmp/integration-test OMNIROUTE_PORT=20129 MODELRELAY_PORT=7353 ./install.sh`
- [ ] `./boot.sh`
- [ ] `./status.sh` → all ✅
- [ ] `./stop.sh` → clean
- [ ] `mnemon recall "minions"` works

#### CI (`.github/workflows/ci.yml`)
- [ ] Codespace Linux runner: full install+boot+status (env ports)
- [ ] GitHub ubuntu-latest: same, with vendored Node/uv
- [ ] Path-filter: full build for `install.sh`/`boot.sh`/`lib/`/`etc/`; lint for docs
- [ ] Shellcheck on all scripts

**Gate:** CI green on both runners.

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

## Deliverables (Docs)

| File | Status |
|------|--------|
| `README.md` | ✅ Updated (this commit) |
| `docs/scout-report-minions-v1.md` | ✅ Updated (this commit) |
| `docs/IMPLEMENTATION-PLAN.md` | ✅ This file |
| `docs/PLAN-v4.md` | ✅ Markdown export from Lavish |
| `etc/versions.env` | ✅ Real pins + checksums (Phase 0) |
| `lib/detect.sh` | ✅ B1/B3/B7 fixes (Phase 0) |

---

## Handoff Checklist

- [ ] Phase 0 blockers fixed
- [ ] Phase 1: OmniRoute + ModelRelay install + boot + preconfig + readiness
- [ ] Phase 2: Hermes CLI preinstall + config block
- [ ] Phase 3: Pi-Agent npm + extensions + config symlinks
- [ ] Phase 4: Mnemon binary + seed import (both)
- [ ] Phase 5: Full integration test + CI green
- [ ] All docs updated
- [ ] PR opened against `main` with squash commits per phase

---

*Ready for Phase 0 implementation.*