# Investigation #66 — `status.sh` wrong icons, truncated output, and divergent footers

> **Scope:** due-diligence only — no code changed yet. This document is the reviewable proposal for Pi-agent.
> **Repo:** `gitricko/.minions` @ `main` (2026-10-12) | **Issue:** [#66](https://github.com/gitricko/.minions/issues/66)

---

## 1. Verdict — the reporter is right

`status.sh` has two hard bugs that exactly reproduce the screenshots in #66, and `boot.sh` / `install.sh` / `self-check.sh` each reimplement "is this up?" differently. Your intuition about a consolidated status lib that `install` and `boot` can reuse is the right fix.

---

## 2. What was checked

- Live repro on this host: `/bin/sh -> dash`, `nc` not installed, `MINIONS_HOME=~/.minions` with services up (omniroute pid 12653, 9router pid 12714).
- Read: `status.sh` (154 lines), `boot.sh` (360 lines), `install.sh` (614 lines), `lib/process.sh` (230 lines), `self-check.sh` (529 lines), `lib/tailscale.sh`, `lib/ollama.sh`, `etc/versions.env`, `stop.sh`, `Makefile`.
- Ran: `status.sh` with `set -x` under `dash` vs `bash`, `/dev/tcp` probes under `dash` vs `bash -c`, minimal `set -e` repro, `boot.sh` footer inspection.

---

## 3. Root causes (with locations)

### P1 — `check_port` always returns `❌` on dash hosts (`status.sh:16-27`)

```sh
#!/usr/bin/env sh          # -> dash on codespace / DTS / most Debian hosts
check_port() {
  if command -v nc >/dev/null 2>&1; then
    nc -z "$host" "$port"    # not installed here
  fi
  (echo > "/dev/tcp/${host}/${port}") 2>/dev/null   # bash-only, fails under dash
}
```

Under `dash`:

```
sh: 1: cannot create /dev/tcp/127.0.0.1/20128: Directory nonexistent  (exit 2)
```

Under `bash -c "exec 3<>/dev/tcp/..."` it works (exit 0 on open, 1 on refused). The correct fallback already exists in `lib/process.sh:187-189` — `status.sh` just doesn't use it. Hence every healthy service shows:

```
  omniroute   (127.0.0.1:20128)
❌              <- port probe (always false)
✅ (pid 1081)   <- pid probe (true)
```

Same for `9router`. That's the double-icon row in #66.

### P2 — `set -e` aborts on missing pid (`status.sh:4-5`, `115-121`)

```sh
set -e
set -u
check_pid() { ...; echo "❌"; return 1; }
# ...
check_pid "omniroute"   # bare call, no guard — abort when down
```

Minimal repro confirms:

```sh
set -e; check_pid(){ echo "❌"; return 1; }; echo line1; check_pid; echo line2
# -> prints line1, ❌, exits before line2
```

So when `omniroute` is down, `status.sh` prints:

```
.minions status:
  omniroute   (127.0.0.1:20128)
❌
❌       <- second ❌ is check_pid, then process exits
         <- 9router / pi / hermes / tailscale / READY never printed
```

When `omniroute` is up, `check_pid` returns 0, so `set -e` doesn't fire and the full report appears (still with wrong port icon). `tailscale` (line 142-146) *is* guarded with `set +e` / `set -e` — the `omniroute`/`9router` pid probes are not. Inconsistency.

### P3 — Two icons per service (`status.sh:114-121`)

```sh
check_port ... && echo "✅" || echo "❌"   # line 1
check_pid "omniroute"                       # line 2
```

Healthy = two rows (`❌` + `✅`), down = two `❌` rows on two lines. Expected: one combined row per service, single icon.

### P4 — Three footers, three answers

| Place | What it checks | What it prints | Problem |
|---|---|---|---|
| `status.sh` | omniroute, 9router, pi, hermes, tailscale, READY | pid+port (broken), versions only for pi/hermes | Missing ollama, mnemon; wrong probes |
| `boot.sh:346-359` | nothing — hardcoded | always `✅` for 5 rows + optional ollama | Lies when a service failed to bind; no versions |
| `install.sh:579-592` | inventory at install time | versions from build-time vars | Not a health check; not reusable at runtime |
| `self-check.sh:102-241` | 9Router/OmniRoute via HTTP codes, ollama, mnemon, tailscale, disk, memory, persistence | rich + JSON | Thorough but heavy, separate codepath |

No shared library — `lib/status-lib.sh` doesn't exist. Fixing a probe in one place doesn't propagate.

### P5 — Versions missing where #66 asks for them

`status.sh` shows versions only for `pi`/`hermes`. `boot.sh` shows none. `install.sh` shows build-time vars, not on-disk truth. #66 asks for omniroute/9router/ollama/mnemon/tailscale versions too.

### P6 — No exit-code discipline, no machine-readable mode

`status.sh` always exits 0. `self-check.sh` already has `0=ok / 1=warn / 2=critical` + `health-report.json`. `status.sh` should at least signal degraded, and ideally support `--json` for CI/boot reuse.

---

## 4. Why the install.sh footer "looks better"

It does — but it's inventory ("what I installed, from `versions.env`"), not a probe. `boot.sh`'s footer is aspirational ("I tried to start these"), `status.sh` is the only one that *probes*. None of them share code, so they drift. The right goal is: **one probe lib, three renderers** (install inventory, boot banner, live status).

---

## 5. Proposal — consolidated `lib/status-lib.sh` (recommended)

### 5.1 New file: `lib/status-lib.sh`

POSIX `sh`, no `set -e` inside, sourced by `status.sh`, `boot.sh`, (optionally `install.sh` and later `self-check.sh`).

Respects the same env as today: `MINIONS_HOME`, `OMNIROUTE_HOST/PORT`, `NINEROUTER_HOST/PORT`, `TAILSCALE_SOCKET`.

Draft API (names bikesheddable in review):

```sh
# low-level (cached, guarded)
_status_has_nc
_status_port_open <host> <port>        # nc -z | bash /dev/tcp | curl fallback
_status_pid_alive <name>               # $MINIONS_HOME/var/run/<name>.pid + kill -0 (+ sudo fallback)
_status_cli_version <bin>              # <bin> --version -> versions.env fallback
_status_service_version <name>         # dispatches per component

# per-component probes — echo "STATUS|DETAIL", return 0/1
status_probe_omniroute
status_probe_9router
status_probe_ollama
status_probe_pi
status_probe_hermes
status_probe_mnemon
status_probe_tailscale                 # kernel vs userspace, Logged out. handling, socket ownership

# aggregate + render
status_collect                         # populates STATUS_* / VERSION_* / DETAIL_* globals
status_render_human                    # one aligned row per component, single ✅/❌, version in parens
status_render_json                     # JSON for --json / CI
status_exit_code                       # echo 0/1/2  (0 all ok, 1 warn, 2 critical)
```

Key invariants for the lib:

- Never calls `exit`; callers decide.
- Port probe reuses the correct `lib/process.sh:186-193` pattern (`bash -c "exec 3<>/dev/tcp/..."`), not `(echo > /dev/tcp/...)` inside `dash`.
- Pid probe mirrors `lib/process.sh:is_service_running` (`kill -0` + `sudo -n kill -0` fallback for root-owned `tailscaled`).
- Tailscale probe extracts the ~60-line `status.sh:44-108` block once, keeping the `Logged out.` -> `rc 0` and ownership-not-writability checks.
- Version order: binary `--version` first, then `versions.env` fallback, else `unknown`.

### 5.2 Rewrite: `status.sh` (thin wrapper)

```sh
#!/usr/bin/env sh
set -u   # no -e — reporter must not abort when degraded
MINIONS_HOME="${MINIONS_HOME:-$HOME/.minions}"
. "${MINIONS_HOME}/lib/status-lib.sh"   # or SCRIPT_DIR/lib/... when run from repo
case "${1:-}" in
  --json) status_collect; status_render_json; exit "$(status_exit_code)" ;;
  --help|-h) echo "Usage: status.sh [--json]"; exit 0 ;;
  *) status_collect; status_render_human; exit "$(status_exit_code)" ;;
esac
```

Human rendering (spec):

```
.minions status:

  omniroute   http://127.0.0.1:20128/v1   ✅ (pid 12653, v3.8.51)
  9router     http://127.0.0.1:7352/v1    ✅ (pid 12714, v0.5.99)
  ollama      http://localhost:11434     ✅ (v0.40.3, nomic-embed-text ready)
  pi-agent    CLI                        ✅ (v1.1.0)
  hermes      CLI                        ✅ (v0.21.6+141.gd94b70f)
  mnemon      memory layer               ✅ (v0.2.10, db at ~/.mnemon)
  tailscale   (opt-in)                   ✅ (kernel, pid 12985, v1.104.1)
  READY           ✅
```

When down — same rows, single `❌`, no truncation:

```
  omniroute   http://127.0.0.1:20128/v1   ❌ (down — no pid, port closed, expected v3.8.51)
```

### 5.3 Update: `boot.sh` footer (`boot.sh:346-359`)

Today it's hardcoded `echo "  ✅ ..."` — always green even if a service failed. Proposed: after `touch var/run/ready`, call the same lib:

```sh
. "${LIB_DIR}/status-lib.sh"
status_collect
echo ""
echo "=============================================="
if [ "$(status_exit_code)" -eq 0 ]; then
  echo "  .minions stack is UP"
else
  echo "  .minions stack is DEGRADED (see below)"
fi
echo ""
status_render_human
echo "=============================================="
```

- Boot no longer lies; banner is truthful.
- Boot and status agree on probes, versions, and formatting.
- Keep the existing "Starting ..." log lines — only the final banner changes.
- Probe cost is ~pid + port + `--version` (~1s), not the heavy curl-retry loops of `self-check.sh`.

### 5.4 Update: `install.sh` (optional, low priority)

Already `cp -f lib/*.sh $MINIONS_HOME/lib/` (`install.sh:234`), so the new `lib/status-lib.sh` ships automatically. Optionally reuse its version/formatting helpers for the inventory footer so install and status look the same. Can be deferred if scope is tight.

### 5.5 `self-check.sh`

Unchanged for this issue. Follow-up: make its Services section call `status_probe_omniroute` etc. instead of its own `curl` loops — avoids a third implementation. Deferred to avoid scope creep.

---

## 6. File change list (for Pi-agent review)

| Change | File | Notes |
|---|---|---|
| **New** | `lib/status-lib.sh` | ~200-250 lines, POSIX sh, shared probes + renderers |
| **Modified** | `status.sh` | thin wrapper: drop `set -e`, one row/service, add ollama/mnemon, versions for omniroute/9router, `--json`, fix port/pid guards |
| **Modified** | `boot.sh` | replace hardcoded footer `346-359` with `status_collect` + `status_render_human` |
| **Touched** | `install.sh` | verify `lib/status-lib.sh` ships via `cp lib/*.sh` (line 234); optional formatting reuse |
| **No change** | `lib/process.sh`, `self-check.sh`, `stop.sh` | `status-lib` reuses their semantics; self-check consolidation is a follow-up |

---

## 7. Alternatives considered

- **A — Patch `status.sh` only:** Fixes the screenshots but leaves boot lying and duplication in place. Next bug drifts again.
- **B — Merge `status.sh` into `self-check.sh` (`--brief`):** `self-check` is heavy (disk/memory/persistence/retries/embed test) — `status.sh` should stay instant (`pid + port + --version`) for interactive use and boot banner.
- **C — Shared lib (recommended):** Fixes the bug *class*. ~200 lines once, removes three copies of the same logic, and `lib/process.sh` already has the right primitives — wiring cost is low.

---

## 8. Testing plan

- `sh -n lib/status-lib.sh && shellcheck lib/status-lib.sh status.sh` (and `boot.sh`).
- `~/.minions/status.sh` with services up: all `✅`, single icon/row, versions present, aligned columns.
- `~/.minions/stop.sh; ~/.minions/status.sh` with services down: full report, no truncation, `❌` rows for omniroute/9router/ollama, later rows still printed.
- Host without `nc` (codespace/DTS): port open detected via `bash /dev/tcp` fallback.
- `~/.minions/boot.sh`: footer matches subsequent `status.sh` run; shows `❌` when a service is intentionally failed.
- `~/.minions/status.sh --json` is valid JSON and machine-readable.
- DTS / real-install CI: assert `status.sh` exit code + `status.sh --json` instead of grepping the hardcoded `stack is UP` banner (banner keeps `stack is UP` string when `exit 0` for backward-compat grep).
- `~/.minions/self-check.sh` still passes (no regression).

---

## 9. Risks and mitigations

- **Divergence after install vs dev mode:** `install.sh` already `cp -f lib/*.sh $MINIONS_HOME/lib/` — new file ships automatically; `boot.sh` sources from `$MINIONS_HOME/lib` (correct).
- **Boot +1-2s from probes:** Only pid+port+`--version`, no deep health. Acceptable; can add `--quick` flag if needed.
- **CI grep `stack is UP` breaks:** Keep that string when `exit 0`; only add `DEGRADED` variant on failure.
- **Exit code breaks callers assuming 0:** Document it; proposal aligns with `self-check.sh`'s `0/1/2`. Alternative is `--strict` opt-in if Pi-agent prefers backward-compat.

---

## 10. Open questions for Pi-agent

1. Should `status.sh` exit non-zero when degraded (`0/1/2` like `self-check.sh`), or stay `0` for backward-compat? Proposal: `0/1/2`.
2. Should `boot.sh` footer be truthful (probe) or stay "attempted"? Proposal: truthful.
3. JSON shape: mirror `self-check.sh`'s `health-report.json` or a simpler `{"components": [...]}`? Proposal: simple, happy to match `self-check` if preferred.
4. Should `install.sh` footer also use the lib's formatting, or stay as inventory? Proposal: defer to follow-up.

---

## 11. References

- Bug locations: `status.sh:4` (`set -e`), `status.sh:16-27` (port), `status.sh:28-41` (pid), `status.sh:114-147` (render)
- Correct helpers: `lib/process.sh:153-207` (pid/port), `boot.sh:346-359` (footer), `install.sh:232-237` / `574-596` (inventory), `self-check.sh:102-241` (health probes)
- Live evidence: `dash` `/dev/tcp` failure + `set -e` minimal repro (see above); current host has `dash` + no `nc` — `status.sh` always shows `❌` for ports.

---

*No code changed yet — this is the reviewable proposal. Happy to land P1+P2+P3 as a first commit and the lib consolidation as a second commit in the same PR so it's bisectable.*
