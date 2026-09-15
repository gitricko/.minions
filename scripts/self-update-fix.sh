#!/usr/bin/env bash
# scripts/self-update-fix.sh — fix a failing dependency update PR.
# Boot minion from stable main in the runner, invoke the fix-agent,
# push fixes to the PR branch, and re-trigger CI.
#
# Usage: scripts/self-update-fix.sh <PR_NUMBER> <DEP> <VERSION> <FAILED_CHECK>
#   PR_NUMBER  — the GitHub PR number to fix
#   DEP        — the dependency that caused the failure
#   VERSION    — the version that was bumped
#   FAILED_CHECK — the CI check name that failed
#
# The fix-agent is invoked via the `self-update-fix` skill
# (skills/self-update-fix/SKILL.md), which documents how to edit
# the PR branch and the guardrails (never touch .github/workflows/).
# If the skill is not yet authored, this script falls back to a
# documented placeholder and exits non-zero (the PR stays open,
# labeled for a human).
#
# Returns 0 if fixes were pushed and CI re-triggered, non-zero otherwise.

set -u
set -e

PR_NUMBER="${1:?PR_NUMBER required}"
DEP="${2:?DEP required}"
VERSION="${3:?VERSION required}"
FAILED_CHECK="${4:?FAILED_CHECK required}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== self-update-fix ==="
echo "PR: ${PR_NUMBER} | dep: ${DEP}@${VERSION} | failed check: ${FAILED_CHECK}"

# Step 1: Boot minion from stable main in the runner.
# This gives the fix-agent access to OmniRoute/ModelRelay (LLM routing).
echo "[1/3] Installing minion from stable main..."
if [ ! -x "${REPO_ROOT}/install.sh" ]; then
    echo "self-update-fix: install.sh not found at ${REPO_ROOT}/install.sh" >&2
    exit 1
fi
bash "${REPO_ROOT}/install.sh" --no-hermes --no-omniroute --no-modelrelay >/tmp/install.log 2>&1 || {
    echo "self-update-fix: install.sh failed" >&2
    cat /tmp/install.log >&2
    exit 1
}

echo "[2/3] Booting the stack..."
export PATH="${REPO_ROOT}/bin:${PATH}"
timeout 300s bash "${REPO_ROOT}/boot.sh" >/tmp/boot.log 2>&1 || {
    echo "self-update-fix: boot.sh failed" >&2
    cat /tmp/boot.log >&2
    exit 1
}

# Step 3: Invoke the fix-agent.
# The agent is expected to:
#   - Checkout the PR branch.
#   - Understand the failure (read the CI check output).
#   - Apply fixes to the PR branch (respecting guardrails: never touch .github/workflows/).
#   - Push fixes to the PR branch (triggers CI re-run).
#
# This delegates to the `self-update-fix` skill when authored.
# Until then, this is a documented placeholder: the skill must be
# created (skills/self-update-fix/SKILL.md) for the agent to know how to proceed.
echo "[3/3] Invoking fix-agent for PR ${PR_NUMBER}..."

AGENT_SKILL="${REPO_ROOT}/skills/self-update-fix/SKILL.md"
if [ ! -f "${AGENT_SKILL}" ]; then
    echo "self-update-fix: fix-agent skill not yet authored at ${AGENT_SKILL}" >&2
    echo "self-update-fix: PR ${PR_NUMBER} left open for human review." >&2
    exit 1
fi

# TODO: Invoke the agent per the self-update-fix skill.
# The skill defines how to call the agent (e.g., via Hermes/Pi CLI)
# with a prompt containing (PR_NUMBER, FAILED_CHECK, DEP, VERSION).
# Example (to be filled when skill is authored):
#   "${MINIONS_HOME}/bin/hermes" --fix-pr "${PR_NUMBER}" ...
#   or
#   pi -p "Fix PR ${PR_NUMBER}..." --provider omniroute ...

echo "self-update-fix: agent invocation pending (skill to be authored)" >&2
exit 1
