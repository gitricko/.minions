# Proposal: Integrating hermes-codespace Knowledge Architecture into .minions

**Date:** 2026-09-09
**Status:** Draft for discussion

---

## 1. What hermes-codespace Has That .minions Doesn't

hermes-codespace builds a rich knowledge layer on top of the same components .minions
installs (Hermes, OmniRoute, ModelRelay, Pi, Mnemon). .minions handles the infrastructure
(install, boot, config) but ships with no skills, no wiki, no persistent memory, and no
knowledge persistence strategy. After install, Hermes and Pi-agent is a blank slate.

| Layer | hermes-codespace | .minions (current) |
|-------|-----------------|---------------------|
| **Skills** | 12+ skills in `.devcontainer/skills/`, symlinked into `~/.hermes/skills/` at boot | None |
| **Wiki** | 20+ reference articles in `.devcontainer/wiki/`, indexed via `INDEX.md` | None |
| **Memories** | `MEMORY.md` + `USER.md` symlinked from `.devcontainer/memories/` → `~/.hermes/memories/` | None |
| **Mnemon seed** | `.devcontainer/mnemon/seed.json` (100+ insights), re-imported at every boot | 5 basic facts in `etc/mnemon-seed-hermes.json` |
| **Persistence** | Git-tracked `.devcontainer/` folder, symlinks survive rebuilds | Ephemeral — wiped on reinstall, unless the git project is .minions* |

---

## 2. The Core Insight

hermes-codespace's knowledge architecture follows a universal pattern:

```
Git-tracked knowledge (skills/ + wiki/ + memories/ + seed.json)
    ↓ symlink at boot
Runtime locations (~/.hermes/skills/, ~/.hermes/memories/, ~/.mnemon/)
    ↓ agent reads at runtime
Rich, context-aware behavior
```

.minions should adopt this pattern **with all hermes-codespace content ported over**.
The primary use case is Codespaces, so Codespace-specific skills (auth, port visibility,
webtop, etc.) are all valuable. The .minions repo becomes the canonical home for both the
infrastructure (install/boot) AND the knowledge layer (skills/wiki/memories).

### Mnemon: Custom Plugin, Not Default

Both hermes-codespace and .minions use **gitricko/hermes-plugin-mnemon** — a custom
Hermes `MemoryProvider` plugin that wraps `mnemon` as a four-graph memory store
(temporal, entity, causal, semantic) with importance decay, dedup, soft-delete, and
optional vector recall via Ollama. This is NOT the default built-in Hermes memory.

The plugin registers three tools on each Hermes session:
- `mnemon_remember(text, category, importance, entities, tags)` — store insight
- mnemon_recall(query, intent, limit)` — recall by natural language
- `mnemon_forget(insight_id)` — soft-delete

It hooks into Hermes lifecycle: `initialize`, `prefetch`, `sync_turn`,
`on_memory_write`, `on_pre_compress`, `on_session_switch`, `shutdown`.

.install.sh must install this plugin (clone or copy into `~/.hermes/plugins/mnemon/`)
and set `memory.provider mnemon` in the Hermes config. Look at hermes-codespace repo as reference how this is done.

---

## 3. Proposed Architecture

### 3.1 New directory structure

```
~/.minions/
├── install.sh           # existing — extended with knowledge + plugin install
├── boot.sh              # existing — extended with knowledge wiring
├── skills/              # NEW: ALL hermes-codespace skills + .minions additions (TO CREATE)
│   ├── codespace-gh-auth/
│   │   └── SKILL.md
│   ├── codespace-persistent-symlinks/
│   │   └── SKILL.md
│   ├── codespace-port-visibility/
│   │   └── SKILL.md
│   ├── codespace-vscode-open/
│   │   └── SKILL.md
│   ├── codespace-lavish/
│   │   └── SKILL.md
│   ├── ci-lint-check/
│   │   └── SKILL.md
│   ├── docker-test-shell/
│   │   ├── SKILL.md
│   │   ├── scripts/dts.sh
│   │   └── references/
│   ├── memory-automation/
│   │   └── SKILL.md
│   ├── mnemon-seed-persistence/
│   │   └── SKILL.md
│   ├── persistent-knowledge/
│   │   └── SKILL.md
│   ├── selkies-native-desktop/
│   │   └── SKILL.md
│   ├── mnemon-graph-export/
│   │   └── SKILL.md
│   ├── pi-agent-basics/           (PROPOSED .minions NEW — Pi config, usage, extensions)
│   │   └── SKILL.md
│   ├── omniroute-guide/           (PROPOSED .minions NEW — OmniRoute combos, proxy setup)
│   │   └── SKILL.md
│   ├── dts-testing/               (PROPOSED .minions NEW — Docker Test Shell workflow)
│   │   └── SKILL.md
│   └── minions-architecture/      (PROPOSED .minions NEW — system overview, component roles)
│       └── SKILL.md
├── wiki/                # NEW: ALL hermes-codespace articles
│   ├── INDEX.md
│   ├── codespace-playbook.md
│   ├── codespace-lifecycle.md
│   ├── codespace-persistent-symlinks.md
│   ├── codespace-port-visibility.md
│   ├── codespace-lavish.md
│   ├── persistent-knowledge.md
│   ├── persistent-memory-proposal.md
│   ├── memory-automation.md
│   ├── mnemon-seed-persistence.md
│   ├── mnemon-graph-viewer.md
│   ├── ci-lint-check.md
│   ├── github-codespace.md
│   ├── github-pr-review.md
│   ├── vscode-cli-codespaces.md
│   ├── karpathy-coding-guidelines.md
│   ├── repository-analysis.md
│   ├── github-actions-testing-plan.md
│   ├── keepalive-proposal.md
│   ├── docker-test-shell-proposal.md
│   ├── selkies-package-discrepancy.md
│   ├── codespace-webtop.md
├── memories/            # NEW: persistent MEMORY.md + USER.md
│   ├── MEMORY.md        # agent memory, symlinked to ~/.hermes/memories/
│   ├── USER.md          # user profile, symlinked
│   └── .gitignore       # *.lock *.log
├── mnemon/
│   └── seed.json        # Expanded mnemon seed (~30-50 insights)
├── etc/                 # existing
├── lib/                 # existing
└── ...
```

### 3.2 Two-mode knowledge delivery (dev vs standalone)

hermes-codespace does NOT replace `~/.hermes/skills/`. It creates a **named subdirectory**
symlink: `~/.hermes/skills/codespace` → `.devcontainer/skills/`. This preserves any other
skills Hermes has. .minions follows the same pattern with `~/.hermes/skills/minions`.

**Wiki is not symlinked** — hermes-codespace does NOT create a `~/.hermes/wiki/` symlink.
The wiki folder stays in the repo (`.devcontainer/wiki/`) and skills reference it via
relative paths like `../wiki/article.md`. .minions does the same: wiki lives in
`~/.minions/wiki/` (or repo `wiki/`), skills use `../wiki/` from the skills directory.

Detection runs at boot (and install):

```bash
# ── Detect: is .minions the current project? ──────────────────
MINIONS_REPO_ROOT=""
if git rev-parse --show-toplevel &>/dev/null; then
    _GIT_ROOT="$(git rev-parse --show-toplevel)"
    if [ -d "${_GIT_ROOT}/skills" ] && [ -d "${_GIT_ROOT}/wiki" ]; then
        MINIONS_REPO_ROOT="$_GIT_ROOT"
    fi
fi

if [ -n "$MINIONS_REPO_ROOT" ]; then
    # DEV MODE: .minions IS the project — symlink for git-aware edits
    MODE="dev"
else
    # STANDALONE MODE: other Codespace or bare machine — copy assets
    MODE="standalone"
fi
```

**Dev mode** (`MINIONS_REPO_ROOT` set — Codespace from .minions repo, or local clone):

```
~/.hermes/skills/minions   →  /workspaces/.minions/skills   (named subdirectory symlink)
~/.hermes/memories         →  /workspaces/.minions/memories  (memories symlink)
```

- Creates `~/.hermes/skills/minions` as a symlink to the repo's `skills/` directory
- Hermes sees skills under `~/.hermes/skills/minions/<skill-name>/SKILL.md`
- Other skills at `~/.hermes/skills/` (built-in, user-installed) are PRESERVED
- Wiki stays in repo at `/workspaces/.minions/wiki/`; skills reference via `../wiki/`
- Edits to skills/memories flow through symlinks into the git repo
- `git commit` captures everything

**Standalone mode** (other Codespace, local machine, CI):

```
~/.hermes/skills/minions   →  ~/.minions/skills/   (named subdirectory symlink)
~/.hermes/memories         →  ~/.minions/memories/  (memories symlink)
```

- Creates `~/.hermes/skills/minions` as a symlink to `~/.minions/skills/`
- Wiki lives in `~/.minions/wiki/` (referenced by skills as `../wiki/` from skills dir)
- NOT git-tracked; local copies in `~/.minions/`
- Acceptable for end users who just want the stack running
- On reinstall, `~/.minions/skills/wiki` refreshed (USER.md preserved)

### 3.3 Boot-time knowledge wiring (boot.sh extension)

After the existing proxy startup and health checks, boot.sh adds:

```bash
# ── Knowledge Layer Setup ──────────────────────────────────────

# (Detection from section 3.2 runs first)

# 1. Skills — named subdirectory symlink (hermes-codespace pattern)
#    ~/.hermes/skills/minions → repo skills/ (dev) or ~/.minions/skills/ (standalone)
HERMES_SKILLS_DIR="${HOME}/.hermes/skills"
MINIONS_SKILLS_LINK="${HERMES_SKILLS_DIR}/minions"

if [ "$MODE" = "dev" ]; then
    _TARGET="${MINIONS_REPO_ROOT}/skills"
else
    _TARGET="${MINIONS_HOME}/skills"
fi

if [ ! -L "$MINIONS_SKILLS_LINK" ] || [ "$(readlink "$MINIONS_SKILLS_LINK" 2>/dev/null)" != "$_TARGET" ]; then
    mkdir -p "$HERMES_SKILLS_DIR"
    rm -rf "$MINIONS_SKILLS_LINK" 2>/dev/null || true
    ln -s "$_TARGET" "$MINIONS_SKILLS_LINK"
    echo "[boot] Skills symlink: $MINIONS_SKILLS_LINK → $_TARGET"
else
    echo "[boot] Skills symlink already correct"
fi

# 2. Wiki — NOT symlinked (hermes-codespace pattern)
#    Wiki lives in ~/.minions/wiki/ (standalone) or repo wiki/ (dev)
#    Skills reference it via relative paths: ../wiki/article.md
#    No ~/.hermes/wiki/ symlink is created.

# 3. Memories — symlink (hermes-codespace pattern)
#    ~/.hermes/memories → repo memories/ (dev) or ~/.minions/memories/ (standalone)
HERMES_MEMORIES="${HOME}/.hermes/memories"

if [ "$MODE" = "dev" ]; then
    _MEM_TARGET="${MINIONS_REPO_ROOT}/memories"
else
    _MEM_TARGET="${MINIONS_HOME}/memories"
fi

if [ "$(readlink "$HERMES_MEMORIES" 2>/dev/null)" != "$_MEM_TARGET" ]; then
    rm -rf "$HERMES_MEMORIES" 2>/dev/null || true
    ln -s "$_MEM_TARGET" "$HERMES_MEMORIES"
    echo "[boot] Memories symlink: $HERMES_MEMORIES → $_MEM_TARGET"
else
    echo "[boot] Memories symlink already correct"
fi

# 4. Import mnemon seed (hermes only — Pi does not use mnemon)
SEED_FILE="${MINIONS_HOME}/mnemon/seed.json"
[ "$MODE" = "dev" ] && SEED_FILE="${MINIONS_REPO_ROOT}/mnemon/seed.json"
if [ -f "$SEED_FILE" ]; then
    mnemon import --dry-run "$SEED_FILE" 2>/dev/null && \
        mnemon import "$SEED_FILE" 2>/dev/null || \
        echo "[boot] mnemon seed import skipped"
fi

# 5. Install hermes-plugin-mnemon (gitricko/hermes-plugin-mnemon) — Hermes only
HERMES_PLUGINS_DIR="${HOME}/.hermes/plugins"
MNEMON_PLUGIN_DIR="${HERMES_PLUGINS_DIR}/mnemon"
if [ ! -d "$MNEMON_PLUGIN_DIR" ]; then
    echo "[boot] Installing hermes-plugin-mnemon..."
    mkdir -p "$HERMES_PLUGINS_DIR"
    git clone --depth 1 https://github.com/gitricko/hermes-plugin-mnemon /tmp/hermes-plugin-mnemon 2>/dev/null && \
        cp -r /tmp/hermes-plugin-mnemon/mnemon "$MNEMON_PLUGIN_DIR" && \
        rm -rf /tmp/hermes-plugin-mnemon && \
        hermes config set memory.provider mnemon 2>/dev/null || \
        echo "[boot] WARNING: Failed to install hermes-plugin-mnemon"
else
    echo "[boot] hermes-plugin-mnemon already installed"
fi

# 6. Pi-Agent: point at shared skills directory (Pi reads via settings.json)
#    Uses same two-mode detection — dev mode uses repo skills, standalone uses ~/.minions/skills
PI_SKILLS_PATH="${MINIONS_HOME}/skills"
[ "$MODE" = "dev" ] && PI_SKILLS_PATH="${MINIONS_REPO_ROOT}/skills"

PI_SETTINGS="${HOME}/.pi/agent/settings.json"
if [ -f "$PI_SETTINGS" ]; then
    # Check if .minions skills path is already there
    if ! grep -q "$PI_SKILLS_PATH" "$PI_SETTINGS" 2>/dev/null; then
        python3 -c "
import json
with open('$PI_SETTINGS') as f:
    cfg = json.load(f)
skills = cfg.get('skills', [])
pi_skills = '$PI_SKILLS_PATH'
if pi_skills not in skills:
    skills.append(pi_skills)
    cfg['skills'] = skills
    with open('$PI_SETTINGS', 'w') as f:
        json.dump(cfg, f, indent=2)
" 2>/dev/null || true
    fi
fi
```

### 3.4 install.sh extension

```bash
# ── Knowledge assets ──────────────────────────────────────────

# Same detection logic as boot.sh (§3.2)
# ...

if [ "$MODE" = "dev" ]; then
    # Dev mode: skills/wiki/memories live in the repo, just symlink
    log_info "Dev mode: knowledge assets are in ${MINIONS_REPO_ROOT} (symlinked at boot)"
else
    # Standalone: copy assets to ~/.minions/
    log_info "Standalone: copying knowledge assets to ${MINIONS_HOME}/"

    mkdir -p "${MINIONS_HOME}/skills" "${MINIONS_HOME}/wiki" "${MINIONS_HOME}/memories" "${MINIONS_HOME}/mnemon"

    # Copy skills (from bundled source — the install tarball or git clone)
    cp -r "${SCRIPT_DIR}/skills/"* "${MINIONS_HOME}/skills/" 2>/dev/null || true

    # Copy wiki
    cp -r "${SCRIPT_DIR}/wiki/"* "${MINIONS_HOME}/wiki/" 2>/dev/null || true

    # Copy memories (don't overwrite existing user content)
    [ -f "${MINIONS_HOME}/memories/MEMORY.md" ] || cp "${SCRIPT_DIR}/memories/MEMORY.md" "${MINIONS_HOME}/memories/"
    [ -f "${MINIONS_HOME}/memories/USER.md" ]   || cp "${SCRIPT_DIR}/memories/USER.md" "${MINIONS_HOME}/memories/"
    [ -f "${MINIONS_HOME}/memories/.gitignore" ] || cp "${SCRIPT_DIR}/memories/.gitignore" "${MINIONS_HOME}/memories/"

    # Copy mnemon seed
    cp "${SCRIPT_DIR}/mnemon/seed.json" "${MINIONS_HOME}/mnemon/seed.json" 2>/dev/null || true
fi
```

---

## 4. Skills to Port (ALL of hermes-codespace)

Since the primary use case is Codespaces, ALL hermes-codespace skills get ported.
Each skill is copied from `.devcontainer/skills/<name>/` into `~/.minions/skills/<name>/`.
The symlink at boot (`~/.hermes/skills/minions` → `~/.minions/skills/`) makes them
all available to Hermes.

### Codespace & Infrastructure Skills

| Skill | Purpose | Adaptation needed |
|-------|---------|-------------------|
| **codespace-gh-auth** | GitHub auth in Codespaces (token extraction, device flow) | Minimal — mostly portable |
| **codespace-persistent-symlinks** | Symlink pattern for memories + skills survival | Reference for .minions pattern |
| **codespace-port-visibility** | Automate port visibility via gh CLI | Direct copy |
| **codespace-vscode-open** | Auto-discover VS Code CLI in Codespaces | Direct copy |
| **codespace-lavish** | Lavish-AXI whiteboard over noVNC | Direct copy |
| **ci-lint-check** | Pre-commit CI lint validation | Adapt for .minions repo |

### Agent & Memory Skills

| Skill | Purpose | Adaptation needed |
|-------|---------|-------------------|
| **memory-automation** | Mnemon workflow (recall/save patterns) | Remove Codespace-specific mnemon plugin references; update to use hermes-plugin-mnemon |
| **mnemon-seed-persistence** | Seed.json management for contributors | Direct copy |
| **persistent-knowledge** | Symlink-based persistence architecture | Adapt paths for .minions layout |
| **mnemon-graph-export** | 3D knowledge graph visualization | Direct copy (if Ollama available) |

### Testing Skills

| Skill | Purpose | Adaptation needed |
|-------|---------|-------------------|
| **docker-test-shell** | `dts` tool for testing in clean containers | Direct copy — already portable |
| **selkies-native-desktop** | Portable Selkies/XFCE webtop | Direct copy |

### NEW Skills (not in hermes-codespace)

| Skill | Purpose |
|-------|---------|
| **pi-agent-basics** | How Pi works, config at `~/.pi/agent/`, failover extension, model selection |
| **omniroute-guide** | OmniRoute combos, model selection, port config, troubleshooting |
| **hermes-configuration** | Hermes config set commands explained, provider setup |
| **minions-architecture** | .minions system overview for agents working on the project |

---

## 5. Mnemon Seed: From 5 Facts to Real Knowledge

The current `etc/mnemon-seed-hermes.json` has 5 basic facts. hermes-codespace's seed.json
has 100+ insights covering architecture, gotchas, workflow patterns, and user preferences.

Proposal: expand `.minions/mnemon/seed.json` to 30-50 insights covering:

1. **Architecture** — component roles, port assignments, config locations
2. **Gotchas** — the 10+ bugs from DOCKER-TEST-LEARNINGS.md encoded as insights
3. **Workflow** — how to use Pi, how to use Hermes, how to test with DTS
4. **Config** — provider setup, model selection, failover behavior
5. **Development** — how to modify .minions itself, PR workflow, CI

Each insight follows the schema hermes-codespace established:
```json
{
  "text": "Pi-Agent config lives at ~/.pi/agent/ (NOT ~/.pi/). getAgentDir() resolves there.",
  "category": "insight",
  "importance": 5,
  "entities": ["pi-agent", "config"],
  "tags": ["gotcha", "config-path"],
  "source": "agent"
}
```

Note: mnemon seed import runs only for Hermes. Pi-Agent does not use mnemon.
The seed file (`mnemon/seed.json`) is imported via `mnemon import` at boot, which
feeds the hermes-plugin-mnemon four-graph memory store.

---

## 6. Wiki: All hermes-codespace Articles + .minions Additions

ALL hermes-codespace wiki articles get ported. They're referenced by skills and
provide reference knowledge for the agent via `read_file()`. .minions adds its own
articles on top.

```
wiki/
├── INDEX.md                           # Combined index (hermes-codespace + .minions)
│
├── # ── Ported from hermes-codespace ──
├── codespace-playbook.md              # Auth, PR monitoring, git push, pitfalls
├── codespace-lifecycle.md             # Idle detection, shutdown, keepalive
├── codespace-persistent-symlinks.md   # Symlink pattern for persistence
├── codespace-port-visibility.md       # Automate port visibility via gh CLI
├── codespace-lavish.md                # Lavish-AXI whiteboard architecture
├── persistent-knowledge.md            # Persistent skills/knowledge via symlinks
├── persistent-memory-proposal.md      # MEMORY.md/USER.md symlink architecture
├── memory-automation.md               # Mnemon persistence workflow
├── mnemon-seed-persistence.md         # Seed.json management
├── mnemon-graph-viewer.md             # 3D knowledge graph viewer
├── ci-lint-check.md                   # Pre-commit CI lint validation
├── github-codespace.md                # Full GitHub Codespace workflow
├── github-pr-review.md                # CodeQL/Copilot review evaluation
├── vscode-cli-codespaces.md           # VS Code CLI discovery
├── karpathy-coding-guidelines.md      # LLM coding pitfall guidelines
├── repository-analysis.md             # Repository deep dive
├── github-actions-testing-plan.md     # CI/CD testing plan
├── keepalive-proposal.md              # Codespace keepalive design
├── docker-test-shell-proposal.md      # DTS design rationale
├── selkies-package-discrepancy.md     # PyPI vs GitHub Actions gotcha
├── codespace-webtop.md                # Selkies/XFCE webtop
│
├── # ── NEW .minions articles ──
├── architecture.md                    # .minions system overview, component roles
├── troubleshooting.md                 # Common issues and fixes
├── port-configuration.md              # Env vars, dev override pattern
├── pi-agent-guide.md                  # Pi-Agent usage, config, extensions
├── omniroute-guide.md                 # OmniRoute combos, model selection
├── hermes-configuration.md            # Hermes config set commands explained
├── testing-with-dts.md                # Docker-based testing workflow
├── mnemon-plugin-setup.md             # hermes-plugin-mnemon installation & config
└── development-guide.md               # How to modify .minions itself
```

All articles are designed to be agent-readable (structured, actionable) as well as
human reference docs. Hermes can `read_file()` any article at runtime.

---

## 7. Memories: Surviving Reinstalls

The hermes-codespace pattern:
- `MEMORY.md` and `USER.md` live in a git-tracked folder
- Symlinked into `~/.hermes/memories/` at boot
- Hermes `atomic_replace` writes through symlinks to the real file
- Git tracks the content; the runtime sees it via symlink

For .minions:
- `~/.minions/memories/MEMORY.md` — tracks learned facts about the user/environment
- `~/.minions/memories/USER.md` — user profile and preferences
- Symlinked to `~/.hermes/memories/` at boot
- **Survives reinstall** because `~/.minions/` is the install target (not `~/.hermes/`)
- On a fresh install, `install.sh` seeds with defaults; existing `~/.minions/memories/`
  is preserved (install.sh should not overwrite existing USER.md/MEMORY.md)

---

## 8. What .minions Does NOT Need from hermes-codespace

Almost everything ports directly. The only items that don't apply:

| hermes-codespace feature | Why .minions doesn't need it |
|--------------------------|------------------------------|
| Ollama local models setup | .minions focuses on proxy-based free LLMs; Ollama is optional for mnemon vector recall |
| Post-create-CMD Codespace lifecycle specifics | .minions has its own install.sh/boot.sh; the knowledge content still ports |

Everything else — auth, port visibility, webtop, keepalive, whiteboard, lint, DTS,
persistent symlinks, memory automation, seed persistence — ALL ported because the
primary use case is Codespaces.

---

## 9. Implementation Plan

### Phase 1: Knowledge scaffold + mnemon plugin
- Create `skills/`, `wiki/`, `memories/`, `mnemon/` directories in .minions
- Add mnemon plugin installation to `install.sh` (clone gitricko/hermes-plugin-mnemon → `~/.hermes/plugins/mnemon/`)
- Set `memory.provider mnemon` in hermes config
- Port `memory-automation` skill (update to reference hermes-plugin-mnemon, not default mnemon setup)
- Create `mnemon-plugin-setup.md` wiki article
- Expand mnemon seed to ~30 insights (encoding lessons from DOCKER-TEST-LEARNINGS.md)
- Extend `boot.sh` with knowledge wiring (symlinks + seed import + plugin install)
- Extend `install.sh` to copy knowledge assets
- Seed memories with default MEMORY.md + USER.md

### Phase 2: Port all hermes-codespace skills (batch)
- Copy all skills from hermes-codespace `.devcontainer/skills/` → `~/.minions/skills/`
- Adapt paths in skills that reference `.devcontainer/` to use `~/.minions/`
- Copy all wiki articles from hermes-codespace `.devcontainer/wiki/` → `~/.minions/wiki/`
- Create combined INDEX.md
- Create `dts.sh` integration (already exists in scripts/, wire into skills)

### Phase 3: NEW .minions-specific skills + wiki
- Create `pi-agent-basics` skill
- Create `omniroute-guide` skill
- Create `hermes-configuration` skill
- Create `minions-architecture` skill
- Create .minions wiki articles (architecture, troubleshooting, port-config, etc.)

### Phase 4: Persistence & CI (see §12 for full CI design)
- Test memory persistence across reinstall
- Port self-check.sh (boot-time health probe) → §12.3
- Port ci-lint-check skill with 7 validation checks → §12.2
- Create GitHub Actions workflow with detect-changes + full-build + lint-check → §12.1
- Add mnemon integration test to CI full-build job → §12.4
- Verify mnemon seed import works end-to-end

---

## 10. Open Questions for You

1. ~~**Pi-Agent integration with skills?~~ ANSWERED: See §11 below. Pi implements the
   Agent Skills standard (same SKILL.md format as Hermes). Pi can load skills from any
   directory via `settings.json` `skills` array. One shared skills directory, both agents.

2. ~~**Skills: git-tracked or downloaded?**~~ ANSWERED: Two-mode detection.
   Dev mode (Codespace from .minions repo): symlink to repo → git-aware.
   Standalone: copy to `~/.minions/skills/` → local-only.

3. ~~**Which hermes-codespace skills to port?**~~ ANSWERED: ALL of them.

4. ~~**Mnemon plugin?**~~ ANSWERED: Clone gitricko/hermes-plugin-mnemon, set `memory.provider mnemon`.

5. ~~**Wiki: agent-readable or human-only?**~~ ANSWERED: Both. Articles structured for
   `read_file()` agent consumption AND human reference.

---

## 11. Pi-Agent Skill Integration: Shared Skills Directory

### The Key Discovery

Pi implements the **Agent Skills standard** (agentskills.io/specification) — the exact
same SKILL.md format with YAML frontmatter (`name`, `description`) that Hermes uses.
Pi even explicitly allows skill names to differ from their parent directory (a lenient
deviation from the standard specifically to support shared skill directories across
multiple agent harnesses).

### How Pi Discovers Skills

Pi loads skills from:
- **Global:** `~/.pi/agent/skills/`, `~/.agents/skills/`
- **Project:** `.pi/skills/`, `.agents/skills/` (cwd and ancestors up to git root)
- **Settings:** `skills` array in `settings.json` — can point to ANY directory
- **CLI:** `--skill <path>` (repeatable)

Pi has **explicit cross-harness support**: you can point it at Claude Code or Codex
skill directories via settings:

```json
// ~/.pi/agent/settings.json
{
  "skills": [
    "~/.claude/skills",
    "~/.codex/skills"
  ]
}
```

This means Pi can also read from `~/.minions/skills/` — the SAME skills Hermes uses.

### Integration Design

**One shared skills directory, two agents reading it.**

```
~/.minions/skills/          <- the canonical skill store
    ^                           ^
    |                           |
Hermes reads via:           Pi reads via:
~/.hermes/skills/minions    ~/.pi/agent/settings.json
(symlink)                   { "skills": ["~/.minions/skills"] }
```

#### For Hermes (boot.sh):

Already covered in section 3.3 — symlink or copy to `~/.hermes/skills/minions`.

#### For Pi (install.sh + boot.sh):

Pi uses the same two-mode detection as Hermes. The skills path depends on mode:

```bash
# ── Two-mode detection (same as Hermes) ──────────────────────────
MINIONS_REPO_ROOT=""
if git rev-parse --show-toplevel &>/dev/null; then
    _GIT_ROOT="$(git rev-parse --show-toplevel)"
    if [ -d "${_GIT_ROOT}/skills" ] && [ -d "${_GIT_ROOT}/wiki" ]; then
        MINIONS_REPO_ROOT="$_GIT_ROOT"
    fi
fi

if [ -n "$MINIONS_REPO_ROOT" ]; then
    # DEV MODE: .minions IS the project — use repo skills
    PI_SKILLS_PATH="${MINIONS_REPO_ROOT}/skills"
else
    # STANDALONE MODE: use ~/.minions/skills
    PI_SKILLS_PATH="${MINIONS_HOME}/skills"
fi

# Install Pi settings to point at shared skills
PI_SETTINGS="${HOME}/.pi/agent/settings.json"
mkdir -p "${HOME}/.pi/agent"

# Create or update settings.json with skills path
if [ -f "$PI_SETTINGS" ]; then
    # Merge skills array into existing settings
    python3 -c "
import json
with open('$PI_SETTINGS') as f:
    cfg = json.load(f)
skills = cfg.get('skills', [])
pi_skills = '$PI_SKILLS_PATH'
if pi_skills not in skills:
    skills.append(pi_skills)
    cfg['skills'] = skills
    with open('$PI_SETTINGS', 'w') as f:
        json.dump(cfg, f, indent=2)
    print('Updated Pi settings with skills path:', pi_skills)
else:
    print('Pi settings already has skills path')
" 2>/dev/null || echo "[install] Could not update Pi settings"
else
    # Create fresh settings.json
    cat > "$PI_SETTINGS" << EOF
{
  "skills": ["$PI_SKILLS_PATH"]
}
EOF
    echo "[install] Created Pi settings with skills path: $PI_SKILLS_PATH"
fi
```

### What This Means

- Skills like `codespace-gh-auth`, `memory-automation`, `pi-agent-basics`, etc. are
  available to BOTH Hermes and Pi
- No duplication — one SKILL.md, both agents read it
- Skills can reference Pi-specific scripts and Hermes-specific scripts — each agent
  follows what applies to it
- When you edit a skill in dev mode, both agents pick up the change immediately

### Skills That Are Agent-Specific

Some skills reference tools only one agent has:
- `memory-automation` references `mnemon_remember()` — a Hermes plugin tool. Pi does NOT
  use mnemon (user prefers not to use Pi's default mnemon implementation). Pi should
  ignore mnemon-related sections. The skill documents Hermes-only mnemon paths.

### Mnemon: Hermes Only

Pi-Agent does NOT integrate with mnemon or the knowledge graph. Only Hermes gets:
- `gitricko/hermes-plugin-mnemon` installed to `~/.hermes/plugins/mnemon/`
- `memory.provider mnemon` in Hermes config
- `mnemon_remember` / `mnemon_recall` / `mnemon_forget` tools

This is by design — Pi's default mnemon implementation is not used. Mnemon memory
and knowledge graph features are Hermes-exclusive in the .minions stack.

### Wiki for Pi

Pi doesn't have a native wiki system. But Pi can read any file via its `read` tool.
Wiki articles at `~/.minions/wiki/` in standalone mode and git project `.minions/wiki` in devmode are accessible to Pi if the skill or user
instructs it to read them:

```markdown
# In a SKILL.md:
For detailed architecture, see [architecture.md](../wiki/architecture.md)
```

Pi's agent will use `read` to load the referenced file — same as Hermes uses
`read_file()`.

---

## 12. CI/CD: Testing the Knowledge Layer

hermes-codespace has three CI components that validate the knowledge layer. All three
must be ported and adapted for .minions.

### 12.1 GitHub Actions Workflow (`devcontainer-ci.yml`)

The workflow has 3 jobs with path-based triggers:

| Job | Trigger | What it does |
|-----|---------|--------------|
| **detect-changes** | Always | Uses `dorny/paths-filter` to categorize changes |
| **full-build** | Infrastructure changed | Runs full install.sh + boot.sh + self-check + mnemon integration test |
| **lint-check** | Runtime or docs changed | Runs the `ci-lint-check` skill's validation script |

Path categories for .minions:
- **Infrastructure**: `install.sh`, `boot.sh`, `lib/*.sh`, `.github/workflows/**`
- **Runtime**: `skills/**`, `wiki/**`, `mnemon/**`, `memories/**`
- **Docs**: `docs/**`, `README.md`

### 12.2 CI Lint Check Skill

Ported from hermes-codespace's `ci-lint-check` skill. 7 validation checks:

| # | Check | What it validates |
|---|-------|-------------------|
| 1 | Markdown lint | All `*.md` files pass markdownlint (MD034 for bare URLs) |
| 2 | SKILL.md structure | Every skill has YAML frontmatter with `name:` field |
| 3 | Wiki INDEX.md consistency | Every article in `wiki/` is listed in `wiki/INDEX.md` |
| 4 | Mnemon seed.json | `mnemon/seed.json` passes `mnemon/validate-seed.py` |
| 5 | Root shell syntax | `install.sh`, `boot.sh` pass `bash -n` |
| 6 | Skill shell syntax | `skills/*/scripts/*.sh` pass `bash -n` |
| 7 | Symlink contract | Boot scripts create correct symlinks (grep for patterns) |

**Dev/prod parity**: the local script IS the CI job. CI delegates to
`skills/ci-lint-check/scripts/ci_lint_check.sh`. No duplicated validation logic.

### 12.3 Self-Check (Boot-Time Health Probe)

Adapted from hermes-codespace's `self-check.sh`. Runs at boot after all services start.
Probes and reports:

| Check | What it verifies |
|-------|-----------------|
| Services | ModelRelay (:7352), OmniRoute (:20128) respond |
| Models | OmniRoute `/v1/models` returns model list |
| Mnemon | Binary installed, database exists |
| Hermes | Config valid, gateway responds |
| Disk | Usage below threshold (85% warn, 95% fail) |
| Memory | Usage below 90% |
| Cron | Hermes cron jobs registered |
| Ollama | Binary, API, embedding model (optional for mnemon vector recall) |
| Persistence | Symlinks for skills and memories are correct |

Output: human-readable report + JSON at `/tmp/health-report.json`.
Optional Telegram delivery via bot token auto-discovered from Hermes config.

### 12.4 Mnemon Integration Test

Runs as part of the full-build CI job:
1. Hermes remembers a unique name via `mnemon_remember`
2. `mnemon recall` finds it
3. Claude retrieves it via `mnemon recall` (tests cross-agent recall)

This validates the full mnemon plugin → hermes-plugin-mnemon → mnemon binary pipeline.

### 12.5 Porting Notes

- All `.devcontainer/` paths become `skills/`, `wiki/`, `mnemon/`, `memories/`
- `.devcontainer/*.sh` becomes root-level scripts (`install.sh`, `boot.sh`)
- Self-check adapts service ports and config paths for .minions
- CI workflow triggers on `skills/**`, `wiki/**`, `mnemon/**`, `memories/**` changes
- `ci-lint-check` skill runs from repo root (not `.devcontainer/`)
