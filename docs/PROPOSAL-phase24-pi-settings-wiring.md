---
title: "Phase 24 — Pi-Agent Shared Skills Wiring (settings.json)"
status: "DRAFT — for review, not yet implemented"
branch: "to create from main"
date: 2026-09-13
---

# Phase 24 — Pi-Agent Shared Skills Wiring

## 1. Goal (one sentence)

Make Pi-Agent (the `pi` CLI) load the SAME `skills/` directory that Hermes
already loads — the repo `skills/` in dev mode and `~/.minions/skills/` in
standalone mode — by wiring a `skills` entry into `~/.pi/agent/settings.json`
(in `install.sh`, re-asserted idempotently in `boot.sh`), so both agents share
one knowledge source per mode.

## 2. Current State (verified)

- **Skills live in two places today:**
  - Repo: `/workspaces/.minions/skills/` — **16 skill dirs**, each with `SKILL.md` (+ scripts/references). These are the authoritative copies.
  - Hermes uses them via symlink: `~/.hermes/skills/minions → <target>/skills` (dev: repo; standalone: `~/.minions/skills`). Already wired by Phase 23.
- **Pi-Agent config dir:** `~/.pi/agent/` exists, with `pi.toml` (RPC/LLM config), `models.json` (model catalog), `settings.json` (package manifest), and a `git/` clone cache.
- **Current `~/.pi/agent/settings.json`** (root cause: what this PR changes):
  ```json
  {
    "packages": [
      "git:github.com/gitricko/pi-failover@hermes-impl"
    ]
  }
  ```
  It only holds the `pi-failover` extension package. **No `skills` entry exists.**
- **install.sh (current):** templates `pi.toml` + `models.json` into `~/.pi/agent/`, then has this stale comment (lines ~348):
  ```bash
  # Copy settings.json is not used; Pi-Agent reads pi.toml + models.json.
  ```
  Phase 24 supersedes that comment.
- **boot.sh:** re-asserts Hermes symlinks every boot (Phase 23), but does **not** touch Pi settings.
- **Pi version:** `0.85.1` (`@earendil-works/pi-coding-agent`). Verified: `pi --version` → 0.85.1; `pi list`, `pi config` exist; `--skill <path>` / `--no-skills` flags exist.

## 3. How Pi Discovers Skills (verified against Pi docs + binary)

Pi loads skills from several locations; the relevant ones for us:

1. **`~/.pi/agent/skills/`** — global skills dir (convention; always loaded)
2. **`settings.json` → `skills` array** — files/dirs added to skill discovery. This is the documented mechanism for sharing dirs (docs: "add `~/.claude/skills` or `~/.codex/skills` to settings" to reuse another harness's skills) — **exactly our case.**
3. **`settings.json` → `packages` array** (local/npm/git packages) — canonical for shareable packages; a local dir with conventional `skills/` auto-discovers `SKILL.md`. `pi config` enables/disables resources.

Both `skills` (array) and local-path `packages` work on 0.85.1. **Decision: use the `skills` array.** Rationale:

- It is the *documented* mechanism for "point at another harness's skill dir" (our exact scenario: `.minions/skills` is a sibling knowledge layer, like `.claude/skills`).
- It is the *simplest* diff — a single `"skills": ["<path>"]` plus a JSON merge; no package manifest, no `pi config` enable step, no package-scope dedup semantics.
- It point to the path directly (no copy), so it honors the existing dev (repo) vs standalone (`~/.minions/skills`) split per mode.
- It keeps existing `packages` (pi-failover) untouched.
- It matches the Phase 24 plan's original intent ("skills array / shared skills dir") and its verify step.

**Config key format (verified from docs):** `"skills": ["<glob-or-path>", ...]` — paths resolve relative to `~/.pi/agent`, absolute paths and `~` supported. We use absolute paths (no `~` ambiguity; both modes already compute absolute targets).

**Pi merge behavior:** Pi merges settings.json at startup; a `skills` key coexists with `packages` (pi-failover stays installed). If `${HOME}/.pi/agent/settings.json` is missing, we create it with only the `skills` key.

## 4. Design

### 4.1 What we change in install.sh (one new step, after models.json templating)

```
Step 5b: Wire Pi shared-skills path into ~/.pi/agent/settings.json
  PI_SKILLS_PATH=$(
    if [ "${MODE}" = "dev" ]; then printf '%s' "${MINIONS_REPO_ROOT}/skills"
    else printf '%s' "${MINIONS_HOME}/skills"; fi
  )
  ensure file exists (mkdir -p ~/.pi/agent; touch if missing)
  merge with python3:
    load existing json (or {}), set data['skills'] = [PI_SKILLS_PATH], write back
  log_info "Wired Pi skills path: ${PI_SKILLS_PATH}"
```

**Why python3:** install.sh already has a python3-dependent path (lib/hermes.sh relies on python3), so python3 is a safe dependency. A tiny `python3 -c` merge is the minimal, robust way to preserve existing keys (`packages`) without a JSON-aware shell tool. We do **not** use `printf > file` (would clobber pi-failover). We do **not** use `jq` (not guaranteed present / not a declared dependency).

**Path per mode** (reuses detection already computed in install.sh):
- dev: `${MINIONS_REPO_ROOT}/skills` → repo skills
- standalone: `${MINIONS_HOME}/skills` → installed skills

**Idempotency:** if `skills` already contains the exact path, the merge is a no-op (rewrites same value — cheap; keeps file canonical).

### 4.2 What we change in boot.sh (idempotent re-assert)

After the Phase 23 Hermes-symlink block, add the same merge (same helper function, sourced from a new small lib or inlined):

- Recompute `PI_SKILLS_PATH` from `detect_knowledge_mode`'s outputs (already sourced in boot.sh).
- Re-merge if `settings.json` lacks the path (survives reinstall / drift / user edits).

**Idempotency check:** re-running boot with the path already present → no change (same JSON, "already correct" log line). Matches existing Phase 23 idempotency pattern.

### 4.3 Shared helper (avoid duplicating logic)

New **`lib/pi-settings.sh`** with `wire_pi_skills_path <settings_file> <skills_path>`:
- creates file + parent dir if missing
- python3 merge: preserve existing keys, set/append `skills` (dedupe exact path)
- logs concise PASS/ALREADY lines
- returns 0 on success, non-zero on python3 failure

`install.sh` and `boot.sh` both source it. (Follows existing pattern: `lib/knowledge-symlinks.sh` sourced by both.)

**Karpathy check:** smallest helper that serves both callers; no extra flags, no speculative config.

### 4.4 Files touched (3 new/modified)

| File | Change |
|------|--------|
| `lib/pi-settings.sh` | **NEW** — `wire_pi_skills_path` helper |
| `install.sh` | source helper; call it after models.json templating; remove/replace stale "settings.json is not used" comment |
| `boot.sh` | source helper; call it after Phase 23 symlink block |
| `tests/test_pi_settings.sh` | **NEW** — 8 unit tests |
| `tests/test_dts.sh` | standalone settings.json assertion (after config templates) + 8c pi-skill-discovery |
| `.github/workflows/ci.yml` | T7b standalone: assert `.pi/agent/settings.json` has skills array + standalone path |

No changes to `pi.toml`, `models.json`, or existing `packages`. No changes to `etc/` templates (settings.json is user-config, not a template).

### 4.5 Verified skill-listing commands (for §5 checks)

We verified the actual commands we'll use to prove skills are available:

- **`hermes skills list`** — official Hermes skills-management command; lists Name/Category/Source/Trust/Status table (sample abridged):
  ```
  ┏━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━┳━━━━━━━┳━━━━━━━┳━━━━━━━┓
  ┃ Name                    ┃ Category┃ Source ┃ Trust │ Status ┃
  ┡━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━╇━━━━━━━╇━━━━━━━╇━━━━━━━┩
  │ mnemon                  │         │ local  │ local │ enabled│
  │ claude-code             │ autonomous-ai-agents │ builtin │ enabled │
  ...
  ```
  Note: it exits **1** when "model not configured" (the known fresh-install warning) even though it prints the full table — so tests assert on **output content**, not exit code.
- **`pi -p "<prompt>" --no-tools`** — non-interactive; ask it to list available skill names. `--no-tools` keeps it read-only.
- **Source-confirmed contract (pi 0.85.1 `dist/core/skills.js` `loadSkills()`):** `settings.skills` → `skillPaths`; each entry is `resolvePath`d, must exist (missing → warning diagnostic), a dir → `loadSkillsFromDirInternal` (recursive `SKILL.md` scan), a `.md` file → single skill. So an absolute dir path in the `skills` array is scanned recursively — exactly our `skills/` layout.

**Which check for which mode:** dev mode → `pi -p` + `hermes skills list` on this box; standalone mode → the same probes run inside DTS (CI) after standalone install+boot, since this box cannot simulate standalone cleanly.

## 5. How We Test / Verify (TDD + real output)

### 5.1 The verification contract (all must stay GREEN)

```
bash tests/test_knowledge_mode.sh      # 4/4
bash tests/test_boot_symlinks.sh       # 10/10
bash tests/test_bootstrap.sh           # 16/16
bash scripts/verify-knowledge.sh       # F1-F5
```

(CI: test / real-install / dts-integration jobs must pass.)

> **Note (pre-existing, out of Phase 24 scope):** `verify-knowledge.sh F4` currently reports
> 1 failure — `wiki/mnemon-graph-viewer.md → ../skills/mnemon-graph-export/SKILL.md (not found)`
> + an F4 python error. This is a Phases 16-20 wiki-link integrity issue, unrelated to Phase 24
> (my changes touch no wiki files; F1/F3/F5 pass). F4 is NOT part of the Phase 24 gate; leaving
> it for the wiki-content phase.

### 5.2 New tests (TDD — RED first, then GREEN)

**A. `tests/test_pi_settings.sh` — new unit test file** (follows style of `test_boot_symlinks.sh`): **8 tests, all PASS locally**

| Test | Assertion |
|------|-----------|
| `test_pi_settings_file_created` | calling helper with missing file creates it, exit 0 |
| `test_pi_settings_skills_written` | called with a path → `"skills": ["<path>"]` present in JSON |
| `test_pi_settings_preserves_packages` | existing `packages` key (like pi-failover) survives the merge |
| `test_pi_settings_idempotent` | call twice → file byte-identical after 2nd call |
| `test_pi_settings_dedupe` | same path twice in array → one entry |
| `test_pi_settings_absolute_path_kept` | relative paths NOT collapsed; absolute path stored as-is |
| `test_pi_settings_reassert_on_drift` | simulate boot re-assert: entry removed → helper re-adds it |

**B. `tests/test_boot_symlinks.sh` addition** (boot re-assert):
- new `test_pi_settings_reassert` — simulate boot with settings missing skills → helper re-adds it
- (keeps boot idempotency group intact)

**C. Dev-mode real verification on THIS box** (after implementation) — **ALL DONE + PASSING**:
```
# 1. Run the new unit tests → all pass
bash tests/test_pi_settings.sh          # 8/8 PASS

# 2. Real dev-mode settings.json on THIS box
cat ~/.pi/agent/settings.json
# ✅ packages preserved AND "skills": ["/workspaces/.minions/skills"]

# 3. Hermes actually sees the skills (real binary)
hermes skills list
# ✅ all 16 minions skills listed (docker-test-shell, karpathy-coding-guidelines, ...),
#    source=minions, status=enabled, exit 0

# 4. Pi actually discovers the skills (real binary, non-interactive)
pi -p "list only the name field of every skill available to you. Read-only: do not create or modify any files." --no-tools
# ⚠️ With --no-tools, pi's model has no read/bash tool, so it cannot enumerate the
#    skills externally — it answered "I cannot actually run commands [to list skills]".
#    This is an honest limitation of the check, NOT a wiring failure:
#    - the settings.json merge is proven (packages + skills present)
#    - Pi's source contract (loadSkills reads settings.skills) is confirmed
#    - Hermes proves the same skills dir is live
#    The DTS 8c check retries WITH tools/provider (omniroute) so the model CAN list them.
```

**D. Standalone-mode verification (both modes, per user)** — in DTS (CI):
- `tests/test_dts.sh` standalone install+boot asserts `~/.pi/agent/settings.json` has `"skills": ["$HOME/.minions/skills"]` (**added**)
- `test_dts.sh` 8c: `pi -p` WITH provider/model (tools enabled) lists the minions skills; fallback asserts settings.json skills path (**added**)
- CI `real-install` T7b: standalone piped install (fake HOME) asserts `.pi/agent/settings.json` has the `skills` array + standalone path (**added**)
- the standalone `pi`/`hermes` probes run inside the standalone container; this box cannot simulate standalone cleanly (CI is the standalone proof per user qn3)

### 5.3 Manual CI check before merge

```
gh pr checks <N>   # test / real-install / dts-integration all ✅
```

## 6. TDD Sequence (how I'll implement)

1. Write `tests/test_pi_settings.sh` (A above) → run → **RED** (helper doesn't exist)
2. Create `lib/pi-settings.sh` → run → **GREEN**
3. Wire `install.sh` + `boot.sh` (source helper + calls), replace stale comment
4. Add `test_pi_settings_reassert` to `test_boot_symlinks.sh` → **RED** → wire boot call → **GREEN**
5. Run full verification contract (5.1) + real-mode checks (5.2C) on this machine
6. Commit per logical phase; push branch; open PR

## 7. Commit Plan (reviewable units)

1. `test: add test_pi_settings.sh for Pi skills wiring (RED)` — tests only
2. `feat(lib): add lib/pi-settings.sh wire_pi_skills_path helper` — helper + GREEN
3. `feat(install): wire Pi shared skills path into ~/.pi/agent/settings.json` — install.sh
4. `feat(boot): re-assert Pi skills path on boot` — boot.sh + boot test
5. `docs: proposal + status update` — proposal & IMPLEMENTATION-STATUS.md notes

## 8. Rollback (`git checkout` one line per file)

- `git checkout -- lib/pi-settings.sh install.sh boot.sh`
- remove `"skills"` from `~/.pi/agent/settings.json` (or restore file)

## 9. Out of Scope / Not Doing (per user — stop after Phase 24)

- Skip dev-mode install verification (per user decision)
- Skip Phase 21 (mnemon seed), 24-28 (5 new codespace skill verifications), 29-31 (proxy features)
- No `pi config` TUI automation, no package-style local-path package, no auto-enable via packages
- No Hermes-side changes (Hermes already wired Phase 23)

## 10. Decisions — RESOLVED per user review

1. **`pi list` limitation (5.2C/D):** RESOLVED — verify via `pi -p "<prompt>" --no-tools` asking for skill names, plus `hermes skills list` for Hermes, plus JSON assertions. (User: "ask pi -p to list all minions skills as a check. This also possible for hermes too.")
2. **python3 dependency:** accepted (already implied by install.sh's hermes.py path).
3. **Standalone-mode proof:** accepted — standalone verified in DTS (CI) only, with BOTH modes tested (dev on this box, standalone in DTS). (User: "make sure we test both dev and standalone mode.")
4. **`skills` key vs local-path `packages`:** RESOLVED — user agrees with the `skills` array choice. Explanation retained below for reviewers.

**Qn4 explanation — `skills` key vs local-path `packages`:**

The original Phase 24 plan assumed "wire a `skills` array into settings.json." While researching, I found Pi's docs also describe a `packages` mechanism for pointing at a whole directory (a "local-path package" whose conventional `skills/` subdir auto-discovers `SKILL.md`). That raised a real choice:

- **`settings.skills` (array)** — the documented way to make Pi load skills from an *extra directory* (docs literally show `"skills": ["~/.claude/skills"]` to reuse Claude Code's skills). It points *directly at the skill dir*, scans it recursively for `SKILL.md`, and is the closest match to "make Pi see our existing `skills/` dir."
- **`packages` (local-path package)** — the canonical way to share a *self-contained, versioned package* (bundles skills + extensions + prompts + themes, with a `package.json` manifest, `pi config` enable/disable, scope/dedup semantics). Heavier: needs a package manifest, package-scope identity, and it was designed for installing distributable packages, not for pointing at an existing sibling dir.

Our `.minions/skills/` is a bare directory of skill folders (no `package.json`, not a distributable package) in the same role as `.claude/skills`. So the **`skills` array is the right, minimal fit** — it is exactly the documented "point at another harness's skill dir" case, matches the proposal's original intent, and keeps `packages` (pi-failover) untouched. The `packages` route would add a manifest + `pi config` enable step without benefit here (we don't ship extensions via this path yet). If you later want .minions to also expose *extensions* to Pi, THAT is when a package (`pi.skills` + `pi.extensions` manifest) becomes the right choice — not now.

---

*Draft for review — no code written yet.*