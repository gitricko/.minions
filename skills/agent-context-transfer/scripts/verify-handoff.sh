#!/usr/bin/env bash
# verify-handoff.sh — Auto-verifies handoff briefing completeness
# Usage: bash verify-handoff.sh <briefing-doc-path>

set -euo pipefail

BRIEFING="${1:-}"
if [[ -z "$BRIEFING" ]]; then
    echo "Usage: $0 <briefing-doc-path>"
    exit 1
fi

if [[ ! -f "$BRIEFING" ]]; then
    echo "ERROR: Briefing document not found: $BRIEFING"
    exit 1
fi

echo "=== Verifying Handoff Briefing: $BRIEFING ==="
echo

MISSING=0

# Required sections (match by section number + keywords)
SECTIONS=(
    "1. Current State Summary"
    "2. Required Skills"
    "3. Verification Checklist"
    "4. Key Files"
    "5. Wiki Articles Populated"
    "6. Remaining Implementation"
    "7. Critical Gotchas"
    "8. CI Pipeline"
    "9. Prompt Template"
    "10. Context Transfer Skill"
    "11. Quick Reference"
    "12. Contact"
)

for section in "${SECTIONS[@]}"; do
    if grep -q "## $section" "$BRIEFING"; then
        echo "  ✅ Section: $section"
    else
        echo "  ❌ MISSING Section: $section"
        ((MISSING++))
    fi
done

# Required elements within sections
echo
echo "=== Checking Required Elements ==="

# Skills list
if grep -q "test-driven-development" "$BRIEFING"; then
    echo "  ✅ test-driven-development skill referenced"
else
    echo "  ❌ MISSING: test-driven-development skill"
    ((MISSING++))
fi

if grep -q "karpathy-coding-guidelines" "$BRIEFING"; then
    echo "  ✅ karpathy-coding-guidelines skill referenced"
else
    echo "  ❌ MISSING: karpathy-coding-guidelines skill"
    ((MISSING++))
fi

# Verification commands
if grep -q "EXPECT:" "$BRIEFING"; then
    echo "  ✅ Verification expectations documented"
else
    echo "  ❌ MISSING: Verification expectations (EXPECT:)"
    ((MISSING++))
fi

# Gotchas
if grep -q "WRONG" "$BRIEFING" && grep -q "CORRECT" "$BRIEFING"; then
    echo "  ✅ Gotchas show WRONG/CORRECT patterns"
else
    echo "  ❌ MISSING: Gotchas with WRONG/CORRECT patterns"
    ((MISSING++))
fi

# Prompt template
if grep -q "You are a fresh agent" "$BRIEFING"; then
    echo "  ✅ Prompt template present"
else
    echo "  ❌ MISSING: Prompt template"
    ((MISSING++))
fi

# Next work
if grep -q "NEXT WORK" "$BRIEFING"; then
    echo "  ✅ Next work items listed"
else
    echo "  ❌ MISSING: Next work items"
    ((MISSING++))
fi

# Known gaps
if grep -q "KNOWN GAPS" "$BRIEFING"; then
    echo "  ✅ Known gaps documented"
else
    echo "  ❌ MISSING: Known gaps"
    ((MISSING++))
fi

echo
if [[ $MISSING -eq 0 ]]; then
    echo "=== HANDOFF BRIEFING COMPLETE ==="
    exit 0
else
    echo "=== HANDOFF BRIEFING INCOMPLETE: $MISSING missing items ==="
    exit 1
fi