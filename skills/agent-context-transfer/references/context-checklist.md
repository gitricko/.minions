# Handoff Context Checklist

Every agent-to-agent handoff must include these sections. Use with `verify-handoff.sh validate`.

## Required Sections

1. **Current State Summary**
   - What's completed (with evidence: test counts, CI status, file paths)
   - Known gaps (explicitly labeled as expected vs bugs)
   - Branch/PR status

2. **Required Skills**
   - Core workflow skills (TDD, coding guidelines) — Hermes built-in
   - Repo-ported skills — authoritative copies in repo
   - Task-relevant skills — load as needed
   - Loading ORDER (workflow skills first)

3. **Verification Checklist**
   - Numbered steps with exact commands
   - Expected output for each step
   - Failure diagnosis commands + trace path

4. **Key Files**
   - Ordered reading list with purpose + critical sections
   - File paths relative to repo root

5. **Remaining Implementation**
   - Phases with dependencies and deliverables
   - Priority ordering
   - Blocking relationships

6. **Critical Gotchas**
   - Each gotcha: WRONG code + CORRECT code + explanation
   - Env scope bugs, precedence bugs, path bugs, test isolation
   - "Do not re-introduce" warnings

7. **CI Pipeline**
   - Job names, durations, scopes
   - Test commands that must stay green
   - Hard-fail vs warn boundaries

8. **Prompt Template**
   - Copy-paste ready prompt for fresh agent
   - Includes all file paths, skill names, verification contract

9. **Quick Reference Commands**
   - Common dev commands (test, DTS, lint, push)
   - Mnemon/skill shortcuts

10. **Contact/Escalation**
    - Repo URL, PR numbers, prior PRs
    - DTS image references

## Quality Gates

- [ ] All verification commands actually run and pass
- [ ] No placeholder text ({{VARS}}) remains in final briefing
- [ ] Gotchas have real code examples from the project
- [ ] Skill names match actual skill_view() names
- [ ] File paths are verified to exist
- [ ] CI job names match .github/workflows/ci.yml
