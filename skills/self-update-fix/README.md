# self-update-fix skill

**Status:** TODO — to be authored

The fix-agent skill that tells the agent how to fix a failing dependency
update PR. Used by `scripts/self-update-fix.sh` and the `self-update.yml`
orchestrator.

## What this skill must define

1. **How to invoke the agent** (Hermes/Pi CLI command) with a prompt
   containing the PR number, failed check, dep, and version.
2. **Guardrails** (D2): the agent must never touch `.github/workflows/`.
3. **How to push fixes** to the PR branch (git auth, branch checkout).
4. **How to re-trigger CI** after pushing.

## See also

- `docs/PROPOSAL-self-update-dependencies.md` — design decisions D9, D10.
- `scripts/self-update-fix.sh` — the helper script that calls this skill.
