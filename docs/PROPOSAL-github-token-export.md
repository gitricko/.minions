---
title: "Durable GitHub Token Export for Hermes/Agent Sessions (boot.sh)"
status: "DRAFT — for review, not yet implemented"
date: 2026-09-13
branch: "proposal only (no code)"
---

# Durable GITHUB_TOKEN Export via boot.sh

## 1. Problem

In a GitHub Codespace, the **VSCode server process** has a `GITHUB_TOKEN` (a
`ghu_…` GitHub App user-to-server token) in its environment, but **Hermes agent
sessions do not inherit it**. The Codespaces git credential helper
(`/.codespaces/bin/gitcredential_github.sh`) only emits credentials when
`GITHUB_TOKEN` is exported into the shell running git — otherwise it `exit 0`s
silently and git falls back to the VSCode "GitHub wants to sign in" prompt,
which **blocks non-interactive pushes** (exactly what happened with PR #29).

## 2. Where the token lives / how it was fixed ad-hoc

- The token is readable from the live VSCode server PID:
  ```bash
  VSCODE_PID=$(pgrep -f "server-main.js" | head -1)
  GITHUB_TOKEN=$(cat "/proc/$VSCODE_PID/environ" | tr '\0' '\n' | grep "^GITHUB_TOKEN=" | cut -d= -f2-)
  ```
- This is exactly what the `codespace-gh-auth` skill's `get_github_token()`
  does. On this box it returned a 40-char `ghu_…` token, and
  `export GH_TOKEN="$GITHUB_TOKEN"` made `gh auth status` work (account
  `laouncle`, API 200).
- The fix was **per-session** — it does not survive a new session/rebuild.
- `~/.config/gh/hosts.yml` does **not** exist, so `gh` has no persisted creds;
  every fresh agent session hits the same wall.

## 3. Where to fix it — boot.sh (user's choice, agreed)

`boot.sh` is the right place: it is the single re-runnable entrypoint that runs
on every boot/env setup in a Codespace, it already sources knowledge libs and
wires Hermes/Pi, and a one-line export there makes **every** subsequent command
in that shell (git push, gh, curl to GitHub API, the credential helper) work
without the VSCode sign-in prompt.

**Goal:** at boot time, if `GITHUB_TOKEN` is not already set and the VSCode
server token is extractable, export it (and set `GH_TOKEN` for `gh`), so agent
sessions and interactive shells inherit working GitHub auth.

## 4. Design

### 4.1 New lib: `lib/gh-auth.sh` (small, testable)

```
lib/gh-auth.sh
  setup_github_auth()   # if GITHUB_TOKEN unset, extract from VSCode server; export GITHUB_TOKEN + GH_TOKEN
  # exports only when a valid token is found; no-op + warn otherwise (non-Codespace/missing VSCode)
```

Behavior:
- If `GITHUB_TOKEN` already set → leave it (respect user override), set `GH_TOKEN` from it.
- Else find VSCode server PID (`pgrep -f server-main.js`), read `/proc/<pid>/environ`, grep `^GITHUB_TOKEN=`, take the value.
- Validate: prefix `ghu_` / non-empty (~40 chars). If valid → `export GITHUB_TOKEN`, `export GH_TOKEN="$GITHUB_TOKEN"`, `log_info`.
- If no VSCode server / no token → `log_warn` and return 0 (non-fatal; don't break boot on non-Codespace hosts like CI containers / DTS).
- Never prompts, never runs `gh auth login`.

### 4.2 Call in boot.sh (after Phase 23/24 wiring, before services start)

```bash
# shellcheck disable=SC1091
. "${LIB_DIR}/gh-auth.sh"
setup_github_auth
```

Placed near the top of boot.sh's source block (after `detect_knowledge_mode`),
so the export is available to everything boot spawns (services, later steps).
Re-run on every boot is idempotent (token already set → no-op).

### 4.3 Why boot.sh and not install.sh / shell profile

| Option | Verdict |
|--------|---------|
| **boot.sh** | ✅ Runs on every Codespace start; user explicitly chose it; exported into the shell that boot runs in (and, being a sourced script, available to processes it launches / same login session). |
| install.sh | ❌ Runs once at install; a later fresh shell won't have it. |
| `~/.bashrc` / `~/.profile` | Possibly, but not every session sources them identically (Hermes may spawn non-login shells), and it widens where the token is persisted. boot.sh is the project's existing "wire the environment" point. |

**Caveat to be explicit about:** `boot.sh` exports the token into **its own
shell context**. Hermes agent sessions that are *separate* OS processes spawned
outside boot's shell won't inherit it automatically — but in a Codespace the
agent's shell typically shares the environment boot sets up (and the
codespace-gh-auth skill remains the fallback for extraction). The export also
makes the git credential helper work for any git command in that shell.

### 4.4 Files touched

| File | Change |
|------|--------|
| `lib/gh-auth.sh` | **NEW** — `setup_github_auth()` (+ extract helper) |
| `boot.sh` | source lib + call it after Phase 23/24 wiring |
| `tests/test_gh_auth.sh` | **NEW** — unit tests (see §5) |
| `docs/…` | proposal/status note |

No changes to the credential helper, `gh` config, or VSCode.

## 5. Testing / Verification (TDD)

**A. `tests/test_gh_auth.sh`** (mirrors `test_pi_settings.sh` style):

| Test | Assertion |
|------|-----------|
| `test_auth_noop_when_token_set` | `GITHUB_TOKEN` pre-set → function leaves it, exports GH_TOKEN=GITHUB_TOKEN |
| `test_auth_extracts_from_vscode` | fake `/proc` env with `GITHUB_TOKEN=ghu_…` → exported GITHUB_TOKEN/GH_TOKEN match |
| `test_auth_no_vscode_noop` | no `server-main.js` PID → warns + returns 0, no export |
| `test_auth_bad_token_noop` | extracted token empty/not `ghu_` → no export |

(Unit tests call the lib with mocked `pgrep`/`/proc` via a test HOME; no real
VSCode needed. RED first, then implement.)

**B. Real-binary verification (this box):**
```
# Before (fresh shell): GITHUB_TOKEN unset
source lib/gh-auth.sh && setup_github_auth
echo ${GITHUB_TOKEN:+set} ${GH_TOKEN:+set}        # both set
gh auth status                                     # Logged in (GH_TOKEN)
git push origin feat/phase24-pi-settings           # no sign-in prompt
```

**C. DTS/CI:** boot.sh runs in DTS (standalone); assert no hang/regression
(export is a no-op in CI containers without VSCode server → warn + return 0).

## 6. Open Questions

1. **Scope of export in boot.sh:** export only `GITHUB_TOKEN`, or also persist
   to `~/.config/gh/hosts.yml` so `gh` works even without the env var? (I'd
   keep it minimal: export env vars only; hosts.yml is a separate concern.)
2. **Security note:** the token is a scoped GitHub App token (`ghu_`, repo
   scope, origin-repo-gated) read from VSCode server. Exporting into the shell
   is what Codespaces already does for its own processes; low additional risk.
   Acceptable?
3. **Do we also want this in `install.sh`** for the standalone (non-Codespace)
   case? (Probably not — standalone has no VSCode server; keep boot-only.)

---

*Draft for review — no code written yet.*