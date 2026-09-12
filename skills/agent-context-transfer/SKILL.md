---
name: agent-context-transfer
description: Transfer implementation context to a fresh agent for seamless handoff
category: productivity
metadata:
  hermes:
    requires_tools:
      - read_file
      - write_file
      - terminal
      - skill_view
      - search_files
    requires_toolsets: []
    requires_plugins: []
---

# Agent Context Transfer Skill

Use when a fresh agent needs to continue work on a multi-session implementation. Provides a standardized briefing template, verification checklist, and handoff protocol.

## Purpose

Eliminate context loss when switching agents or sessions. Captures:
- Current implementation state (what's done/verified/broken)
- Required skills and loading order
- Verification contract (tests that must stay green)
- Remaining work with dependencies
- Critical gotchas and pitfalls
- Ready-to-use prompt template for the fresh agent

## Files

- `templates/briefing-template.md` — Reusable briefing template
- `scripts/verify-handoff.sh` — Auto-verifies handoff completeness
- `references/context-checklist.md` — What must be included in any handoff

## Usage

```bash
# As the OUTGOING agent: create briefing from template
bash ~/.hermes/skills/agent-context-transfer/scripts/verify-handoff.sh create

# As the INCOMING agent: load this skill + read the briefing
skill_view(name='agent-context-transfer')
read_file("~/.hermes/skills/agent-context-transfer/templates/briefing-template.md")
```

## Handoff Protocol

1. **Outgoing agent** fills template with current state
2. **Outgoing agent** runs `verify-handoff.sh validate` — checks all required sections present
3. **Outgoing agent** commits briefing to repo (or shares via mnemon/memory)
4. **Incoming agent** loads this skill, reads briefing, loads listed skills, begins verification
