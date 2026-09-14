#!/usr/bin/env bash
# check-updates.sh — read-only dependency freshness report.
# Sources etc/versions.env (current pins) + etc/deps.yaml (how to check each)
# and reports which are outdated. Never writes, never opens a PR.
#
# Only the SMALLEST guaranteed contract is implemented here (skeleton).
# The per-source adapters (github_tag / npm / release_tarball) land in v2.
#
# Usage: scripts/check-updates.sh [--json] [--offline]
# Env overrides (for hermetic tests): VERSIONS_ENV, DEPS_YAML.

set -u

# Resolve paths, honoring env overrides so tests can point at temp fixtures.
[ -z "${VERSIONS_ENV:-}" ] && VERSIONS_ENV="$(cd "$(dirname "$0")/../etc" && pwd)/versions.env"
[ -z "${DEPS_YAML:-}" ] && DEPS_YAML="$(cd "$(dirname "$0")/../etc" && pwd)/deps.yaml"

JSON=0
OFFLINE=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --offline) OFFLINE=1 ;;
  esac
done

[ -f "${VERSIONS_ENV}" ] || { echo "missing ${VERSIONS_ENV}" >&2; exit 1; }
[ -f "${DEPS_YAML}" ] || { echo "missing ${DEPS_YAML}" >&2; exit 1; }

# shellcheck source=/dev/null
. "${VERSIONS_ENV}"

if [ "${JSON}" -eq 1 ]; then
  # Guaranteed machine-readable contract (skeleton: no live adapters yet).
  printf '{"catalog":"%s","outdated":[],"note":"source adapters TODO"}\n' "${DEPS_YAML}"
else
  echo "check-updates.sh (skeleton): catalog ${DEPS_YAML}"
  echo "source adapters (npm/github_tag/release_tarball) not yet implemented."
fi

exit 0