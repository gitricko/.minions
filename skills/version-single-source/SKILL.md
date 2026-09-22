---
name: version-single-source
description: Use when adding a new component dependency or versioning a binary in install/boot scripts.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [versions, dependencies, install, maintainability, deps]
    related_skills: [self-update-fix, ci-debugging]
---

# Single Source of Truth for Component Versions

Every hardcoded version is a maintenance trap. Use the `deps.yaml → versions.env`
pattern for all component version management.

## The rule

**Never hardcode a version in a script file.** Always source it from the
central lockfile (`etc/versions.env`), which is generated from
`etc/deps.yaml` by `scripts/sync-versions.sh`.

## How the pattern works

```
etc/deps.yaml          ←  single source of truth (edit this)
       ↓ sync-versions.sh
etc/versions.env       ←  generated (do not edit; regenerated on every install)
       ↓ . source
lib/*.sh install_*()   ←  uses ${COMPONENT_VERSION}
```

## Adding a new dependency

1. **Add to `etc/deps.yaml`:**
   ```yaml
   dependencies:
     - name: MY_NEW_DEP
       version: "1.2.3"
       source_type: github_tag
       repo: org/repo-name
       sha_source: none
   ```

2. **Re-generate `versions.env`:**
   ```bash
   bash scripts/sync-versions.sh
   ```

3. **In your `lib/` script, source versions.env at the top of the function:**
   ```bash
   # shellcheck disable=SC1091,SC2153
   if [ -f "${MINIONS_HOME}/etc/versions.env" ]; then
       . "${MINIONS_HOME}/etc/versions.env"
   fi
   my_dep_version="${MY_NEW_DEP_VERSION:-1.2.3}"
   ```
   The fallback default (`:-1.2.3`) protects against standalone contexts
   where `versions.env` may not have been copied yet.

4. **Validate:**
   ```bash
   grep MY_NEW_DEP etc/versions.env
   bash -n lib/my-new-dep.sh
   shellcheck lib/my-new-dep.sh
   ```

## Common mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Hardcoded version in `lib/foo.sh` | Bump `deps.yaml` but install still gets old version | Source `versions.env` |
| Missing `sha_source: none` | `sync-versions.sh` tries to fetch checksums and fails | Add explicit `sha_source: none` |
| Source inside function (not top-level) | shellcheck SC2153 "MINIONS_HOME may not be assigned" | Move `. versions.env` to module top-level |
| Omitting shellcheck disable | CI `shellcheck` test fails with SC1091/SC2153 | Add `# shellcheck disable=SC1091,SC2153` above the source line |

## Real-world example

`lib/mnemon.sh` hardcoded `mnemon_version="0.2.5"` (4 releases behind
`0.2.9`), while `etc/versions.env` had `MNEMON_VERSION="0.2.9"`. The
installer still *worked* (download succeeded), but installed a stale
version silently. Fix: source `versions.env` at module top-level, use
`${MNEMON_VERSION:-0.2.9}` with a fallback default.