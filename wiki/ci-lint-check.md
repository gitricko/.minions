# CI Lint Check Skill

> **Reference**: Run pre-commit CI lint validation locally before pushing to avoid GitHub Actions failures.

## Overview

The `ci-lint-check` skill provides a local script that mirrors the `lint-check` job in `.github/workflows/.github/workflows/ci.yml`. Running this before every commit/PR ensures CI passes without wasting time debugging in GitHub Actions.

## CI Job Classification

The CI workflow uses `dorny/paths-filter@v3` to classify changes:

| Category | Paths | CI Job | Duration |
|----------|-------|--------|----------|
| **infrastructure** | `install.sh`, `boot.sh`, `self-check.sh`, `devcontainer.json`, `.github/workflows/**` | `full-build` | ~15min |
| **runtime** | `skills/**`, `wiki/**`, `mnemon/**`, `memories/**`, `.hermes.md`, `codespace-cleanup.sh` | `lint-check` | ~30s |
| **docs** | `README.md`, `*.md` (root) | `lint-check` | ~30s |

**Key insight**: Changes to skills, wiki, mnemon, memories, and devcontainer shell scripts ONLY run the fast `lint-check` job (~30s). Only boot scripts, devcontainer.json, and workflow changes trigger the slow `full-build` (~15min).

## What the Lint Check Validates

| Check | Description | Files |
|-------|-------------|-------|
| **Markdown lint** | Style/formatting rules via markdownlint-cli | Wiki articles, SKILL.md files, .hermes.md, README.md |
| **SKILL.md structure** | YAML frontmatter with `name:` field | All skills in `skills/*/SKILL.md` |
| **Wiki INDEX.md** | Every article referenced in INDEX.md table | `wiki/*.md` |
| **Mnemon seed.json** | Schema validation (schema_version=1, insights array) | `mnemon/seed.json` |
| **Root shell syntax** | `bash -n` validation | `*.sh` |
| **Skill shell syntax** | `bash -n` validation | `skills/*/scripts/*.sh` |
| **Symlink persistence** | Boot scripts create correct symlinks | install.sh, boot.sh |

## Usage

### Install Dependencies (one-time)
```bash
npm install -g markdownlint-cli
```

### Run Full Validation
```bash
bash skills/ci-lint-check/scripts/ci_lint_check.sh
```

### Run Specific Checks
```bash
bash skills/ci-lint-check/scripts/ci_lint_check.sh --markdown-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --skills-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --wiki-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --mnemon-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --shell-only
bash skills/ci-lint-check/scripts/ci_lint_check.sh --symlink-only
```

### Pre-Commit Workflow
```bash
# 1. Make your changes
# 2. Run lint check
bash skills/ci-lint-check/scripts/ci_lint_check.sh

# 3. Fix any issues reported
# 4. Commit and push
git add -A
git commit -m "your message"
git push
```

## Mandatory Rule

> **ALWAYS run the lint check before committing or creating a PR** when modifying:
> - `skills/**`
> - `wiki/**`
> - `mnemon/**`
> - `memories/**`
> - `*.sh`

This is not optional — CI will fail and you'll waste time debugging in GitHub Actions.

## Integration with Git Hooks

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
bash skills/ci-lint-check/scripts/ci_lint_check.sh || exit 1
```

## Common Failures & Fixes

| Failure | Fix |
|---------|-----|
| Markdown lint error (MD056, MD013, etc.) | Fix line/column reported; check table column counts |
| SKILL.md missing frontmatter | Ensure file starts with `---` and has `name:` field |
| Wiki article missing from INDEX.md | Add row to INDEX.md table |
| Mnemon seed.json invalid | Run `python3 mnemon/validate-seed.py mnemon/seed.json` for details |
| Shell syntax error | Run `bash -n <script>` to see exact error |
| Symlink contract fails | Check boot scripts have `ln -s` for memories/skills |

## Files

| File | Purpose |
|------|---------|
| `skills/ci-lint-check/SKILL.md` | Procedural skill documentation |
| `skills/ci-lint-check/scripts/ci_lint_check.sh` | Validation script |
| `.github/workflows/.github/workflows/ci.yml` | Source of truth for CI jobs |
| `wiki/github-actions-testing-plan.md` | CI design document |

## Related Skills

- `codespace-persistent-symlinks` — Symlink architecture validated by this check
- `memory-automation` — Mnemon workflow that feeds into seed.json

## Verification

```bash
# Should output "=== ALL CHECKS PASSED ==="
bash skills/ci-lint-check/scripts/ci_lint_check.sh
```