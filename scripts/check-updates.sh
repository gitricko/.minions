#!/usr/bin/env bash
# check-updates.sh — read-only dependency freshness report.
# Reads the current pin from etc/deps.yaml (the single source of truth),
# compares against upstream (adapters in v2), and reports outdated deps.
# Never writes, never opens a PR.
#
# Usage: scripts/check-updates.sh [--json] [--offline]
# Env overrides (for hermetic tests): VERSIONS_ENV, DEPS_YAML.

set -u
[ -z "${DEPS_YAML:-}" ] && DEPS_YAML="$(cd "$(dirname "$0")/../etc" && pwd)/deps.yaml"

JSON=0
OFFLINE=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --offline) OFFLINE=1 ;;
  esac
done

[ -f "${DEPS_YAML}" ] || { echo "missing ${DEPS_YAML}" >&2; exit 1; }

if [ "${JSON}" -eq 1 ]; then
  # Machine-readable report: each dep with its current pin (from deps.yaml)
  # and a note that live upstream adapters are pending (v2).
  python3 - "${DEPS_YAML}" <<'PY'
import sys, yaml, json
data = yaml.safe_load(open(sys.argv[1]))
report = []
for d in data['dependencies']:
    report.append({
        'name': d['name'],
        'version': d['version'],
        'source_type': d['source_type'],
        'outdated': None  # upstream adapters pending (v2)
    })
print(json.dumps({'catalog': sys.argv[1], 'outdated': report}, indent=2))
PY
else
  echo "check-updates.sh: catalog ${DEPS_YAML}"
  echo "Reading current pins from deps.yaml. Upstream adapters (v2) pending."
fi

exit 0