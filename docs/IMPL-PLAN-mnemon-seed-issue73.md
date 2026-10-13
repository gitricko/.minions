# Design: Default Mnemon Seeding — Issue #73

## Problem
`mnemon/seed.json` missing (only `.gitkeep`), `lib/mnemon.sh:setup_mnemon_all()` is a no-op,
`boot.sh` never imports, ephemeral `~/.mnemon` DB + explicit `mnemon_recall` only.
Result: clean installs / fresh spawns start with empty memory; skills/wiki exist but
are not represented in Mnemon.

Reference: `hermes-codespace/.devcontainer/mnemon/seed.json` (36 insights,
`content`/`category`/`importance`/`tags`/`entities`) + `validate-seed.py` +
`check-seed-export.sh` (`mnemon recall "" --limit 100 --basic` diff for
`importance>=4`).

## Decision
Canonical seed: `mnemon/seed.json` (checked-in, `content` field). Legacy
`etc/mnemon-seed-*.json` deleted in Phase A — they used `text` field which fails
`mnemon import --dry-run` (`content is required`), have no consumer after
`lib/mnemon.sh` no-op, and `verify-knowledge`/`mnemon-seed-persistence` point at
`mnemon/seed.json`. `scripts/check-seed-export.sh` is a skill workflow
(ported from HC), not a CI gate — CI runs with blank Mnemon DB, so diff would
always fire. It lives at `scripts/check-seed-export.sh` and is documented in
`skills/mnemon-seed-persistence/SKILL.md`.

Parity ports for context: `skills/adopting-external-skills` + `wiki/ci-lint-check.md`
+ `wiki/codespace-lavish.md`.

## Architecture (fits current .minions: dev vs standalone)

```
lib/knowledge-detection.sh  → MODE + MINIONS_REPO_ROOT (shared by install.sh + boot.sh)
lib/knowledge-symlinks.sh   → dev: ~/.minions/{skills,wiki,mnemon,memories} → repo
lib/mnemon.sh               → install_mnemon / ensure_mnemon / import_mnemon_seed / setup_mnemon_all
mnemon/seed.json            → checked-in seed (36 insights, schema_version="1")
mnemon/validate-seed.py     → schema/required-field validator (F9)
scripts/check-seed-export.sh→ skill-only: recall→diff importance>=4 (not CI)
scripts/verify-knowledge.sh → F1..F9 (F9 = validate-seed.py, fixes F4 ../skills skip + F7 backtick)
tests/test_knowledge.sh     → counts updated 26 skills / 24 wiki / 23 INDEX rows, pipefail-safe, -L for symlinks
```

## Wiring

install.sh:
  - removes legacy `cp etc/mnemon-seed-*.json` → comment
  - `ensure_mnemon "${MINIONS_HOME}"` then `setup_mnemon_all "${MINIONS_HOME}"` (already present;
    `setup_mnemon_all` now does real work, non-fatal)
  - standalone branch already `cp -r mnemon/. → MINIONS_HOME/mnemon/` (no change)

lib/mnemon.sh:
  - new `import_mnemon_seed <seed_file>`: resolves `MNEMON_BIN` (`MINIONS_HOME/bin/mnemon` else `command -v`),
    `import --dry-run` gate (exit code, not grep), real `import` (deduped, head -20, non-fatal),
    `embed --status | head -5 || true`.
  - `setup_mnemon_all` resolves seed via MODE:
      dev + MINIONS_REPO_ROOT/mnemon/seed.json → else MINIONS_HOME/mnemon/seed.json → else MINIONS_HOME/mnemon/seed.json
    wraps `import_mnemon_seed` in `set +e`/`set -e`.

boot.sh:
  - after `pull_ollama_model "nomic-embed-text" &` inserts identical MODE-based block:
    resolve `MNEMON_BIN`, resolve `_mn_seed`, `set +e`, `import --dry-run` gate, `import` + `embed --status|head -5`,
    logs to `boot.log`, non-fatal (`|| log_warn`).

verify-knowledge.sh / ci.yml:
  - F4: skip `../skills` cross-links inside wiki scan; F7: strip trailing backticks.
  - New F9: `python3 mnemon/validate-seed.py mnemon/seed.json`.
  - `run_all` → F1..F9. ci.yml lint + test jobs run F1,F3,F9,F5. No CI wiring for check-seed-export.

Tests:
  - `test_knowledge.sh` counts: wiki 24, INDEX data rows 23, skills 26 (incl. adopting-external-skills),
    standalone counts via `find -L`, pipefail-safe `out="$(...)" | grep`, spot-check updated.

## Phases

A — seed + validator + skill-only check-seed-export + wiki/skills parity + etc deletions + tests/verify fixes
  → verify all 9 pass, 22/23 tests pass (only `test_standalone_full` placeholder remains red outside DTS)

B — boot/install wiring (lib/mnemon.sh import helpers, boot import block, install comment)
  → `mnemon import --dry-run` passes, import is deduped + non-fatal

C — docs (this doc, PR description, skill docs reference new seed path)

## Alternatives considered
- Keep `etc/mnemon-seed-*.json` and migrate `text`→`content`: rejected — dead weight, no consumer, fails validation.
- Wire `check-seed-export.sh` as CI job: rejected — blank DB in fresh runner always diffs.
- `command -v mnemon` in boot: rejected per pi review — use `$MINIONS_HOME/bin/mnemon` fallback.

## Verification
- `bash scripts/verify-knowledge.sh all` → 9/9 pass
- `python3 mnemon/validate-seed.py mnemon/seed.json` → 36 insights, schema_version=1
- `~/.minions/bin/mnemon import --dry-run mnemon/seed.json` → Dry run: 36 insights, 0 explicit edges — validation passed
- `bash tests/test_knowledge.sh` → 22 passed, 1 failed (`test_standalone_full` DTS placeholder)
