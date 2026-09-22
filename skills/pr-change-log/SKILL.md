---
name: pr-change-log
description: Use when a multi-commit PR needs its description written/updated, or when closing out a long branch with many fix commits.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [pr, documentation, git, changelog, github]
    related_skills: [github-codespace, github-pr-review, karpathy-coding-guidelines]
---

# PR Change-Log Capture

Write a PR description that tells the *story* of the branch — root causes fixed,
decisions made, and what reviewers should focus on — not just a list of commits.

## The core idea

A long branch (10–50 commits) is a *debugging narrative*, not a change log.
Most commits are iterations: "fix attempt", "whoops, that broke X", "CI
debounce". The PR body is the one permanent artifact reviewers and future
maintainers read — make it the distilled story, not the raw transcript.

## The 5-step procedure

1. **Get the full commit list.**
   ```bash
   git log --oneline main..<branch>
   git log --oneline main..<branch> | wc -l       # scope check
   git diff main...<branch> --stat | tail -5      # file/line totals
   ```

2. **Classify each commit** into buckets:
   - **Root-cause fixes** → these go in the body (with commit hashes)
   - **Test/logging/CI plumbing** → one line "improved test capture"
   - **Cosmetic/iteration noise** → drop or fold into a single line
   - **Docs** → one line

3. **Write the body as a story**, not a list:
   - Opening: what the PR does in 1–2 sentences
   - "Key fixes" table: symptom → root cause → fix → commit hash
   - "Remaining known issues" section: what's intentionally left (with reasons)
   - CI status: which jobs pass, durations
   - Never include: every commit message, installation instructions, or
     the same info twice.

4. **Verify against reality** before submitting:
   ```bash
   gh pr view <n> --json state,mergeable,statusCheckRollup
   # make sure the description matches the actual final state
   # (e.g. don't say "3 jobs pass" if CI is still running)
   ```

5. **Update the body:**
   ```bash
   gh pr edit <n> --body-file /tmp/pr_body.md
   ```

## Templates

### Table for "Key Fixes"

```
| Area | Fix | Commit |
|------|-----|--------|
| <component> | <what was wrong + what fixed it> | <short sha> |
```

### "Remaining known issues" format

```
| Warning/Issue | Reason | Action |
|---------------|--------|--------|
| <symptom> | <root cause, often upstream> | <optional: tracked where> |
```

## Anti-patterns

- **Dumping `git log` output into the body** — reviewers can run
  `git log` themselves; the body must add interpretation.
- **Listing every commit** — a 38-commit PR with 38 bullets is unreadable.
  Distill to the ~8 that matter.
- **Stale description** — if the branch evolved after the body was written
  (new failures fixed, old fixes reverted), the body must be updated before
  merge, not left as the first draft.
- **Overselling** — don't say "all WARNs gone" when benign warnings remain.
  List them with reasons; it builds reviewer trust.

## Real-world example

PR #42 (ModelRelay → 9Router migration): 38 commits, 35 files, +758/−287.
The original auto-generated body was an alphabetical list of every file
changed. The final body restructured it as:

- Core migration (5 bullets)
- Key fixes table (8 rows: mnemon PATH, Hermes config, log capture, self-check,
  mnemon version, log upload naming, chat max_tokens, Ubuntu 26.04)
- Remaining benign WARNs table (4 rows with upstream reasons)
- CI status line

This let the reviewer see at a glance: what broke, what was found, what was
fixed, and what remains intentionally unfixed — instead of wading through
`diffhunk` links.

## When NOT to use

- Single-commit PR → the commit message is enough
- Trivial docs/typo PR → overkill
- The branch only has code already reviewed commit-by-commit (like a
  self-update PR with one dep bump)