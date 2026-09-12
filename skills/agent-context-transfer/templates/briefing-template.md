# {{PROJECT_NAME}} — Fresh Agent Briefing

**Date:** {{DATE}}
**Branch:** {{BRANCH}} (PR #{{PR_NUMBER}} {{PR_STATUS}})
**Status:** Phases {{COMPLETED_PHASES}} {{COMPLETION_STATUS}}

---

## What This Document Is

Complete transfer package for a fresh agent taking over the {{PROJECT_NAME}} project.

---

## 1. Current State Summary

### ✅ Completed

| Area | Status | Evidence |
|------|--------|----------|
| {{#COMPLETED_ITEMS}} | ✅ | {{EVIDENCE}} |
| {{/COMPLETED_ITEMS}} |

### ⚠️ Known Gaps (Expected — Not Blockers)

| Gap | Phase | Current State |
|-----|-------|---------------|
| {{#KNOWN_GAPS}} | {{PHASE}} | {{STATE}} |
| {{/KNOWN_GAPS}} |

---

## 2. Required Skills — Load These FIRST

### A. Core Workflow Skills (Hermes built-in)

```bash
{{#CORE_SKILLS}}
skill_view(name='{{NAME}}')        # {{PURPOSE}}
{{/CORE_SKILLS}}
```

### B. Repo-Ported Skills (authoritative copies)

```bash
{{#REPO_SKILLS}}
skill_view(name='{{NAME}}')              # {{PURPOSE}}
{{/REPO_SKILLS}}
```

### C. Task-Relevant Skills (load as needed)

```bash
{{#TASK_SKILLS}}
skill_view(name='{{NAME}}')              # {{PURPOSE}}
{{/TASK_SKILLS}}
```

### Skill Loading Order

```
{{#LOAD_ORDER}}
{{ORDER}}. {{NAME}}          ← {{REASON}}
{{/LOAD_ORDER}}
```

---

## 3. Verification Checklist

{{#VERIFICATION_STEPS}}
### {{STEP_NUM}}. {{TITLE}}
```bash
{{COMMAND}}
# EXPECT: {{EXPECTATION}}
```
{{/VERIFICATION_STEPS}}

### If Verification Fails

```bash
{{FAILURE_COMMANDS}}
# Trace: {{TRACE_PATH}}
```

---

## 4. Key Files — Read in Order

| File | Purpose | Critical Sections |
|------|---------|-------------------|
| {{#KEY_FILES}}
| {{PATH}} | {{PURPOSE}} | {{SECTIONS}} |
| {{/KEY_FILES}} |

---

## 5. Remaining Implementation

### {{PHASE_GROUP_1}} (Priority: {{PRIORITY_1}})

| Phase | Task | Dependencies | Deliverable |
|-------|------|--------------|-------------|
| {{#PHASES_1}}
| **{{NUM}}** | {{TASK}} | {{DEPS}} | {{DELIVERABLE}} |
| {{/PHASES_1}} |

### {{PHASE_GROUP_2}}

| Phase | Task | Dependencies | Deliverable |
|-------|------|--------------|-------------|
| {{#PHASES_2}}
| **{{NUM}}** | {{TASK}} | {{DEPS}} | {{DELIVERABLE}} |
| {{/PHASES_2}} |

---

## 6. Critical Gotchas

{{#GOTCHAS}}
### Gotcha {{NUM}}: {{TITLE}}
```bash
# {{WRONG_LABEL}}
{{WRONG_CODE}}

# {{CORRECT_LABEL}}
{{CORRECT_CODE}}
```
{{EXPLANATION}}
{{/GOTCHAS}}

---

## 7. CI Pipeline

```yaml
# {{CI_CONFIG_PATH}} — {{NUM_JOBS}} jobs, MUST all pass

{{#CI_JOBS}}
{{NAME}}:              # {{DURATION}} — {{SCOPE}}
  - {{TEST_1}}
  - {{TEST_2}}
{{/CI_JOBS}}
```

---

## 8. Prompt Template for Fresh Agent

```
{{PROMPT_TEMPLATE}}
```

---

## 9. Quick Reference — Commands

```bash
{{#QUICK_COMMANDS}}
# {{DESC}}
{{COMMAND}}
{{/QUICK_COMMANDS}}
```

---

## 10. Contact / Escalation

- **Repo:** {{REPO_URL}}
- **Current PR:** #{{PR_NUMBER}} ({{PR_STATUS}})
- **Prior PR:** #{{PRIOR_PR}} ({{PRIOR_STATUS}})

---

*Generated {{DATE}} by the agent that completed Phases {{COMPLETED_PHASES}}.*
