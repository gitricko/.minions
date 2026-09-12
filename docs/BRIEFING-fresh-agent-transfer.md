# Fresh Agent Briefing — .minions Implementation Handoff

**Date:** 2026-09-12
**Branch:** `main` (PR #24 merged)
**Status:** Phases 0-23 **COMPLETE** — dev-mode verified, CI green, docs updated

---

## What This Document Is

This is a **complete transfer package** for a fresh agent taking over the .minions project. It contains:
1. **Current implementation state** — what's done, what's verified, what's broken
2. **Exact skills to load** — with paths and why each matters
3. **Verification checklist** — the 7-step dev-mode verification the prior agent ran
4. **Remaining implementation plan** — Phases 16-31 with dependencies
5. **Known gotchas** — bugs fixed, pitfalls to avoid
6. **Prompt template** — ready-to-use prompt for the fresh agent

---

## 1. Current State Summary

### ✅ Completed (Phases 0-23, PR #24 merged)

| Area | Status | Evidence |
|------|--------|----------|
| Knowledge layer foundation (Phase 0-0.6) | ✅ | `lib/knowledge-detection.sh`, `lib/knowledge-symlinks.sh`, `verify-knowledge.sh`, `self-check.sh` |
| 15 skills ported (Phases 1-15) | ✅ | `skills/` — codespace-*, memory-*, mnemon-*, docker-test-shell, ci-lint-check, karpathy-coding-guidelines, github-* |
| Two-mode detection (Phase 22) | ✅ | `detect_knowledge_mode()` — dev vs standalone, persists to `~/.minions/etc/knowledge.env` |
| Curl\|bash bootstrap (Phase 22.5) | ✅ | `install.sh` preamble — piped detection, tarball fetch, re-exec |
| Dev-mode symlinks (Phase 23) | ✅ | `setup_knowledge_symlinks()` — 4 symlinks in dev mode |
| **Hermes skills/memories links (PR #24)** | ✅ | `setup_hermes_skill_link()`, `setup_hermes_memories_link()` — `~/.hermes/skills/minions` + `~/.hermes/memories` |
| **Mode detection fix (PR #24)** | ✅ | Live git probe > persisted env; `MINIONS_BOOTSTRAPPED=1` skips stale fallback |
| **Bootstrap INSTALL_URL (PR #24)** | ✅ | Auto-derives `BOOTSTRAP_URL` from `INSTALL_URL`; fixes `curl \| bash` env scope bug |
| All CI suites | ✅ | Test 58s, Real Install 4m25s, DTS 7m22s — all GREEN |
| README docs | ✅ | Branch install pattern documented |

### ⚠️ Known Gaps (Expected — Not Blockers)

| Gap | Phase | Current State |
|-----|-------|---------------|
| `wiki/` content | 16-20 | Near-empty (only `.gitkeep`) — skills reference `../wiki/` |
| `mnemon/seed.json` | 21 | Minimal — needs 30-50 insights from DTS learnings |
| Pi-Agent skills wiring | 24 | `settings.json` shared skills path not yet wired |
| 5 new Codespace skills | 24-28 | Ported to repo but need verification |
| Advanced proxy features | 29-31 | OmniRoute multi-model, ModelRelay, Collective Wisdom |

---

## 2. Required Skills — Load These FIRST

The fresh agent **MUST** load these skills before doing any work. They define the HOW (TDD, coding style) while the verification tasks are the WHAT.

### A. Hermes-Built-in Skills (load via `skill_view`)

```bash
# Core workflow skills
skill_view(name='test-driven-development')        # RED→GREEN→REFACTOR; tests before code
skill_view(name='karpathy-coding-guidelines')     # Minimal diffs, root-cause fixes, verify by real output
skill_view(name='github')                          # PR management, reviews, CI
skill_view(name='ci-lint-check')                  # Pre-commit lint validation locally
```

### B. Repo-Ported Skills (load via `skill_view` — these are the authoritative copies)

```bash
# From /workspaces/.minions/skills/
skill_view(name='codespace-gh-auth')              # GitHub token extraction from VS Code server for git push
skill_view(name='docker-test-shell')              # DTS: clean-container integration testing
skill_view(name='docker-test-shell')              # References: references/dts-usage.md
skill_view(name='persistent-knowledge')           # Symlink-based persistence architecture
skill_view(name='mnemon-seed-persistence')        # Seed.json management for contributors
skill_view(name='memory-automation')              # Mnemon workflow (recall/save patterns)
skill_view(name='mnemon-graph-export')            # 3D knowledge graph visualization
```

### C. Task-Relevant Skills (load as needed)

```bash
skill_view(name='codespace-persistent-symlinks')  # Persist Hermes state across Codespace rebuilds
skill_view(name='codespace-port-visibility')      # Automate port visibility via CLI
skill_view(name='codespace-webtop')               # Selkies/XFCE browser desktop
skill_view(name='codespace-vscode-open')          # Auto-discover VS Code CLI
skill_view(name='codespace-lavish')               # Whiteboard over noVNC
skill_view(name='github-pr-review')               # Evaluate CodeQL/Copilot suggestions
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

## 3. Verification Checklist — The 7 Steps (COMPLETED)

The prior agent ran these on a fresh Codespace. All PASS. A fresh agent should re-verify if on a new machine.

```bash
# 1. Mode detection — is it DEV?
cat ~/.minions/etc/knowledge.env
# EXPECT: MODE=dev
#         MINIONS_REPO_ROOT=/workspaces/.minions

# 2. Symlinks — are the 4 knowledge dirs linked to the repo?
ls -la ~/.minions/
# EXPECT symlinks: skills→repo, wiki→repo, mnemon→repo, memories→repo

# 3. Content reachable through links
ls ~/.minions/skills/
test -d ~/.minions/skills/codespace-gh-auth && echo "skills reachable"

# 4. Re-boot re-links (boot.sh honors persisted env)
bash ~/.minions/boot.sh
# EXPECT: [INFO] Knowledge mode: dev (from .../etc/knowledge.env)
#         [INFO] Linked ~/.minions/skills -> /workspaces/.minions/skills (×4)

# 5. Self-check: Persistence section GREEN
bash self-check.sh  # from REPO_ROOT
# EXPECT: Persistence section shows all 4 as symlinks -> REPO_ROOT/...

# 6. Hermes sees dev-mode skills
hermes --version
ls ~/.hermes/skills/minions/  # should list 15 ported skills

# 7. CI contract
bash tests/test_knowledge_mode.sh      # 4/4
bash tests/test_boot_symlinks.sh       # 10/10
bash tests/test_bootstrap.sh           # 16/16
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
| `docs/IMPLEMENTATION-STATUS.md` | Authoritative reality record | "NEXT AGENT: DEV-MODE INSTALL VERIFICATION", "Still Open" |
| `docs/PROPOSAL-skills-wiki-integration.md` | Architecture design | §3.1 (dir structure), §3.2 (two-mode), §3.3 (boot wiring), §4 (skills list) |
| `docs/IMPL-PLAN-skills-wiki-integration.md` | 32-phase plan | Phases 16-31 (remaining), phase dependencies |
| `docs/BRIEFING-fresh-agent-transfer.md` | This file | All sections |
| `lib/knowledge-detection.sh` | Mode detection logic | `detect_knowledge_mode()` — live git probe first |
| `lib/knowledge-symlinks.sh` | Symlink creation | `setup_knowledge_symlinks()`, `setup_hermes_skill_link()`, `setup_hermes_memories_link()` |
| `install.sh` | Bootstrap + install | Piped detection, tarball fetch, re-exec, INSTALL_URL auto-derivation |
| `boot.sh` | Service startup + re-link | Sources detection + symlinks; re-links on every boot |
| `self-check.sh` | Health verification | Persistence section checks symlinks vs dirs |
| `.github/workflows/ci.yml` | CI pipeline | `test`, `real-install`, `dts-integration` jobs |

---

## 5. Remaining Implementation — Phases 16-31

### Phase 16-21: Content Population (Priority: HIGH — blocks agent usefulness)

| Phase | Task | Dependencies | Deliverable |
|-------|------|--------------|-------------|
| **16** | Wiki batch 1: core architecture | `wiki/INDEX.md`, `codespace-playbook.md`, `codespace-lifecycle.md` | 3 articles |
| **17** | Wiki batch 2: skills reference | Each skill's usage doc (persistent-knowledge, mnemon-seed, etc.) | ~8 articles |
| **18** | Wiki batch 3: testing/CI | `docker-test-shell-proposal.md`, `github-actions-testing-plan.md`, `ci-lint-check.md` | 3 articles |
| **19** | Wiki batch 4: advanced | `codespace-webtop.md`, `selkies-package-discrepancy.md`, `repository-analysis.md` | 3 articles |
| **20** | Wiki batch 5: remaining | `karpathy-coding-guidelines.md`, `keepalive-proposal.md`, `github-codespace.md`, etc. | ~6 articles |
| **21** | Mnemon seed + validator | `mnemon/seed.json` (30-50 insights), `validate-seed.py` (schema: `content` field) | Seed + validator |

**Dependency:** Wiki F4 (link integrity check) gates each batch. `verify-knowledge.sh` runs F1-F5.

### Phase 24: Pi-Agent Skills Wiring

- Wire `settings.json` shared skills directory for Pi
- Both modes: dev → repo skills, standalone → `~/.minions/skills`

### Phase 24-28: New Codespace Skills (already ported, need verification)

| Skill | Status | Verification Needed |
|-------|--------|---------------------|
| `codespace-persistent-symlinks` | Ported | Survives Codespace rebuild |
| `codespace-port-visibility` | Ported | Port visibility automated |
| `codespace-webtop` | Ported | Browser desktop launches |
| `codespace-vscode-open` | Ported | VS Code CLI auto-discovery |
| `codespace-lavish` | Ported | Whiteboard over noVNC |

### Phase 29-31: Advanced Features

| Phase | Feature |
|-------|---------|
| 29 | OmniRoute multi-model routing (priority, cost, fallback) |
| 30 | ModelRelay + Pi-Agent full proxy stack |
| 31 | Collective Wisdom (skill sharing) |

---

## 6. Critical Gotchas — Do Not Re-Introduce

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
1. Check `$0` script location for git root
2. Check `cwd` for git root
3. If NO git root found:
   - If `MINIONS_BOOTSTRAPPED=1` → skip persisted fallback (default standalone)
   - Else → fall back to persisted `$MINIONS_REPO_ROOT`

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

---

## 7. CI Pipeline — Keep These Green

```yaml
# .github/workflows/ci.yml — 3 jobs, MUST all pass

test:              # ~1 min — unit tests only
  - tests/test_knowledge_mode.sh (4)
  - tests/test_boot_symlinks.sh (10)
  - tests/test_bootstrap.sh (16)
  - verify-knowledge.sh (F1-F5)

real-install:      # ~4 min — full standalone install
  - T7: tarball install → standalone mode
  - T7b: INSTALL_URL piped install → branch tarball auto-derived
  - Binary version checks (hard-fail)
  - Config verification (~/.hermes/config.yaml)

dts-integration:   # ~7 min — fresh container end-to-end
  - test_dts.sh full flow
  - install → boot → health → chat → hermes/pi CLI → stop
```

**Do not weaken any hard-fail to warn.** The binary verification was hardened for a reason.

---

## 8. Prompt Template for Fresh Agent

Copy-paste this to start a fresh agent:

```
You are a fresh agent taking over the .minions project (self-contained AI stack installer).

REPO: /workspaces/.minions (branch main, PR #24 merged)
GOAL: Continue implementation from Phase 16 (wiki content) onward.

READ FIRST (in this order):
1. docs/BRIEFING-fresh-agent-transfer.md          ← THIS FILE — your complete briefing
2. docs/IMPLEMENTATION-STATUS.md                  ← Reality record + verification steps
3. docs/PROPOSAL-skills-wiki-integration.md       ← Architecture design
4. docs/IMPL-PLAN-skills-wiki-integration.md      ← 32-phase plan (Phases 16-31 pending)

LOAD SKILLS (mandatory before any work):
- test-driven-development          (Hermes built-in) — RED→GREEN→REFACTOR
- karpathy-coding-guidelines       (Hermes built-in) — Minimal diffs, verify by real output
- codespace-gh-auth                (repo skills/)   — GitHub token extraction for git push
- docker-test-shell                (repo skills/)   — DTS clean-container testing
- ci-lint-check                    (repo skills/)   — Pre-commit lint locally

KEY FILES:
- lib/knowledge-detection.sh       — Mode detection (live git probe > persisted)
- lib/knowledge-symlinks.sh        — 4 knowledge symlinks + 2 Hermes links
- install.sh                       — Bootstrap + install (INSTALL_URL auto-derivation)
- boot.sh                          — Re-links on every boot from persisted env
- self-check.sh                    — Persistence section validates symlinks
- .github/workflows/ci.yml         — 3 jobs: test, real-install, dts-integration

VERIFICATION CONTRACT (all must stay GREEN):
- bash tests/test_knowledge_mode.sh      # 4/4
- bash tests/test_boot_symlinks.sh       # 10/10
- bash tests/test_bootstrap.sh           # 16/16
- bash tests/test_dts.sh                 # Full DTS integration

NEXT WORK: Phase 16 — Populate wiki/ content (5 batches, F4 gates each)
           Phase 21 — Create mnemon/seed.json + validate-seed.py
           Phase 24 — Wire Pi-Agent settings.json shared skills

KNOWN GAPS (don't chase):
- wiki/ is near-empty (Phases 16-20) — expected
- mnemon/seed.json minimal (Phase 21) — expected

CODING STYLE: Karpathy (minimal diffs, root-cause, verify by real output)
WORKFLOW: TDD — write failing test first, implement fix, refactor, keep CI green
```

---

## 9. Skill for Context Transfer (Generic)

Create this as a reusable skill: `agent-context-transfer`

```yaml
# SKILL.md for agent-context-transfer
name: agent-context-transfer
description: Transfer implementation context to a fresh agent for seamless handoff
category: productivity
metadata:
  hermes:
    requires_tools: [read_file, write_file, terminal, skill_view, search_files]
    requires_toolsets: []
    requires_plugins: []
```

**Files to create in skill:**
- `templates/briefing-template.md` — Reusable briefing template
- `scripts/verify-handoff.sh` — Auto-verifies handoff completeness
- `references/context-checklist.md` — What must be included in any handoff

This skill captures the **pattern** used here so future handoffs are systematic.

---

## 10. Quick Reference — Commands

```bash
# Run all unit tests
bash tests/test_knowledge_mode.sh && bash tests/test_boot_symlinks.sh && bash tests/test_bootstrap.sh

# Run DTS integration test (requires Docker)
bash tests/test_dts.sh
bash tests/test_dts.sh --no-clean  # Leave container for manual testing

# Verify CI locally (lint)
bash scripts/ci-lint-check.sh

# Push with Codespace auth (if git rejects)
source ~/.minions/skills/codespace-gh-auth/scripts/extract-token.sh
git push origin HEAD

# View mnemon memories
mnemon recall "dev mode" --limit 5

# Install wiki content (Phase 16+)
# Copy from hermes-codespace .devcontainer/wiki/ to ~/.minions/wiki/
# Run verify-knowledge.sh F4 (link integrity) after each batch
```

---

## 11. Contact / Escalation

- **Repo:** https://github.com/gitricko/.minions
- **PR #24:** `fix: wire Hermes skills/memories links + fix dev-mode detection` (MERGED)
- **Prior PR #22:** `minion-knowledge-base` (knowledge layer, superseded by #24)
- **DTS Images:** `ghcr.io/gitricko/minions-dts:latest` (auto-built)

---

*Generated 2026-09-12 by the agent that completed Phases 0-23 verification and PR #24.*