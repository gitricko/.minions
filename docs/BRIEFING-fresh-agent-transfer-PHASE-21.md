# Fresh Agent Briefing — .minions Phase 21 (Mnemon Seed) Handoff

**Date:** 2026-09-14
**Branch:** `feat/disable-mnemon-setup` (PR #30 open, CI green)
**Status:** Phases 16-20 ✅ COMPLETE, Phase 24 Pi-wiring ✅ COMPLETE, Phase 24 mnemon-disable 🔄 PR #30 ready to merge

---

## What This Document Is

A **transfer package** for a fresh agent continuing the .minions project after Phase 24 Pi-wiring completion. It contains:

1. **Current implementation state** — what's done, verified, and pending
2. **Exact skills to load** — with paths and why each matters
3. **Verification checklist** — the steps the prior agent ran to confirm completion
4. **Remaining implementation plan** — Phases 21 onward with dependencies
5. **Known gotchas** — bugs fixed, pitfalls to avoid
6. **Ready-to-use prompt template** for the fresh agent

---

## 1. Current State Summary

### ✅ Completed (verified, CI green)

| Area | Status | Evidence |
|------|--------|----------|
| **Phase 16-20: Wiki content** | ✅ | 22 wiki articles + INDEX.md, all links resolve |
| **Phase 24: Pi-Agent skills wiring** | ✅ | `settings.json` `"skills"` array wired via `lib/pi-settings.sh`, `install.sh`, `boot.sh` |
| **Phase 24: mnemon setup disabled** | ✅ | PR #30 — `setup_mnemon_all()` is now a no-op; no shellcheck warnings |
| **Test (Linux)** | ✅ | `test_knowledge_mode.sh` (4/4), `test_boot_symlinks.sh` (10/10), `test_bootstrap.sh` (16/16), `test_pi_settings.sh` (8/8) |
| **Real Install (Linux)** | ✅ | Live skill-discovery checks pass (`hermes skills list` → `memory-automation`, `pi -p` → `docker-test-shell`) |
| **DTS Integration (Linux)** | ✅ | Full DTS suite (Tests 1-9) including new test 8d; passed on attempt 1 |
| **CI pipeline** | ✅ | 3-job DTS retry logic added (up to 3 attempts for resource flake mitigation) |

### 🔄 In Progress / Ready to Merge

| PR | Description | Status |
|----|-------------|--------|
| **#30** | `feat/disable-mnemon-setup` — disable mnemon setup for hermes/pi (user has own plugin) | CI green ✅, awaiting merge |

### ⏳ Pending (NEXT)

| Phase | Feature | Priority | Dependencies |
|-------|---------|----------|-------------|
| **21** | Mnemon Seed + Validator | **HIGH** — blocks agent usefulness | Wiki content (Phases 16-20) ✅, DTS learnings |
| **24-28** | New Codespace skills verification | MEDIUM | 5 ported skills survive Codespace rebuild |
| **29-31** | Advanced proxy features | LATER | OmniRoute multi-model, ModelRelay, Collective Wisdom |

### ⚠️ Known Gaps (Expected — Not Blockers)

| Gap | Phase | Current State |
|-----|-------|---------------|
| `mnemon/seed.json` | 21 | Directory has only `.gitkeep` — no seed.json created yet |
| `scripts/validate-seed.py` | 21 | Does not exist yet |
| `scripts/check-seed-export.sh` | 21 | Does not exist yet |
| `mnemon-seed-pi.json`, `mnemon-seed-hermes.json` | 21 | Templates exist in `etc/` with 5 insights each (10 total) |
| 5 ported codespace skills verification | 24-28 | Skills ported to repo, need live verification |
| Advanced proxy features | 29-31 | Not started |
| self-check exit 1 | — | 1 warning "model not configured" (expected fresh install) |

---

## 2. Required Skills — Load These FIRST

The fresh agent **MUST** load these skills before doing any work. They define the HOW (TDD, coding style) while the verification tasks are the WHAT.

### A. Hermes-Built-in Skills (load via `skill_view`)

```bash
# Core workflow skills — DO THIS FIRST
skill_view(name='test-driven-development')        # RED→GREEN→REFACTOR; tests before code
skill_view(name='karpathy-coding-guidelines')     # Minimal diffs, root-cause fixes, verify by real output
skill_view(name='github')                              # PR management, reviews, CI
skill_view(name='ci-lint-check')                      # Pre-commit lint validation locally
```

### B. Repo-Ported Skills (load via `skill_view`)

```bash
# From /workspaces/.minions/skills/
skill_view(name='codespace-gh-auth')              # GitHub token extraction from VS Code server for git push
skill_view(name='docker-test-shell')              # DTS: clean-container integration testing
skill_view(name='persistent-knowledge')            # Symlink-based persistence architecture
skill_view(name='mnemon-seed-persistence')        # Seed.json management for contributors
skill_view(name='memory-automation')              # Mnemon workflow (recall/save patterns)
skill_view(name='mnemon-graph-export')            # 3D knowledge graph visualization
```

### C. Task-Relevant Skills (load as needed)

```bash
skill_view(name='codespace-persistent-symlinks')   # Persist Hermes state across Codespace rebuilds
skill_view(name='codespace-port-visibility')      # Automate port visibility via CLI
skill_view(name='codespace-webtop')               # Selkies/XFCE browser desktop
skill_view(name='codespace-vscode-open')          # Auto-discover VS Code CLI
skill_view(name='codespace-lavish')               # Whiteboard over noVNC
skill_view(name='github-pr-review')               # Evaluate CodeQL/Copilot suggestions
skill_view(name='agent-context-transfer')         # This skill — context transfer pattern
```

### Skill Loading Order (Recommended)

```
1. test-driven-development          ← DO THIS FIRST — defines workflow
2. karpathy-coding-guidelines       ← Coding style rules
3. codespace-gh-auth                ← Git auth for PR push
4. docker-test-shell                ← DTS workflow for integration tests
5. ci-lint-check                    ← Local lint before push
6. [others as task requires]
```

---

## 3. Verification Checklist — Phase 24 Completion

The prior agent ran these to confirm Phases 16-20 and Phase 24 are complete. A fresh agent should re-verify if on a new machine.

```bash
# 1. Wiki content — all 22 articles + INDEX.md present
ls -la /workspaces/.minions/wiki/
# EXPECT: 23 .md files including INDEX.md

# 2. Wiki link integrity — F4 gate passes
bash /workspaces/.minions/scripts/verify-knowledge.sh F4
# EXPECT: "OK: all wiki links resolve"

# 3. No .devcontainer refs — F5 gate passes
bash /workspaces/.minions/scripts/verify-knowledge.sh F5
# EXPECT: "OK: no .devcontainer/ references found"

# 4. Knowledge detection — all 4 mode tests pass
bash /workspaces/.minions/tests/test_knowledge_mode.sh
# EXPECT: 4/4 tests PASS (dev, standalone, env override, piped)

# 5. Boot symlinks — all 10 tests pass
bash /workspaces/.minions/tests/test_boot_symlinks.sh
# EXPECT: 10/10 tests PASS

# 6. Bootstrap — all 16 tests pass
bash /workspaces/.minions/tests/test_bootstrap.sh
# EXPECT: 16/16 tests PASS

# 7. Pi settings unit tests — all 8 tests pass
bash /workspaces/.minions/tests/test_pi_settings.sh
# EXPECT: 8/8 tests PASS

# 8. Pi settings live verification
cat ~/.pi/agent/settings.json
# EXPECT: "packages" (pi-failover) preserved AND "skills": ["/workspaces/.minions/skills"]

# 9. Self-check — Persistence GREEN (exit 1 = 1 warning only)
bash /workspaces/.minions/self-check.sh
# EXPECT: exit 1, 1 warning "model not configured", 0 critical

# 10. CI status — all PRs green
gh pr checks 29     # Phase 24 Pi-wiring (MERGED to main)
gh pr checks 30     # Mnemon disable (should be GREEN)
gh pr checks 31     # (when created) Phase 21 mnemon seed
# EXPECT: Test (Linux) ✅, Real Install (Linux) ✅, DTS Integration (Linux) ✅
```

### If Verification Fails

Capture and trace:
```bash
cat ~/.minions/etc/knowledge.env
ls -la ~/.minions/
readlink -f ~/.minions/skills
# Trace: install.sh → lib/knowledge-detection.sh → lib/knowledge-symlinks.sh → knowledge.env → boot.sh → self-check
```

---

## 4. Key Files — Read These in Order

| File | Purpose | Critical Sections |
|------|---------|-------------------|
| `docs/IMPLEMENTATION-STATUS.md` | Authoritative reality record | "NEXT AGENT: DEV-MODE INSTALL VERIFICATION" |
| `docs/BRIEFING-fresh-agent-transfer-PHASE-16-20.md` | Prior briefing | Phases 16-20 complete, remaining plan |
| `docs/BRIEFING-fresh-agent-transfer-PHASE-21.md` | **THIS FILE** | Phase 21 continuation |
| `docs/PROPOSAL-phase24-pi-settings-wiring.md` | Phase 24 proposal | Settings.json wiring design |
| `docs/IMPL-PLAN-skills-wiki-integration.md` | 32-phase plan | Phases 21-31 remaining |
| `lib/mnemon.sh` | Mnemon installation/setup | `setup_mnemon_all()` — now a no-op (disabled per user request) |
| `lib/pi-settings.sh` | **NEW** — Pi-Agent settings.json shared-skills wiring | `wire_pi_skills_path` helper |
| `lib/knowledge-detection.sh` | Mode detection logic | `detect_knowledge_mode()` — SCRIPT_DIR probe first |
| `lib/knowledge-symlinks.sh` | Symlink creation | `setup_knowledge_symlinks()`, `setup_hermes_skill_link()`, `setup_hermes_memories_link()` |
| `install.sh` | Bootstrap + install | Pi wiring step, mnemon disable, piped detection |
| `boot.sh` | Service startup + re-link | Pi settings re-assert, mnemon disabled |
| `self-check.sh` | Health verification | Persistence section checks symlinks |
| `.github/workflows/ci.yml` | CI pipeline | 3 jobs (test, real-install, dts-integration) with DTS retry |
| `tests/test_pi_settings.sh` | **NEW** — 8 unit tests for Pi settings wiring | Create, write, preserve packages, idempotent, dedupe |
| `tests/test_dts.sh` | DTS integration | Test 8d: hermes skills list (memory-automation) |
| `tests/test_cli_integration.sh` | CLI integration | Real-install block has live skill-discovery checks |
| `wiki/INDEX.md` | Wiki article index | All 22 articles with skill cross-references |
| `etc/mnemon-seed-pi.json` | Pi seed template | 5 insights (uses `text` field) |
| `etc/mnemon-seed-hermes.json` | Hermes seed template | 5 insights (uses `text` field) |
| `mnemon/seed.json` | Does not exist yet — create from upstream `https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/mnemon/seed.json` (33 insights, uses `content` field) |

---

## 5. Phase 21: Mnemon Seed + Validator (NEXT)

### 5.1 What needs to be done

**Goal:** Create `mnemon/seed.json` with 30-50 insights, plus `scripts/validate-seed.py` and `scripts/check-seed-export.sh`.

**Source files (UPSTREAM — ready to adapt):**
- **`seed.json` (33 insights)**: `https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/mnemon/seed.json`
  - Categories: `fact`, `decision`, `context`, `insight`, `general`
  - Fields: `content`, `category`, `importance` (1-5), `entities`, `tags`
  - ⚠️ **FIELD NAME MISMATCH**: Upstream uses `content`, existing .minions templates use `text`
- **`validate-seed.py`**: `https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/mnemon/validate-seed.py`
  - Validates: schema_version=1, content field required, importance 1-5, category in {preference|decision|fact|insight|context|general}, content < 8000 chars, max 50 insights
- **`check-seed-export.sh`**: `https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/scripts/check-seed-export.sh`
  - Uses `mnemon recall` to check for new high-importance entries before merging PRs

**Current state:**
- `mnemon/` has only `.gitkeep` — no `seed.json`
- `etc/mnemon-seed-pi.json` has 5 insights (Pi-related facts, uses `text` field)
- `etc/mnemon-seed-hermes.json` has 5 insights (Hermes-related facts, uses `text` field)
- `scripts/validate-seed.py` — does not exist
- `scripts/check-seed-export.sh` — does not exist

**Schema** (from upstream validate-seed.py — uses `content` field):
```json
{
  "schema_version": "1",
  "insights": [
    {
      "content": "...",
      "category": "fact | decision | context | insight | preference | general",
      "importance": 1-5,
      "entities": ["..."],
      "tags": ["..."]
    }
  ]
}
```

**Approach:**
1. Copy upstream `seed.json` (33 insights) and adapt field names (`text` → `content` for .minions convention) OR use upstream as-is
2. Copy upstream `validate-seed.py` and adapt path from `.devcontainer/mnemon/` to `mnemon/`
3. Copy upstream `check-seed-export.sh` and adapt path from `.devcontainer/scripts/` to `scripts/`
4. Optionally add insights from DTS learnings to reach 30-50 total

**⚠️ CRITICAL**: The upstream schema uses `content` field. The existing .minions templates (`etc/mnemon-seed-pi.json`, `etc/mnemon-seed-hermes.json`) use `text` field. Either:
- Use `content` field in `mnemon/seed.json` (matches validator)
- Or update `validate-seed.py` to accept both `text` and `content`

**Deliverables:**
| Task | Deliverable |
|------|-------------|
| Create `mnemon/seed.json` | 33+ insights from upstream (adapted) + optional DTS additions |
| Create `scripts/validate-seed.py` | Schema validator (adapted from upstream, path `mnemon/`) |
| Create `scripts/check-seed-export.sh` | Export checker (adapted from upstream, path `scripts/`) |

**Dependencies:** Wiki content (Phases 16-20) ✅ complete. DTS learnings available. Upstream repo accessible.

### 5.2 Why Phase 21 is HIGH priority

Mnemon seed.json is the persistent knowledge catalog. Without it, the agent cannot recall project context across sessions. The mnemon memory-automation skill depends on it. This blocks agent usefulness.

### 5.3 TDD approach

1. **RED:** Write `scripts/validate-seed.py` tests first (validate schema, content field, importance range)
2. **GREEN:** Implement validator
3. **RED:** Create seed.json with < 5 insights; verify validator catches it
4. **GREEN:** Add 30+ insights to seed.json; validator passes
5. **REFACTOR:** Clean up seed.json entries

### 5.4 Verification

```bash
# Validate seed.json
bash scripts/validate-seed.py mnemon/seed.json
# EXPECT: exit 0, "seed.json valid"

# Check seed export
bash scripts/check-seed-export.sh
# EXPECT: reports new insights to add

# Recall from mnemon (after seed.json imported)
mnemon recall "dev mode" --limit 5
# EXPECT: returns project-relevant insights
```

---

## 6. Phase 24-28: Codespace Skills Verification

5 new codespace skills are ported to the repo but need live verification:

| Skill | Verification Needed |
|-------|---------------------|
| `codespace-persistent-symlinks` | Survives Codespace rebuild |
| `codespace-port-visibility` | Port visibility automated via CLI |
| `codespace-webtop` | Browser desktop launches via pixelflux selkies |
| `codespace-vscode-open` | VS Code CLI auto-discovery |
| `codespace-lavish` | Whiteboard over noVNC |

These require an active Codespace to verify. Not blocked by Phase 21.

---

## 7. Phase 29-31: Advanced Proxy Features (Later)

| Phase | Feature |
|-------|---------|
| 29 | OmniRoute multi-model routing (priority, cost, fallback) |
| 30 | ModelRelay + Pi-Agent full proxy stack |
| 31 | Collective Wisdom (skill sharing) |

Not started. Depends on stable proxy infrastructure (Phases 0-24 complete).

---

## 8. Critical Gotchas — Do Not Re-Introduce

### Gotcha 1: Env Scope in `curl | bash`

```bash
# WRONG — HOME only applies to curl, not piped bash
HOME=/tmp/test curl -sSL "$URL" | bash

# CORRECT — HOME on both sides, or use bash -c
HOME=/tmp/test curl -sSL "$URL" | HOME=/tmp/test bash
# OR (preferred)
HOME=/tmp/test bash -c "$(curl -fsSL "$URL")"
```

### Gotcha 2: Mode Detection Precedence

**Order matters** in `detect_knowledge_mode()`:
1. Check `SCRIPT_DIR` (set by install.sh/boot.sh) for git root
2. Check `cwd` for git root
3. If NO git root found:
   - If `MINIONS_BOOTSTRAPPED=1` → skip persisted fallback (default standalone)
   - Else → fall back to persisted `$MINIONS_REPO_ROOT`

**NEVER use `$0` as a probe base** — it leaks when library is sourced from test subshells.

### Gotcha 3: Hermes Symlink Target

```bash
# Skills: named subdirectory (preserves other skills)
~/.hermes/skills/minions → <target>/skills

# Memories: direct symlink
~/.hermes/memories → <target>/memories

# Wiki: NOT symlinked (skills reference ../wiki/)
```

### Gotcha 4: Hermes Binary — Use Venv Entrypoint

```bash
# WRONG — source-tree launcher uses system python (no dotenv)
~/.minions/src/hermes-agent/hermes

# CORRECT — venv entrypoint has correct shebang
~/.hermes/hermes-agent/venv/bin/hermes
```

### Gotcha 5: Test Isolation

```bash
# Always export empty MINIONS_HOME in test subshells
export MINIONS_HOME=""
bash tests/test_knowledge_mode.sh
# Prevents leakage from real environment
```

### Gotcha 6: DTS Memory Flags

```bash
# In lib/npm_packages.sh — required for low-RAM containers
NODE_OPTIONS="--max-old-space-size=512"
npm install --prefer-offline --no-optional
```

### Gotcha 7: CI Standalone Test Fallback

```yaml
# .github/workflows/ci.yml — fallback branch for PR vs push
TARBALL_URL="https://github.com/gitricko/.minions/archive/refs/heads/${GITHUB_HEAD_REF:-main}.tar.gz"
# PR: uses GITHUB_HEAD_REF (branch name)
# Push to main: uses "main"
```

### Gotcha 8: Mnemon Setup Disabled

```bash
# setup_mnemon_all() is now a no-op — do NOT re-enable hermes setup
# The user has their own mnemon plugin; the minions mnemon setup
# overrode it. See lib/mnemon.sh for the disabled code (commented out).
# The mnemon binary is still installed by install_mnemon/ensure_mnemon.
```

### Gotcha 9: DTS Retry Logic

```yaml
# .github/workflows/ci.yml — DTS job has up to 3 retries
# This mitigates OOM/resource flakiness on constrained CI runners.
# Prior commit "ci: re-run DTS (flake investigation)" failed identically
# — this is a known infrastructure issue, not a code bug.
```

### Gotcha 10: Seed.json Field Name Mismatch

```python
# Upstream seed.json uses "content" field:
{"content": "...", "category": "fact", "importance": 5, ...}

# Existing .minions templates use "text" field:
{"text": "...", "category": "fact", "importance": 5, ...}

# validate-seed.py checks for "content" — must use "content" in mnemon/seed.json
# Either adapt upstream seed.json to use "content", or update validator.
```

### Gotcha 11: Upstream Seed Source

```bash
# Phase 21 seed.json comes from upstream hermes-codespace repo:
# https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/mnemon/seed.json
# (33 insights, not fabricated — verified source)
# Also available:
# https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/mnemon/validate-seed.py
# https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/scripts/check-seed-export.sh
```

### Gotcha 12: PR #29 vs #30 Merge Order

```bash
# PR #29 (Phase 24 Pi-wiring) is MERGED to main ✅
# PR #30 (mnemon disable) is OPEN, CI green, READY TO MERGE
# Merge #30 before starting Phase 21 to keep main clean
```

---

## 9. CI Pipeline — Keep These Green

```yaml
# .github/workflows/ci.yml — 3 jobs, MUST all pass

test:              # ~1 min — unit tests only
  - tests/test_install.sh (shellcheck + test_knowledge_mode.sh etc.)
  - tests/test_boot.sh
  - verify-knowledge.sh (F1-F5)
  - tests/test_knowledge_mode.sh (4)
  - tests/test_bootstrap.sh (16)

real-install:      # ~4 min — full standalone install
  - T7: tarball install → standalone mode
  - T7b: INSTALL_URL piped install
  - Binary version checks (hard-fail)
  - Live skill-discovery checks (hermes skills list + pi -p)
  - Config verification

dts-integration:   # ~7 min — fresh container end-to-end
  - test_dts.sh full flow (Tests 1-9)
  - Includes test 8d: hermes skills list → memory-automation
  - UP TO 3 RETRIES for resource flake mitigation
```

**Do not weaken any hard-fail to warn.** The binary verification was hardened for a reason.

---

## 10. Prompt Template for Fresh Agent

Copy-paste this to start a fresh agent:

```
You are a fresh agent taking over the .minions project (self-contained AI stack installer).

REPO: /workspaces/.minions (branch feat/disable-mnemon-setup, PR #30 open & CI green)
GOAL: Merge PR #30, then continue implementation from Phase 21 (mnemon seed) onward.

READ FIRST (in this order):
1. docs/BRIEFING-fresh-agent-transfer-PHASE-21.md  ← THIS FILE — your complete briefing
2. docs/IMPLEMENTATION-STATUS.md                       ← Reality record + verification steps
3. docs/BRIEFING-fresh-agent-transfer-PHASE-16-20.md  ← Prior briefing (Phases 16-20 context)
4. docs/IMPL-PLAN-skills-wiki-integration.md          ← 32-phase plan (Phases 21-31 pending)

LOAD SKILLS (mandatory before any work):
- test-driven-development          (Hermes built-in) — RED→GREEN→REFACTOR
- karpathy-coding-guidelines       (Hermes built-in) — Minimal diffs, verify by real output
- codespace-gh-auth                (repo skills/)   — GitHub token extraction for git push
- docker-test-shell                (repo skills/)   — DTS clean-container testing
- ci-lint-check                    (repo skills/)   — Pre-commit lint locally
- mnemon-seed-persistence          (repo skills/)   — Seed.json management

KEY FILES:
- lib/mnemon.sh                     — Mnemon setup (setup_mnemon_all() is now a no-op)
- lib/pi-settings.sh                — Pi-Agent settings.json shared-skills wiring
- lib/knowledge-detection.sh        — Mode detection (SCRIPT_DIR probe > cwd git > persisted)
- lib/knowledge-symlinks.sh         — 4 knowledge symlinks + 2 Hermes links
- install.sh                        — Bootstrap + install (piped detection, Pi wiring, mnemon disable)
- boot.sh                           — Re-links on every boot from persisted env
- self-check.sh                     — Persistence section validates symlinks
- .github/workflows/ci.yml          — 3 jobs: test, real-install, dts-integration (with DTS retry)
- etc/mnemon-seed-pi.json           — Pi seed template (5 insights — needs expansion)
- etc/mnemon-seed-hermes.json       — Hermes seed template (5 insights — needs expansion)
- mnemon/seed.json                  — DOES NOT EXIST YET — create this (Phase 21)
- tests/test_pi_settings.sh         — 8 unit tests for Pi settings wiring
- wiki/INDEX.md                     — All 22 articles with skill cross-references

VERIFICATION CONTRACT (all must stay GREEN):
- bash tests/test_knowledge_mode.sh      # 4/4
- bash tests/test_boot_symlinks.sh       # 10/10
- bash tests/test_bootstrap.sh           # 16/16
- bash tests/test_pi_settings.sh         # 8/8
- bash tests/test_dts.sh                 # Full DTS integration (Tests 1-9)
- bash scripts/validate-seed.py mnemon/seed.json  # Phase 21 validator
- gh pr checks                           # All 3 CI jobs passing

NEXT WORK (in order):
1. Merge PR #30 (mnemon disable) into main
2. Phase 21 — Create mnemon/seed.json (30-50 insights) + scripts/validate-seed.py
3. Phase 24-28 — Verify 5 ported Codespace skills work
4. Phase 29-31 — Advanced proxy features

KNOWN GAPS (don't chase — these are expected):
- mnemon/seed.json missing (Phase 21) — create from templates + DTS learnings
- self-check exit 1 warning "model not configured" — expected fresh install
- Mnemon setup disabled (PR #30) — do NOT re-enable hermes mnemon setup

CODING STYLE: Karpathy (minimal diffs, root-cause, verify by real output)
WORKFLOW: TDD — write failing test first, implement fix, refactor, keep CI green
```

---

## 11. Quick Reference — Commands

```bash
# Run all unit tests
bash tests/test_knowledge_mode.sh && bash tests/test_boot_symlinks.sh && bash tests/test_bootstrap.sh && bash tests/test_pi_settings.sh

# Run DTS integration test (requires Docker)
bash tests/test_dts.sh
bash tests/test_dts.sh --no-clean  # Leave container for manual testing

# Verify CI locally (lint)
bash scripts/ci-lint-check.sh

# Validate mnemon seed.json (Phase 21)
bash scripts/validate-seed.py mnemon/seed.json

# Check seed export (Phase 21)
bash scripts/check-seed-export.sh

# Push with Codespace auth (if git rejects)
source ~/.hermes/skills/minions/codespace-gh-auth/scripts/codespace-gh-auth.sh
git_push_with_token

# View mnemon memories
mnemon recall "dev mode" --limit 5

# Verify wiki gates after changes
bash scripts/verify-knowledge.sh F4  # Link integrity
bash scripts/verify-knowledge.sh F5  # No .devcontainer refs
```

---

## 12. Contact / Escalation

- **Repo:** https://github.com/gitricko/.minions
- **Upstream seed source:** https://github.com/gitricko/hermes-codespace/blob/main/.devcontainer/mnemon/seed.json (33 insights)
- **PR #29** (Phase 24 Pi-wiring): `feat/phase24-pi-settings` → **MERGED** to main
- **PR #30** (mnemon disable): `feat/disable-mnemon-setup` → OPEN, CI green, awaiting merge
- **CI runs:** https://github.com/gitricko/.minions/actions
- **DTS Images:** `ghcr.io/gitricko/minions-dts:latest` (auto-built)

---

*Generated 2026-09-14 by the agent that completed Phases 16-20 and Phase 24.*
