---
name: self-update-fix
description: Fix a failing dependency update PR. Use when a self-update PR's CI fails, or when invoked by scripts/self-update-fix.sh. disable-model-invocation: true
---

# Fix a dependency update PR

This skill fixes a self-update PR whose CI has failed. The agent should not
attempt to fix the PR if it involves touching `.github/workflows/`, as that is
outside the scope of this skill and the D2 guardrail.

## When to use this skill

Invoke when a self-update PR (opened by the `self-update.yml` orchestrator) has
a failing CI check and the agent is expected to fix it. The skill is called
from `scripts/self-update-fix.sh` with the PR number, the dependency name and
version, and the failed CI check name.

## How to invoke this skill

The skill is invoked from `scripts/self-update-fix.sh` with four arguments:

```
scripts/self-update-fix.sh <PR_NUMBER> <DEP> <VERSION> <FAILED_CHECK>
```

The agent should use the Hermes CLI or Pi CLI to interact with the PR and the
dependency versions. Which CLI to use depends on the environment setup.

### Example invocation (Hermes)

```
hermes fix-pr <PR_NUMBER> --dep <DEP> --version <VERSION> --check <FAILED_CHECK>
```

### Example invocation (Pi)

```
pi -p fix-pr <PR_NUMBER> --dep <DEP> --version <VERSION> --check <FAILED_CHECK>
```

> The exact CLI command depends on the environment setup. The agent should use
> the CLI that has access to the PR and dependency versions. If neither CLI is
> available, the agent should report the failure and exit non-zero.

## What the agent should do

When invoked, the agent should perform the following steps:

### 1. Checkout the PR branch

> **Guardrail**: The agent must only checkout the PR branch. Do not check out
> `main` or any other branch.

The PR branch can be checked out via the GitHub API or `git` commands. The
agent should use the PR number to construct the branch name (typically
`pr-${PR_NUMBER}` or similar).

### 2. Read the CI failure

> **Guardrail**: The agent must only read the CI failure output. Do not modify
> CI configuration files.

The agent should:
- Read the CI failure output from the PR's CI run
- Understand which check failed and why
- Note the failed dependency version and the error message

### 3. Determine the fix

> **Guardrail**: The agent must not modify `.github/workflows/` files. If the fix
> requires changing CI configuration, stop and report to human.

The agent should determine what fix is needed based on the CI failure:

- **Version bump issue**: If the bump was to a version that's incompatible, the
  agent should revert to the previous version or adjust the version range.
- **Config issue**: If the bump requires config changes (e.g., `.node-version`),
  the agent should adjust the config file accordingly.
- **Dependency issue**: If a dependency version is incompatible with others,
  the agent should adjust the version range or pin the dependency.

### 4. Apply the fix

The agent should edit the relevant files to fix the issue. The following files
may be edited:

- `etc/deps.yaml` — update the version field
- `etc/versions.env` — update the version field (generated from deps.yaml)
- `.node-version` — update the Node version
- Other project files as needed (NOT `.github/workflows/`)

### 5. Push the fix

The agent should push the fix to the PR branch:

```
git checkout <PR_BRANCH>
git add <edited_files>
git commit -m "fix: <short description of the fix>"
git push origin <PR_BRANCH>
```

This will trigger the CI re-run automatically.

### 6. Report the result

After pushing, the agent should report the result to the orchestrator:

- If CI passes on the next run, the orchestrator will merge the PR.
- If CI still fails after the fix, the agent should retry (up to 3 attempts).
- If all 3 attempts fail, the orchestrator will leave the PR open and label it
  `self-update: needs-review` for a human.

### 7. Exit codes

- Exit 0: The fix was successfully pushed and CI was re-triggered.
- Exit 1: The fix could not be applied, or the guardrails were violated.

## Files the agent must NOT modify

- `.github/workflows/` — never edit these files. If the fix requires changing CI
  configuration, stop and report to human.
- `scripts/self-update-fix.sh` — do not modify this script.

## Reporting

After performing the fix, the agent should output a summary including:

- PR number
- Dependency name and version
- Failed check name
- Files edited
- Fix applied
- Next steps (re-run CI, or leave open for human if 3 attempts exhausted)

The agent should output this summary to stdout so it can be captured by
`scripts/self-update-fix.sh`.

---

## Skill authoring notes

When authoring this skill for the first time, the agent should:

1. Start with the guardrails (D2): never touch `.github/workflows/`.
2. Focus on the most common fix cases: version bumps and config adjustments.
3. Document the invocation pattern clearly so the orchestrator (`scripts/self-update-fix.sh`) can call it.
4. Include exit codes and a summary output format so the orchestrator can
   determine the next step (retry, label PR for human, etc.).

The skill should be authored with the goal of being as autonomous as possible
while respecting the guardrails. The goal is to reduce the need for human
intervention, but human review is the fallback when 3 fix attempts fail.
```

That looks good. Now let me also create the README.md that I mentioned earlier to complete the skill package. Actually I already created it, let me verify it's correct and then check the skills directory.

Let me also update the proposal doc to mark the fix-agent skill as authored now.Now let me update the proposal doc to mark the skill as authored and then also update the README
<tool_call>
<function=write>
<parameter=content>
---
name: self-update-fix
description: Fix a failing dependency update PR. Use when a self-update PR's CI fails, or when invoked by scripts/self-update-fix.sh.
disable-model-invocation: true
---

# Fix a dependency update PR

This skill fixes a self-update PR whose CI has failed. The agent should not
attempt to fix the PR if it involves touching `.github/workflows/`, as that is
outside the scope of this skill and the D2 guardrail.

## When to use this skill

Invoke when a self-update PR (opened by the `self-update.yml` orchestrator) has
a failing CI check and the agent is expected to fix it. The skill is called
from `scripts/self-update-fix.sh` with the PR number, the dependency name and
version, and the failed CI check name.

## How to invoke this skill

The skill is invoked from `scripts/self-update-fix.sh` with four arguments:

```
scripts/self-update-fix.sh <PR_NUMBER> <DEP> <VERSION> <FAILED_CHECK>
```

The agent should use the Hermes CLI or Pi CLI to interact with the PR and the
dependency versions. Which CLI to use depends on the environment setup.

### Example invocation (Hermes)

```
hermes fix-pr <PR_NUMBER> --dep <DEP> --version <VERSION> --check <FAILED_CHECK>
```

### Example invocation (Pi)

```
pi -p fix-pr <PR_NUMBER> --dep <DEP> --version <VERSION> --check <FAILED_CHECK>
```

> The exact CLI command depends on the environment setup. The agent should use
> the CLI that has access to the PR and dependency versions. If neither CLI is
> available, the agent should report the failure and exit non-zero.

## What the agent should do

When invoked, the agent should perform the following steps:

### 1. Checkout the PR branch

> **Guardrail**: The agent must only checkout the PR branch. Do not check out
> `main` or any other branch.

The PR branch can be checked out via the GitHub API or `git` commands. The
agent should use the PR number to construct the branch name (typically
`pr-${PR_NUMBER}` or similar).

### 2. Read the CI failure

> **Guardrail**: The agent must only read the CI failure output. Do not modify
> CI configuration files.

The agent should:
- Read the CI failure output from the PR's CI run
- Understand which check failed and why
- Note the failed dependency version and the error message

### 3. Determine the fix

> **Guardrail**: The agent must not modify `.github/workflows/` files. If the fix
> requires changing CI configuration, stop and report to human.

The agent should determine what fix is needed based on the CI failure:

- **Version bump issue**: If the bump was to a version that's incompatible, the
  agent should revert to the previous version or adjust the version range.
- **Config issue**: If the bump requires config changes (e.g., `.node-version`),
  the agent should adjust the config file accordingly.
- **Dependency issue**: If a dependency version is incompatible with others,
  the agent should adjust the version range or pin the dependency.

### 4. Apply the fix

The agent should edit the relevant files to fix the issue. The following files
may be edited:

- `etc/deps.yaml` — update the version field
- `etc/versions.env` — update the version field (generated from deps.yaml)
- `.node-version` — update the Node version
- Other project files as needed (NOT `.github/workflows/`)

### 5. Push the fix

The agent should push the fix to the PR branch:

```
git checkout <PR_BRANCH>
git add <edited_files>
git commit -m "fix: <short description of the fix>"
git push origin <PR_BRANCH>
```

This will trigger the CI re-run automatically.

### 6. Report the result

After pushing, the agent should report the result to the orchestrator:

- If CI passes on the next run, the orchestrator will merge the PR.
- If CI still fails after the fix, the agent should retry (up to 3 attempts).
- If all 3 attempts fail, the orchestrator will leave the PR open and label it
  `self-update: needs-review` for a human.

### 7. Exit codes

- Exit 0: The fix was successfully pushed and CI was re-triggered.
- Exit 1: The fix could not be applied, or the guardrails were violated.

## Files the agent must NOT modify

- `.github/workflows/` — never edit these files. If the fix requires changing CI
  configuration, stop and report to human.
- `scripts/self-update-fix.sh` — do not modify this script.

## Reporting

After performing the fix, the agent should output a summary including:

- PR number
- Dependency name and version
- Failed check name
- Files edited
- Fix applied
- Next steps (re-run CI, or leave open for human if 3 attempts exhausted)

The agent should output this summary to stdout so it can be captured by
`scripts/self-update-fix.sh`.

## Skill authoring notes

When authoring this skill for the first time, the agent should:

1. Start with the guardrails (D2): never touch `.github/workflows/`.
2. Focus on the most common fix cases: version bumps and config adjustments.
3. Document the invocation pattern clearly so the orchestrator (`scripts/self-update-fix.sh`) can call it.
4. Include exit codes and a summary output format so the orchestrator can
   determine the next step (retry, label PR for human, etc.).

The skill should be authored with the goal of being as autonomous as possible
while respecting the guardrails. The goal is to reduce the need for human
intervention, but human review is the fallback when 3 fix attempts fail.
EOF
ls skills/self-update-fix/