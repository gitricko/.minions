---
name: codespace-gh-auth
description: "Extract GitHub token from VS Code for API in Codespaces."
---

# GitHub Codespace Authentication

## Problem
In a GitHub Codespace, the GITHUB_TOKEN env var is set in the VS Code server process but NOT inherited by the Hermes agent session.

## Solution

### Quick Usage (Source the script, then use functions)

```bash
source /home/codespace/.hermes/skills/minions/codespace-gh-auth/scripts/codespace-gh-auth.sh

# Get token for API calls
get_github_token
curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/...

# Push with token-embedded URL (no credential prompts)
git_push_with_token

# Set up gh CLI
setup_gh_cli
gh pr create ...

# Full workflow: commit → push → PR
codespace_create_pr "Title" "Body"
```

### Step 1: Extract the real GITHUB_TOKEN from the VS Code server

```bash
VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
GITHUB_TOKEN=$(cat /proc/$VSCODE_PID/environ 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
```

### Step 2: Use it for API calls

```bash
curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/OWNER/REPO/issues/ISSUE_NUM/comments" \
  -d '{"body": "your comment"}'
```

### Step 3: Use it for gh CLI (optional)

```bash
unset GH_TOKEN
export GH_TOKEN="$GITHUB_TOKEN"
gh auth status
```

## Pitfalls
- Do NOT use GITHUB_CODESPACE_TOKEN for REST API calls (returns 401)
- Do NOT run gh auth login (unnecessary)
- The VS Code server PID can be found with: pgrep -f "server-main.js"
- Token is a GitHub App user-to-server token (ghu_xxx prefix), ~40 chars
- **Critical limitation**: This is a GitHub App token gated by Codespaces app installation. It works for the origin repo and Codespaces-connected repos, but FAILS (403) on other repos the user has access to. Use device code flow for those cases.

### Token Scope Comparison

| Method | Token Type | Scope | Works On |
|--------|------------|-------|----------|
| **Extract from VS Code** | GitHub App user-to-server (`ghu_`) | `repo` (app-gated) | Origin repo + Codespaces-connected repos only |
| **Device code flow** | Classic OAuth (`gho_`/`ghp_`) | Full user scopes | **All repos the user has access to** |
| **Unauthenticated API** | None | Public only | Public repos (read-only) |

**When to use device flow instead**: Working on repos outside the Codespaces app installation (other users' repos, orgs without Codespaces app).

## Scripts

- `scripts/codespace-gh-auth.sh` — Reusable functions: `get_github_token`, `git_push_with_token`, `setup_gh_cli`, `codespace_create_pr`

## References

- `references/git-push-with-token.md` — Complete git push + PR workflow using extracted token