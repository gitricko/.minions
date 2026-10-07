---
name: ci-debugging
description: Use when a CI/test failure seems to have one cause but the real root is different, or when a silent failure hides the real issue.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [ci, debugging, root-cause, tests, github-actions]
    related_skills: [github-codespace, karpathy-coding-guidelines, tdd]
---

# CI Debugging — Find the Root Cause

Debug CI failures by comparing passing vs failing commits, never by weakening the test.

## The core rule

**Fix the root cause, never weaken the test.**

When a fix seems to work, verify it actually fixed the right thing. If a test
is flaky or "fails sometimes", the failure is telling you something about the
code — not about the test.

## The 5-step procedure

1. **Get the failing commit's full log.**
   ```bash
   gh run view <run-id> --log | grep -E "FAIL|Error|✗" | head -20
   # identify the exact step and line
   ```

2. **Compare passing vs failing commits.**
   ```bash
   git log --oneline <passing>..<failing>
   git diff <passing>..<failing> -- <suspect-file>
   ```
   A "silent failure" (process killed before writing output) gives you zero
   error info — the only signal is which commit changed the behavior.

3. **Reproduce locally in isolation** (not by guessing).
   Use the repo's test harness (`dts` / `scripts/dts.sh`) to run the exact
   failing command inside a throwaway container, so the host environment
   can't mask the bug.

4. **Fix the root cause, then re-run the original test.**
   If your fix "works" but the test had to be weakened, you fixed the wrong
   thing.

5. **Verify with a clean test run** — not just the one case that failed.
   Run the full suite; a root-cause fix should not require relaxing other
   tests.

## Step 0: Ensure logs are captured *before* debugging

If probes redirect to `/dev/null`, there is nothing to debug with.
Before any debugging, verify the test suite captures failure output
to files that get uploaded as CI artifacts.

See the `ci-log-capture` skill for the pattern: replace
`>/dev/null 2>&1` with file captures to `${CI_LOGS_DIR}` so that:
- On **success**: clean `[PASS]` in CI log, full output sits quietly in artifact
- On **failure**: `[FAIL]` + the full captured body is `cat`-ed to stderr
  (visible in CI log immediately) AND persisted to artifact for later analysis

### The `run_and_log` helper pattern

```sh
# Add after CI_LOGS_DIR setup:
run_and_log() {
    local test_name="$1"; shift
    local log_file="${CI_LOGS_DIR}/${test_name}.log"
    if "$@" >"${log_file}" 2>&1; then
        log_info "${test_name} — OK"
        return 0
    else
        log_error "${test_name} — FAILED (see ${log_file})"
        cat "${log_file}"   # print to CI log for immediate visibility
        return 1
    fi
}
```

### Which probes to capture

| Category | Examples | Why |
|----------|----------|-----|
| **Version checks** | `hermes --version`, `9router --version` | Confirms binary installed correctly |
| **Health/model checks** | `/v1/models` curl probes | Shows HTTP status, model count |
| **Chat completion** | Chat completion endpoints | Shows **400/401/403 body** from upstream OC bug |
| **Preconfig** | 9Router/OmniRoute login/setup | Shows which step failed in the chain |

All captured files must match the artifact upload path (`path: ${{ env.CI_LOGS_DIR }}/`)
so they're downloaded on failure. See `ci-log-capture` skill.

## Silent failure patterns (hardest to debug)

| Symptom | Likely cause | How to find it |
|---------|--------------|----------------|
| Process exits 0 but no output written | Process killed early (OOM, timeout) before flush | Compare exit code + check for killed processes in CI log |
| Test "passes" but artifact is empty | `if-no-files-found: warn` masks empty upload | Check artifact size/content, not just job status |
| Fail only in CI, never locally | NGINX/CI PATH differs, env var unset, runner image change | Compare `env` output between local and CI |
| Fail only sometimes (flaky) | Race condition, retry logic, provider rate-limit | Look for "retry" loops and timeouts; bump tolerance only if truly ephemeral |
| `rm -rf` reports success but `verify CLEAN` fails with leftover mount | Docker volume mount (`-v host:container/path`) blocks removal — `rm -rf` cannot delete a mountpoint | Check `mount` output for `$HOME` in failure logs; unmount with `umount -l` plus `sudo umount -l` fallback (container runs as uid 1000) before retrying removal |
| `--keep-config` test fails "removed X (should preserve)" | Install never created X because its setup is disabled by default | Ensure install creates empty placeholder dirs (`mkdir -p ~/.mnemon ~/.ollama ~/.9router`) even when disabled so the uninstall contract has something to preserve |
| Uninstall test deletes real `~/.mnemon`/`~/.hermes` on host/codespace | Test ran with real `$HOME` instead of isolated temp dir — codespace mnemon is the memory layer, deleting it kills the session's model proxy | Always run uninstall/purge tests with `HOME=$(mktemp -d)` and clean up; never `rm -rf` with real `$HOME` in tests or scripts |
| `var=$(failing_cmd); rc=$?` error handler never runs and log stays empty | `set -e` aborts at a failing command substitution before the next line, so the `[FAIL] + tail` branch is dead code | Wrap the capture: `set +e; var=$(cmd 2>&1); rc=$?; set -e` so the handler can print diagnostics |
| `mkdir` fails "Read-only filesystem" or "Permission denied" on a path that is a symlink | Dir symlink `lib/ollama -> /tmp/cache:ro` makes `mkdir -p lib/ollama` walk through the ro mount; or the base image pre-creates `$HOME` owned by root and a conditional `[ -d $home ] or chown` skipped the fix | Mount cache outside the tree (`/tmp/cache:ro`) and symlink files not dirs (`lib/ollama/ollama -> /tmp/cache/ollama`); always `mkdir -p $home && chown` unconditionally |
| Cache miss causes re-download then a different downstream failure | Version string carries `v` prefix (`v0.40.0` in deps.yaml) but cache dir is `ollama-0.40.0-...` — un-stripped key leaves `OLLAMA_HOST_CACHE` empty so the container mounts nothing | Normalize before use: `version=${version#v}` and map arch aliases before building `OLLAMA_HOST_CACHE` |
| `bash install.sh \| tee log` reports success while install OOMed | Pipe exit is `tee`'s 0 when `pipefail` is off, masking left-side failure — downstream keep-config then sees missing dot dirs | Prefix the pipe: `set -o pipefail; cmd \| tee log` so failure propagates |
| `npm install` OOM `JavaScript heap out of memory` in constrained container | `NODE_OPTIONS=--max-old-space-size=512` too small for large package (e.g. omniroute@3.8.x) under DTS/CI limits | Raise heap in shared `install_npm_package` wrapper (512 → 2048) |
| `.tar.zst` extract fails `stdin: not in gzip format` or `zstd required` | DTS container lacks `zstd` and `tar -xzf` handles gzip only — `.tar.zst` needs `zstd -dc \| tar -xf` or `tar --zstd -xf` | Install `zstd` in DTS prereqs and fix `lib/download.sh` `.tar.zst` branch to use `tar --zstd -xf` fallback |

## Anti-patterns

- **Weakening the test to make it pass** — changes the contract, hides the bug.
- **Silencing output with `>/dev/null` without understanding why** — every
  silenced probe should have a log capture path (see `ci-log-capture` skill).
- **Skipping the health-check step** — if the stack isn't fully up, the check
  that "works" is meaningless.
- **"It passed locally"** — always verify in the actual CI environment.

## Real-world example (from this repo)

The mnemon PATH issue appeared as "mnemon not found" in `self-check.sh` even
though install claimed success. Root cause was not the install at all: the
PATH snippet was added only to `~/.bashrc` (not `~/.profile`), and non-
interactive login shells (like `dts exec`) never source `.bashrc`. Comparing
passing (codespace) vs failing (CI) environments revealed the PATH diff.

**Lesson:** when a fix appears to work but the symptom persists, diff the
*environments*, not just the code.