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

## Real-world example

`mnemon` was installed by `.minions` to `~/.minions/bin/mnemon` with a
symlink, but `self-check.sh` reported "mnemon not found in PATH". The
installer only appended the PATH snippet to `~/.bashrc` — after the
interactive guard — so `dts exec` (non-interactive `bash -l -c`) never
sourced it. Fix: add the same snippet to `~/.profile`, which all login
shells source regardless of interactivity.