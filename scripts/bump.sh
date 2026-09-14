#!/usr/bin/env bash
# bump.sh — deterministic dependency bump (no agent).
# Edits etc/versions.env, regenerates .node-version for NODE_VERSION, and for
# tarball deps (NODE/UV) fetches + writes real SHA256 for the pinned platforms.
# Opens a single batch PR, one commit per dependency.
#
# Currently implements the hermetically-testable core: parse args, bump the
# version line(s) in versions.env, regenerate .node-version. PR/commit glue and
# SHA fetching land in the next iteration.
#
# Usage: scripts/bump.sh DEP=VERSION [DEP2=VERSION ...] [--dry-run] [--open-pr]
# Env overrides (for hermetic tests): VERSIONS_ENV, NODE_VERSION_FILE.

set -u

[ -z "${VERSIONS_ENV:-}" ] && VERSIONS_ENV="$(cd "$(dirname "$0")/../etc" && pwd)/versions.env"
[ -z "${NODE_VERSION_FILE:-}" ] && NODE_VERSION_FILE="$(cd "$(dirname "$0")/.." && pwd)/.node-version"

OPEN_PR=0
DRY_RUN=0
BUMPS=()

for arg in "$@"; do
  case "$arg" in
    --open-pr) OPEN_PR=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *=*) BUMPS+=("$arg") ;;
    *) echo "bump.sh: unknown arg '$arg'" >&2; exit 1 ;;
  esac
done

[ "${#BUMPS[@]}" -gt 0 ] || {
  echo "usage: bump.sh DEP=VERSION [...] [--dry-run] [--open-pr]" >&2
  exit 1
}

[ -f "${VERSIONS_ENV}" ] || { echo "missing ${VERSIONS_ENV}" >&2; exit 1; }

# Preserve content for later idempotency check (dry-run must not write).
ORIGINAL=""
[ "${DRY_RUN}" -eq 1 ] && ORIGINAL="$(cat "${VERSIONS_ENV}")"

for b in "${BUMPS[@]}"; do
  dep="${b%%=*}"
  ver="${b##*=}"
  upper=$(echo "$dep" | tr '[:lower:]' '[:upper:]')
  # Guard: only bump a known <X>_VERSION line.
  if ! grep -Eq "^${upper}_VERSION=" "${VERSIONS_ENV}"; then
    echo "bump.sh: no ${upper}_VERSION in ${VERSIONS_ENV}" >&2
    exit 1
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    echo "dry-run: would set ${upper}_VERSION=${ver}"
  else
    sed -i "s|^${upper}_VERSION=.*|${upper}_VERSION=\"${ver}\"|" "${VERSIONS_ENV}"
    echo "bumped ${upper}_VERSION -> ${ver}"
  fi
done

# D6: keep the CI runner's Node in sync with the vendored one.
if [ "${DRY_RUN}" -eq 0 ] && grep -q '^NODE_VERSION=' "${VERSIONS_ENV}"; then
  # shellcheck source=/dev/null
  . "${VERSIONS_ENV}"
  echo "${NODE_VERSION}" > "${NODE_VERSION_FILE}"
  echo "wrote .node-version -> ${NODE_VERSION}"
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  # Verify nothing was written.
  if [ "$(cat "${VERSIONS_ENV}")" != "${ORIGINAL}" ]; then
    echo "bump.sh: BUG: --dry-run modified versions.env!" >&2
    exit 2
  fi
  echo "dry-run: no files modified."
  exit 0
fi

if [ "${OPEN_PR}" -eq 1 ]; then
  # TODO: one commit per dep, gh pr create on an update branch.
  echo "bump.sh: --open-pr not yet implemented (skeleton)."
fi

echo "bump.sh complete."
exit 0