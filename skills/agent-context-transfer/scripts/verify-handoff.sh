#!/usr/bin/env bash
# verify-handoff.sh — Validate handoff briefing completeness

set -euo pipefail

BRIEFING_FILE="${1:-/workspaces/.minions/docs/BRIEFING-fresh-agent-transfer.md}"
ACTION="${2:-validate}"

REQUIRED_SECTIONS=(
    "Current State Summary"
    "Required Skills"
    "Verification Checklist"
    "Key Files"
    "Remaining Implementation"
    "Critical Gotchas"
    "CI Pipeline"
    "Prompt Template"
)

if [ "$ACTION" = "create" ]; then
    echo "Creating briefing from template..."
    TEMPLATE="/home/codespace/.hermes/skills/agent-context-transfer/templates/briefing-template.md"
    if [ -f "$TEMPLATE" ]; then
        cp "$TEMPLATE" "$BRIEFING_FILE"
        echo "Created $BRIEFING_FILE from template"
        echo "Edit it with project-specific details"
    else
        echo "Template not found at $TEMPLATE"
        exit 1
    fi
    exit 0
fi

if [ "$ACTION" = "validate" ]; then
    echo "Validating briefing: $BRIEFING_FILE"
    if [ ! -f "$BRIEFING_FILE" ]; then
        echo "FAIL: Briefing file not found"
        exit 1
    fi
    
    content=$(cat "$BRIEFING_FILE")
    missing=()
    for section in "${REQUIRED_SECTIONS[@]}"; do
        if echo "$content" | grep -q "## $section" || echo "$content" | grep -q "# $section"; then
            echo "  ✓ $section"
        else
            echo "  ✗ $section (MISSING)"
            missing+=("$section")
        fi
    done
    
    if [ ${#missing[@]} -eq 0 ]; then
        echo ""
        echo "All required sections present. Handoff ready."
        exit 0
    else
        echo ""
        echo "Missing sections: ${missing[*]}"
        exit 1
    fi
fi

echo "Usage: $0 [briefing-file] [create|validate]"
exit 1
