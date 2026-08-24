# Scout Report: .minions Bootstrap v1 — Implementation State Assessment

**Task:** `scout-report-on-minions-bootstrap-v1-implementat` (kind=scout, worktree `#2`)
**Scope:** Assessment only — report, no PR, no push. (Read-only inspection of the sibling `fm` worktree `#1` where the prior crewmate's uncommitted work lives.)
**Date assessed:** 2026-08-24
**Overall verdict:** The scaffolding + dry-run/boot tests are in good shape and PASS, but the **real install path is broken** by a blocking `set -u` defect plus wrong download URLs. The work is **not PR-ready** until those are fixed and real-install coverage is added.

---

## 1. What I did

1. Mapped the repository topology across the three linked worktrees and the `fm/implement-v1-of-the-minions-bootstrap-system-bas` branch.
2. Read every implementation file in the `fm` worktree (`#1`): `install.sh`, `boot.sh`, `stop.sh`, `status.sh`, `lib/*.sh` (8 files), `etc/*`, `tests/*`, `docs/requirements-research.md`.
3. Copied the implementation into my own lab worktree (`#2`) and ran the test suites (`shellcheck`, `tests/test_install.sh`, `tests/test_boot.sh`).
4. Ran a **real (non-dry-run) `boot.sh`** with mock services to validate the actual supervisor/pid/health/stop lifecycle end-to-end.
5. Ran a **real `install.sh`** (sandboxed `HOME`/`MINIONS_HOME`) to validate the actual install/download path — this is where the blockers appear.
6. Verified download URLs against upstream (nodejs.org, GitHub releases, npm) to confirm 200 vs 404.
7. Checked git/branch/PR state (`git status`, `git log`, `gh pr list`).
8. Passed the captain-hold-lifecycle completion gate for the open captain-level decisions surfaced below.

---

## 2. Files present and their state

All implementation files live as **uncommitted working-tree changes** in the `fm` worktree (`#1`), on branch `fm/implement-v1-of-the-minions-bootstrap-system-bas` whose only commit is the design proposal:

```
#1/.minions/  (worktree on fm/implement-v1-of-the-minions-bootstrap-system-bas, uncommitted)
  install.sh              executable, set -eu, arg parse (--dry-run/--no-hermes/--minions-home)
  boot.sh                 executable, set -eu, arg parse (--daemon/--dry-run)
  stop.sh                 executable, set -eu
  status.sh               executable, set -eu
  lib/
    detect.sh             OS/arch + get_download_url + get_sha256   ← contains 2 blocking bugs
    download.sh           download_file (curl/wget, sha256 verify), extract_tarball, fix_macos_quarantine
    node.sh               check_node_version, install_vendored_node, ensure_node
    uv.sh                 check_uv, install_vendored_uv, ensure_uv    ← hits bug #1 at runtime
    pi.sh                 install_pi, ensure_pi                       ← hits bug #1 + broken URL at runtime
    hermes.sh             install_hermes (uv venv), ensure_hermes
    npm_packages.sh       install_npm_package, ensure_omniroute, ensure_modelrelay
    process.sh            start_service/stop_service/is_service_running/wait_for_port/wait_for_health
  etc/
    versions.env          version lockfile + checksums (all checksums are PLACEHOLDER_*)
    minions.env           runtime config (MINIONS_* vars, ports, LLM base URL)
    pi.toml               Pi-Agent RPC/LLM/agent config
  tests/
    test_install.sh       shellcheck dry-run + structure assertions
    test_boot.sh          mock-services boot/stop/status lifecycle (dry-run focused)
  bin/                    EMPTY  (design proposal §5 expects symlinks/shims here)
  var/{run,log}            runtime dirs (created at install/boot time)
  docs/requirements-research.md   committed (design proposal, the prior crewmate's artifact)
  README.md                MODIFIED vs committed (rewritten to document the bootstrap)
  LICENSE                  unchanged
```

**Complete vs. not:** The four shell entrypoints + 8 lib modules + 3 config files + design proposal + 2 tests = complete and internally consistent for v1 scope. **Missing vs. the design proposal §5** (aspirational, not in v1): `update.sh`, `etc/omniroute.env`, `etc/modelrelay.env`, `etc/hermes.env`, per-component `bin/` shims/symlinks (bin/ is empty), and `bin/fm-decision-hold.sh`. These are documented gaps, not regressions.

---

## 3. Test results

### shellcheck (all implementation scripts) — PASS
`shellcheck -x` on `install.sh boot.sh stop.sh status.sh lib/*.sh` → **no errors, no warnings**. Only info-level SC2015 hints (`A && B || C`) exist in the two test files themselves (not linted by the suite), and they don't fail the suite.

### tests/test_install.sh — PASS (exit 0)
All 3 sub-tests green: shellcheck (12 scripts), `install.sh --dry-run` (dir structure + config copies + lib copies), script permissions/shebangs.

### tests/test_boot.sh — PASS (exit 0)
All 5 sub-tests green: dry-run READY print, pid files, Hermes-default-off, Hermes-on, stop.sh, status.sh, config-port assertions.

### Real (non-dry-run) boot/stop/status lifecycle — PASS
Ran `boot.sh` (not dry-run) with mock `omniroute`/`modelrelay`/`pi`/`hermes`/`nc`/`curl` binaries. Observed: correct startup order (omniroute→modelrelay→(hermes opt-in)→pi), pid files track **real** PIDs (all `alive=yes`), `status.sh` reports correct ✅ PIDs/ports, `stop.sh` TERM-then-clean removes pid files, no processes remain after stop. `boot.sh` exits 0 and prints `READY FOR FIRSTMATE DISPATCH`.

**Caveat:** the test suite only exercises `boot.sh`/`install.sh` in `--dry-run`. There is **no real (non-dry-run) install or boot integration test** and **no network/mock test for `install.sh`** — which is exactly why the real install bugs below are invisible to the current tests.

---

## 4. Blocking bug: real `install.sh` aborts immediately (set -u)

Running a real install (sandboxed `HOME`/`MINIONS_HOME`) aborts before downloading anything:

```
[INFO] Platform: linux-x64
[INFO] Creating directory structure at .../.minions
[INFO] Copying config templates...
[INFO] Installing prerequisites...
System Node.js v24.14.0 meets requirement (>= 22.22.2)
uv not found, installing vendored uv...
install.sh: 1: eval: uv_SHA256_LINUX_X64: parameter not set        ← ABORT (exit 2)
```

**Root cause — `lib/detect.sh`, `get_sha256()` (line 96):**
```sh
var_name="${component}_SHA256_${platform_upper}"   # component is passed lowercase ("uv")
eval "echo \${${var_name}}"                        # → ${uv_SHA256_LINUX_X64} (lowercase)
```
But `etc/versions.env` defines **uppercase** names: `UV_SHA256_LINUX_X64`, `NODE_SHA256_LINUX_X64`, `PI_SHA256_LINUX_X64`, `HERMES_SHA256_LINUX_X64`. So the constructed variable name never exists → under the script's `set -u`/`set -e`, `eval` hits an unbound variable and aborts. This breaks `install_vendored_node`, `install_vendored_uv`, and `install_pi` (the first one reached is uv).

**Reproduced in isolation:** sourcing `versions.env` then `get_sha256 uv "$UV_VERSION"` under `set -u` prints `lib/detect.sh: line 98: uv_SHA256_LINUX_X64: unbound variable` and returns empty. `${UV_SHA256_LINUX_X64:-<UNSET>}` = `<UNSET>`; `${uv_SHA256_LINUX_X64:-<UNSET>}` = `PLACEHOLDER_UV_LINUX_X64_SHA256` — confirming the case mismatch.

**Dry-run hides it:** `install.sh --dry-run` overrides `install_vendored_node`/`install_vendored_uv`/`install_pi`/`install_npm_package` with no-op stubs *before* calling `ensure_*`, so the real `get_sha256` path is never exercised by the tests.

**Scratch fix (applied in my lab worktree `#2`, NOT shipped — scout is report-only):** uppercase the component before building the name:
```sh
component_upper=$(echo "${component}" | tr '[:lower:]' '[:upper:]')
var_name="${component_upper}_SHA256_${platform_upper}"
```
After this fix, the install proceeds past the crash and reaches the download stage (then hits the next blocker below). Re-running `tests/test_install.sh` + `tests/test_boot.sh` after the edit → still pass (exit 0); `shellcheck -x lib/detect.sh` → clean.

---

## 5. Blocking bug: wrong download URLs (404)

Even with the `get_sha256` fix, the real install cannot fetch components:

### 5a. uv URL 404 (`lib/detect.sh` lines 54/57/60/63)
`get_download_url` builds `https://github.com/astral-sh/uv/releases/download/${version}/uv-${PLATFORM}.tar.gz` → `uv-linux-x64.tar.gz`.
- `curl -sIL .../uv-linux-x64.tar.gz` → **HTTP/2 404**.
- Correct asset: `uv-x86_64-unknown-linux-gnu.tar.gz` → **HTTP/2 200** (verified).
The uv release asset naming is `uv-<target>.tar.gz` where the target is the Rust triple (`x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `x86_64-apple-darwin`, `aarch64-apple-darwin`), not `linux-x64`. `get_download_url` has no platform→target mapping for uv.

### 5b. Pi-Agent binary URL 404 (`lib/detect.sh` line 69)
`install_pi` → `https://github.com/earendil-works/pi/releases/download/pi-coding-agent%400.84.2/pi-linux-x64` → **HTTP/2 404**. The `earendil-works/pi` GitHub release tagged `pi-coding-agent@0.84.2` is not publicly reachable from this sandbox (release page redirects to sign-in; API rate-limited). The npm package `@earendel-works/pi-coding-agent` (latest `0.84.2`) **does** resolve from npm. `install.sh` only implements the standalone-binary path for Pi (no npm fallback), so Pi install is broken in v1.

### 5c. Node URL correct
`https://nodejs.org/dist/v22.22.2/node-v22.22.2-linux-x64.tar.xz` → **HTTP/2 200**. (And `ensure_node` is skipped entirely on hosts with Node ≥22.22.2, e.g. this box's `v24.14.0`.)

### 5d. Checksums are all placeholders
Every `*_SHA256_*` in `versions.env` is `PLACEHOLDER_*`, and `download_file` skips placeholders (`case PLACEHOLDER*)`). So checksum verification is effectively a no-op for all vendored downloads — a supply-chain gap the design proposal §7.4 explicitly warns about.

---

## 6. Correctness inconsistency: boot readiness marker

`boot.sh` prints `READY FOR FIRSTMATE DISPATCH` (line 204) but **never writes the `var/run/ready` marker** that `status.sh` checks:
- `boot.sh`: grep for `ready` → no match (no `touch var/run/ready`).
- `status.sh:79` → `if [ -f "${MINIONS_HOME}/var/run/ready" ]` → prints `READY FOR FIRSTMATE DISPATCH ✅` / `NOT READY ❌`.
- `stop.sh:24` → `rm -f "${MINIONS_HOME}/var/run/ready"` (expects the marker to exist).

Observed live: a successful real boot showed `status.sh` printing `NOT READY ❌` because the marker was never created. **Fix:** `boot.sh` should `touch "${MINIONS_HOME}/var/run/ready"` right before/after the final READY print (and `stop.sh` already cleans it). The proposal §6 step 7 / §7.7 ("readiness-based, not just process-based") calls for this.

Other boot.sh nit: `--daemon` is parsed (shifted) but never acted upon, and `MINIONS_DAEMON` (in `etc/minions.env`) is never read by `boot.sh`. Not blocking, but a gap vs. proposal §3.3/§4.

---

## 7. What needs work before a PR is ready

| # | Issue | Type | Fix |
|---|-------|------|-----|
| 1 | `get_sha256` variable-name case mismatch aborts install (uv) | **Blocking, runtime** | Uppercase component before `eval` (see §4 scratch fix). |
| 2 | uv download URL `uv-${PLATFORM}` 404s | **Blocking, runtime** | Map platform→Rust triple target (`uv-x86_64-unknown-linux-gnu.tar.gz`, etc.). |
| 3 | Pi-Agent binary URL 404 (release not public) | **Blocking, runtime** | Use npm `@earendel-works/pi-coding-agent` with `--ignore-scripts` (exists, recommended by proposal §2.2 §5 D4), or restore a real binary asset URL. `install.sh` has no npm fallback for Pi. |
| 4 | All checksums are `PLACEHOLDER_*` → verification is a no-op | Supply-chain risk (proposal §7.4) | Pin real SHA256s per version/platform. |
| 5 | `boot.sh` never creates `var/run/ready` marker | **Correctness** | `touch` the marker on readiness; honors `status.sh`/`stop.sh` contract. |
| 6 | `--daemon`/ `MINIONS_DAEMON` not implemented | Feature gap | Implement daemon detach per proposal §4/§3.3. |
| 7 | No real (non-dry-run) install/boot integration test | Test coverage | Add a network-mocked `install.sh` test and a real `boot.sh` (mock-services) test so bugs #1–#3/#5 can't hide. |
| 8 | Design-proposal §5 extras absent (`update.sh`, per-component `*.env`, `bin/` shims) | Scope gap | Decide v1 scope; either implement or trim the proposal. |

**Repro to validate fixes:** a real `install.sh` in a sandboxed `HOME`/`MINIONS_HOME` is the right CI target — the current suite can't see these bugs.

---

## 8. Git / branch / PR state

- **Remote:** `origin` = `https://github.com/gitricko/.minions`; a local `no-mistakes` remote exists.
- **Branch:** local `fm/implement-v1-of-the-minions-bootstrap-system-bas` (no upstream configured → **not pushed**).
- **Commits:** the branch's only commit is `31866a1 Add design proposal for portable .minions system` — which is **already on `origin/main`** (remote tip == branch tip). The commit that exists locally-and-on-origin is the design proposal + modified README.
- **The implementation is NOT committed.** `git status` in `#1` shows it entirely as uncommitted working-tree changes (`?? boot.sh`, `?? etc/`, `?? install.sh`, `?? lib/`, `?? status.sh`, `?? stop.sh`, `?? tests/`, `M README.md`). **There is no commit containing the implementation**, so there is nothing yet to push.
- **No PR exists:** `gh pr list` → empty. Task brief says work was "interrupted before creating a PR" — consistent: the implementation never reached a commit.
- **Bottom line (Q4):** There is a local `fm/` branch name and a design-proposal commit on origin/main, but **no commit/PR carries the implementation**. To ship: commit `boot.sh/stop.sh/status.sh/install.sh`, `lib/`, `etc/`, `tests/`, and the README change onto the `fm/` branch, push to origin, then open a PR. The blocking bugs (#1–#5) should be fixed (and covered by a real install test) before that PR.

---

## 9. Evidence index (commands run)

- `git status` / `git log --oneline -20` / `git branch -a` / `git ls-tree -r --name-only fm/implement-v1-of-the-minions-bootstrap-system-bas` → topology (§2, §8).
- `shellcheck -x install.sh boot.sh stop.sh status.sh lib/*.sh` → clean (§3).
- `sh tests/test_install.sh` → exit 0, all PASS (§3).
- `sh tests/test_boot.sh` → exit 0, all PASS (§3).
- Real `install.sh` in sandbox (`HOME`/​`MINIONS_HOME` = mktemp): aborts `uv_SHA256_LINUX_X64: parameter not set` exit 2 (§4); after scratch `get_sha256` fix → proceeds to download, then `curl: (22) ... 404` on uv (§5a).
- Isolated repro: `get_sha256 uv "$UV_VERSION"` under `set -u` → `unbound variable` (§4).
- `curl -sIL …/uv-linux-x64.tar.gz` → 404; `…/uv-x86_64-unknown-linux-gnu.tar.gz` → 200 (§5a).
- `curl -sIL …/pi-0.84.2/pi-linux-x64` → 404; npm `@earendel-works/pi-coding-agent` `latest=0.84.2` (§5b).
- `curl -sIL …/node-v22.22.2-linux-x64.tar.xz` → 200 (§5c).
- Real `boot.sh` (mock services, non-dry-run): pid files track real PIDs; `status.sh` reports ✅; `stop.sh` cleans up; only `var/run/ready` mismatch (§6).
- `gh pr list` → empty; `git for-each-ref`/`git log` → fm local-only, no upstream (§8).

---

## 10. Open captain decisions (carried to a held task — see §11)

Per the design proposal §8, these remain unresolved and belong to the captain. My investigation confirms they are still open and (for D4) freshly urgent:

- **D1 — Pi-Agent dispatch transport.** stdio vs. localhost HTTP RPC port vs. unix socket. Determines what "ready for firstmate dispatch" means and how firstmate connects to Pi's `rpc-entry`. Proposal recommends a localhost HTTP RPC port in `pi.toml`. (Not verifiable without a real Pi binary; my mock `pi` was a `sleep` stub.)
- **D2 — Proxy default.** OmniRoute (default per proposal) vs. ModelRelay vs. user-picked as Pi's `MINIONS_LLM_BASE_URL`.
- **D3 — Hermes gateway default.** Start `hermes gateway` by default? Proposal: opt-in via `MINIONS_HERMES=on`.
- **D4 — Pi-Agent delivery form (urgent).** `install.sh` currently downloads a standalone Pi binary whose release URL 404s / is not publicly reachable. Options: (a) ship npm `@earendel-works/pi-coding-agent@0.84.2` with `--ignore-scripts` (exists; proposal §2.2 §5 recommends the npm-or-binary path), or (b) restore a valid standalone-binary asset URL. This is blocking for v1 install completeness.

These four are consolidated into one captain-held task (`minions-bootstrap-v1-decisions`) per the captain-hold-lifecycle policy ("a multi-question review is one held task pointing at its report").

---

## 11. Completion gate (captain-hold-lifecycle)

Per `.agents/skills/captain-hold-lifecycle/SKILL.md`, this investigation surfaces genuine unresolved captain choices (§10), so `complete --none` is not an honest attestation. I held them as a single durable captain task and ran the gate:

- `fm-captain-hold.sh hold minions-bootstrap-v1-decisions --origin scout-report-on-minions-bootstrap-v1-implementat ...` → created + captain-held.
- Status line appended to `…/scout-report-on-minions-bootstrap-v1-implementat.status`:
  `needs-decision [key=minions-bootstrap-v1-decisions]: minions bootstrap v1 captain calls D1-D4 (Pi transport, proxy default, Hermes mode, Pi delivery form); D4 urgent (Pi binary URL 404). See report §10.`
- `fm-captain-hold.sh complete scout-report-on-minions-bootstrap-v1-implementat minions-bootstrap-v1-decisions` → verified the task durable, unioned into origin metadata, transferred the open keyed decision to the durable holder (status close: `captain-held [key=minions-bootstrap-v1-decisions]: tracked by minions-bootstrap-v1-decisions`).
- `fm-captain-hold.sh verify scout-report-on-minions-bootstrap-v1-implementat` → `verified: … captain-call inventory` (decisions_reviewed=1 in origin `.meta`; no open keyed decision remains in the status fold).

**Status is therefore `needs-decision`** (not `done`): the report deliverable is complete and written, but the task awaits the captain's choices before the work can be promoted to ship. Per scout rule 6, I stop here and let firstmate relay the call.

---

## 12. Bottom line (answers to the requested questions)

1. **Files that exist & look complete:** `install.sh`, `boot.sh`, `stop.sh`, `status.sh`, `lib/` (8 modules), `etc/` (3 configs), `tests/` (2 suites), `docs/requirements-research.md`, README. Structurally complete for v1; `bin/` is empty and proposal §5 extras (`update.sh`, per-component env, shims) are intentionally absent.
2. **Needs work before PR:** fix the 3 blocking install bugs (`get_sha256` case, uv URL, Pi URL/delivery), the readiness-marker gap, pin real checksums, implement `--daemon`, and add a real (non-dry-run, network-mocked) install+boot integration test.
3. **Remaining test failures:** **None** — the existing suites (`test_install.sh`, `test_boot.sh`, shellcheck) all PASS (exit 0). But they only cover dry-run paths, so bug count = 0 from tests vs. 4 blocking bugs from a real install.
4. **Branch/commit to push:** local branch `fm/implement-v1-of-the-minions-bootstrap-system-bas` exists but holds only the design-proposal commit (already on `origin/main`); **the implementation itself is uncommitted** and **no PR exists**. Nothing is yet pushed that contains the implementation.
