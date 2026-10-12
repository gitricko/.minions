# Proposal for #66 — consolidate status reporting (status.sh / boot.sh / install.sh)

Author: hermes agent (minions due-diligence)
Date: 2026-10-12
Status: implemented — lib/status-lib.sh + status.sh + boot.sh footer (#66), verified green
Related: #66 — implementation at `lib/status-lib.sh`, `status.sh`, `boot.sh:346-379`, tests `tests/test_status.sh` (20 tests)

----------------------------------------------------------------
## 1. TL;DR — is the reporter right?

Yes.

* status.sh has two bugs that exactly produce the screenshots in #66.
* boot.sh and install.sh each invent their own "footer" with divergent
  coverage and none of them agree with status.sh or with self-check.sh.
* There is no shared library — 4 places reimplement "is this up?".
* A single lib/status-lib.sh consumed by status.sh, boot.sh (footer) and
  optionally install.sh is feasible, low-risk, and the right fix.

----------------------------------------------------------------
## 2. Reproduction and evidence

Reproduced live on codespace host (2026-10-12):

  /bin/sh -> dash (not bash)
  nc not installed
  MINIONS_HOME pid files exist, services up

Observations:

* `sh -c '(echo > "/dev/tcp/127.0.0.1/20128")'` under dash:
  "cannot create /dev/tcp/127.0.0.1/1: Directory nonexistent" exit 2
  Under bash the same probe works (exit 1 on ECONNREFUSED, 0 on success).
  status.sh:16-26 uses that dash-broken fallback, so check_port always
  returns 1 on this host. Hence per-service you see:

    omniroute   (127.0.0.1:20128)
    ❌                         <-- port check (always false)
    ✅ (pid 1081)              <-- pid file check (true)

  That is the double-icon row in #66. Same for 9router.

* `set -e` + bare `check_pid` (status.sh:116,121):
  `check_pid` returns 1 when the pid file is missing/stale.
  Under `set -e`, a bare failing command aborts the script.
  Verified with minimal repro:

    set -e; check_pid(){ echo "❌"; return 1; }; echo line1; check_pid; echo line2
    -> exits after check_pid, line2 never prints.

  So when omniroute is down, status.sh prints:

    .minions status:
      omniroute   (127.0.0.1:20128)
    ❌
    ❌        <-- second ❌ is from check_pid, then script exits
              <-- 9router/pi/hermes/tailscale/READY never printed

  When omniroute is up, check_pid returns 0, so `set -e` does not fire
  and the full report appears (with the still-wrong port icon).

* Tailscale block (status.sh:42-108, 142-146) is correctly guarded with
  `set +e`/`set -e` around the capture, so it does not abort. The
  omniroute/9router pid probes are not guarded — inconsistency.

* Live `~/.minions/status.sh` with services up currently prints (checked
  with `bash -c` vs `sh -x`):

    omniroute  ❌          (port probe, wrong)
    ✅ (pid 12653)        (pid probe, correct)
    9router    ❌          (same)
    ✅ (pid 12714)
    pi-agent   ✅ (1.1.0)  ok
    hermes     ✅ (...)    ok
    tailscale  ✅ (kernel, pid 12985)  ok (guarded)

  With services down the file truncates after the first ❌❌ pair,
  exactly as #66 reports.

----------------------------------------------------------------
## 3. Full problem inventory (with locations)

P1 — port probe broken on dash (status.sh:16-27)
    Shebang is `#!/usr/bin/env sh` (dash in codespace/DTS), but
    fallback uses `/dev/tcp` which is bash-only and furthermore is
    invoked as `(echo > "/dev/tcp/...")` inside dash, not `bash -c`.
    Result: every port check is ❌ even when the port is listening.
    Note: lib/process.sh:187-189 already has the correct fallback:
      `bash -c "exec 3<>/dev/tcp/$1/$2"` when nc is absent.
      status.sh does not reuse it.

P2 — set -e abort on missing pid (status.sh:1-5, 116,121)
    `set -e` + bare `check_pid` = early exit when any daemon is down.
    The footer (READY marker) and later components are never printed,
    so the report looks "half empty". Fix is to either drop `set -e`
    for a reporter script, or guard every probe (`|| true`, `set +e`
    block, or `if check_pid; then ...`).

P3 — two icons per service (status.sh:115-121)
    Each service prints a port line and a pid line on separate lines:
      check_port && echo "✅" || echo "❌"
      check_pid
    So a healthy service shows two rows (❌ + ✅), a down service shows
    two ❌ rows on two lines. Expected is one combined row per service.

P4 — missing components (status.sh vs boot.sh vs install.sh)
    status.sh checks: omniroute, 9router, pi, hermes, tailscale, READY.
    Omits: ollama (boot.sh does start it), mnemon (CLI + DB),
           versions for omniroute/9router/ollama/mnemon/tailscale.
    boot.sh footer (boot.sh:346-359) always prints 5 ✅ lines + optional
    ollama line, hardcoded, no probe, no version.
    install.sh footer (install.sh:579-592) prints inventory with
    versions from versions.env variables, but is install-time only.
    self-check.sh (self-check.sh:102-334) probes 9Router/OmniRoute via
    curl HTTP codes, ollama via /api/tags + model + embeddings,
    mnemon binary+DB, tailscale via status/pgrep, plus disk/memory/
    persistence — but none of that is shared with status.sh.

    Result: three different "is the stack up?" answers that disagree.

P5 — no versions where useful (#66 asks for it)
    status.sh prints versions only for pi and hermes (via --version).
    boot.sh prints no versions.
    install.sh prints versions from build-time variables, not from the
    actual binaries on disk.
    self-check.sh prints only mnemon + ollama versions.
    Requirement from #66: show versions for omniroute/9router as well,
    and also ollama, mnemon, tailscale.

P6 — no machine-readable mode, no exit-code discipline
    status.sh always exits 0, even when degraded.
    self-check.sh already has 0=ok,1=warn,2=critical and writes
    health-report.json. status.sh should at least exit non-zero when
    required services are down, and optionally support --json for boot
    and install to reuse.

P7 — no shared library
    lib/status-lib.sh does not exist. lib/process.sh has
    is_service_running, wait_for_port, wait_for_health — but status.sh
    reimplements its own check_port/check_pid. Tailscale logic is
    duplicated three times (status.sh:44-108, self-check.sh:194-241,
    boot.sh:188-291). DRY violation; bug fixes in one place do not
    propagate.

----------------------------------------------------------------
## 4. Design options considered

A — "Patch status.sh only" (minimal)
    Fix P1+P2+P3 inside status.sh alone, add ollama/mnemon rows.
    Pros: small diff. Cons: boot footer stays lying, duplication remains,
    next bug again drifts.

B — "Merge status.sh into self-check.sh"
    Make self-check.sh the one true reporter and make status.sh a wrapper
    `self-check.sh --brief`.
    Pros: self-check is already thorough. Cons: self-check is heavy
    (disk, memory, persistence, JSON, CI mode) and slow (curl retries,
    ollama embed test). status.sh should be instant (pid + port + version)
    for interactive use. Also boot.sh wants a quick footer, not a full
    health report.

C — "Shared lib" (recommended)
    Create lib/status-lib.sh as the single source of truth for
    "what is the stack and how do we probe it?".
    status.sh becomes a thin renderer over the lib.
    boot.sh footer calls the same lib to render a truthful summary
    instead of hardcoded ✅ lines.
    install.sh footer optionally uses the lib's formatting helpers so
    inventory and health reports look the same.
    self-check.sh can gradually adopt the lib for its service probes
    (follow-up, not required for #66).

Selected: C. Fixes the bug class, not just the symptom.

----------------------------------------------------------------
## 5. Proposed solution (detailed)

### 5.1 New file: lib/status-lib.sh

POSIX sh, no bashisms, no `set -e` inside. Sourced by status.sh,
boot.sh, install.sh, and later self-check.sh.

Environment it respects (same as today):
  MINIONS_HOME (default $HOME/.minions)
  OMNIROUTE_HOST / OMNIROUTE_PORT / NINEROUTER_HOST / NINEROUTER_PORT
  TAILSCALE_SOCKET (default $MINIONS_HOME/var/run/tailscaled.sock)

Functions (names draft, to be bikeshedded in review):

  # low-level
  _status_has_nc()                # test once, cache
  _status_port_open <host> <port> # nc -z if present, else bash -c 'exec 3<>/dev/tcp/...' if bash exists, else curl fallback; returns 0/1
  _status_pid_alive <name>        # reads $MINIONS_HOME/var/run/<name>.pid, kill -0 + sudo kill -0 fallback, echoes pid or empty, returns 0/1
  _status_cli_version <bin>       # tries: <bin> --version, <bin> version, <bin> --help head -1; normalises "v1.2.3" vs "1.2.3"; falls back to versions.env if bin missing; echoes version or "not installed"
  _status_service_version <name>  # name in {omniroute,9router,ollama,mnemon,tailscale,pi,hermes}; dispatches to _status_cli_version with correct flag per binary

  # per-component probes — each echoes a single line "STATUS|DETAIL" and returns 0/1
  # STATUS in {ok,warn,missing,down}, DETAIL is human text for the row
  status_probe_omniroute          # port + pid + version; ok if port open and pid alive; warn if one of the two; down if neither
  status_probe_9router
  status_probe_ollama             # binary + API /api/tags + model list; reuses lib/ollama.sh helpers if present
  status_probe_pi
  status_probe_hermes
  status_probe_mnemon             # binary + DB dir check (same as self-check.sh:178-185)
  status_probe_tailscale          # delegates to existing lib/tailscale.sh semantics but extracted; handles kernel vs userspace, Logged out. case, socket ownership check (stat -c %u / stat -f %u)

  # aggregate
  status_collect                  # runs all probes, sets globals like STATUS_OMNIROUTE, STATUS_9ROUTER, ... and VERSION_* variables
  status_render_human             # prints the canonical human report (one row per component, aligned columns, single ✅/❌ per row, version in parens)
  status_render_json              # prints JSON array/object for --json mode (compatible with self-check's health-report.json shape if possible)
  status_exit_code                # 0 all ok, 1 degraded/warn, 2 critical — same discipline as self-check.sh

Design rules for the lib:

* Never call `exit`; library returns codes, callers decide.
* No `set -e` inside; every probe is guarded (`set +e` where needed, or `|| true`).
* Port probe MUST use the correct fallback from lib/process.sh:186-193,
  not the broken `(echo > /dev/tcp/...)` inside dash. Specifically:
    if command -v nc >/dev/null 2>&1; then
      port_check() { nc -z "$1" "$2" 2>/dev/null; }
    elif command -v bash >/dev/null 2>&1; then
      port_check() { bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }
    else
      # last resort: curl -fsS http://$1:$2/healthz or /v1/models with --max-time 2
      port_check() { curl -fsS --max-time 2 "http://$1:$2/" >/dev/null 2>&1; }
    fi
* Pid probe MUST mirror lib/process.sh:is_service_running (kill -0 plus
  sudo -n kill -0 fallback) so root-owned tailscaled pids are not
  reported as ❌.
* Version probe: prefer binary's own --version, fall back to versions.env
  (the pinned version we installed). That way "not yet booted" still
  shows what *would* run, and "running but binary missing from PATH"
  is visible.
* Tailscale probe is the longest; extract the existing ~60-line
  status.sh:44-108 block into a single function, keep the Logged out.
  handling ( `case *Logged out.*` -> rc 0 ) and the kernel-vs-userspace
  socket-ownership check (ownership, not writability).

### 5.2 Rewrite: status.sh

Before (today, 154 lines, sh, set -eu, two icons per service, early exit):
  set -e; set -u
  check_port ... && echo "✅" || echo "❌"
  check_pid "omniroute"      # bare, aborts under set -e when down

After (thin wrapper, no logic duplication):

  #!/usr/bin/env sh
  set -u   # no -e — reporter must not abort on degraded state
  MINIONS_HOME="${MINIONS_HOME:-$HOME/.minions}"
  # shellcheck disable=SC1091
  . "${MINIONS_HOME}/lib/status-lib.sh"   # or SCRIPT_DIR/lib/... when running from repo
  # also source versions.env for fallback versions if lib needs it
  case "${1:-}" in
    --json) status_collect; status_render_json; exit "$(status_exit_code)" ;;
    --help|-h) echo "Usage: status.sh [--json]"; exit 0 ;;
    *) status_collect; status_render_human; exit "$(status_exit_code)" ;;
  esac

Human rendering (spec):

  .minions status:

    omniroute   http://127.0.0.1:20128/v1   ✅ (pid 12653, v3.8.51)
    9router     http://127.0.0.1:7352/v1    ✅ (pid 12714, v0.5.99)
    ollama      http://localhost:11434     ✅ (v0.40.3, nomic-embed-text ready)
    pi-agent    CLI                        ✅ (v1.1.0)
    hermes      CLI                        ✅ (v0.21.6+141.gd94b70f)
    mnemon      memory layer               ✅ (v0.2.10, db at ~/.mnemon)
    tailscale   (opt-in)                   ✅ (kernel, pid 12985, v1.104.1)
    READY FOR FIRSTMATE DISPATCH           ✅

  When down, same rows but single ❌ and detail, no early truncation:

    omniroute   http://127.0.0.1:20128/v1   ❌ (down — no pid, port closed, expected v3.8.51)
    9router     http://127.0.0.1:7352/v1    ❌ (down)
    ...

  Each row is one line, one icon. No more split ❌ + ✅ lines.

Exit codes (align with self-check.sh):
  0 — all required services ok (omniroute, 9router, ollama if mnemon needs it)
  1 — warnings only (e.g. tailscale not logged in, optional model not yet pulled)
  2 — critical (omniroute or 9router down, READY missing)

### 5.3 Update: boot.sh footer

Today boot.sh:346-359 hardcodes:

  echo "  ✅ omniroute    http://..."
  echo "  ✅ 9router      http://..."
  echo "  ✅ pi-agent     CLI ready ..."
  echo "  ✅ hermes       CLI ready ..."
  echo "  ✅ mnemon       memory layer ready"
  if [ -x .../ollama ]; then echo "  ✅ ollama ..." ; fi

Proposed: after READY marker, call the same lib to render a truthful
footer. Keep the "Starting ..." log lines as today (they are boot
progress), but replace the final banner:

  # Step 8: Print READY message (truthful, via status-lib)
  # shellcheck disable=SC1091
  . "${LIB_DIR}/status-lib.sh"
  status_collect   # re-probes what we just started
  echo ""
  echo "=============================================="
  if [ "$(status_exit_code)" -eq 0 ]; then
    echo "  .minions stack is UP"
  else
    echo "  .minions stack is DEGRADED (see below)"
  fi
  echo ""
  status_render_human   # same rows as status.sh, but after boot
  echo "=============================================="

Benefits:
* Boot no longer lies — if omniroute failed to bind, banner shows ❌.
* Boot and status agree on probes, versions, and formatting.
* Boot log (var/log/boot.log) already captures start_service output;
  the banner is just presentation.

Alternative if Pi-agent prefers boot stay simple: keep hardcoded banner
but add a one-liner `~/.minions/status.sh` hint and ensure the banner
is clearly labelled "boot attempted" not "health verified". The
proposal prefers the truthful banner.

### 5.4 Update: install.sh footer (optional, low priority)

Today install.sh:574-596 prints inventory with versions from shell
variables (PI_VERSION etc. sourced from versions.env).

Proposed: source status-lib's version helpers so formatting is shared,
but keep the semantics "installed to ..." (inventory) not "running".

  . "${SCRIPT_DIR}/lib/status-lib.sh"
  _status_cli_version omniroute  # or just use versions.env fallback
  # then print with same column alignment as status.sh

This is cosmetic; can be deferred to a follow-up if scope is tight.
At minimum, install.sh should `cp` the new status-lib.sh into
$MINIONS_HOME/lib (install.sh:232-237 copies lib/*.sh) so the first
boot after install has the lib.

### 5.5 Relationship to self-check.sh

self-check.sh is a deeper diagnostic (services via HTTP codes, model
counts, disk, memory, persistence symlinks, JSON report). It should
remain separate — its scope is "is this host healthy for firstmate
dispatch?" while status.sh is "is the stack up?".

Follow-up (not required for #66): make self-check.sh's Services section
call status-lib's `status_probe_omniroute` etc. instead of its own
curl loops, to avoid a third implementation. Defer to avoid scope creep.

----------------------------------------------------------------
## 6. File change list (for Pi-agent review)

New:
  lib/status-lib.sh          — shared probes + renderers (POSIX sh, ~200-250 lines)

Modified:
  status.sh                  — rewrite as thin wrapper over lib/status-lib.sh
                              (drop set -e, one row per service, add ollama/mnemon,
                               add versions for omniroute/9router, add --json,
                               fix port probe, guard pid probe)
  boot.sh                    — replace hardcoded footer (lines 346-359) with
                              status_collect + status_render_human; add
                              . "${LIB_DIR}/status-lib.sh" source
  install.sh                 — ensure lib/status-lib.sh is copied to
                              $MINIONS_HOME/lib (already covered by cp lib/*.sh,
                              but verify); optionally share version formatting
  lib/process.sh             — no change, but status-lib reuses its
                              is_service_running / wait_for_port semantics
                              (consider extracting _port_open helper there if
                              Pi-agent prefers single implementation)
  README.md                  — document `~/.minions/status.sh [--json]`
                              and that boot footer is now health-checked

No change (for #66 scope):
  self-check.sh, stop.sh, lib/mnemon.sh, lib/ollama.sh, lib/tailscale.sh
  (tailscale probe extraction is internal to status-lib, not a change to
   lib/tailscale.sh)

----------------------------------------------------------------
## 7. API and rendering details (for review)

Proposed `status-lib.sh` function signatures (final names to be
reviewed by Pi-agent; keep POSIX sh, no associative arrays):

  status_collect
    Runs all probes, populates globals:
      STATUS_OMNIROUTE, STATUS_9ROUTER, STATUS_OLLAMA, STATUS_PI,
      STATUS_HERMES, STATUS_MNEMON, STATUS_TAILSCALE, STATUS_READY
    and
      VERSION_OMNIROUTE, VERSION_9ROUTER, VERSION_OLLAMA, VERSION_PI,
      VERSION_HERMES, VERSION_MNEMON, VERSION_TAILSCALE
      DETAIL_OMNIROUTE, ... (human detail string)
    Returns 0 always (collection never aborts).

  status_render_human
    Prints aligned rows to stdout, one per component, plus READY line.
    Uses printf "%-11s %-28s %s\n" for columns.

  status_render_json
    Prints JSON to stdout, e.g.:
      {"timestamp":"...","components":[
        {"name":"omniroute","status":"ok","version":"3.8.51","detail":"pid 12653, port open"},
        ...
      ],"ready":true,"exit_code":0}
    If self-check's health-report.json shape is preferred, match that
    schema instead — Pi-agent to decide.

  status_exit_code
    Echoes 0/1/2 to stdout (and returns same), for `exit $(status_exit_code)`.

Version resolution order per component:
  1. Binary on disk:  $MINIONS_HOME/bin/<name> --version  (or variant)
  2. Fallback:        $MINIONS_HOME/etc/versions.env  (pinned version)
  3. If neither:      "unknown"

Row spec (human):
  LABEL        ENDPOINT/ROLE                ICON DETAIL
  omniroute    http://127.0.0.1:20128/v1    ✅ (pid 12653, v3.8.51)
  9router      http://127.0.0.1:7352/v1     ✅ (pid 12714, v0.5.99)
  ollama       http://localhost:11434      ✅ (v0.40.3, nomic-embed-text ready)
  pi-agent     CLI                         ✅ (v1.1.0)
  hermes       CLI                         ✅ (v0.21.6+141.gd94b70f)
  mnemon       memory layer                ✅ (v0.2.10)
  tailscale    (opt-in)                    ✅ (kernel, pid 12985, v1.104.1)
                                           -- not installed (install with install.sh --tailscale)  [when absent]
                                           ❌ (installed but not running — run: ts up)           [when down]
  READY FOR FIRSTMATE DISPATCH             ✅ / ❌

----------------------------------------------------------------
## 8. Testing plan

* Unit: sh -n lib/status-lib.sh && shellcheck lib/status-lib.sh status.sh
* Manual with services up:   ~/.minions/status.sh  (expect all ✅, single icon per row, versions present)
* Manual with services down: ~/.minions/stop.sh; ~/.minions/status.sh (expect full report, no truncation, ❌ rows for omniroute/9router/ollama, later rows still printed)
* Port probe: on host without nc (codespace), verify port open is detected via bash /dev/tcp fallback
* Boot: ~/.minions/boot.sh; verify footer matches subsequent status.sh run, and shows ❌ when a service is intentionally failed
* Install: ./install.sh --dry-run or in DTS; verify footer inventory still correct
* DTS (docker-test-shell) matrix: the existing real-install CI that currently
  checks boot footer should be updated to assert `status.sh` exit code 0
  and `status.sh --json` validity instead of grepping the hardcoded banner.
* Self-check still passes: ~/.minions/self-check.sh (no regression)

----------------------------------------------------------------
## 9. Risks and mitigations

* Risk: status-lib.sh sourced from two locations (repo lib/ and
  $MINIONS_HOME/lib) diverges after install vs dev mode.
  Mitigate: install.sh already `cp -f lib/*.sh $MINIONS_HOME/lib/` (line
  234) — new file is automatically copied. boot.sh sources from
  $MINIONS_HOME/lib (correct).

* Risk: boot.sh now does real probes, adding ~1-2s to boot.
  Mitigate: probes are just pid file + port + --version (no curl retries
  except optional health). Acceptable. If needed, boot can call
  status_render_human with a --quick flag that skips ollama embed check.

* Risk: changing boot footer breaks CI that greps for "stack is UP".
  Mitigate: keep the "stack is UP" string when exit code 0, so existing
  grep still passes; only add "DEGRADED" variant for failure.

* Risk: status.sh exit code change breaks scripts that assume 0.
  Mitigate: document it; keep default human mode exit 0 for backwards
  compat if Pi-agent prefers (opt-in strict mode via --strict). Proposal
  prefers proper exit codes (aligns with self-check.sh).

----------------------------------------------------------------
## 10. Why not just fix status.sh?

We could fix P1+P2+P3 with a 10-line patch to status.sh. That would
close #66's screenshots but leave the class of bug: next time boot.sh
or self-check.sh changes its probe, status.sh drifts again. The shared
lib is ~200 lines once and removes three copies of the same logic. The
incremental cost is low because lib/process.sh already has the correct
primitives — status-lib is mostly wiring.

If Pi-agent wants minimal risk for this PR, we can land P1+P2+P3 as a
first commit and the lib consolidation as a second commit in the same
PR, so the fix is bisectable.

----------------------------------------------------------------
## 11. Open questions for Pi-agent

1. Should status.sh exit non-zero when degraded (like self-check), or
   stay 0 for backwards compat? Proposal: non-zero (0/1/2) — please
   confirm.
2. Should boot.sh footer be truthful (probe) or stay as "attempted"?
   Proposal: truthful — confirm.
3. JSON shape: mirror self-check's health-report.json or a simpler
   `{"components": [...]}`? Proposal: simple, but happy to match
   self-check if you prefer one schema.
4. Should install.sh footer also use the lib's formatting, or stay
   as inventory? Proposal: defer to follow-up — confirm.

----------------------------------------------------------------
## 12. References

* status.sh:16-27 (port), 28-41 (pid), 114-147 (render), set -e at line 4
* lib/process.sh:153-207 (correct port/pid helpers)
* boot.sh:346-359 (hardcoded footer), 139-183 (service start)
* install.sh:232-237 (lib copy), 574-596 (inventory footer)
* self-check.sh:102-241 (service/tailscale probes)
* Live repro: /bin/sh -> dash, nc absent, /dev/tcp fails under dash
