# Implementation Plan: hermes-codespace Knowledge Architecture → .minions

**Companion to:** [PROPOSAL-skills-wiki-integration.md](PROPOSAL-skills-wiki-integration.md) — read the proposal first for the full architecture (two-mode detection §3.2, boot wiring §3.3, install extension §3.4, Pi integration §11).
**Date:** 2026-09-09
**Status:** Ready for phased execution

---

## 0. How to Use This Plan

This plan breaks the work into the smallest independently testable/mergeable phases
(Phase 0 → Phase 31). **Each phase is a self-contained PR.** An agent can start at any
phase if the listed prerequisites are satisfied.

- Work happens in the repo at `/workspaces/.minions/` (this environment; `<REPO_ROOT>`
  below). Runtime install target is `MINIONS_HOME="${HOME}/.minions"`.
- **Phase state tracking:** to determine progress, `git log --oneline` and
  `ls skills/ wiki/ memories/ mnemon/` — presence of the phase's files + a passing
  verification block = phase done.
- Global verification helpers for all phases (single commands, run from repo root):
  ```bash
  # F1: shell syntax for every shell file
  for f in install.sh boot.sh status.sh stop.sh lib/*.sh skills/*/scripts/*.sh; do
      [ -f "$f" ] && sh -n "$f" || echo "SYNTAX FAIL: $f"
  done
  # F2: YAML frontmatter parses for every skill
  python3 - <<'EOF'
  import glob, yaml
  for p in glob.glob('skills/*/SKILL.md'):
      txt = open(p).read()
      fm = txt.split('---')[1]
      d = yaml.safe_load(fm)
      assert d.get('name') and d.get('description'), f'bad frontmatter: {p}'
      print('OK', p, d['name'])
  EOF
  # F3: JSON validity everywhere
  for f in mnemon/*.json etc/*.json; do [ -f "$f" ] && python3 -m json.tool "$f" >/dev/null && echo "OK $f"; done
  # F4: wiki internal-link integrity
  python3 - <<'EOF'
  import glob, re, os
  bad = []
  for p in glob.glob('wiki/*.md'):
      for m in re.findall(r'\]\(([^)#]+\.md)\)', open(p).read()):
          if m.startswith('http'): continue
          if not os.path.exists(os.path.join('wiki', os.path.basename(m))):
              bad.append((p, m))
  print('BROKEN LINKS:', bad or 'none')
  EOF
  # F5: no leftover upstream-absolute path references (paths that only exist in hermes-codespace)
  grep -rn '\.devcontainer/' skills/ wiki/ --include='*.md' --include='*.sh' --include='*.py' || echo "no .devcontainer refs"
  ```
  F5 has an allow-list: files that *describe* the upstream project (e.g. repository-analysis.md, ci-lint-check references) may mention `.devcontainer/` literally — keep an explicit note in the PR when that is intentional.

---

## 1. Corrections to the Proposal (verified against upstream 2026-09-09)

| Proposal says | Verified upstream reality | Plan impact |
|---|---|---|
| 12 skills in §4 | **15 skills** in `.devcontainer/skills/` | Phases 1–15, one per skill |
| `selkies-native-desktop` skill | Does **not** exist; equivalent content is the `codespace-webtop` skill | We port `codespace-webtop`; no separate `selkies-native-desktop` dir |
| 21 wiki articles in §6 | **23 articles + INDEX.md** (extra: `codespace-gh-auth.md`, `persistent-knowledge-proposal.md`) | Phases 16–20, 5+5+5+5+3 |
| Seed schema field `text` (proposal §5 example) | Upstream `seed.json` and `validate-seed.py` use **`content`** (required field) | New `mnemon/seed.json` uses `content`; existing `etc/mnemon-seed-*.json` keep `text` (still imported by `setup_mnemon_all`) — migration deferred, see Phase 21 |
| — | `.minions` already writes `memory.provider: mnemon` in install.sh config.yaml template (line 230–233) | No config change needed; plugin install is the missing piece |
| — | Upstream `docker-test-shell/scripts/dts.sh` AND repo `scripts/dts.sh` both exist, likely divergent | Phase 7 reconciles |

**Source URLs used for porting:**
- Skills: `https://github.com/gitricko/hermes-codespace/tree/main/.devcontainer/skills/<name>/` (git clone: `git clone --depth 1 https://github.com/gitricko/hermes-codespace.git`)
- Wiki: `.../tree/main/.devcontainer/wiki/<article>.md`
- Mnemon plugin: `https://github.com/gitricko/hermes-plugin-mnemon` (clone → `~/.hermes/plugins/mnemon/`)

**Universal adaptation checklist** (applies to every ported skill/article; F5 gates it):
1. `/devcontainer/skills/<name>/` → `skills/<name>/`, `.devcontainer/wiki/<a>.md` → `wiki/<a>.md`.
2. Replace repo-internal path references: `.devcontainer/wiki/X.md` → `../wiki/X.md` (skills reference wiki relatively); `.devcontainer/` root refs → `<REPO_ROOT>` (dev) or `~/.minions` (standalone) as appropriate; keep `~/.hermes/...` refs unchanged.
3. Preserve `scripts/`, `references/`, `templates/` subdirs; keep executable bits (`find skills -name '*.sh' -exec chmod +x {} +`).
4. Do not alter upstream *content* beyond path fixes + the per-skill adaptation notes below; keep upstream as the diff baseline for review.

**Dependency map:**
```
P0 → P0.5 (test contract) + P0.6 (self-check)
P0 → P1..P15 (skills) ─┐
P0 → P16..P20 (wiki) ──┤→ P22 (install.sh copies) → P23 (boot.sh) → P24 (Pi) → P31 (smoke)
P0 → P21 (seed) ───────┘                                                ↓
P25..P28 (new content) ─┘                                    P29 (CI workflow) → P30 (mnemon CI)
```

---

## Phase 0 — Directory scaffold

- **Goal:** Create the four git-tracked knowledge directories so every later phase has a landing spot (Git doesn't track empty dirs → placeholder files).
- **Files (new):** `skills/.gitkeep`, `wiki/.gitkeep`, `mnemon/.gitkeep`, `memories/.gitignore` (content: `*.lock\n*.log\n` — plus a `# Agent-negotiated memory; do not commit PR-branch edits` header comment; `.gitignore` doubles as the dir placeholder).
- **Steps:** `mkdir -p skills wiki mnemon memories` → write the four files.
- **Verify:** `git status` shows the 4 files; `ls -d skills wiki mnemon memories` all exist; F3 passes on `.gitignore` (n/a — trivial).
- **Prerequisites:** None.
- **Rollback:** `git rm -r skills wiki mnemon memories` (files only; dirs vanish with them).

---

## Phase 0.5 — Smoke test contract (test-first)

- **Goal:** Write the end-to-end knowledge layer test **before** any wiring exists. This defines the contract every subsequent phase must satisfy. The test starts RED and phases turn it GREEN incrementally.
- **Files (new):** `tests/test_knowledge.sh` (1 file).
- **Steps:**
  1. Create `tests/test_knowledge.sh` that accepts `KNOWLEDGE_TEST_MODE=dev|standalone` and asserts:
     - **Dev mode:** detection → MODE=dev; `~/.hermes/skills/minions` is a symlink to `<REPO_ROOT>/skills`; `~/.hermes/memories` → `<REPO_ROOT>/memories`; `readlink -f` targets exist; no `~/.hermes/wiki` symlink; Hermes sees 15 skill dirs under the symlink.
     - **Standalone mode** (fresh DTS container): run full install.sh + boot.sh; assert knowledge-mode line, `~/.minions/skills` count == 15, wiki count == 27 (23+4), seed imported (log line), settings.json skills array correct, memories copied and NOT clobbered on reinstall, `mnemon import --dry-run` passes on `~/.minions/mnemon/seed.json`.
     - **Global:** F1–F5 run clean from repo root; `python3 mnemon/validate-seed.py mnemon/seed.json` OK; `ls wiki/ | wc -l` == 27; INDEX reverse-link check.
  2. Make it executable: `chmod +x tests/test_knowledge.sh`.
  3. Run locally in dev mode: `KNOWLEDGE_TEST_MODE=dev bash tests/test_knowledge.sh` → EXPECTED TO FAIL (RED).
- **Verify:** Test file exists, parses (`bash -n`), runs and produces readable output (RED is expected).
- **Prerequisites:** Phase 0.
- **Rollback:** `git rm tests/test_knowledge.sh`.

---

## Phase 0.6 — self-check.sh (boot-time health probe, ported early)

- **Goal:** Port hermes-codespace's `self-check.sh` for .minions. This becomes the **runtime guard** — runs on every boot and fails fast if wiring is broken. Written early so it can validate every subsequent wiring phase.
- **Files (new/modified):** `self-check.sh` (1 file).
- **Steps:**
  1. Fetch upstream `.devcontainer/self-check.sh` from `gitricko/hermes-codespace`.
  2. Adapt for .minions:
     - Service ports: ModelRelay (:7352), OmniRoute (:20128) — same as upstream
     - Add Hermes gateway (:9119) probe
     - Config path: `~/.hermes/config.yaml` (same)
     - Symlink checks: `~/.hermes/skills/minions` (not `codespace`), `~/.hermes/memories`
     - Remove Telegram delivery (not configured in .minions by default)
     - Keep JSON report output at `/tmp/health-report.json`
  3. All path references updated from `.devcontainer/` to repo root or `~/.minions/`
- **Verify:** F1; run `bash self-check.sh` locally — should print health report and
  exit 0 (or 1 for warnings). JSON report file created.
- **Prerequisites:** Phase 0. Works best after Phase 23 (boot.sh wiring) for full symlinks.
- **Rollback:** `git rm self-check.sh`.

---

## Phases 1–15 — Port the 15 hermes-codespace skills (one skill per phase)

Each phase: copy the skill tree, apply the universal adaptation checklist + the per-skill
notes below, verify. **One PR per skill** — each is independently reviewable.

| Phase | Skill dir | Proposal §4 entry | Per-skill adaptation notes |
|---|---|---|---|
| 1 | `codespace-gh-auth` | codespace-gh-auth | Minimal. Port `references/git-push-with-token.md`. Token-extraction is Codespace-specific — that's fine (primary use case). |
| 2 | `codespace-persistent-symlinks` | codespace-persistent-symlinks | Direct copy (no subdirs). Keep as reference for the .minions symlink pattern. |
| 3 | `codespace-port-visibility` | codespace-port-visibility | Direct copy incl. 4 scripts (`export_codespace_token.sh`, `expose_port.py`, `get_codespace_token.py`, `set_port_visibility.py`). |
| 4 | `codespace-vscode-open` | codespace-vscode-open | Direct copy incl. `scripts/install.sh` + `scripts/vscode-open.sh`. Nested `scripts/install.sh` ≠ repo `install.sh` — no rename needed, but note both exist. |
| 5 | `codespace-lavish` | codespace-lavish | Direct copy (3 scripts, 3 references: artifact-tokens, chrome-gpu-fix, session-learnings). |
| 6 | `ci-lint-check` | ci-lint-check | **Adapt for .minions repo:** `references/dev-prod-parity.md` and `scripts/ci_lint_check.sh` reference upstream's `.devcontainer/skills` / CI layout — update paths to `.minions` repo equivalents; keep the lint philosophy. |
| 7 | `docker-test-shell` | docker-test-shell | **Reconcile dts.sh:** upstream `scripts/dts.sh` vs existing repo `scripts/dts.sh`. Diff both; repo copy is canonical (has the `bash -l` fix from DOCKER-TEST-LEARNINGS). Ship the skill with its `references/dts-usage.md` and the upstream `scripts/dts.sh` only if it's ≥ parity; otherwise have the skill reference `scripts/dts.sh` (repo root) — document the decision in the PR. |
| 8 | `memory-automation` | memory-automation | **Adapt:** remove upstream Codespace-specific mnemon-plugin references; point at `gitricko/hermes-plugin-mnemon` tools (`mnemon_remember` / `mnemon_recall` / `mnemon_forget`). Add a note: Hermes-only — Pi ignores mnemon sections. |
| 9 | `mnemon-seed-persistence` | mnemon-seed-persistence | Direct copy; path refs `.devcontainer/mnemon/seed.json` → `mnemon/seed.json`. |
| 10 | `persistent-knowledge` | persistent-knowledge | **Adapt paths** for .minions layout (`~/.minions/skills`, `~/.minions/wiki`, symlink targets). Port `references/cleanup-deleted-skill.md`. |
| 11 | `mnemon-graph-export` | mnemon-graph-export | Direct copy (6 script/html files incl. `export_graph.py`, `build.py`). Note Ollama vector recall optional — graph export works with JSON export. |
| 12 | `codespace-webtop` | (proposal's selkies-native-desktop — no separate upstream skill) | Direct copy: `references/{architecture,disk-optimization,troubleshooting,web-client-no-sidebar}.md`, `scripts/{prereqs,selkies-native}.sh`, `templates/autostart.bashrc`. This is the Selkies/XFCE webtop content. |
| 13 | `github-codespace` | (extra — not in proposal §4) | Direct copy; port `references/selkies-package-discrepancy.md` alongside. |
| 14 | `github-pr-review` | (extra) | Direct copy (single SKILL.md). |
| 15 | `karpathy-coding-guidelines` | (extra) | Direct copy incl. `references/examples.md`. |

**Common steps (all of P1–P15):**
1. `cp -r <upstream>/<dir> skills/<name>/` (or write via patch tool from extracted content).
2. Apply adaptation checklist (F5 after; keep allow-listed mentions purposeful).
3. `chmod +x` any scripts.
**Verify (per phase):** F2 (frontmatter: `name` == dir, `description` present), F1 for any `.sh`, skill dir listing matches the upstream file manifest, F5 with allow-list review, `git diff --stat` shows only the new skill subtree.
**Prerequisites:** Phase 0 (skills/ exists).
**Rollback:** `git rm -r skills/<name>` — nothing else touched.

---

## Phases 16–20 — Port the 23 wiki articles (batches of 5, last batch 3 + INDEX.md)

All articles: copy from upstream wiki/, apply checklist (link fixes, path rewrites). Keep
article-to-article relative links intact. Target ~"agent-readable + human reference" per
proposal §10 Q5 — no content rewrite beyond paths.

| Phase | Group | Articles |
|---|---|---|
| 16 | A — Codespace auth & lifecycle ops | `codespace-playbook.md`, `codespace-gh-auth.md` ⚠(new vs proposal §6), `codespace-lifecycle.md`, `codespace-persistent-symlinks.md`, `codespace-port-visibility.md` |
| 17 | B — Editor & GitHub workflow | `vscode-cli-codespaces.md`, `github-codespace.md`, `github-pr-review.md`, `github-actions-testing-plan.md`, `karpathy-coding-guidelines.md` |
| 18 | C — Persistence & memory | `memory-automation.md`, `persistent-knowledge.md`, `persistent-knowledge-proposal.md` ⚠(new vs proposal §6), `persistent-memory-proposal.md`, `mnemon-seed-persistence.md` |
| 19 | D — Architecture, GUIs & reference | `repository-analysis.md`, `ci-lint-check.md`, `codespace-lavish.md`, `codespace-webtop.md`, `selkies-package-discrepancy.md` |
| 20 | E — Design docs + index | `mnemon-graph-viewer.md`, `docker-test-shell-proposal.md`, `keepalive-proposal.md`, **+ create** `wiki/INDEX.md` (adapted from upstream: 23-row table, "How to Use" section rewritten for `wiki/` + `../wiki/` paths per §11) |

**Verify (per phase):** article count matches the group table (`ls wiki/*.md | wc -l` cumulative check), F4 (link integrity), F5, each article has an `#` title; **Phase 20 additionally:** INDEX.md lists all 23 articles and every listed file exists (reverse link check).
**Prerequisites:** Phase 0; Phase 20 requires Phases 16–19.
**Rollback:** `git rm wiki/<articles>` (P20: also `git rm wiki/INDEX.md`).

---

## Phase 21 — Mnemon seed file + validator

- **Goal:** Create `.minions/mnemon/seed.json` (30–50 insights) encoding DOCKER-TEST-LEARNINGS.md knowledge + port the upstream validator.
- **Files (new):** `mnemon/seed.json`, `mnemon/validate-seed.py`; (optional, 3rd) `mnemon/README.md` noting schema + how to validate.
- **Steps:**
  1. Port `validate-seed.py` from upstream `.devcontainer/mnemon/` unchanged — it already enforces the `content`-field schema, categories ∈ {preference, decision, fact, insight, context, general}, importance 1–5, ≤50 insights, ≤8000 chars.
  2. Author `seed.json` with `schema_version: "1"` and `insights` using the **`content`** field (upstream standard). ~35 insights:
     - **Gotchas (from DOCKER-TEST-LEARNINGS.md)** — one insight each: xz-utils needed for Node `.tar.xz`; g++/make needed for node-pty (node-gyp) or Hermes install hangs; npm 9+ hoists `node_modules/` to prefix root (Pi wrapper paths); `docker exec bash -c` skips `.bashrc` → use `bash -l`; run installed `${MINIONS_HOME}/boot.sh`, never the /src mount copy; python-yaml failure → literal `\n` in config.yaml breaks YAML → always cat-validate; Pi-Agent needs explicit provider auth (Hermes is keyless via OmniRoute); 503 = transient upstream free-provider outage → retry (3×/10s) in CI; hermes reads `${HERMES_HOME}/config.yaml` NOT `.hermes/config.yaml` (get_config_path); use `cp` not `cp -n` for lib code so fixes propagate.
     - **Architecture** — component roles, ports (OmniRoute 20128, ModelRelay 7352), config locations (`~/.pi/agent/pi.toml`+`models.json`, `~/.hermes/config.yaml`, `~/.minions/etc/`), memory.provider=mnemon.
     - **Workflow** — dts up/apt/exec flow, boot/status/stop, keyless `hermes chat -q`, expected Pi key error.
     - **Knowledge layer** — symlink pattern (`~/.hermes/skills/minions` → repo or `~/.minions/skills`), wiki not symlinked, seed re-imported at boot (fresh-spawn persistence), memory/seed in sync rule.
  3. `python3 mnemon/validate-seed.py mnemon/seed.json` until OK.
- **Verify:** validator prints `OK: N insights`; F3; JSON keys per insight exactly `content|category|importance|tags|entities` (+optional `source`); spot-check 3 gotcha insights against DOCKER-TEST-LEARNINGS.md.
- **Prerequisites:** Phase 0.
- **Rollback:** `git rm mnemon/seed.json mnemon/validate-seed.py` (+README if added). Note: existing `etc/mnemon-seed-hermes.json` (5 facts, `text` field) stays untouched — still imported by `setup_mnemon_all`; unifying the two schemas is deferred follow-up.

---

## Phase 22 — install.sh: two-mode detection + knowledge asset copy (+ seed memories)

- **Goal:** Installer detects dev vs standalone, copies knowledge assets in standalone mode, installs the mnemon plugin, and seeds default memories (needed so the Phase 23 memories symlink has a target).
- **Files:** modify `install.sh`; add `memories/MEMORY.md` + `memories/USER.md` (3 files total).
- **Steps:**
  1. After the existing `SCRIPT_DIR` block, add the two-mode detection exactly as proposal §3.2:
     ```sh
     MINIONS_REPO_ROOT=""
     if git rev-parse --show-toplevel &>/dev/null; then
         _GIT_ROOT="$(git rev-parse --show-toplevel)"
         if [ -d "${_GIT_ROOT}/skills" ] && [ -d "${_GIT_ROOT}/wiki" ]; then
             MINIONS_REPO_ROOT="$_GIT_ROOT"
         fi
     fi
     MODE="dev"; [ -z "$MINIONS_REPO_ROOT" ] && MODE="standalone"
     log_info "Knowledge mode: ${MODE}"
     ```
  2. Standalone copy block (proposal §3.4): `mkdir -p` skills/wiki/memories/mnemon under `MINIONS_HOME`; `cp -r "${SCRIPT_DIR}/skills/"*` etc.; memories copied only if absent (`[ -f ... ] || cp`) so USER.md/MEMORY.md survive reinstall; copy `mnemon/seed.json`.
  3. Dev mode: skip copies (assets live in repo; symlinked at boot) — log it.
     ⚠ **Install method gap (resolve in this PR):** the current one-liner `curl -fsSL https://minions.sh/install.sh | bash` has **no repo on disk**, so `${SCRIPT_DIR}/skills` won't exist in standalone. Either (A) make standalone bootstrap `git clone --depth 1` the repo (or a tarball) before copying assets, or (B) keep the one-liner framework-only and document `git clone && bash install.sh` as the knowledge-enabled path. Pick A, verify in DTS; note it in the PR description.
  4. Mnemon plugin install (Hermes-only): after `ensure_hermes`, if `~/.hermes/plugins/mnemon` missing → clone `gitricko/hermes-plugin-mnemon --depth 1` → copy `mnemon/` subdir → `hermes config set memory.provider mnemon` (idempotent; already true from config template — the setter is belt-and-suspenders).
  5. Author `memories/MEMORY.md` (agent memory seed: stack layout, key paths, the two-mode rule) and `memories/USER.md` (user profile seed: dev/engineer, concise responses, PR-to-main, root-cause fixes — adapted from upstream USER.md, trimmed of his-codespace-only facts).
- **Verify:** F1 on install.sh; run in a fresh DTS Ubuntu 24.04 container (standalone): `~/.minions/skills|wiki|memories|mnemon` populated, counts match (15 skills / 23 articles + INDEX / seed.json present), plugin dir exists, `hermes config get memory.provider` == mnemon; re-run install.sh → memories preserved, no clobber. Dev mode: run in this repo → prints "Knowledge mode: dev", no copies.
- **Prerequisites:** Phases 0, 1–15, 16–20, 21 (assets to copy).
- **Rollback:** `git checkout -- install.sh`; `git rm memories/MEMORY.md memories/USER.md`. In a container: `rm -rf ~/.minions/{skills,wiki,memories,mnemon} ~/.hermes/plugins/mnemon`.

---

## Phase 23 — boot.sh: two-mode detection + symlink wiring + seed import

- **Goal:** Every boot asserts the knowledge wiring (works after fresh install AND after rebuild).
- **Files:** modify `boot.sh` (1 file).
- **Steps:** after the existing READY marker (Step 5), or before it — add proposal §3.3 block adapted:
  1. Same two-mode detection block as Phase 22's (shared snippet — keep byte-identical between the two scripts so later edits are one-liner greps).
  2. Skills: `HERMES_SKILLS_DIR="${HOME}/.hermes/skills"`, link `minions` → `${MINIONS_REPO_ROOT}/skills` (dev) or `${MINIONS_HOME}/skills` (standalone); recreate only if `readlink` differs (never clobber a *directory* at that path — `rm -rf` only when it's a symlink or empty).
  3. Memories: `~/.hermes/memories` → `${MINIONS_REPO_ROOT}/memories` (dev) / `${MINIONS_HOME}/memories` (standalone), same readlink-guard logic.
  4. Wiki: **no symlink** (proposal §3.3 item 2) — just a log line stating where wiki lives.
  5. Seed import (Hermes only): `SEED_FILE="mnemon/seed.json"` per mode; `if mnemon import --dry-run "$SEED_FILE"; then mnemon import "$SEED_FILE"; fi` (non-fatal on any failure; mirrors `lib/mnemon.sh` import pattern — reuse `import_mnemon_seed` if preferable).
  6. Plugin fallback: if `~/.hermes/plugins/mnemon` still missing (e.g. install was framework-only), clone it here (same snippet as Phase 22.4).
  7. Pi-Agent: leave to Phase 24.
- **Verify:** F1; boots fine in this repo (dev): `ls -l ~/.hermes/skills/minions` → symlink to `<REPO_ROOT>/skills`; `readlink ~/.hermes/memories` → `<REPO_ROOT>/memories`; boot log contains knowledge-mode line + seed import line. Standalone container: symlinks target `~/.minions/*`; `mnemon import --dry-run` log line present. Re-run boot → "already correct" idempotency lines.
- **Prerequisites:** Phase 22 (memories + assets must exist to link/copy).
- **Rollback:** `git checkout -- boot.sh`; `unlink ~/.hermes/skills/minions ~/.hermes/memories` (or restore prior targets).

---

## Phase 24 — Pi-Agent settings.json wiring (shared skills dir)

- **Goal:** Pi reads the SAME `skills/` dir via the `skills` array in `~/.pi/agent/settings.json` (proposal §11).
- **Files:** modify `install.sh` + `boot.sh` (2 files).
- **Steps:**
  1. In install.sh (after models.json/pi.toml templating — note current comment on line 209 claiming settings.json isn't used; supersede it): compute `PI_SKILLS_PATH` per mode (`${MINIONS_REPO_ROOT}/skills` dev / `${MINIONS_HOME}/skills` standalone); create `~/.pi/agent/`; then either merge into existing settings.json (python3 json merge, proposal §11 snippet) or create fresh `{"skills": ["$PI_SKILLS_PATH"]}`. Keep `pi.toml` + `models.json` untouched.
  2. In boot.sh: idempotent re-assert — if settings.json lacks the skills path, re-run the merge (cheap, survives reinstall).
- **Verify:** F1, F3 on generated settings.json; `python3 -c "import json;print(json.load(open('$HOME/.pi/agent/settings.json'))['skills'])"` shows the path; confirm this is how your Pi build discovers skills (run whatever `pi` exposes — e.g. `pi --help`, `pi config`, or a dry prompt — and confirm the skills list includes a ported skill like `docker-test-shell`; if the CLI has no list command, verify the file merge only and note manual confirmation in the PR). Both modes (repo vs container).
- **Prerequisites:** Phases 22, 23 (detection blocks reused).
- **Rollback:** `git checkout -- install.sh boot.sh`; remove the `skills` key from `~/.pi/agent/settings.json` (or restore the file).

---

## Phase 25 — New .minions skills (batch 1: pi-agent-basics, omniroute-guide)

- **Goal:** Two of the four new skills from proposal §4.
- **Files (new):** `skills/pi-agent-basics/SKILL.md`, `skills/omniroute-guide/SKILL.md`.
- **Content:** `pi-agent-basics` — how Pi works, `~/.pi/agent/` config (pi.toml, models.json, settings.json), pi-failover extension, model selection, shared-skills-dir usage, "Pi ignores mnemon" note. `omniroute-guide` — OmniRoute combos/model selection, proxy setup, port config (20128), troubleshooting (requireLogin, /v1/models 401), keyless vs auth. Both: agent-readable, cite `../wiki/` articles where they exist (link to `omniroute-guide.md` planned in Phase 27 — forward links OK, F4 only checks `wiki/` targets).
- **Verify:** F2 (frontmatter name matches dir), F5, `sh -n` n/a (no scripts), readable by a fresh agent (self-review: description triggers correctly).
- **Prerequisites:** Phase 0.
- **Rollback:** `git rm skills/pi-agent-basics skills/omniroute-guide`.

---

## Phase 26 — New .minions skills (batch 2: hermes-configuration, minions-architecture)

- **Goal:** Remaining two new skills from proposal §4.
- **Files (new):** `skills/hermes-configuration/SKILL.md`, `skills/minions-architecture/SKILL.md`.
- **Content:** `hermes-configuration` — `hermes config set/get` commands explained, `~/.hermes/config.yaml` (the `${HERMES_HOME}` — not `.hermes/` — gotcha from DOCKER-TEST-LEARNINGS Issue 10), provider setup (omniroute/modelrelay), memory.provider=mnemon, plugin install. `minions-architecture` — system overview: install.sh/boot.sh/status.sh/stop.sh roles, component layout (`lib/`, `etc/`, `bin/`), two-mode knowledge delivery, port map, where things run from (DOCKER-TEST-LEARNINGS "What Goes Where" table).
- **Verify:** F2, F5, cross-check facts against DOCKER-TEST-LEARNINGS.md.
- **Prerequisites:** Phase 0.
- **Rollback:** `git rm skills/hermes-configuration skills/minions-architecture`.

---

## Phase 27 — New .minions wiki articles (batch 1: architecture, omniroute-guide)

- **Goal:** Two foundational articles (pair with minions-architecture / omniroute-guide skills).
- **Files (new):** `wiki/architecture.md`, `wiki/omniroute-guide.md`, **+ update** `wiki/INDEX.md` (append both rows) — 3 files.
- **Content:** `architecture.md` — .minions system overview, component roles/responsibilities, directory map, two-mode knowledge layer (mirror of proposal §3). `omniroute-guide.md` — combos/model selection, env-var overrides (`OMNIROUTE_PORT`, `MINIONS_LLM_BASE_URL`), troubleshooting (401/no-models/requireLogin), port-config interplay (forward-ref `../wiki/port-configuration.md` as planned-future article).
- **Verify:** F4 (links incl. INDEX rows resolve), F5, titles present.
- **Prerequisites:** Phases 16–20 (INDEX.md exists), 25–26 optional but recommended (skills reference these).
- **Rollback:** `git rm wiki/architecture.md wiki/omniroute-guide.md` + revert INDEX rows.

---

## Phase 28 — New .minions wiki articles (batch 2: pi-agent-guide, hermes-configuration)

- **Goal:** Final two planned articles (pair with pi-agent-basics / hermes-configuration skills).
- **Files (new):** `wiki/pi-agent-guide.md`, `wiki/hermes-configuration.md`, **+ update** `wiki/INDEX.md` — 3 files.
- **Content:** `pi-agent-guide.md` — Pi usage/config/extensions incl. settings.json skills array, failover, model selection, Hermes-vs-Pi auth models. `hermes-configuration.md` — `hermes config` CLI, config.yaml anatomy, provider/fallback setup, mnemon plugin + provider, common failure modes (Issue 10 config-path gotcha).
- **Verify:** F4, F5; INDEX.md now lists 27 articles (23 ported + 4 new); reverse-check every INDEX row's file exists.
- **Prerequisites:** Phase 27.
- **Rollback:** `git rm wiki/pi-agent-guide.md wiki/hermes-configuration.md` + revert INDEX rows.
- **Follow-up (out of scope, noted):** remaining 5 proposal articles — `troubleshooting.md`, `port-configuration.md`, `testing-with-dts.md`, `mnemon-plugin-setup.md`, `development-guide.md` — land in a later PR series.

---

## Phase 29 — GitHub Actions workflow

- **Goal:** Create `.github/workflows/ci.yml` with 3 jobs: detect-changes, full-build,
  lint-check. Mirrors hermes-codespace's `devcontainer-ci.yml` adapted for .minions.
- **Files (new/modified):** `.github/workflows/ci.yml` (replace or merge with existing
  `test.yml` — check which exists).
- **Steps:**
  1. `detect-changes` job with `dorny/paths-filter@v3`:
     - `infrastructure`: `install.sh`, `boot.sh`, `self-check.sh`, `lib/*.sh`,
       `.github/workflows/**`
     - `runtime`: `skills/**`, `wiki/**`, `mnemon/**`, `memories/**`
     - `docs`: `docs/**`, `README.md`
  2. `full-build` job (runs only when infrastructure changed):
     - Checkout, setup Node.js 24
     - Run `install.sh` (standalone mode in fresh container)
     - Run `boot.sh`
     - Run `self-check.sh` (Phase 0.6)
     - Run mnemon integration test (Phase 30)
     - Collect diagnostic logs on failure (upload as artifact)
  3. `lint-check` job (runs when runtime or docs changed):
     - Install `markdownlint-cli`
     - Run `bash skills/ci-lint-check/scripts/ci_lint_check.sh` (ported in Phase 6)
  4. Add concurrency group to cancel in-progress runs for same branch/PR
- **Verify:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` parses;
  push to test branch, verify GitHub Actions triggers. Lint-check should run on
  any `skills/` or `wiki/` change; full-build only on infra changes.
- **Prerequisites:** Phases 1–15 (skills exist, including ci-lint-check), Phase 0.6
  (self-check.sh).
- **Rollback:** `git rm .github/workflows/ci.yml` or restore previous workflow.

---

## Phase 30 — Mnemon integration test (CI)

- **Goal:** Add mnemon integration test to the full-build CI job. Validates the
  mnemon plugin → hermes-plugin-mnemon → mnemon binary pipeline end-to-end.
- **Files:** modify `.github/workflows/ci.yml` (add test steps to full-build job).
- **Steps:**
  1. After self-check.sh in the full-build job, add mnemon integration test:
     ```yaml
     - name: Mnemon Integration Test
       run: |
         set -euo pipefail
         TEST_NAME="ci-mnemon-$(date +%s)-$$"
         echo "=== Mnemon Integration Test: $TEST_NAME ==="
         hermes chat -q "my name is $TEST_NAME, remember this in mnemon"
         mnemon recall "$TEST_NAME" --limit 5 | grep -q "$TEST_NAME"
         echo "=== ALL MNEMON CHECKS PASSED ==="
     ```
  2. This test only runs in the full-build job (infrastructure changes), not lint-check.
  3. Validates: mnemon_remember tool → mnemon recall CLI → end-to-end pipeline.
- **Verify:** Push to test branch; verify full-build job includes mnemon test step.
- **Prerequisites:** Phase 29 (workflow exists), Phase 22 (mnemon plugin installed).
- **Rollback:** Remove the mnemon test step from ci.yml.

---

## Phase 31 — Smoke test: full end-to-end verification

- **Goal:** Re-run the Phase 0.5 test contract end-to-end. All assertions should now be
  GREEN in both dev and standalone modes. This proves the full knowledge layer works.
- **Files:** `tests/test_knowledge.sh` (already written in Phase 0.5; this phase runs it).
- **Steps:**
  1. Run in dev mode locally: `KNOWLEDGE_TEST_MODE=dev bash tests/test_knowledge.sh` — expect GREEN.
  2. Run in standalone mode inside DTS (`dts up` → mount repo → `dts exec bash tests/test_knowledge.sh` with standalone env) — expect GREEN.
  3. Run existing test suites to ensure nothing is broken: `tests/test_install.sh`, `tests/test_boot.sh`, `tests/test_cli_integration.sh` — all GREEN.
- **Verify:** `bash tests/test_knowledge.sh` green in both modes. All existing suites pass.
- **Prerequisites:** All of Phases 0–30.
- **Rollback:** N/A (test file was already written; this phase is verification-only).

---

## Remaining risks / open decisions (track in PRs)

1. **Standalone asset source** (Phase 22) — one-liner `curl|bash` has no repo; option A (clone) chosen, verify in DTS.
2. **Seed schema drift** (`content` vs `text`, Phase 21) — new seed uses `content`; old `etc/mnemon-seed-*.json` migrate later; confirm `mnemon import` accepts both during Phase 21 verification.
3. **Pi settings.json discovery** (Phase 24) — proposal asserts settings.json `skills` array; confirm against the pinned Pi version (`PI_VERSION=0.85.1`) during that phase; if unsupported, fall back to documenting `pi --skill` usage in the skill.
4. **dts.sh reconciliation** (Phase 7) — repo `scripts/dts.sh` wins unless upstream is newer; state the diff in the PR.
5. **CI self-check adaptation** (Phase 0.6) — upstream self-check uses Telegram delivery and Ollama checks; .minions may not have these configured. Make those checks optional/warn-only rather than fail.
6. **GitHub Actions runner** (Phase 29) — full-build job runs `install.sh` which needs network access for npm/curl; verify Actions runner has outbound access. Mnemon integration test needs `hermes` CLI available — confirm it's on PATH after install.sh.