# Local Docker Testing with `dts`

The `.minions` install/boot/verify loop, run in a throwaway container. This replaces the old `docker-test.sh` — the generic [docker-test-shell (`dts`)] skill is now the single source of truth, and this file is the `.minions`-specific recipe (deps, flow, and the long-install pattern).

## Why

- CI is the merge gate, but its feedback loop is 5-10 min per push.
- `dts` gives the same fresh-environment validation locally in ~1-5 min, with dev-prod parity (uid-1000, `bash -l`, same `ubuntu:24.04` base as CI's `ubuntu-latest`).
- Never trust the host: stale `~/.minions`, leftover services, and cached packages mask fresh-install bugs. Only a clean container proves `install.sh`/`boot.sh` work from zero.

## Prereqs (the container)

`dts` spins up a bare `ubuntu:24.04` — it installs NOTHING. `.minions` needs these apt packages inside the container before `install.sh`:

```bash
dts apt "curl git ca-certificates xz-utils g++ make sqlite3 python3 python3-yaml"
```

| Package | Why |
|---------|-----|
| `curl` | download Node.js, npm packages, hermes install script |
| `git` | clone hermes / pi / mnemon |
| `ca-certificates` | HTTPS works |
| `xz-utils` | Node.js `.tar.xz` extraction |
| `g++ make` | Hermes `node-pty` native compilation (silently fails without) |
| `sqlite3` | omniRoute storage (login-off writes sqlite) |
| `python3 python3-yaml` | `hermes_update_config` YAML manipulation |

Run this ONCE per container (after `dts up`). It needs root — that's what `dts apt` is for.

## Standard flow

```bash
cd <repo>                                  # repo is bind-mounted at /src
export PATH="<hermes-codespace>/.devcontainer/skills/docker-test-shell/scripts:$PATH"

dts up                                     # fresh container, repo at /src, uid-1000
dts apt "curl git ca-certificates xz-utils g++ make sqlite3 python3 python3-yaml"
dts exec "bash /src/install.sh"            # install.sh ALWAYS runs from /src
dts exec "bash -l /home/ubuntu/.minions/boot.sh"   # boot.sh runs from MINIONS_HOME
```

Verify:

```bash
dts exec 'export PATH="/home/ubuntu/.minions/bin:/home/ubuntu/.minions/lib/node/bin:$PATH"; curl -s http://127.0.0.1:20128/healthz'   # → ok
dts exec 'export PATH="/home/ubuntu/.minions/bin:/home/ubuntu/.minions/lib/node/bin:$PATH"; timeout 15 omniroute combo list'          # → auto-fastest, enabled
dts exec 'export PATH="/home/ubuntu/.minions/bin:/home/ubuntu/.minions/lib/node/bin:$PATH"; omniroute --version'                        # → 3.8.50
```

Cleanup:

```bash
dts clean
```

## Long installs/boots: run them detached (`dts exec 'nohup ...'`)

A full `install.sh` + `boot.sh` takes several minutes (npm resolving the big omniRoute 3.8.x tree, hermes compile). If you run it as a plain foreground `dts exec`, it can get SIGTERM'd (exit 143 / "Terminated") when the driving process ends, and a `pkill -f install.sh` on the host will match your own exec command line and kill your own pipeline.

**Detach the long-running part with `nohup`** so no signal path reaches it, write to a log, then poll progress with short separate `dts exec` calls:

```bash
dts exec 'nohup bash -c "bash /src/install.sh > /home/ubuntu/install.log 2>&1; \
  echo INSTALL_EXIT=$? >> /home/ubuntu/install.log; \
  bash -l /home/ubuntu/.minions/boot.sh >> /home/ubuntu/boot.log 2>&1; \
  echo BOOT_EXIT=$? >> /home/ubuntu/boot.log" >/dev/null 2>&1 & echo launched'
```

Then poll (foreground, short):

```bash
sleep 120
dts exec 'grep -E "omniroute@|installed and verified|INSTALL_EXIT|Terminated|Killed" /home/ubuntu/install.log | tail -5'
dts exec 'tail -5 /home/ubuntu/boot.log; grep BOOT_EXIT /home/ubuntu/boot.log'
```

**Rules for long runs:**
- Wrap the pipeline in `nohup bash -c '...' &` — fully detaches the child from the exec session.
- Log to a file (`install.log` / `boot.log`), not stdout, so the detach doesn't lose output.
- Poll with separate short `dts exec` calls; never `pkill -f 'install.sh'` (matches your own pipeline).

## Tips

- **Verify the mount once** if anything looks stale: compare `md5sum <repo>/install.sh` on host vs `md5sum /src/install.sh` in container — must match.
- **Never run test commands as root** (`docker exec -u 0:0`) — root masks the permission bugs that would fail in CI/Codespace. Root is only for `dts apt` or explicit inspection (sqlite, stuck processes).
- **Interactive debugging**: `dts shell` drops you into an interactive terminal.
- **CI parity**: CI's `real-install` job does the same install+boot+CLI sequence in `ubuntu-latest` — if it works under `dts` locally it should pass CI, and vice versa.

## See also

- The `docker-test-shell` skill (`SKILL.md` + `references/dts-usage.md`) — full command reference, golden rules, pitfalls.
- `tests/test_install.sh`, `tests/test_boot.sh`, `tests/test_cli_integration.sh` — what CI runs (the assertions to aim for locally).
- `docs/DOCKER-TEST-LEARNINGS.md` — universal install/boot pitfalls with root causes.

[docker-test-shell (`dts`)]: https://github.com/gitricko/hermes-codespace/tree/main/.devcontainer/skills/docker-test-shell
