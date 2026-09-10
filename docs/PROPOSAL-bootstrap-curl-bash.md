# PROPOSAL — Self-Contained curl|bash Bootstrap (Bootstrap + Standalone Detection)

**Status:** Draft
**Date:** 2026-09-10
**Related:** IMPL-PLAN-skills-wiki-integration.md, PROPOSAL-skills-wiki-integration.md
**Branches:** `minion-knowledge-base`

---

## 1. Problem

README advertises the oh-my-zsh-style one-liner:

    curl -fsSL https://minions.sh/install.sh | bash

(minions.sh domain doesn't exist yet; the working equivalent is the GitHub raw URL.)

This one-liner **fails today** for three distinct reasons, verified by simulation:

1. **Bootstrap is not self-contained.** `install.sh` computes `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`; when piped, `$0` is `bash` and `dirname "$0"` is empty → `SCRIPT_DIR` resolves to `.` (the cwd), which is wrong. When piped from an empty dir, `SCRIPT_DIR` === `.`, and all `$SCRIPT_DIR/lib/*.sh`, `$SCRIPT_DIR/boot.sh`, `$SCRIPT_DIR/etc/*` copies silently no-op (glob fails → `2>/dev/null || true`).

2. **stdin collision (exit 141 / SIGPIPE).** The `curl ... | bash` pipe means the script's stdin IS the script text. When the script later runs `read` (or any stdin-consuming command), it consumes the remainder of its own script from the pipe and/or gets SIGPIPE. Clean-HOME simulation: fails at "uv not found, installing vendored uv..." with exit 141.

3. **Knowledge assets have no source.** Even if the base install worked, the knowledge layer (skills/wiki/mnemon/memories) needs to come from somewhere in standalone mode. Phase 22's F09 already proposed "tarball download" **only for knowledge assets**, assuming the base install already worked piped. It doesn't.

So: the one-liner path — which *defines* standalone mode — is unproven end-to-end even without knowledge assets.

## 2. Design

### 2.1 Bootstrap stages (single script, two flows)

`install.sh` gains a **bootstrap preamble** that runs ONLY when `$0` is not a real file (piped/stdin). Detection:

```sh
# Works for: bash <(curl ...), curl ... | bash, /dev/stdin
if [ ! -f "$0" ] || [ "$(basename "$0")" = "bash" ] || [ "$0" = "-" ]; then
    PIPED=1
fi
```

When `PIPED=1`:

1. **Resolve source.** Try in order:
   - `BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://github.com/gitricko/.minions/raw/refs/heads/main.tgz}"` ???
   - Actually: the raw install.sh has no bundled assets. The installer must fetch the **repo tarball** (or `git clone --depth 1`) to a scratch dir, then re-exec `install.sh` from that checkout.
2. **Fetch + extract:** `curl -fsSL https://github.com/gitricko/.minions/archive/refs/heads/main.tar.gz | tar xz -C "$SCRATCH"` (or `git clone --depth 1 --branch main https://github.com/gitricko/.minions "$SCRATCH"`).
3. **Re-exec the checkout's install.sh** (now `$0` is a real file, SCRIPT_DIR ∈ checkout; all asset copies work).

The bootstrap preamble is **tiny** — it must not assume anything about the environment except `curl`/`tar` (or `git`).

### 2.2 Why tarball over git clone

- **Lighter**: no git history; raw URL works on any box with curl+tar.
- **Deterministic**: pinned to `main` at fetch time.
- **Matches the curl|bash idiom**: curl in, tar out.
- git clone remains a fallback when `git` exists and tarball URL 404s (mirror).

### 2.3 Mode detection stays as planned (lib/knowledge-detection.sh)

After re-exec, `detect_knowledge_mode` runs inside the checkout:

- In a dev checkout (`/workspaces/.minions`, has `.git` + `skills/` + `wiki/`): `MODE=dev`, MINIONS_REPO_ROOT=checkout root.
- After curl|bash (checkout at `/tmp/...`, no `.git` — tarball has none): `MODE=standalone`, MINIONS_REPO_ROOT="" → knowledge assets copied to `~/.minions/skills` etc from the tarball checkout.

**Key insight:** the tarball extract has NO `.git` dir (tarballs don't ship `.git`), so even the bootstrap flow's local checkout is detected standalone. Detection is thus correct without special-casing.

Actually — wait. If the bootstrap unpacks to a scratch dir and that dir has `skills/` + `wiki/` but no `.git`, `detect_knowledge_mode` says standalone. If a user later runs `install.sh` from a git checkout with `.git` AND skills/wiki → dev. Both correct.

### 2.4 What the bootstrap must NOT do

- No knowledge-layer logic (that's Phase 22 post-preamble).
- No mode detection (that's the shared helper, after preamble).
- No service start.
- Just: fetch repo → extract → re-exec install.sh.

## 3. Files touched

| File | Change |
|---|---|
| `install.sh` | Add bootstrap preamble (PIPED detection + fetch + re-exec). No other logic changes. |
| `docs/README.md` | Update one-liner to raw-GitHub URL until minions.sh domain lands; document `BOOTSTRAP_URL` override. |
| `tests/test_bootstrap.sh` (NEW) | Test the piped path in isolation (see §4, §6). |
| `.github/workflows/ci.yml` | Add bootstrap test to `Test (Linux)` job. |
| `tests/test_dts.sh` | Add "piped curl|bash in clean container" block. |

## 4. Verification strategy (how we know it works in real)

Three layers, each asserting BOTH detection branches:

### 4.1 Unit (Test (Linux) job, fast, no docker)

`tests/test_bootstrap.sh`:
- **Piped detection**: `bash <(cat install.sh) --help`-style invocation asserts the preamble recognizes piped mode (no crash, prints "bootstrap" message).
- **Re-exec correctness**: simulate by extracting the main tarball to a temp dir WITHOUT .git, then run `install.sh` from there → assert `MODE=standalone` output + assets (once Phase 22 lands) copied to a temp HOME.
- **Dev detection (existing)**: run install.sh from a git checkout with skills/wiki → assert `MODE=dev` (this is `test_dev_detection` in test_knowledge.sh; run here too).

### 4.2 DTS (dts-integration job)

`tests/test_dts.sh` gains:
- **Test 9.5 (standalone piped)**: in the clean container, run the literal one-liner against the raw URL (or local file to avoid network flake): `curl -fsSL <RAW_URL>/install.sh | bash` from an EMPTY cwd → assert exit 0, `~/.minions` populated, `MODE=standalone`, knowledge assets copied (post-Phase 22).
- **Test 9.6 (dev in repo)**: from `/src` (the bind-mounted repo WITH .git), run `bash /src/install.sh` → assert `MODE=dev`, symlinks to repo.

### 4.3 Real-install job

The existing real-install CI job does `git checkout` then install.sh → becomes a **dev-mode** test automatically once detection exists. Add an assertion step: after install, `grep -q "Knowledge mode: dev"` install log OR `lib/knowledge-detection.sh` says dev. This proves dev-mode in real CI.

For REAL standalone in real-install, add a light second step: fetch the main tarball (`BOOTSTRAP_URL`) into a scratch dir (no .git), run that install.sh against a temp HOME with a `--bootstrap-test` flag that stops after the knowledge copy (avoids doubling the full-stack install cost) → assert MODE=standalone + `~/.minions/skills` populated. The full standalone stack install is covered by DTS T4.

## 5. Ordering / dependencies

| Depends on | Why |
|---|---|
| Phase 22 base (mode detection + lib helpers + knowledge copy) | Bootstrap preamble needs `detect_knowledge_mode` + knowledge copy to exist before standalone assertions are meaningful |
| Phases 16–21 (wiki/mnemon content) | For full knowledge-copy assertions, but NOT required for bootstrap itself (bootstrap works with empty skills/ wiki/) |

**Proposed placement: Phase 22.5 (bootstrap), right after Phase 22.** Phase 22 builds the detection + knowledge copy; 22.5 builds the one-liner that feeds both modes. Wiki/mnemon content (16–21) can stay after 22.5, or before — bootstrap doesn't depend on their content, only on the DIRS existing (Phase 0).

**Simplest commit order respecting the reorder:**
1. Phase 22 (detection + lib helpers + knowledge copy [memory seeds now]) — already planned.
2. **Phase 22.5 (this proposal): bootstrap preamble + tests.** Uses Phase 22's helpers; test suite extended per §4.
3. Phases 16–21 (wiki/mnemon content) — fills in what standalone copies; bootstrap tests re-run and now assert real content counts.
4. Rest unchanged (23→31).

## 6. Test matrix (concrete)

| # | Test | Where | Assertion |
|---|---|---|---|
| T1 | `bash <(cat install.sh)` (piped, clean HOME) | unit | Preamble detects PIPED; bootstrap fetch+re-exec runs; exit 0; ~/.minions populated |
| T2 | tarball extract → run install.sh (no .git) | unit | `MODE=standalone`; assets copied to ~/.minions |
| T3 | git checkout run install.sh | unit / real-install | `MODE=dev`; symlinks to repo |
| T4 | curl -fsSL <RAW> \| bash in fresh DTS container | DTS | exit 0; ~/.minions populated; MODE=standalone; knowledge copied |
| T5 | `bash /src/install.sh` in DTS (repo mount, .git) | DTS | MODE=dev; symlinks to /src/skills |
| T6 | real-install job: after `bash install.sh` (git checkout) | real-install | MODE=dev |
| T7 | real-install job: tarball fetch → install.sh (--bootstrap-test, temp HOME) | real-install | MODE=standalone; ~/.minions/skills populated |

## 7. Risks / open questions

1. **exit 141 (SIGPIPE) in the base script** — even after re-exec fixes the piped path, if any later stage reads stdin, it breaks. The re-exec approach sidesteps this: once re-exec'd from a real file, stdin is free. Verify no stage consumes stdin post-re-exec (none should — all downloads use curl -o / explicit streams).
2. **`bash <(cat install.sh)` vs `curl | bash`** — process substitution gives `$0` = `/dev/fd/63`; the PIPED detection must treat `/dev/fd/*` as piped. T1 above covers it.
3. **Tarball URL stability** — `/archive/refs/heads/main.tar.gz` is stable while branch `main` exists. Document it; `BOOTSTRAP_URL` env override for mirrors/tests.
4. **Raw domain minions.sh** — placeholder until domain exists; README states the raw URL is canonical until then.
5. **Does the bootstrap need a version pin?** For now: always `main`. A release-tag pin (v0.x) is future work — document as non-goal.

## 8. Non-goals

- Domain provisioning (minions.sh) — external.
- Release tags / versioned installs.
- Windows install support.
- Changing the dev-mode install path (still `~/.minions` in both modes).