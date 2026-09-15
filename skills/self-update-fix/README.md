# self-update-fix skill

**Status:** Authored ✅

The fix-agent skill that tells the agent how to fix a failing dependency
update PR. Used by `scripts/self-update-fix.sh` and the `self-update.yml`
orchestrator.

## What this skill defines

1. **How to invoke the agent** (Hermes/Pi CLI command) with a prompt
   containing `(PR_NUMBER, DEP, VERSION, FAILED_CHECK)`.
2. **Guardrails** (D2): the agent must never touch `.github/workflows/`.
3. **How to push fixes** to the PR branch (git auth, branch checkout).
4. **How to re-trigger CI** after pushing.
5. **Exit codes and summary output** so the orchestrator can determine
   the next step (retry, label PR for human, etc.).

## Key decisions

- The agent should not touch `.github/workflows/` (D2).
- Fix attempts are capped at 3 (D9). After 3 failed attempts, the PR
  is left open and labeled `self-update: needs-review` for a human.
- The agent must use the Hermes or Pi CLI to interact with the PR.

## See also

- `docs/PROPOSAL-self-update-dependencies.md` — design decisions D9, D10.
- `scripts/self-update-fix.sh` — the helper script that calls this skill.
- `skills/self-update-fix/SKILL.md` — the skill file.
