#!/usr/bin/env bash
# admin-update.sh - Administrative one-command update for self-update system
# Parses check-updates.sh output and runs bump.sh with the detected updates
#
# Usage:
#   scripts/admin-update.sh                 # Bump all outdated deps
#   scripts/admin-update.sh --dry-run      # Preview only (no changes)
#   scripts/admin-update.sh NODE UV        # Bump specific deps only
#
# Guardrails:
#   - Does NOT modify .github/workflows/ (D2)
#   - Requires check-updates.sh to have run first (or runs it automatically)
#   - Exits 1 if no outdated deps found (unless --force)

# Remove set -u to avoid unbound variable issues, or handle it carefully
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DPS_YAML="${REPO_ROOT}/etc/deps.yaml"
VERSIONS_ENV="${REPO_ROOT}/etc/versions.env"

# Helper: parse check-updates.sh --json output and return name=value pairs
parse_outdated() {
    local json_file="$1"
    python3 -c "
import sys, json
with open('$json_file') as f:
    data = json.load(f)
pairs = []
for dep in data.get('outdated', []):
    if dep.get('outdated') is True:
        pairs.append(f\"{dep['name']}={dep['latest']}\")
print(' '.join(pairs))
" 2>/dev/null || echo ""
}

# Parse deps from command line args, or from check-updates.sh
DEPS=""
FORCE=0
DRY_RUN=0

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        *)
            # Treat as deps to bump (name=version pairs)
            DEPS="$DEPS $1"
            shift
            ;;
    esac
done

# If no deps specified, parse from check-updates.sh
if [ -z "$DEPS" ]; then
    JSON_FILE=$(mktemp)
    if scripts/check-updates.sh --json > "$JSON_FILE" 2>/dev/null; then
        DEPS=$(parse_outdated "$JSON_FILE")
    fi
    rm -f "$JSON_FILE"
fi

# If no deps found, exit
if [ -z "$DEPS" ]; then
    echo "No outdated dependencies found."
    if [ "$FORCE" -ne 1 ]; then
        exit 1
    fi
    echo " (use --force to override)"
    exit 1
fi

# If dry-run, just show what would be done
if [ "${DRY_RUN:-0}" -eq 1 ]; then
    echo "Would bump: $DEPS"
    echo " (run without --dry-run to actually update)"
    exit 0
fi

# Run the bump
echo "Bumping: $DEPS"
scripts/bump.sh --open-pr $DEPS

# Optionally sync versions
if [ "${SYNC_VERSIONS:-0}" -eq 1 ]; then
    echo "Syncing versions.env..."
    scripts/sync-versions.sh
fi

echo "admin-update.sh complete."
exit 0
