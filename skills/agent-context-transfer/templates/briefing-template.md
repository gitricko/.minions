# Agent Handoff Briefing Template

**Date:** YYYY-MM-DD
**Branch:** `<branch-name>` (PR #<number> <status>)
**Status:** Phases X-Y **<STATUS>** — <summary>

---

## What This Document Is

This is a **complete transfer package** for a fresh agent taking over the project after Phases X-Y completion. It contains:

1. **Current implementation state** — what's done, what's verified, what's broken
2. **Exact skills to load** — with paths and why each matters
3. **Verification checklist** — the steps the prior agent ran to confirm completion
4. **Remaining implementation plan** — next phases with dependencies
5. **Known gotchas** — bugs fixed, pitfalls to avoid
6. **Prompt template** — ready-to-use prompt for the fresh agent

---

## 1. Current State Summary

### ✅ Completed (Phases X-Y, PR #<number> <merged/open>)

| Area | Status | Evidence |
|------|--------|----------|
| <Area 1> | ✅ | <Evidence> |
| <Area 2> | ✅ | <Evidence> |
| <Area 3> | ✅ | <Evidence> |

### ⚠️ Known Gaps (Expected — Not Blockers)

| Gap | Phase | Current State |
|-----|-------|---------------|
| <Gap 1> | <Phase> | <State> |
| <Gap 2> | <Phase> | <State> |

---

## 2. Required Skills — Load These FIRST

The fresh agent **MUST** load these skills before doing any work.

### A. Built-in Skills (load via `skill_view`)

```bash
# Core workflow skills
skill_view(name='test-driven-development')        # RED→GREEN→REFACTOR; tests before code
skill_view(name='karpathy-coding-guidelines')     # Minimal diffs, root-cause fixes, verify by real output
skill_view(name='github')                          # PR management, reviews, CI
skill_view(name='ci-lint-check')                  # Pre-commit lint validation locally
```

### B. Repo-Ported Skills (load via `skill_view` — authoritative copies)

```bash
# From <repo-path>/skills/
skill_view(name='<skill-1>')              # <description>
skill_view(name='<skill-2>')              # <description>
skill_view(name='<skill-3>')              # <description>
```

### C. Task-Relevant Skills (load as needed)

```bash
skill_view(name='<skill-a>')  # <description>
skill_view(name='<skill-b>')  # <description>
```

### Skill Loading Order (Recommended)

```
1. test-driven-development          ← DO THIS FIRST — defines workflow
2. karpathy-coding-guidelines       ← Coding style rules
3. <auth-skill>                     ← Git auth for PR push
4. <integration-test-skill>         ← Integration testing workflow
5. ci-lint-check                    ← Local lint before push
6. [others as task requires]
```

---

## 3. Verification Checklist — Phases X-Y Completion

```bash
# 1. <Verification 1>
<command>
# EXPECT: <expected output>

# 2. <Verification 2>
<command>
# EXPECT: <expected output>

# 3. <Verification 3>
<command>
# EXPECT: <expected output>
```

### If Verification Fails

Capture and trace:
```bash
<diagnostic command 1>
<diagnostic command 2>
# Trace: <trace path>
```

---

## 4. Key Files — Read These in Order

| File | Purpose | Critical Sections |
|------|---------|-------------------|
| `<file-1>` | <purpose> | <sections> |
| `<file-2>` | <purpose> | <sections> |
| `<file-3>` | <purpose> | <sections> |

---

## 5. Artifacts Created (Phases X-Y)

| Phase | Artifacts |
|-------|-----------|
| **X** | <list> |
| **Y** | <list> |

---

## 6. Remaining Implementation — Phases <next>-<last>

### Phase <next>: <Title> (Priority: HIGH/MEDIUM/LOW)

| Task | Dependencies | Deliverable |
|------|--------------|-------------|
| <Task 1> | <Dep> | <Deliverable> |

### Phase <next+1>: <Title>

...

---

## 7. Critical Gotchas — Do Not Re-Introduce

### Gotcha 1: <Name>

```bash
# WRONG
<wrong pattern>

# CORRECT
<correct pattern>
```

### Gotcha 2: <Name>

...

---

## 8. CI Pipeline — Keep These Green

```yaml
# <ci-config-path> — <N> jobs, MUST all pass

<job-1>:              # <time> — <description>
  - <test-1>
  - <test-2>

<job-2>:              # <time> — <description>
  - <test-3>
```

**Do not weaken any hard-fail to warn.** <Reason if applicable>.

---

## 9. Prompt Template for Fresh Agent

Copy-paste this to start a fresh agent:

```
You are a fresh agent taking over the <project> project.

REPO: <path> (branch <branch>, PR #<number> <status>)
GOAL: <next goal>

READ FIRST (in this order):
1. <briefing-doc>          ← THIS FILE — your complete briefing
2. <status-doc>            ← Reality record + verification steps
3. <design-doc>            ← Architecture design
4. <plan-doc>              ← Phase plan (remaining phases pending)

LOAD SKILLS (mandatory before any work):
- test-driven-development          (built-in) — RED→GREEN→REFACTOR
- karpathy-coding-guidelines       (built-in) — Minimal diffs, verify by real output
- <auth-skill>                     (repo skills/)   — Git auth for git push
- <integration-test-skill>         (repo skills/)   — Integration testing
- ci-lint-check                    (repo skills/)   — Pre-commit lint locally

KEY FILES:
- <key-file-1>       — <purpose>
- <key-file-2>       — <purpose>

VERIFICATION CONTRACT (all must stay GREEN):
- <verification-cmd-1>
- <verification-cmd-2>

NEXT WORK (in order):
1. <Next task>
2. <Following task>

KNOWN GAPS (don't chase — these are expected):
- <Gap 1>
- <Gap 2>

CODING STYLE: Karpathy (minimal diffs, root-cause, verify by real output)
WORKFLOW: TDD — write failing test first, implement fix, refactor, keep CI green
```

---

## 10. Quick Reference — Commands

```bash
# Run all unit tests
<test-command-1> && <test-command-2>

# Run integration test (requires Docker)
<integration-test-cmd>

# Verify CI locally (lint)
<lint-cmd>

# Push with auth (if git rejects)
<auth-cmd>
git push origin HEAD

# Other useful commands
<other-cmd>
```

---

## 11. Contact / Escalation

- **Repo:** <repo-url>
- **PR #<current>:** <description> (<status>)
- **PR #<previous>:** <description> (<status>)
- **Images:** <image-refs>

---

*Generated <date> by the agent that completed Phases X-Y.*