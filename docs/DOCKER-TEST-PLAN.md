# Docker-Based Local Testing Plan

**Problem:** CI is the only way to test a fresh install, but the feedback loop is slow (push → wait 5-10 min → check logs → fix → repeat). On an empty Codespace, Hermes failed to work and debugging via CI was painful.

**Solution:** A single shell script (`docker-test.sh`) that spins up a bare Ubuntu container, volume-mounts the repo, and runs install.sh + boot.sh + status.sh. No Dockerfile — just `docker pull ubuntu:24.04` and `docker exec`.

---

## Why Docker (not just CI)

| Aspect | CI | Docker |
|--------|-----|--------|
| Feedback loop | 5-10 min (push + queue + run) | 30-60 sec (cached base image) |
| Debugging | Read logs after the fact | Drop into shell, poke around live |
| Fresh environment | Every run (but slow) | Every `docker run` (fast) |
| File editing | Edit → commit → push → wait | Edit on host, instantly visible in container |
| Cost | GitHub Actions minutes | Free |

CI still runs on PRs as a merge gate. Docker is for **development iteration** — find and fix bugs before pushing.

---

## Design

### No Dockerfile

The repo files are volume-mounted into a bare Ubuntu container. Nothing is baked in.

```
docker pull ubuntu:24.04
docker run -d --name m -v $(pwd):/src ubuntu:24.04 sleep infinity
docker exec m bash /src/install.sh
```

This works because:
- `-v $(pwd):/src` mounts the repo live — edits on host are instantly visible inside
- Ubuntu 24.04 has bash but no curl/git/node — install.sh must provision everything
- No image build step, no cache to invalidate

### What the container needs

Only three packages (installed via `apt-get` before running install.sh):

```
curl, git, ca-certificates
```

Everything else (Node, uv, npm packages, hermes, pi, mnemon) is provisioned by install.sh. That's the whole point — test that install.sh works from a bare machine.

---

## Script: `docker-test.sh`

Location: `docker-test.sh` (repo root)

### Modes

```bash
# Full test: install + boot + status + CLI checks
./docker-test.sh test

# Interactive: drop into shell for manual debugging
./docker-test.sh shell

# Cleanup: remove the container
./docker-test.sh clean
```

### Test mode flow

```
1. Pull ubuntu:24.04 (if not cached)
2. Remove any existing container named "minions-test"
3. docker run -d --name minions-test -v $(pwd):/src ubuntu:24.04 sleep infinity
4. docker exec: apt-get update && apt-get install -y curl git ca-certificates
5. docker exec: bash /src/install.sh
6. docker exec: bash /src/boot.sh
7. docker exec: bash /src/status.sh
8. docker exec: hermes --version, pi --version, mnemon --version
9. Test LLM call via OmniRoute (keyless via free providers)
10. Print pass/fail summary
```

### Shell mode flow

```
1-4. Same as test mode
5. docker exec -it minions-test bash
   (user is now inside the container with /src mounted read-only)
```

### Clean mode

```
docker rm -f minions-test
```

### What gets tested

| Step | What it proves |
|------|----------------|
| `install.sh` | All components install correctly from zero (Node vendored, npm packages, hermes git install, pi npm, mnemon binary) |
| `boot.sh` | OmniRoute + ModelRelay start, preconfigure, readiness marker created |
| `status.sh` | All components report healthy |
| `hermes --version` | Hermes binary works and is on PATH |
| `pi --version` | Pi-Agent binary works and is on PATH |
| `mnemon --version` | Mnemon binary works |
| LLM call | OmniRoute answers keyless via free providers (model=auto) — `hermes chat -q "Reply with exactly: OK"` works without API keys |

### What does NOT get tested in Docker

- Hermes gateway/dashboard (dropped from v1)
- macOS-specific paths (Docker is Linux)
- LLM inference performance under load

### Known limitations

1. **Network:** Container needs internet for npm/git downloads. Works on local machine; may need proxy config behind corporate firewalls.
2. **Root user:** Docker runs as root by default. Some tools behave differently as root vs regular user. Could add `--user` flag if this becomes an issue.
3. **Ubuntu only:** Tests the Linux path. macOS/Windows are explicitly deferred from v1.

---

## Files to create

| File | Purpose |
|------|---------|
| `_docker/docker-test.sh` | The test script (test / shell / clean modes) |
| `docker-test.sh` | Moved to repo root for convenience |

No Dockerfile. No docker-compose. Just one script.

---

## Next steps

1. Write `docker-test.sh`
2. Test it against current `main` (reproduce the Hermes failure on empty Codespace)
3. Fix whatever breaks
4. Commit to a branch, open PR
