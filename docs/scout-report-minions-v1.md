# Scout Report: .minions Bootstrap v1 — Implementation Plan (v4 aligned)

**Status:** Planning complete — ready for phased implementation  
**Branch:** `fm/save-minions-v1-implementation` (to be created from current worktree)  
**Reference:** `hermes-codespace/.devcontainer/post-create-cmd.sh` + `start-hermes.sh` + `pi-config/`  
**Date:** 2026-08-24  

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

---

## Phase Plan (Iterative, Test-Gated)

| Phase | Goal | Entrypoint | Verification |
|-------|------|------------|--------------|
| **0** | Fix blockers in existing scaffolding | `lib/detect.sh`, `etc/versions.env` | `install.sh --dry-run` + real install in sandbox |
| **1** | LLM Proxies (OmniRoute + ModelRelay) | `install.sh` → npm installs; `boot.sh` → bg + preconfig | `status.sh` ✅ both proxies healthy |
| **2** | Hermes CLI (preinstall + config) | `install.sh` → uv venv + `hermes config set` block | `hermes --version` + `hermes config get` |
| **3** | Pi-Agent (npm + extensions + config) | `install.sh` → npm + `pi-failover@hermes-impl` + mnemon Pi ext + symlinks | `pi --version` + `pi config` |
| **4** | Mnemon (binary + seed import for both) | `install.sh` → mnemon binary + seed import | `mnemon status` (both stores) |
| **5** | Full integration + CI | `install.sh` + `boot.sh` + `status.sh` | CI green on Codespace + GitHub runner Linux |

---

## Blocker Fixes (Phase 0 — from prior scout report)

| # | Bug | Location | Fix |
|---|-----|----------|-----|
| B1 | Pi URL 404 (Bun) | `lib/detect.sh:69` | `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` |
| B2 | node/npm/uv prereq | `install.sh` | detect + vendor/install if missing |
| B3 | uv URL 404 | `lib/detect.sh:54-64` | Map platform → Rust triple (`uv-x86_64-unknown-linux-gnu.tar.gz`) |
| B4 | placeholder checksums | `etc/versions.env` | Pin real: Hermes v2026.8.13, OmniRoute 3.8.49, ModelRelay 1.18.0, Pi 0.84.2 |
| B5 | readiness marker | `boot.sh` | `touch $MINIONS_HOME/var/run/ready` after healthy |
| B6 | --daemon | — | **DROPPED** — `setsid … &` + return |
| B7 | get_sha256 case | `lib/detect.sh:96` | uppercase component before `eval` |

---

## Implementation Details per Phase

### Phase 1: LLM Proxies
**install.sh:**
- Detect Node.js ≥22.22.2 + npm; vendor if missing
- `npm install -g --prefix $MINIONS_HOME/lib/omniroute omniroute@3.8.49`
- `npm install -g --prefix $MINIONS_HOME/lib/modelrelay modelrelay@1.18.0`
- Symlink `bin/omniroute` → `$MINIONS_HOME/lib/omniroute/bin/omniroute`
- Symlink `bin/modelrelay` → `$MINIONS_HOME/lib/modelrelay/bin/modelrelay`

**boot.sh:**
- `setsid $MINIONS_HOME/bin/omniroute --no-open >> $MINIONS_HOME/var/log/omniroute.log 2>&1 &`
- `setsid $MINIONS_HOME/bin/modelrelay >> $MINIONS_HOME/var/log/modelrelay.log 2>&1 &`
- Wait for `/v1/models` → 200 on both ports (`$OMNIROUTE_PORT`, `$MODELRELAY_PORT`)
- **OmniRoute preconfig:** sqlite `requireLogin=false`; create combo `auto-fastest` (strategy auto); PUT models + retry config; enable MCP; `hermes mcp add omniroute` (if Hermes installed)
- `touch $MINIONS_HOME/var/run/ready`

### Phase 2: Hermes CLI
**install.sh:**
- Install uv (Rust triple mapping, real checksum)
- `uv venv $MINIONS_HOME/lib/hermes/venv --python 3.11`
- `uv pip install --python $MINIONS_HOME/lib/hermes/venv/bin/python hermes-agent@v2026.8.13`
- Symlink `bin/hermes` → `$MINIONS_HOME/lib/hermes/venv/bin/hermes`
- **Hermes config set block** (reads `OMNIROUTE_PORT` / `MODELRELAY_PORT`):
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

### Phase 3: Pi-Agent
**install.sh:**
- `npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.2`
- Symlink `bin/pi` → npm global bin
- `pi install git:github.com/gitricko/pi-failover@hermes-impl`
- **Pi config symlinks:** `etc/pi/{models,settings}.json` → `~/.pi/agent/`
  - `models.json`: `defaultProvider: omniroute`, `modelrelay` fallback chain
  - `settings.json`: `defaultProvider: omniroute`, `defaultModel: auto-fastest`
- **Mnemon Pi extension:** `mnemon setup --target pi --global --yes` (skill + TypeScript extension)

### Phase 4: Mnemon
**install.sh:**
- Download mnemon binary (GitHub releases, real checksum) → `$MINIONS_HOME/bin/mnemon`
- `mnemon import --dry-run $MINIONS_HOME/etc/seed.json` → validate → `mnemon import`
- Pi mnemon already installed in Phase 3

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
- **Skill:** `/home/codespace/.pi/agent/skills/mnemon/SKILL.md`
- **Extension:** `/home/codespace/.pi/agent/extensions/mnemon.ts` (hooks: `resources_discover`, `before_agent_start`, `agent_end`, `session_before_compact`)
- **Prompts:** `/home/codespace/.mnemon/prompt/` (guide.md, skill.md)

This is the pattern to replicate in `.minions/install.sh`.

---

## Seed.json Content

Mirror `hermes-codespace/.devcontainer/mnemon/seed.json` but for .minions stack:
- Architecture facts (this plan)
- Version pins
- Key decisions (D1–D4 resolved)
- Blocker list + fixes
- Port configurability rules
- Process safety rules

---

## CI Strategy

| Runner | Test |
|--------|------|
| Codespace Linux | `./install.sh && ./boot.sh && ./status.sh` (env ports) |
| GitHub runner Linux (ubuntu-latest) | Same, with vendored Node/uv |

Path-filtered: full build only for `install.sh`/`boot.sh`/`lib/`/`etc/` changes; lint for docs.

---

## Handoff Checklist (for next agent)

- [ ] Phase 0 blockers fixed (`lib/detect.sh`, `etc/versions.env`)
- [ ] Phase 1: OmniRoute + ModelRelay install + boot + preconfig + readiness
- [ ] Phase 2: Hermes CLI preinstall + config block
- [ ] Phase 3: Pi-Agent npm + extensions + config symlinks
- [ ] Phase 4: Mnemon binary + seed import (both)
- [ ] Phase 5: Full integration test + CI green
- [ ] All docs updated (README, this report, PLAN-v4.md)
- [ ] PR opened against `main` with squash commits per phase

---

## Files to Create / Update

| File | Purpose |
|------|---------|
| `README.md` | Project vision + quickstart + phases (this commit) |
| `docs/scout-report-minions-v1.md` | This file (updated to reflect v4 plan) |
| `docs/IMPLEMENTATION-PLAN.md` | Detailed phase breakdown (this commit) |
| `docs/PLAN-v4.md` | Markdown export of Lavish board v4 (this commit) |
| `etc/versions.env` | Real version pins + checksums |
| `lib/detect.sh` | B1/B3/B7 fixes |
| `install.sh` | Full implementation per phases |
| `boot.sh` | Full implementation + `--doctor` |
| `stop.sh` / `status.sh` | Updated for readiness marker |
| `tests/` | Real install/boot integration tests (network-mocked) |
| `.github/workflows/ci.yml` | CI pipeline |

---

*Captain: v4 plan is approved. Ready to commit to branch and begin Phase 0.*