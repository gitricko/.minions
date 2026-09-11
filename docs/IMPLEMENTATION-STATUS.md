# Implementation Status

**Branch:** `minion-knowledge-base` (PR #22, knowledge-layer integration)
**Base:** `main` (contains the earlier simplification work this doc previously tracked)
**Last updated:** 2026-09-11 (CI green on tip `54b2117`: Test ✅, Real Install ✅, DTS ✅)

> **READ THIS FIRST, NEXT AGENT** — you are being brought online in a fresh instance that
> will install .minions in **dev mode**. Your first job after install is to **VERIFY dev
> mode actually works** (mode detected, symlinks created, assets reachable). Skip to
> **[NEXT AGENT: DEV-MODE INSTALL VERIFICATION](#next-agent-dev-mode-install-verification)**.
> The rest of this doc is context: the earlier simplification work + the knowledge-layer
> integration that makes dev mode possible.

This doc is the authoritative record of what the knowledge-layer integration changed,
what works, and what remains for a follow-up agent. Read
`PROPOSAL-skills-wiki-integration.md` + `IMPL-PLAN-skills-wiki-integration.md` for design
intent; this file tracks reality (verified by shellcheck + real DTS container install →
boot → chat run + CI).

---

## Knowledge-Layer Integration (Phases 0–23) — the current work

**Goal:** Port the hermes-codespace knowledge stack (skills, wiki, mnemon seeds, memories)
into .minions, with **two install modes**:

- **dev mode** — running inside a git checkout of this repo (has `.git` + `skills/` + `wiki/`).
  Knowledge assets stay in the repo; `~/.minions/{skills,wiki,mnemon,memories}` become
  **symlinks** to the checkout. This is what a fresh dev-mode install must produce.
- **standalone mode** — installed via `curl -fsSL .../install.sh | bash` (no `.git`).
  Knowledge assets are **copied** into `~/.minions/` by install.sh.

**Phase completion:** 0, 0.1, 0.5, 0.6, 1–15 (15 skills ported), 22 (detection + copy),
22.5 (curl|bash bootstrap), 23 (symlink wiring). **Remaining:** 16–21 (wiki content +
mnemon seed), 24–31 (Pi wiring, new content, CI, smoke). PR #22 carries everything so far.

**Shared helpers:**
- `lib/knowledge-detection.sh` — `detect_knowledge_mode()`: dev vs standalone. Persists to
  `~/.minions/etc/knowledge.env` (`MODE`, `MINIONS_REPO_ROOT`). Sourced by install.sh and
  boot.sh (byte-identical detection).
- `lib/knowledge-symlinks.sh` — `setup_knowledge_symlinks()`: creates the 4 symlinks in dev
  mode; no-op in standalone. Idempotent (`rm -rf` + `ln -sfn`).
- `lib/install-mnemon-plugin.sh` — idempotent hermes-plugin-mnemon install.

**Key wiring:**
- `install.sh` — bootstrap preamble (piped detection + tarball fetch + re-exec, Phase 22.5),
  detection, standalone asset copy, knowledge.env persist, dev symlinks.
- `boot.sh` — sources detection + symlinks; re-links on every boot from persisted env.
- `self-check.sh` — Persistence section checks `~/.minions/{skills,wiki,mnemon,memories}`
  (symlink in dev, dir in standalone). Exit 1 = warnings (tolerated in CI), exit 2 = critical.
- `scripts/verify-knowledge.sh` — F1 (bash -n syntax), F2 (frontmatter), F3 (JSON),
  F4 (wiki links), F5 (no upstream path refs). File checks only.

**Test contract (all GREEN):**
- `tests/test_knowledge_mode.sh` — 3/3 (dev, standalone, MINIONS_HOME override)
- `tests/test_boot_symlinks.sh` — 7/7 (symlinks, standalone no-op, idempotence)
- `tests/test_bootstrap.sh` — 16/16 (piped detection, tarball standalone, git dev)
- DTS Tests 9.5 (standalone piped) + 9.6 (dev in repo) — verified in CI
- Real-install T7 (standalone tarball) — verified in CI

**Pipeline placement:** `test` job = file checks + unit tests only. Full probes
(self-check, service health, chat) run in `real-install` + `dts-integration`.

---

## NEXT AGENT: DEV-MODE INSTALL VERIFICATION

**You will be installed in dev mode on a fresh instance. Your first job: verify dev mode
actually works end-to-end.** Do NOT assume it works because CI is green — the point of
this exercise is that you confirm it in the real environment. Run these in order; stop
and investigate anything that fails.

### 0. Load the required skills FIRST

Before touching anything, load the skills this work depends on. There are **two places**
skills live — check both:

1. **Hermes skills** (your own agent skills, if running inside Hermes): the TDD and
   coding-guidelines workflows are not in this repo — you likely already have them as
   Hermes skills (`test-driven-development`, `karpathy-coding-guidelines`). If not, load
   them from the repo copy (see below) or your Hermes skill store.
2. **Repo skills** (this project's ported skills, under `skills/` — these are the
   authoritative copies): `karpathy-coding-guidelines`, `docker-test-shell`,
   `test-driven-development` if it lives in the repo, plus anything task-relevant.

**Load these skill files from the repo:**
```bash
# From <REPO_ROOT>:
#   skills/karpathy-coding-guidelines/SKILL.md        — Karpathy coding guidelines (VERIFIED: ported, present)
#   skills/test-driven-development/SKILL.md           — TDD workflow (check presence; not in the 48-file listing above)
#   skills/docker-test-shell/SKILL.md                 — DTS workflow (present: references/dts-usage.md)
```
- If `test-driven-development` is NOT in the repo listing, load it from your Hermes
  skill store instead (it's a standard Hermes skill used throughout this project's CI).
- `karpathy-coding-guidelines` IS in the repo (ported Phase 15) — read
  `skills/karpathy-coding-guidelines/SKILL.md`.
- Also relevant if the task touches them: `memory-automation`, `persistent-knowledge`,
  `mnemon-seed-persistence`, `mnemon-graph-export`, `codespace-gh-auth` (git push auth),
  `ci-lint-check`.

> These skills define the HOW (TDD: red-green-refactor, Karpathy: minimal diffs, test
> the behavior not the implementation). The verification below is the WHAT. Do the work
> their way.

### Orientation
- Repo checkout: `<REPO_ROOT>` (this repo, branch `minion-knowledge-base`, PR #22).
- `.minions` installs to `~/.minions` (i.e. `$HOME/.minions`).
- Mode + repo-root are persisted in `~/.minions/etc/knowledge.env` — that file is the
  single source of truth for which mode install picked.

### 1. Mode detection — is it DEV?
```bash
cat ~/.minions/etc/knowledge.env
# EXPECT:  MODE=dev
#          MINIONS_REPO_ROOT=<REPO_ROOT>   (a real path, not empty)
```
- `MODE=dev` + non-empty `MINIONS_REPO_ROOT` = correct for a git-checkout install.
- If `MODE=standalone` in a dev checkout → install ran in the wrong mode; investigate
  `lib/knowledge-detection.sh` (git-root probe should find `<REPO_ROOT>`).
- Also expect the install log to have printed `Knowledge mode: dev`.

### 2. Symlinks — are the 4 knowledge dirs linked to the repo?
```bash
ls -la ~/.minions/
# EXPECT all four of these entries to exist and be SYMLINKS:
#   skills    -> <REPO_ROOT>/skills
#   wiki      -> <REPO_ROOT>/wiki       (content not yet ported: Phases 16–20 — dir may be near-empty; that's FINE)
#   mnemon    -> <REPO_ROOT>/mnemon     (seed content: Phase 21 pending)
#   memories  -> <REPO_ROOT>/memories   (seed content present)
```
- Each must be `l` (symlink) pointing INTO `<REPO_ROOT>`, e.g.
  `skills -> /home/.../.minions/skills`. A plain directory = standalone-style COPY →
  wrong for dev mode.
- **Symlinks must resolve:** `readlink -f ~/.minions/skills` should equal `<REPO_ROOT>/skills`.
  `ls ~/.minions/skills/` should list the repo's skills (e.g. `codespace-gh-auth/`).

### 3. Content reachable through the links
```bash
ls ~/.minions/skills/          # non-empty: ported skills
test -d ~/.minions/skills/codespace-gh-auth && echo "skills reachable"
test -f ~/.minions/wiki/.gitkeep && echo "wiki link ok"   # content arrives in P16–20
```

### 4. Re-boot re-links (boot.sh honors persisted env)
```bash
bash ~/.minions/boot.sh        # or the repo's boot.sh — both source detection + symlinks
# EXPECT:  [INFO] Knowledge mode: dev (from .../etc/knowledge.env)
#          [INFO] Linked ~/.minions/skills -> <REPO_ROOT>/skills   (×4)
```
- boot.sh MUST read `knowledge.env` (dev from persisted env) — not re-detect into some
  other mode. This is the boot-time re-link guarantee.

### 5. Self-check: Persistence section GREEN
```bash
bash self-check.sh             # from <REPO_ROOT>
# EXPECT: Persistence section shows all 4 as symlinks -> <REPO_ROOT>/...
```
- In dev mode a plain dir would be wrong — self-check FAILs on a missing symlink when
  knowledge exists. See `self-check.sh` Persistence section for exact semantics.
- Exit codes: 0 = healthy, 1 = warnings (non-fatal in CI), 2 = critical (must fix).

### 6. Hermes sees the dev-mode skills
```bash
hermes --version
ls ~/.hermes/skills/           # should include the .minions skills via plugin/wiring
```
- If you're inside Hermes itself, the loaded skills in your session should include the
  ported ones (codespace-gh-auth, etc.).

### 7. Known gaps (don't chase these)
- `wiki/` content is EMPTY until Phases 16–20; `mnemon/` seed until Phase 21. Symlinks
  exist but target near-empty dirs — expected, not a bug.
- The skills live in the repo; standalone mode (curl|bash) copies them. You are DEV mode —
  confirm the symlink path, not the copy path.

### If verification fails
- Capture `cat ~/.minions/etc/knowledge.env`, `ls -la ~/.minions/`,
  `readlink -f ~/.minions/skills`, and the install log, then trace:
  install.sh detection → `lib/knowledge-detection.sh` → `lib/knowledge-symlinks.sh` →
  knowledge.env → boot.sh re-link → self-check. Fix the root cause (likely detection or
  the env persist step), not the symptom.
- CI contract is the safety net: `bash tests/test_knowledge_mode.sh` (3) +
  `bash tests/test_boot_symlinks.sh` (7) + `bash tests/test_bootstrap.sh` (16) must all
  stay GREEN; DTS Tests 9.5/9.6 + real-install T7 must stay green.

---

## What Changed (vs main)

| Area | Change |
|------|--------|
| **Multi-instance** | `MINIONS_HOME` fixed to `~/.minions`; `--minions-home` and `--dry-run` removed |
| **Ports** | `OMNIROUTE_PORT` (20128), `MODELRELAY_PORT` (7352) env-overridable in install.sh + boot.sh |
| **Config** | install.sh copies/interpolates `etc/pi.toml` → `~/.pi/agent/pi.toml`, `etc/models.json` → `~/.pi/agent/models.json`; Hermes config written to `~/.hermes/config.yaml` |
| **`etc/minions.env`** | deleted — no runtime config file |
| **Wrapper install** | `install_npm_package`, `install_pi` keep thin wrappers (npm needs vendored Node 22.22.2) |
| **Hermes install** | simplified (see below) |
| **CI** | added `dts-integration` job running `test_dts.sh`; real-install job now does full install (no `--no-hermes`) |
| **Tests** | all DTS/real paths upgraded from `--no-hermes` to full install; `settings.json` references dropped |
| **README** | rewritten to single-instance reality |

Files touched: `install.sh`, `boot.sh`, `status.sh`, `lib/hermes.sh`, `scripts/dts.sh`,
`.github/workflows/ci.yml`, `tests/{test_install,test_boot,test_cli_integration,test_dts}.sh`,
`README.md`, `docs/SIMPLIFICATION-PROPOSAL.md` (reconciled).

---

## Two Deliberate Deviations From the Proposal

These are DOCUMENTED intent changes, not bugs. The proposal text was reconciled to match.

1. **`omniroute_preconfigure` runs at BOOT, not install.** The proposal said remove it from
   boot (open question #1). In practice it must run at boot: `combo create auto-fastest` is a
   **client command that needs the OmniRoute server running**. Login-off (`setup` + disable
   `requireLogin`) happens at install because it writes sqlite directly and needs no server.
   → `boot.sh` still calls `omniroute_preconfigure`.

2. **npm packages use thin wrappers, not bare symlinks.** The proposal's "Direct Binaries,
   No Wrappers" promise is impossible for OmniRoute/ModelRelay/Pi: they need vendored Node
   22.22.2 + `NODE_PATH`. `~/.minions/bin/{omniroute,modelrelay,pi}` are wrappers; only
   `hermes`/`mnemon` are plain symlinks. Documented in proposal §5.

---

## The Hermes Install Fix (critical, VERIFIED)

Original code installed Hermes with a fake `HOME` (`HERMES_HOME_OVERRIDE="${install_dir}/home"`),
which orphaned the config we write at `~/.hermes/config.yaml`.

**Fix (`lib/hermes.sh`):**
- Install to the **real** `~/.hermes` (no `HOME` override). Hermes resolves config via
  `get_hermes_home()` = `$HERMES_HOME` or `$HOME/.hermes`, so the fake HOME was dead weight.
- Symlink `~/.minions/bin/hermes` → **the venv entrypoint**
  `~/.hermes/hermes-agent/venv/bin/hermes` (preferably), NOT the source-tree launcher.

> **Gotcha found & fixed:** the source-tree `hermes` launcher uses `#!/usr/bin/env python3`,
> which resolves to the **system** python (3.12) that lacks `dotenv` → `ModuleNotFoundError`.
> The venv `bin/hermes` has the correct venv-python shebang and works. Use the venv binary.

**Verified in DTS container:**
- `bin/hermes --version` → `Hermes Agent v0.21.1`
- `hermes config show` → `Config: /home/ubuntu/.hermes/config.yaml`, provider `omniroute`,
  model `auto-fastest` — i.e. it **reads the config we wrote**. Single source of truth.

---

## Mnemon Seed Import (fixed, worth double-checking)

Two bugs in the original install:
1. `setup_mnemon_all` looks for seeds at `${minions_home}/etc/mnemon-seed-*.json`, but
   install.sh only copied `versions.env` to `~/.minions/etc/` — seeds were never copied.
   → **Fix:** install.sh now copies `etc/mnemon-seed-*.json` → `~/.minions/etc/` alongside
   versions.env (before the mnemon setup step).
2. install.sh had a redundant broken block calling an undefined `mnemon_import` function
   (real func is `import_mnemon_seed`, called by `setup_mnemon_all`). → **Removed** the dead
   duplicate block.

**Status:** mnemon binary installs (v0.2.5) and the seed files are copied, but **seed import
was not directly verified** in this DTS run — the `mnemon setup` output was non-fatal. A
follow-up should confirm seeds actually land in the mnemon store.

---

## Dead Code Removed

- `--no-omniroute` / `--no-modelrelay` flags: were parsed but never used (SC2034). Now wired
  to actually skip those installs (`if [ "${INSTALL_*}" -eq 1 ]`).
- `status.sh`: removed stale source of `etc/minions.env` (file no longer exists).
- `install.sh`: removed dead `settings.json` copy block (no such template file exists).
- `scripts/dts.sh`: removed dead/broken `user_home()` function (never called, and it didn't
  capture its own output).
- `lib/hermes.sh`: removed the python-dotenv install block written against the old fake-HOME
  path (redundant now that we use the venv entrypoint which already has dotenv).

---

## CI Changes

- **New `dts-integration` job** (runs after `test`): `actions/checkout` → `bash tests/test_dts.sh`.
  This is the real end-to-end gate: fresh ubuntu:24.04 container → install → boot → health →
  chat completion → stop → clean. Requires Docker (available on GH ubuntu-latest runners).
- **`real-install` job**: now runs `bash install.sh` (full, incl. Hermes) instead of
  `--no-hermes`, and verifies `~/.hermes/config.yaml` has the expected ports (guards against
  the fake-HOME regression).
- **Binary verification hardened:** real-install now hard-fails on `omniroute/pi/hermes --version`
  failure (was a warn). modelrelay has no `--version` flag upstream; it's verified by binary
  presence + `/v1/models` endpoint (hard-fail in CLI test).

---

## Fixes Since Initial DTS Verification (2026-09-09)

### 1. modelrelay `--version` warning → HARD FAIL on real-install
**Problem:** CI real-install loop ran `--version` on all 4 binaries; modelrelay has **no `--version`
flag** upstream (it starts the server and hangs). Every run printed `WARN: modelrelay installed but
--version failed` and continued. A genuinely broken omniroute/pi/hermes would also only warn.

**Fix (`.github/workflows/ci.yml`):** Split the loop. omniroute/pi/hermes: `--version` is a **hard
fail** (exit 1). modelrelay: binary presence check + functional validation via `/v1/models` in
`test_cli_integration.sh` (already hard-fail).

### 2. pi `--version` restored to hard-fail (was incorrectly weakened)
**Problem:** Commit `291e99a` downgraded pi `--version` to a warning claiming "upstream hang".
Investigation proved this was **wrong**: the `--version` arg parser is synchronous
(`pkg.version` → `console.log`, no network), and `pi --version` returns `0.85.1` in ~400ms
reliably on dev host and clean DTS container. The original CI failure was OOM/low-memory starving
Node startup, now fixed by `NODE_OPTIONS=--max-old-space-size=512` + `--prefer-offline --no-optional`
in `lib/npm_packages.sh`.

**Fix (`tests/test_dts.sh`, `tests/test_cli_integration.sh`):** Restored hard-fail on pi `--version`
failure in both test files.

### 3. `pi extensions reload` removed from install.sh (source of "Connection error" spam)
**Problem:** After installing pi-failover extension, `install.sh` ran `pi extensions reload`,
which starts the Pi REPL and immediately tries to connect to OmniRoute (20128) and ModelRelay (7352)
— but those services aren't up until `boot.sh` runs. Users saw "Connection error" spam during install.

**Fix (`install.sh`):** Removed the reload call. Extension is registered on disk; it loads
automatically when the user runs `pi` after `boot.sh`.

### 4. Test assertions added to catch install.sh connection attempts
**Problem:** The tests ran `install.sh` → `boot.sh` → validate endpoints. The connection errors
during install were printed but didn't fail the test (reload had `|| true`, install.sh exited 0).

**Fix (`tests/test_dts.sh`, `tests/test_cli_integration.sh`):** Both DTS test paths now capture
`install.sh` stderr and **fail** if any "Connection error" or connection attempt to 20128/7352
appears. This validates the install/boot split is clean.

---

## Still Open / For a Follow-Up Agent

1. **Wiki content (Phases 16–20)** — `wiki/` contains only `.gitkeep`. Port the 23
   upstream articles from `hermes-codespace` `.devcontainer/wiki/` in 5 batches, per the
   plan. F4 (link integrity) gates each batch.
2. **Mnemon seed + validator (Phase 21)** — `mnemon/seed.json` + `validate-seed.py` not yet
   created (schema uses `content` field; existing `etc/mnemon-seed-*.json` use `text`).
3. **Pi-Agent wiring (Phase 24)** — settings.json shared skills dir not yet wired.
4. **Phases 25–31** — new .minions skills/wiki, GitHub Actions finalization, mnemon CI,
   full smoke test.
5. **Prerequisite verification of dev-mode install (THIS instance)** — see
   [NEXT AGENT: DEV-MODE INSTALL VERIFICATION](#next-agent-dev-mode-install-verification)
   at top. Everything in CI is green, but the real dev-mode install on a fresh machine
   must be confirmed: `MODE=dev`, 4 symlinks to the repo, boot re-links, self-check ok.

Older simplification-era open items (see below) are mostly resolved; the mnemon seed
import + pi-failover extension notes remain from that work.

---

## How to Re-verify (DTS)

```bash
bash tests/test_dts.sh              # full flow, requires docker; exit 0 = pass
bash tests/test_dts.sh --no-clean   # same, but leave the container up afterwards to shell
                                    # in for manual testing (dts shell / dts exec)
```

This runs install (full, incl. hermes) → boot → health → auto-fastest combo → chat
completion → **hermes chat -q + pi -p CLI chat** → stop → clean, all in a fresh container.

### New in test_dts.sh (added 2026-09-08/09)
- **Test 8 (CLI chat):** the final end-to-end check — `hermes chat -q 'Reply with exactly:
  OK'` and `pi -p 'Reply with exactly: OK' --provider omniroute --model
  omniroute/auto-fastest`, both keyless via the auto-fastest combo. These exercise the
  real toolchains (hermes + pi wrappers).
- **`--no-clean` flag:** leave the DTS container running after tests (no `dts clean`) so you
  can shell in and test manually. On error AND on success it prints:
  `dts shell` / `dts exec "<cmd>"` / `dts clean`. Note: the test runs `stop.sh` at the end,
  so with `--no-clean` services are STOPPED — run `dts exec "cd /src && bash boot.sh"` again
  before manual CLI testing.
- **install.sh connection guard:** Test 1 now captures install.sh output and fails on any
  "Connection error" or connection attempt to 20128/7352.

### Pitfall (environment, not code)
On a resource-limited container, `npm install omniroute@3.8.50` can be **OOM-killed**
(`Killed` in the log). This is an environment memory limit, not a script bug — omniroute
installs fine with adequate RAM.

**Fix applied 2026-09-08:** Added memory-frugal flags to `lib/npm_packages.sh`:
- `NODE_OPTIONS="--max-old-space-size=512"` limits Node.js heap to 512MB
- `--prefer-offline` avoids network-dependent memory spikes
- `--no-optional` skips optional dependency installation

These flags let omniroute install within the container's memory limits. With adequate RAM (>6GB) these flags are harmless; on low-RAM environments they're essential.

OmiRoute installs fine with 6GB+ RAM without the flags; on 2-4GB containers the flags are required.

---

## Key Commits (chronological)

| Commit | Change |
|--------|--------|
| `d77b4ee` | Refactor installation and boot for simplification and clarity |
| `9cfaedf` | Simplify installation and boot by removing temporary directories |
| `f390d35` | Update actions/checkout to v7 |
| `fb4fa7b` | Refactor integration tests to use DTS for verification |
| `abc8a40` | docs: add simplification proposal |
| `291e99a` | pi `--version` → warn (WRONG diagnosis — upstream hang) |
| `60160d9` | pi.toml test greps `localhost` (template uses localhost) |
| `eb6d83a` | nohup service starts + pi wrapper hardcodes MINIONS_HOME |
| `bd7cf48` | 10s retry + omniroute.log dump on `/v1/models` failure |
| `5721e59` | Capture real HTTP status when `/v1/models` fails |
| `8b2acfb` | Fix OmniRoute login via direct sqlite write, not REST api |
| `d3be56e` | **Restore pi --version to hard-fail** (proved deterministic) |
| `4d366b0` | **CI binary verification hard-fail** (modelrelay verified via /v1/models) |
| `0850968` | **Remove pi extensions reload** from install.sh (source of Connection error) |
| `1c1f9d0` | **Test assertions** for install.sh connection attempts |

### Knowledge-layer commits (the current work, PR #22 — branch `minion-knowledge-base`)

| Commit | Change |
|--------|--------|
| `00678e3` | feat: Phase 0–0.6 knowledge layer foundation (scaffold, verify-knowledge.sh, test contract, self-check.sh) |
| `aee4747` | Phase 1: port codespace-gh-auth |
| `8b297b8` `9dd152a` `b571a2d` `bcee46f` | Phases 2–5: codespace-persistent-symlinks, -port-visibility, -vscode-open, -lavish |
| `91efd90` | fix: F1 uses bash -n (bash-only syntax in lavish script) |
| `25e6acc` | Phase 6: port ci-lint-check (path-adapted) |
| `b73cd6d` `51bc21b` | Phase 7: reconcile docker-test-shell (scripts/dts.sh + skill wrapper) |
| `f8418c5` `b59636d` `290b218` `453d6e2` `fa72a2a` | Phases 8–15: memory-automation, mnemon-seed-persistence, persistent-knowledge, mnemon-graph-export, codespace-webtop, github-codespace, github-pr-review, karpathy-coding-guidelines |
| `5802cfb` | docs: reorder plan — Phases 22/23 before wiki content 16–21 |
| `730b639` | docs: PROPOSAL-bootstrap-curl-bash.md + Phase 22.5 |
| `67565b3` | **Phase 22: two-mode detection + knowledge asset copy** |
| `e3b3c1e` | fix(shellcheck): Phase 22 libs sh-clean (no `local`, SC1091 disabled) |
| `300759a` | **Phase 22.5: self-contained curl\|bash bootstrap preamble** |
| `17ba7fd` | fix(test_dts): avoid pipeline export scope issue in Test 9.5 |
| `5081dd5` | fix(test_bootstrap): T3 expects symlink in dev mode |
| `ad10907` | **Phase 23: dev-mode symlink wiring** |
| `6ed8c31` | fix(self-check): update symlink paths for Phase 23 knowledge layer |
| `b25bc52` | fix(test_dts): Test 9.5 git archive HEAD + prefix layout |
| `869378a` | fix(test_dts): Test 9.5 real curl\|bash via stdin, unmask RC |
| `4ca6b5c` | fix(test_dts): mkdir /tmp/empty before Test 9.5 bootstrap run |
| `bf75e8c` | fix(test_dts): Test 9.6 accept symlink for dev-mode skills |
| `54b2117` | fix(ci): T7 real-install standalone test actually runs (was silent skip) |

**Tip:** `54b2117` — all 3 CI jobs green; PR #22 mergeable/clean.

---

## Verification Checklist

**Knowledge layer (current work) — all passing:**
- [x] `tests/test_knowledge_mode.sh` 3/3 (dev, standalone, MINIONS_HOME override)
- [x] `tests/test_boot_symlinks.sh` 7/7 (4 symlinks, standalone no-op, idempotence)
- [x] `tests/test_bootstrap.sh` 16/16 (piped detection, tarball standalone, git dev)
- [x] DTS Test 9.5 standalone piped install: exit 0, standalone detected, assets copied, knowledge.env persisted
- [x] DTS Test 9.6 dev in repo: dev detected, skills symlink correct
- [x] Real-install T7 standalone bootstrap: exit 0, standalone detected, assets copied (fixed `54b2117`, no silent skip)
- [x] self-check.sh Persistence section: symlinks at `~/.minions/{skills,wiki,mnemon,memories}`
- [x] CI all green on `54b2117`: Test, Real Install, DTS

**Simplification era (superseded baseline) — was passing:**
- [x] DTS Integration: fresh container → install → boot → health → chat → hermes/pi CLI → stop
- [x] Real Install (Linux): install → boot → CLI integration (including `/v1/models` for modelrelay)
- [x] `pi --version` works in DTS container (0.85.1, rc=0)
- [x] `modelrelay --version` correctly not checked (no upstream flag); verified via `/v1/models`
- [x] `install.sh` produces no "Connection error" or port connection attempts
- [x] Hermes reads `~/.hermes/config.yaml` (single source of truth)

**Not yet verified (deliberately — see Still Open):**
- [ ] Real dev-mode install on a fresh machine: MODE=dev, 4 symlinks to repo, boot re-link, self-check ok ← **NEXT AGENT's job**
- [ ] Wiki content (Phases 16–20) / mnemon seed (Phase 21) / Pi wiring (Phase 24)

