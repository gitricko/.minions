---
name: shell-path-login
description: Use when a binary or script works in one shell context but not another (interactive vs non-interactive login vs non-login shell).
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [shell, path, login-shell, bash, environment]
    related_skills: [ci-debugging, docker-test-shell]
---

# Shell PATH & Login-Shell Debugging

When a command "works in my terminal" but not in CI, cron, or a container,
the usual culprit is which shell startup files got sourced.

## The 3 shell contexts

| Shell context | Sources | Typical invocation |
|---------------|---------|-------------------|
| Interactive login | `~/.bash_profile`, then `~/.profile` (which sources `~/.bashrc`) | `bash -l`, SSH login |
| Interactive non-login | `~/.bashrc` only | new terminal tab |
| Non-interactive (script, CI, docker exec) | **Neither** by default | `bash script.sh`, `docker exec` |

Key trap: `~/.bashrc` starts with an interactive-check guard:

```bash
case $- in
    *i*) ;;            # interactive — continue
      *) return;;      # non-interactive — EXITS EARLY
esac
```

Anything you `export` or `PATH=` after that guard (e.g. the installer's
PATH snippet) **never runs in non-interactive shells**. That's why a binary
"works in my terminal" but not in `dts exec` or CI.

## Diagnosis checklist

```bash
# 1. Which shells find the binary?
which <bin>                    # current shell
bash -l -c 'which <bin>'       # login shell
bash -c 'which <bin>'          # non-interactive
env -i PATH="$PATH" bash -c 'echo $PATH'   # clean env

# 2. What's actually in the startup files?
cat ~/.bashrc | tail -10       # look for PATH exports AFTER the interactive guard
cat ~/.profile  | tail -10     # sourced by ALL login shells
grep -n "PATH=" ~/.bashrc ~/.profile

# 3. Does a login shell pick it up?
bash -l -c 'echo "PATH=$PATH"'
```

## Canonical fixes

1. **Add the PATH snippet to `~/.profile`** (runs for all login shells):
   ```bash
   # ~/.profile
   export PATH="$HOME/.minions/bin:$PATH"
   ```
   This is the single most robust fix for "works interactively, not in CI".

2. **Make the CI/test invocation a login shell** if the environment allows:
   ```bash
   docker exec ... bash -l -c "your-command"
   ```

3. **Export the PATH explicitly at the top of the script** that needs it
   (self-contained, most reliable):
   ```bash
   export PATH="${HOME}/.minions/bin:${PATH}"
   ```

## Installer lesson

When `install.sh` adds a PATH snippet, add it to **all three** of
`~/.bashrc`, `~/.zshrc`, **and** `~/.profile`. The `.profile` entry is what
makes it work in non-interactive login contexts (cron, `docker exec -l`,
CI jobs that source login shells).

## CLI wrappers vs shell aliases

Prefer a `bin/<wrapper>` executable on `PATH` over a shell alias. Aliases only work in interactive shells — scripts, `make`, CI steps, `ssh host cmd`, and `sudo` never inherit them, so users get "command not found" in non-interactive contexts.

- Ship `~/.minions/bin/ts` (or similar) as a POSIX `sh` wrapper that execs the real binary with the correct flags. `PATH` already contains `~/.minions/bin`, so the wrapper works immediately without reloading a shell.
- Do not add an `alias ts=...` to rc files when a wrapper exists — it is redundant and misleading. If an alias already shipped, remove it and keep only the wrapper.

## Socket and tilde pitfalls

- `--flag=~/path` does not expand `~`. `~` only expands at the start of a word or after `:` in `PATH`-like assignments; `--socket=~/.minions/...` is not an assignment, so the binary dials a literal `~` path and fails with "no such file". Always use `$HOME` or `$MINIONS_HOME` (`--socket="$HOME/.minions/..."`).
- Some CLIs ignore their env var for socket selection (e.g. Tailscale `v1.104.1` ignores `TAILSCALE_SOCKET`). Verify with a live probe: `ENV=... bin status` failing while `bin --socket=... status` succeeds proves the env is ignored — fix probes to use the flag.
- Wrapper socket resolution: use `${MINIONS_HOME:-$HOME/.minions}/var/run/<sock>` not `$HOME` alone — `$HOME` may not match the daemon's home in CI, `ssh`, or `sudo` contexts where `MINIONS_HOME` is the exported canonical path.
- Always pass `--socket` in the wrapper; do not gate on `[ -S "$SOCK" ]` then fall back to the default. The socket can disappear between the check and the exec, causing a silent fallback to the wrong path. Let the CLI fail explicitly if the socket is gone.

## Real-world example

`mnemon` was installed by `.minions` to `~/.minions/bin/mnemon` with a
symlink, but `self-check.sh` reported "mnemon not found in PATH". The
installer only appended the PATH snippet to `~/.bashrc` — after the
interactive guard — so `dts exec` (non-interactive `bash -l -c`) never
sourced it. Fix: add the same snippet to `~/.profile`, which all login
shells source regardless of interactivity.