# PROPOSAL — Self-Updating Dependencies

**Status:** Design (iteration 1) — drafted from a grilling session, not yet implemented
**Owner:** custody via pi/Hermes discussion
**Related:** `etc/versions.env`, `etc/deps.yaml`, `scripts/check-updates.sh`, `scripts/bump.sh`, `.github/workflows/self-update.yml`

## tl;dr

A **scheduled** GitHub Actions workflow wakes on a cron, checks every dependency
pinned in `etc/versions.env` against its real upstream, and when anything is newer:

1. **Deterministically** bumps `versions.env` (and the derived `.node-version`)
   and opens a single **batch PR** (one commit per dependency).
2. Watches that PR's CI. If **green → merges to `main`** via our own script.
3. If **red → boots minion from stable `main` in the runner and an agent fixes**
   the failing build, pushes, re-runs CI, and loops until green or a budget (3
   attempts) is hit — then leaves the PR open, labeled `self-update:
   needs-review`, for a human (no auto-close).

Key rule that protects supply-chain and `main`: the agent **never modifies
`.github/workflows/`**. Updates to the runner toolchain propagate through a
generated `.node-version` file, not by editing CI.

## Goals / non-goals

**Goals**
- Keep `main` stable and tested end-to-end at all times.
- Reduce manual dependency bump toil to zero.
- Deterministic for clean version bumps; agentic **only** for failure-fixing.
- Reuse the existing, already-strong CI (`test`, `dts-integration`,
  `real-install`).

**Non-goals**
- Not re-inventing a lockfile resolver — one version per component, as now.
- No LLM involvement in a *clean* bump (deterministic code only).
- No unattended agent in the cron happy path (no LLM to talk to in a fresh runner).

## Decisions log (locked in iteration 1)

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Bumps are deterministic code; agent only fixes failures.** | An LLM adds cost+flakiness with zero value on a `.env` + SHA bump. |
| D2 | **Agent never touches `.github/workflows/`.** | Self-updating the very thing that validates you is a supply-chain hole; keeps `main` trustworthy. |
| D3 | **One batch PR per run, one commit per dep.** | Batching handles coupled deps; per-dep commits allow reverting one bad bump without losing the good ones. |
| D4 | **Skip newer versions while a bump PR is pending.** | Idempotency — no duplicate/spam PRs across cron ticks. |
| D5 | **`MINIONS_VERSION` is a release marker bumped on green merge.** | Currently unused; cosmetic. |
| D6 | **Node pinned via `node-version-file: .node-version`** (not a hardcoded `ci.yml` value). | One source of truth, scheduler-safe, no CI edits. |
| D7 | **Merge via our own script**, not GitHub auto-merge. | Explicit control over merge timing + guardrails. |
| D8 | **SHA256 populated only for NODE + UV** (the tarball deps `download.sh` already hashes). | npm deps get integrity from npm itself; Hermes has none. Minimal added complexity. |
| D9 | **Fix loop capped at 3 attempts, then leave the PR open + label `self-update: needs-review` for a human.** No auto-close, no skip-list. | Bound cost/time; after the agent quits, a human decides. A stuck red PR also naturally blocks newer versions (D4) until a human closes it. |
| D10 | **LLM for the agent comes from booting minion (from stable `main`) in the runner.** | OmniRoute/ModelRelay are localhost proxies; neither is reachable in a bare Actions container. |

## Architecture

```
                        ┌────────────────────────────────────────────┐
   cron ───────────────▶│  .github/workflows/self-update.yml        │
                        │  (orchestrator)                            │
                        └──────────────┬─────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
 script/check-updates.sh      script/bump.sh                    merge/fix logic
 (read-only: any newer?)      (bump versions.env +             (own script)
        │                     .node-version, open PR)                 │
        │                              │                              │
        │                    ┌─────────┴─────────┐                    │
        │                    ▼                   ▼                    ▼
        │            ci.yml runs on PR     green? ──yes──▶ merge to main
        │                    │                 │                      │
        │                    │                no (red)               │
        │                    │                 ▼                      │
        │                    │    boot minion from main ──▶ agent fix
        │                    │          push, re-run CI              │
        │                    │          loop ≤ 3 attempts       │
        │                    │          else: leave open + label│
        │                    │               needs-review       │
        └────────────────────┘                                       │
                                                                     ▼
                                                           bump MINIONS_VERSION (D5)
```

### Flow detail (one cron tick)

1. Run `check-updates.sh` → emits machine-readable list of outdated deps.
2. If empty: no-op (don't even open a runner-heavy stack).
3. If an update PR already exists (D4): sink — stop here.
4. Else `bump.sh` edits `versions.env` + regenerates `.node-version`, commits
   one per dep, opens the batch PR.
5. Wait/poll `ci.yml` checks on the PR (poll `GET /checks` until complete).
6. **Green** → run our merge step: ensure check is from a clean run, merge,
   bump `MINIONS_VERSION`. done.
7. **Red** → fix loop (D9):
   - Boot minion from `main` in the runner (`install.sh` + `boot.sh`).
   - Invoke agent with a fix prompt → (PR number, failed check, dep→version).
   - Load the repo's fix skill (author this if absent) for how-to.
   - Push fixes, re-run CI, poll again. On green → go to (6).
   - After 3 failed attempts → **do not close.** Leave the PR open, label
     `self-update: needs-review`, and comment the failed check + dep/version.
     A human resolves it (merge, adjust, or close). D4 keeps newer versions
     blocked until then, forcing the human to act.

## State

- `etc/deps.yaml` — declarative catalog (source of truth for what to check + how).
- **No skip-list.** A PR the agent can't fix stays open, labeled
  `self-update: needs-review`, for a human (D9).

## Repo permissions needed (the cron workflow)

- `contents: write` (merge + push)
- `pull-requests: write` (open/update/close PRs)
- `checks: read` (poll check status)
- `actions: write` (re-run CI) — scope to cleanup only

## Open items / next steps

- [ ] Author/find the repo skill that tells the fix-agent *how* to edit (D2 guardrails).
- [ ] `check-updates.sh` — per-source adapters (github_tag / npm / release_tarball).
- [ ] `bump.sh` — versions.env edit + `.node-version` regen + real SHA for NODE/UV.
- [ ] `self-update.yml` — cron + merge + fix-loop orchestration (run on `workflow_dispatch` too).
- [ ] Guardrails test: assert the agent's changes never touch `.github/`.
- [ ] Decide poll cadence + timeout budgets (esp. for `dts-integration` ~60min).