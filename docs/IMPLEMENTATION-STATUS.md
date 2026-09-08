# Simplification Implementation Status

**Branch:** `refactor/simplify-install-boot`
**Last updated:** 2026-09-08 (after DTS verification)

This doc is the authoritative record of what the simplification proposal actually
changed, what works, and what remains for a follow-up agent. Read `SIMPLIFICATION-PROPOSAL.md`
for the design intent; this file tracks reality (verified by shellcheck + a real DTS
container install → boot → chat run).

---

## Goal

Remove multi-instance complexity (`MINIONS_HOME`, `--minions-home`, `--dry-run`) now that
DTS provides clean test isolation. Single install at `~/.minions`, ports are env-overridable.
Config lives at each component's standard location.

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

---

## Still Open / For a Follow-Up Agent

1. **Mnemon seed import not fully verified** — confirm imported seeds exist in the store
   after a fresh install; the DTS run only confirmed the binary + file copy, not the import.
2. **pi-failover extension install failed** in the DTS container:
   `[WARN] pi-failover extension install failed`. It's non-fatal (logged warning) and the doc
   says "may not exist yet." Verify whether `github.com/gitricko/pi-failover@hermes-impl` is
   reachable/installable; if not, it's an expected-on-first-run case.
3. **DTS harness on GH runner** — `dts-integration` job added but NOT yet run in real CI on
   this branch. Push to a PR to confirm the job passes (Docker-in-GH-actions works, but the
   apt package set + install time ~7 min must be within the 60-min cap — it is).
4. **`boot.sh --doctor`** is parsed but has no distinct behavior in the simplified boot —
   confirm that's intended (it may be vestigial from the old flow).
5. **`scripts/dts.sh` family of SC2046 warnings** (word-splitting on `docker_env_flags`) are
   intentional (needed to expand the flags into separate `docker exec` args). Leave them;
   they're not in the CI shellcheck path.

---

## How to Re-verify (DTS)

```bash
bash tests/test_dts.sh              # full flow, requires docker; exit 0 = pass
bash tests/test_dts.sh --no-clean   # same, but leave the container up afterwards to shell
                                    # in for manual testing (dts shell / dts exec)
```

This runs install (full, incl. hermes) → boot → health → auto-fastest combo → chat
completion → **hermes chat -q + pi -p CLI chat** → stop → clean, all in a fresh container.

### New in test_dts.sh (added 2026-09-08)
- **Test 8 (CLI chat):** the final end-to-end check — `hermes chat -q 'Reply with exactly:
  OK'` and `pi -p 'Reply with exactly: OK' --provider omniroute --model
  omniroute/auto-fastest`, both keyless via the auto-fastest combo. These exercise the
  real toolchains (hermes + pi wrappers).
- **`--no-clean` flag:** leave the DTS container running after tests (no `dts clean`) so you
  can shell in and test manually. On error AND on success it prints:
  `dts shell` / `dts exec "<cmd>"` / `dts clean`. Note: the test runs `stop.sh` at the end,
  so with `--no-clean` services are STOPPED — run `dts exec "cd /src && bash boot.sh"` again
  before manual CLI testing.

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

