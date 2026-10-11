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

## The 4-file sync invariant

`deps.yaml` is the single source of truth. Three derived files must stay in sync — CI enforces this as blocking:

| Derived file | Generator | CI job |
|--------------|-----------|--------|
| `etc/versions.env` | `scripts/sync-versions.sh` | `version-sync` |
| `.node-version` | `scripts/sync-versions.sh` (NODE entry) | `version-sync` |
| `README.md` badges | `scripts/sync-readme-badges.sh` | `version-sync` (badge check) |

After editing `deps.yaml`, always run both generators before committing:

```bash
bash scripts/sync-versions.sh
bash scripts/sync-readme-badges.sh
bash scripts/sync-versions.sh --check && bash scripts/sync-readme-badges.sh --check
```

## Fixing dependency drift (advisory CI failure)

`dependency-drift` is advisory (`continue-on-error: true`) — it queries upstream (GitHub tags / npm) and fails when a pin is behind `latest`. Fix with `bump.sh --open-pr`, which fetches real SHA256 for tarball deps (NODE/UV) and regenerates derived files:

```bash
bash scripts/check-updates.sh --json  # identify outdated dep
bash scripts/bump.sh DEP=VERSION --open-pr  # e.g. NODE=v26.11.0 — strips leading v for release_tarball, fetches SHASUMS256.txt
bash scripts/sync-readme-badges.sh       # bump.sh syncs versions.env + .node-version; badges need separate step
bash scripts/check-updates.sh --json     # verify 0 outdated
```

For release_tarball deps the pin omits the leading `v` (URL template already embeds it); github_tag deps keep it.

## Common mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Hardcoded version in `lib/foo.sh` | Bump `deps.yaml` but install still gets old version | Source `versions.env` |
| Missing `sha_source: none` | `sync-versions.sh` tries to fetch checksums and fails | Add explicit `sha_source: none` |
| Source inside function (not top-level) | shellcheck SC2153 "MINIONS_HOME may not be assigned" | Move `. versions.env` to module top-level |
| Omitting shellcheck disable | CI `shellcheck` test fails with SC1091/SC2153 | Add `# shellcheck disable=SC1091,SC2153` above the source line |
| Bumped `deps.yaml` but forgot derived files | `version-sync` fails "badges/versions.env out of date" | Run both `sync-versions.sh` and `sync-readme-badges.sh` |
| Ran `bump.sh` without `--open-pr` for NODE/UV | SHA256 placeholders stale, install fetches wrong tarball | Use `--open-pr` so `populate_shas` fetches real SHAs |
| Deferred pin for an opt-in dep ("pin later") | Latest drifts silently, `version-sync` passes but installed version unauditable | Pin every managed binary in `deps.yaml` even if install is opt-in (`--tailscale` still needs `TAILSCALE_VERSION`) |
| Used `curl \| sh` latest for a dep that releases static tarballs on a separate host (e.g. `pkgs.tailscale.com`) | GitHub Releases has no assets, `sha_source: none` + `github_tag` is correct — tarball pin via `release_tarball` only if you actually fetch from GitHub | Verify upstream release layout first: if tarballs live off-GitHub, keep `github_tag`/`sha_source: none` and fetch from the vendor host with a `TAILSCALE_VERSION` pin |

## Real-world example

`lib/mnemon.sh` hardcoded `mnemon_version="0.2.5"` (4 releases behind
`0.2.9`), while `etc/versions.env` had `MNEMON_VERSION="0.2.9"`. The
installer still *worked* (download succeeded), but installed a stale
version silently. Fix: source `versions.env` at module top-level, use
`${MNEMON_VERSION:-0.2.9}` with a fallback default.