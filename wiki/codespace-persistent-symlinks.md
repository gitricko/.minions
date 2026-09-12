# Persistent Symlinks for Hermes State in Codespaces

## Overview

Hermes knowledge/memory (`~/.hermes/memories/MEMORY.md`, `USER.md`) and skills die on Codespace rebuild unless persisted. The durable technique mirrors how the repo already persists skills: a **whole-folder symlink** from runtime to a git-tracked repo directory.

This article documents the reference architecture for persisting Hermes runtime state across Codespace rebuilds using whole-folder symlinks.

## The Validated Pattern

```
runtime:  ~/.hermes/memories            (a symlink → the tracked folder)
target:   memories/                     (git-tracked: MEMORY.md, USER.md, .gitignore)
.gitignore:  *.lock  *.log              (Hermes writes lock/log beside the memories)

runtime:  ~/.hermes/skills/minions      (a symlink → the tracked folder)
target:   skills/                       (git-tracked: all skills)
```

### Key Principles

1. **Whole-folder symlink (skills-style), NOT per-file links** — single point of truth, no copy-back between `~/.hermes` and the repo, edits flow both ways instantly.

2. **Hermes memory writes are symlink-safe** — `atomic_replace` (utils.py) re-solves the symlink and writes the real git file — no Hermes change needed.

3. **Memory path is `~/.hermes/memories/`, NOT `profiles/default/memories/`** — this is the canonical path Hermes uses.

## Placement Decision: Option A (Validated 2026-08)

Two layers, keep `boot.sh` trivial:

### Layer 1: Authoritative = `install.sh`

Runs once on a FRESH container (via install). Creates the symlink right after Hermes is installed, before Hermes first instantiates `~/.hermes/memories`. Cleanest moment — nothing to migrate.

```bash
# In install.sh
# Create memories symlink
if [ ! -L ~/.hermes/memories ]; then
  rm -rf ~/.hermes/memories
  ln -s "$REPO_ROOT/memories" ~/.hermes/memories
fi

# Create skills symlink
if [ ! -L ~/.hermes/skills/minions ]; then
  rm -rf ~/.hermes/skills/minions
  ln -s "$REPO_ROOT/skills" ~/.hermes/skills/minions
fi
```

### Layer 2: Repair Guard = `boot.sh`

Keep under ~12 lines. `install.sh` only runs once, so a guard catches reboots and containers created before the feature shipped:

```bash
# In boot.sh
# Repair memories symlink
TARGET_MEM="$REPO_ROOT/memories"
if [ "$(readlink ~/.hermes/memories)" != "$TARGET_MEM" ]; then
  rm -rf ~/.hermes/memories
  ln -s "$TARGET_MEM" ~/.hermes/memories
fi

# Repair skills symlink
TARGET_SKILLS="$REPO_ROOT/skills"
if [ "$(readlink ~/.hermes/skills/minions)" != "$TARGET_SKILLS" ]; then
  rm -rf ~/.hermes/skills/minions
  ln -s "$TARGET_SKILLS" ~/.hermes/skills/minions
fi
```

**Handles 3 cases per link:**
- Already-correct symlink → no-op
- Real directory → repair via `rm -rf` + `ln -s`
- Missing entirely → just link

**Do NOT** port a first-run migration/seed block into `boot.sh`. If the tracked files are committed, that code is dead weight and reads as convoluted.

## Verification (Automated)

`self-check.sh` asserts both symlinks in its `Persistence` section (section 9), so CI fails loudly if either drifts:

- `~/.hermes/memories` → `$REPO_ROOT/memories`
- `~/.hermes/skills/minions` → `$REPO_ROOT/skills`

Handles 3 cases per link: correct symlink (ok), real dir (fail), missing (fail), plus checks tracked MEMORY.md / USER.md / SKILL.md exist.

CI wiring: The `detect-changes` path filter lists `memories/**` and `skills/**` under `infrastructure`, so persistence changes trigger `full-build` (which runs self-check.sh).

Run locally:
```bash
bash self-check.sh
```

## Pitfalls Reference

| Pitfall | Description | Prevention |
|---------|-------------|------------|
| **Removing seed block loses behavioral nudges** | Before deleting a start-hermes.sh seed that writes USER.md, fold its content into tracked USER.md first | Always migrate seed content to tracked files before removing seed code |
| **Undo-by-`head -n -1` corrupts memory files** | When testing write-through, remove ONLY the injected marker line (perl/grep), never tail-trim | Use precise line removal, never `head -n -1` |
| **Guard not tested against all 3 cases** | Verify the guard against: correct link, real dir, missing | Test all three cases in CI/local |

## Sync Note (Wiki ↔ Skill)

- `persistent-memory-proposal.md` — reference/proposal doc vs this procedural skill
- Keep the Option-A split and the self-check wiring mirrored in both

## Related

- **Skill**: `../skills/codespace-persistent-symlinks/` — Procedural how-to
- **Wiki**: [persistent-memory-proposal.md](persistent-memory-proposal.md) — Architecture decision document
- **Wiki**: [persistent-knowledge-proposal.md](persistent-knowledge-proposal.md) — Broader knowledge persistence architecture
- **Skill**: `../skills/mnemon-seed-persistence/` — Mnemon seed.json persistence
- **Skill**: `../skills/persistent-knowledge/` — Knowledge persistence pattern