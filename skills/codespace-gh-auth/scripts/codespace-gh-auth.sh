#!/usr/bin/env bash
# codespace-gh-auth.sh — Extract GitHub token from VS Code server for Codespaces
# Usage: source this file, then call get_github_token

# Returns the GitHub token extracted from VS Code server process
# Sets GITHUB_TOKEN env var and returns 0 on success, 1 on failure

get_github_token() {
    local vscode_pid
    vscode_pid=$(pgrep -f "server-main.js" | head -1)
    
    if [[ -z "$vscode_pid" ]]; then
        echo "ERROR: VS Code server not found (server-main.js)" >&2
        return 1
    fi
    
    local token
    token=$(cat "/proc/$vscode_pid/environ" 2>/dev/null | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
    
    if [[ -z "$token" ]]; then
        echo "ERROR: GITHUB_TOKEN not found in VS Code server environment" >&2
        return 1
    fi
    
    export GITHUB_TOKEN="$token"
    echo "$token"
    return 0
}

# Push current branch using token-embedded URL (no VS Code credential helper)
git_push_with_token() {
    local remote="${1:-origin}"
    local branch="${2:-$(git branch --show-current)}"
    
    if ! get_github_token; then
        return 1
    fi
    
    local remote_url
    remote_url=$(git remote get-url "$remote")
    
    # Rewrite remote URL with token embedded
    local token_url
    token_url=$(echo "$remote_url" | sed -E "s|https://github.com/|https://${GITHUB_TOKEN}@github.com/|")
    
    git remote set-url "$remote" "$token_url"
    git push "$remote" "$branch"
}

# Set GH_TOKEN for gh CLI commands
setup_gh_cli() {
    if ! get_github_token; then
        return 1
    fi
    export GH_TOKEN="$GITHUB_TOKEN"
}

# Complete workflow: commit, push, create PR
# Usage: codespace_create_pr "PR Title" "PR Body" [base_branch]
codespace_create_pr() {
    local title="$1"
    local body="$2"
    local base="${3:-main}"
    local branch
    branch=$(git branch --show-current)
    
    if [[ "$branch" == "main" ]]; then
        echo "ERROR: Cannot create PR from main branch" >&2
        return 1
    fi
    
    # Push with token
    if ! git_push_with_token; then
        echo "ERROR: git push failed" >&2
        return 1
    fi
    
    # Create PR via gh CLI
    if ! setup_gh_cli; then
        echo "ERROR: gh CLI setup failed" >&2
        return 1
    fi
    
    gh pr create --repo "$(git remote get-url origin | sed -E 's|.*github\.com[:/](.*)\.git|\1|')" \
        --head "$branch" --base "$base" --title "$title" --body "$body"
}