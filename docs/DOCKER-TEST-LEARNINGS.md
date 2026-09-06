# Docker Test Iteration: Learnings & Pitfalls

**Date:** September 2026
**Context:** First-time docker-test.sh creation and iteration for .minions

---

## Summary

Created `docker-test.sh` for testing .minions install/boot in a fresh Ubuntu container. Iterated through 5 issues during local testing. This document captures all root causes and fixes for future captains/firstmates.

---

## Issue 1: Node.js tarball extraction fails

**Symptom:**
```
tar (child): xz: Cannot exec: No such file or directory
tar (child): Error is not recoverable: exiting now
```

**Root cause:** Ubuntu 24.04 base image does not include `xz-utils`. The Node.js tarball is `.tar.xz` format.

**Fix:** Add `xz-utils` to apt-get install in docker-test.sh.

**Lesson:** Bare Ubuntu containers need explicit `xz-utils` for tar.xz extraction.

---

## Issue 2: Hermes install times out compiling node-pty

**Symptom:** Docker test hangs at hermes install, eventually times out at 7 min.

**Root cause:** Hermes install compiles `node-pty` native module via `node-gyp`, which requires `g++` and `make`. Ubuntu 24.04 has `gcc-14-base` but not the full compiler toolchain.

**Fix:** Add `g++ make` to apt-get install in docker-test.sh.

**Lesson:** Native Node module compilation (node-pty, better-sqlite3, etc.) needs build-essential. The Hermes install silently fails without it.

---

## Issue 3: Pi-Agent wrapper script wrong paths

**Symptom:**
```
/home/ubuntu/.minions/bin/pi: 4: cd: can't cd to /lib/pi/npm
/home/ubuntu/.minions/bin/pi: 5: exec: /lib/pi/npm/node_modules/.bin/pi: not found
```

**Root cause:** `lib/pi.sh` wrapper script used `lib/node_modules/` but actual npm structure is `node_modules/` (npm 9+ hoists to root). Also, Node binary wasn't in PATH (only `.bin` folder was).

**Fix in lib/pi.sh:**
- Changed `lib/node_modules` → `node_modules`
- Added `${MINIONS_HOME}/lib/node/bin` to wrapper PATH

**Lesson:** npm package structure varies by npm version. Always verify the actual installed paths with `ls -la` in the container.

---

## Issue 4: Docker exec doesn't source .bashrc

**Symptom:**
```
bash: line 1: hermes: command not found
```
Even though `.bashrc` has the correct PATH.

**Root cause:** `docker exec ... bash -c` runs non-interactive shell, which doesn't source `.bashrc`. `.profile` is only sourced by login shells.

**Fix in docker-test.sh:**
- Changed `docker_exec_user` to use `bash -l -c` (login shell)
- Updated `install.sh` to write PATH snippet to `.profile` too (not just `.bashrc/.zshrc`)

**Lesson:** For Docker dev-prod parity, always use `bash -l` (login shell) or write to `/etc/environment`. CI workflows use `export` in the step, which Docker doesn't have.

---

## Issue 5: boot.sh runs from wrong location

**Symptom:** Boot failed silently (no clear error, just timeout).

**Root cause:** docker-test.sh ran `bash /src/boot.sh` but `install.sh` copies boot.sh to `${MINIONS_HOME}/boot.sh`. The `/src/boot.sh` is the source, not the installed copy. Using the installed copy ensures it runs with the correct environment.

**Fix:** Changed `bash ${SRC_MOUNT}/boot.sh` → `bash ${CONTAINER_HOME}/boot.sh` (same for status.sh).

**Lesson:** Only `install.sh` should run from `/src` (the volume mount). Everything else gets installed to `${MINIONS_HOME}` and should run from there.

---

## Issue 6: Hermes config.yaml malformed (literal \n)

**Symptom:**
```
Failed to parse config.yaml: mapping values are not allowed in this context
in config.yaml, line 1, column 53
```

**Root cause:** `hermes_update_config()` uses Python YAML dump which writes proper YAML, but the fallback sed approach (line 184) writes literal `\n` characters instead of actual newlines. If Python yaml import fails, sed produces broken YAML.

**Status:** Pre-existing bug. Not a docker-test issue but surfaced during testing.

**Lesson:** When testing install scripts in Docker, YAML config generation is a common failure point. Always validate the generated config with `cat` before the service tries to parse it.

---

## Issue 7: Pi-Agent -p requires provider auth

**Symptom:**
```
No API key found for the selected model.
```

**Root cause:** Pi-Agent doesn't auto-use OmniRoute's keyless free providers. It needs explicit provider config (API key or OAuth). Hermes uses OmniRoute automatically; Pi-Agent does not.

**Fix:** Docker test verifies binary works (gives meaningful "API key" error, not "command not found"). Full integration test requires provider config.

**Lesson:** Hermes and Pi-Agent have different auth models. Don't assume pi -p will work keyless just because hermes chat -q does.

---

## Architecture: What Goes Where

| What | Runs from | Why |
|------|-----------|-----|
| `install.sh` | `/src/install.sh` (volume mount) | Entry point, copies everything to MINIONS_HOME |
| `boot.sh` | `${MINIONS_HOME}/boot.sh` | Installed copy, uses installed env |
| `status.sh` | `${MINIONS_HOME}/status.sh` | Same as boot.sh |
| `hermes chat` | `${MINIONS_HOME}/bin/hermes` | Wrapper sets HERMES_HOME |
| `pi -p` | `${MINIONS_HOME}/bin/pi` | Wrapper sets PATH to node_modules/.bin |

---

## Docker Test Flow (Final)

```
1. docker run ubuntu:24.04 sleep infinity
2. apt-get install: curl git ca-certificates xz-utils g++ make
3. bash /src/install.sh
   → Creates MINIONS_HOME, installs all components
   → Writes PATH to ~/.profile, ~/.bashrc
4. bash -l ${MINIONS_HOME}/boot.sh
   → Starts OmniRoute + ModelRelay
5. bash -l ${MINIONS_HOME}/status.sh
   → Verifies all components healthy
6. hermes --version / pi --version / mnemon --version
7. hermes chat -q "Reply with exactly: OK" (keyless via OmniRoute)
8. pi -p "Reply with exactly: OK" (expects provider error without auth)
```

---

## Key Config Files

| File | Purpose | Bug-prone? |
|------|---------|------------|
| `lib/pi.sh` wrapper | Sets PATH to pi node_modules | Yes — path structure varies by npm version |
| `lib/hermes.sh` hermes_update_config | Writes custom_providers to config.yaml | Yes — Python yaml vs sed fallback can produce broken YAML |
| `install.sh` PATH snippet | Writes MINIONS_HOME to shell rc files | Fixed — now writes to .profile too |
| `docker-test.sh` docker_exec_user | Runs commands as non-root user | Was non-interactive — fixed to use bash -l |

---

## Commands for Debugging

```bash
# Drop into container with correct env
docker exec -e MINIONS_HOME=/home/ubuntu/.minions -e PATH=/home/ubuntu/.minions/bin:/home/ubuntu/.minions/lib/node/bin:$PATH minions-test bash -l

# Check what install produced
docker exec minions-test bash -c "cat /home/ubuntu/.minions/lib/pi/pi"
docker exec minions-test bash -c "cat /home/ubuntu/.minions/lib/hermes/home/config.yaml"

# Verify hermes config
docker exec -e MINIONS_HOME=/home/ubuntu/.minions -e PATH=/home/ubuntu/.minions/bin:/home/ubuntu/.minions/lib/node/bin:$PATH minions-test bash -l -c "hermes config get"

# Test individual components
docker exec -e MINIONS_HOME=/home/ubuntu/.minions -e PATH=/home/ubuntu/.minions/bin:/home/ubuntu/.minions/lib/node/bin:$PATH minions-test bash -l -c "hermes chat -q 'hello'"
```
