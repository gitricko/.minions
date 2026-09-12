# Context Handoff Checklist

This checklist defines what **must** be included in any agent-to-agent handoff briefing. Use with `verify-handoff.sh` to auto-validate.

## Required Sections (All Mandatory)

| # | Section | Purpose |
|---|---------|---------|
| 1 | Current State Summary | What's done, verified, known gaps |
| 2 | Required Skills | Skills to load, in order, with justification |
| 3 | Verification Checklist | Exact commands + expected outputs |
| 4 | Key Files | Priority-ordered reading list |
| 5 | Artifacts Created | Deliverables per phase |
| 6 | Remaining Implementation | Next phases with dependencies |
| 7 | Critical Gotchas | Bugs fixed, patterns to avoid (WRONG/CORRECT) |
| 8 | CI Pipeline | Jobs that must stay green |
| 9 | Prompt Template | Copy-paste for fresh agent startup |
| 10 | Quick Reference | Common commands |
| 11 | Contact / Escalation | Repo, PRs, images |

## Required Elements Within Sections

### Current State Summary
- [ ] Table with Area/Status/Evidence columns
- [ ] Separate table for Known Gaps with Phase/State
- [ ] Clear ✅/⚠️ visual indicators

### Required Skills
- [ ] Built-in skills listed with `skill_view(name='...')` calls
- [ ] Repo-ported skills with paths
- [ ] Task-relevant skills as needed
- [ ] **Loading order** explicitly numbered (test-driven-development FIRST)

### Verification Checklist
- [ ] Exact bash commands to run
- [ ] `EXPECT:` lines showing expected output
- [ ] Failure diagnosis commands
- [ ] Trace path from entry point through layers

### Key Files
- [ ] Table with File/Purpose/Critical Sections
- [ ] Ordered by reading priority

### Artifacts Created
- [ ] Per-phase deliverables listed
- [ ] File paths or descriptions

### Remaining Implementation
- [ ] Phases numbered with titles
- [ ] Priority indicators (HIGH/MEDIUM/LOW)
- [ ] Dependencies between phases
- [ ] Concrete deliverables

### Critical Gotchas
- [ ] Each gotcha has **WRONG** and **CORRECT** code blocks
- [ ] Root cause explained
- [ ] Pattern is generalizable (not one-off)

### CI Pipeline
- [ ] Job names, durations, purposes
- [ ] List of tests per job
- [ ] Explicit "Do not weaken hard-fail" warning

### Prompt Template
- [ ] Starts with "You are a fresh agent..."
- [ ] REPO, GOAL clearly stated
- [ ] READ FIRST list with 4+ docs in order
- [ ] LOAD SKILLS with mandatory/optional distinction
- [ ] KEY FILES table
- [ ] VERIFICATION CONTRACT (commands)
- [ ] NEXT WORK ordered list
- [ ] KNOWN GAPS (don't chase)
- [ ] CODING STYLE + WORKFLOW reminders

### Quick Reference
- [ ] Unit test command
- [ ] Integration test command
- [ ] Lint command
- [ ] Auth + push command
- [ ] Other project-specific commands

### Contact / Escalation
- [ ] Repo URL
- [ ] Current PR with status
- [ ] Previous relevant PR
- [ ] Container images if applicable

## Quality Gates

A handoff is **complete** only if:
- [ ] `verify-handoff.sh <briefing>` exits 0
- [ ] Fresh agent can run verification checklist and all pass
- [ ] Fresh agent can start Phase N+1 without asking clarifying questions
- [ ] All gotchas have WRONG/CORRECT patterns
- [ ] Prompt template is copy-paste ready

## Anti-Patterns to Avoid

| Anti-Pattern | Why It Breaks Handoff |
|--------------|----------------------|
| "Figure it out" / "See code" | Fresh agent has no context |
| Missing expected outputs | Can't verify correctness |
| No skill loading order | Wrong workflow applied first |
| Gotchas without CORRECT code | Re-introduces fixed bugs |
| Vague next steps ("continue work") | No actionable direction |
| Missing known gaps | Fresh agent wastes time on expected state |

---

*This checklist is part of the `agent-context-transfer` skill. Update when handoff patterns evolve.*