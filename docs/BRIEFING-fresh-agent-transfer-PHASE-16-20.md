# Fresh Agent Briefing — .minions Phase 16-20 Completion Handoff

**Date:** 2026-09-12
**Branch:** `feat/phase-16-20-wiki-content` (PR #25 open, CI passing)
**Status:** Phases 16-20 **COMPLETE** — Wiki populated, knowledge detection fixed, CI green

---

## What This Document Is

This is a **complete transfer package** for a fresh agent taking over the .minions project after Phases 16-20 completion. It contains:

1. **Current implementation state** — what's done in Phases 16-20, what's verified, what's pending
2. **Exact skills to load** — with paths and why each matters
3. **Verification checklist** — the steps the prior agent ran to confirm Phases 16-20
4. **Remaining implementation plan** — Phases 21-31 with dependencies
5. **Known gotchas** — bugs fixed, pitfalls to avoid
5. **Prompt template** — ready-to-use prompt for the fresh agent

---

## 1. Current State Summary

### ✅ Completed (Phases 16-20, PR #25)

| Area | Status | Evidence |
|------|--------|----------|
| **Phase 16: Wiki batch 1** | ✅ | 5 core architecture articles + `wiki/INDEX.md` |
| **Phase 17: Wiki batch 2** | ✅ | 5 skills reference articles |
| **Phase 18: Wiki batch 3** | ✅ | 3 testing/CI articles |
| **Phase 19: Wiki batch 4** | ✅ | 3 advanced articles |
| **Phase 20: Wiki batch 5** | ✅ | 6 remaining articles |
| **Total wiki articles** | ✅ | **22 articles + INDEX.md** |
| **F4 (wiki link integrity)** | ✅ | `verify-knowledge.sh F4` — all links resolve |
| **F5 (no .devcontainer refs)** | ✅ | `verify-knowledge.sh F5` — 0 occurrences |
| **Phase 19: Knowledge detection fix** | ✅ | `lib/knowledge-detection.sh` — SCRIPT_DIR probe order fixed |
| **Phase 20: CI workflow fallback fix** | ✅ | `.github/workflows/ci.yml` — fallback branch `main` not `minion-knowledge-base` |
| **All unit tests** | ✅ | `test_knowledge_mode.sh` (4/4), `test_boot_symlinks.sh` (10/10), `test_bootstrap.sh` (16/16) |
| **Real Install** | ✅ | Full standalone bootstrap test passes (fetches from branch) |
| **DTS Integration** | ✅ | Full end-to-end container test passes |

### ⚠️ Known Gaps (Expected — Not Blockers)

| Gap | Phase | Current State |
|-----|-------|---------------|
| `mnemon/seed.json` | 21 | Minimal — needs 30-50 insights from DTS learnings |
| Pi-Agent skills wiring | 24 | `settings.json` shared skills path not yet wired |
| 5 new Codespace skills | 24-28 | Ported to repo but need verification |
| Advanced proxy features | 29-31 | OmniRoute multi-model, ModelRelay, Collective Wisdom |
| Self-check exit 1 | — | 1 warning "model not configured" (expected fresh install) |

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

## 3. Verification Checklist — Phases 16-20 Completion

The prior agent ran these to confirm Phases 16-20 are complete. A fresh agent should re-verify if on a new machine.

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

# 7. Self-check — Persistence GREEN (exit 1 = 1 warning only)
bash /workspaces/.minions/self-check.sh
# EXPECT: exit 1, 1 warning "model not configured", 0 critical

# 8. CI status — PR #25 checks
gh pr checks 25
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
| `docs/IMPLEMENTATION-STATUS.md` | Authoritative reality record | "NEXT AGENT: PHASE 16-20 COMPLETE", "Still Open" |
| `docs/PROPOSAL-skills-wiki-integration.md` | Architecture design | §3.1 (dir structure), §3.2 (two-mode), §3.3 (boot wiring), §4 (skills list) |
| `docs/IMPL-PLAN-skills-wiki-integration.md` | 32-phase plan | Phases 21-31 (remaining), phase dependencies |
| `docs/BRIEFING-fresh-agent-transfer-PHASE-16-20.md` | This file | All sections |
| `lib/knowledge-detection.sh` | Mode detection logic | `detect_knowledge_mode()` — SCRIPT_DIR probe first |
| `lib/knowledge-symlinks.sh` | Symlink creation | `setup_knowledge_symlinks()`, `setup_hermes_skill_link()`, `setup_hermes_memories_link()` |
| `install.sh` | Bootstrap + install | Piped detection, tarball fetch, re-exec, INSTALL_URL auto-derivation |
| `boot.sh` | Service startup + re-link | Sources detection + symlinks; re-links on every boot |
| `self-check.sh` | Health verification | Persistence section checks symlinks vs dirs |
| `.github/workflows/ci.yml` | CI pipeline | `test`, `real-install`, `dts-integration` jobs |
| `wiki/INDEX.md` | Wiki article index | All 22 articles with cross-references to skills |

---

## 5. Wiki Articles Populated (Phases 16-20)

All articles sourced from upstream `hermes-codespace/.devcontainer/wiki/`, paths rewritten from `.devcontainer/` to repo-relative `../skills/` / `../wiki/`:

| Phase | Articles |
|-------|----------|
| **16** | `codespace-playbook.md`, `codespace-lifecycle.md`, `codespace-persistent-symlinks.md`, `codespace-port-visibility.md`, `codespace-gh-auth.md` |
| **17** | `github-codespace.md`, `github-pr-review.md`, `docker-test-shell.md`, `karpathy-coding-guidelines.md`, `repository-analysis.md` |
| **18** | `mnemon-graph-viewer.md`, `ci-lint-check.md`, `github-actions-testing-plan.md` |
| **19** | `codespace-webtop.md`, `keepalive-proposal.md`, `persistent-knowledge-proposal.md` |
| **20** | `persistent-memory-proposal.md`, `INDEX.md` (auto-generated with skill cross-refs) |

---

## 6. Remaining Implementation — Phases 21-31

### Phase 21: Mnemon Seed + Validator (Priority: HIGH — blocks agent usefulness)

| Task | Dependencies | Deliverable |
|------|--------------|-------------|
| Create `mnemon/seed.json` with 30-50 insights | Wiki content (Phases 16-20), DTS learnings | Seed file |
| Create `scripts/validate-seed.py` | Schema: `content` field required | Validator |

**Dependency:** Seed insights should come from actual DTS integration learnings, not fabricated.

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

## 7. Critical Gotchas — Do Not Re-Introduce

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

---

## 8. CI Pipeline — Keep These Green

```yaml
# .github/workflows/ci.yml — 3 jobs, MUST all pass

test:              # ~1 min — unit tests only
  - tests/test_knowledge_mode.sh (4)
  - tests/test_boot_symlinks.sh (10)
  - tests/test_bootstrap.sh (16)
  - verify-knowledge.sh (F1-F5)

real-install:      # ~4 min — full standalone install
  - T7: tarball install → standalone mode (fetches from branch)
  - T7b: INSTALL_URL piped install → branch tarball auto-derived
  - Binary version checks (hard-fail)
  - Config verification (~/.hermes/config.yaml)

dts-integration:   # ~7 min — fresh container end-to-end
  - test_dts.sh full flow
  - install → boot → health → chat → hermes/pi CLI → stop
```

**Do not weaken any hard-fail to warn.** The binary verification was hardened for a reason.

---

## 9. Prompt Template for Fresh Agent

Copy-paste this to start a fresh agent:

```
You are a fresh agent taking over the .minions project (self-contained AI stack installer).

REPO: /workspaces/.minions (branch feat/phase-16-20-wiki-content, PR #25 open & passing)
GOAL: Merge PR #25, then continue implementation from Phase 21 (mnemon seed) onward.

READ FIRST (in this order):
1. docs/BRIEFING-fresh-agent-transfer-PHASE-16-20.md     ← THIS FILE — your complete briefing
2. docs/IMPLEMENTATION-STATUS.md                          ← Reality record + verification steps
3. docs/PROPOSAL-skills-wiki-integration.md               ← Architecture design
4. docs/IMPL-PLAN-skills-wiki-integration.md              ← 32-phase plan (Phases 21-31 pending)

LOAD SKILLS (mandatory before any work):
- test-driven-development          (Hermes built-in) — RED→GREEN→REFACTOR
- karpathy-coding-guidelines       (Hermes built-in) — Minimal diffs, verify by real output
- codespace-gh-auth                (repo skills/)   — GitHub token extraction for git push
- docker-test-shell                (repo skills/)   — DTS clean-container testing
- ci-lint-check                    (repo skills/)   — Pre-commit lint locally

KEY FILES:
- lib/knowledge-detection.sh       — Mode detection (SCRIPT_DIR probe > cwd git > persisted)
- lib/knowledge-symlinks.sh        — 4 knowledge symlinks + 2 Hermes links
- install.sh                       — Bootstrap + install (INSTALL_URL auto-derivation)
- boot.sh                          — Re-links on every boot from persisted env
- self-check.sh                    — Persistence section validates symlinks
- .github/workflows/ci.yml         — 3 jobs: test, real-install, dts-integration
- wiki/INDEX.md                    — All 22 articles with skill cross-references

VERIFICATION CONTRACT (all must stay GREEN):
- bash tests/test_knowledge_mode.sh      # 4/4
- bash tests/test_boot_symlinks.sh       # 10/10
- bash tests/test_bootstrap.sh           # 16/16
- bash tests/test_dts.sh                 # Full DTS integration
- gh pr checks 25                        # All 3 CI jobs passing

NEXT WORK (in order):
1. Merge PR #25 into main (user will handle merge)
2. Phase 21 — Create mnemon/seed.json + validate-seed.py
3. Phase 24 — Wire Pi-Agent settings.json shared skills
4. Phase 24-28 — Verify 5 ported Codespace skills work
5. Phase 29-31 — Advanced proxy features

KNOWN GAPS (don't chase — these are expected):
- mnemon/seed.json minimal (Phase 21) — expected
- self-check exit 1 warning "model not configured" — expected fresh install

CODING STYLE: Karpathy (minimal diffs, root-cause, verify by real output)
WORKFLOW: TDD — write failing test first, implement fix, refactor, keep CI green
```

---

## 10. Context Transfer Skill (Reusable)

This handoff pattern is captured as a reusable skill: `agent-context-transfer`

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

**Files in skill:**
- `templates/briefing-template.md` — Reusable briefing template
- `scripts/verify-handoff.sh` — Auto-verifies handoff completeness
- `references/context-checklist.md` — What must be included in any handoff

This skill captures the **pattern** used here so future handoffs are systematic.

---

## 11. Quick Reference — Commands

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

# Verify wiki gates after changes
bash scripts/verify-knowledge.sh F4  # Link integrity
bash scripts/verify-knowledge.sh F5  # No .devcontainer refs
```

---

## 12. Contact / Escalation

- **Repo:** https://github.com/gitricko/.minions
- **PR #25:** `feat: Phase 16-20 wiki content population + knowledge detection fix` (OPEN, passing)
- **PR #24:** `fix: wire Hermes skills/memories links + fix dev-mode detection` (MERGED)
- **DTS Images:** `ghcr.io/gitricko/minions-dts:latest` (auto-built)

---

*Generated 2026-09-12 by the agent that completed Phases 16-20 and PR #25.*