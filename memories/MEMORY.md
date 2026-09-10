# Agent memory — seeded at install (standalone) / linked at boot (dev).

## Stack layout

- `.minions` installs a self-contained AI coding stack at `~/.minions`.
- Components: OmniRoute (LLM proxy, :20128), ModelRelay (proxy alt, :7352),
  Pi-Agent (CLI), Hermes (CLI), Mnemon (memory layer CLI).
- `install.sh` one-time bootstrap (binaries + configs/templates).
  `boot.sh` starts services + asserts knowledge wiring. `stop.sh`/`status.sh` ops.
- Ports env-overridable: `OMNIROUTE_PORT`, `MODELRELAY_PORT`, `MINIONS_LLM_BASE_URL`.

## Knowledge layer (two modes)

- **dev** — running from a `.minions` git checkout (has `.git` + `skills/` + `wiki/`).
  Symlinks at boot: `~/.hermes/skills/minions` → `<repo>/skills`,
  `~/.hermes/memories` → `<repo>/memories`. Wiki NOT symlinked (lives in repo).
- **standalone** — installed via curl|bash / tarball (no `.git`).
  Knowledge assets copied to `MINIONS_HOME` by install.sh;
  boot links `~/.hermes/skills/minions` → `~/.minions/skills` etc.
- Mode detected by `lib/knowledge-detection.sh` (shared: install.sh + boot.sh);
  persisted for boot in `~/.minions/etc/knowledge.env`.

## Key paths

- `~/.hermes/config.yaml` — Hermes config (provider omniroute, memory.provider mnemon).
- `~/.pi/agent/pi.toml` + `~/.pi/agent/models.json` — Pi config/ports.
- `~/.minions/{bin,lib,etc,var}` — install layout. `~/.minions/bin/*` on PATH.
- `~/.hermes/plugins/mnemon` — mnemon Hermes plugin.
- `~/.hermes/skills/minions` — symlink to skills (dev: repo, standalone: ~/.minions).
- `~/.hermes/memories` — symlink to memories dir (same two targets).
- Mnemon seed: `mnemon/seed.json` (repo) / `~/.minions/mnemon/seed.json` (standalone).

## Rules

- Knowledge symlinks must not clobber real directories — recreate only when
  `readlink` differs (or path missing/empty).
- Memory/seed in sync: seed is the checked-in snapshot; runtime edits live in
  `~/.hermes/memories`. Re-import seed at boot (fresh-spawn persistence).
- Reinstall must preserve `USER.md`/`MEMORY.md` (copy only if absent).