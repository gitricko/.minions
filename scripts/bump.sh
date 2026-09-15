#!/usr/bin/env bash
# bump.sh — deterministic dependency bump (no agent).
# Edits etc/deps.yaml (the single source of truth), then regenerates
# etc/versions.env via scripts/sync-versions.sh. Also regenerates .node-version
# for NODE_VERSION. For tarball deps (NODE/UV), SHA fetching lands next.
#
# Usage: scripts/bump.sh DEP=VERSION [DEP2=VERSION ...] [--dry-run] [--open-pr]
# Env overrides (for hermetic tests): VERSIONS_ENV, DEPS_YAML, NODE_VERSION_FILE.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -z "${DEPS_YAML:-}" ] && DEPS_YAML="${REPO_ROOT}/etc/deps.yaml"
[ -z "${VERSIONS_ENV:-}" ] && VERSIONS_ENV="${REPO_ROOT}/etc/versions.env"
[ -z "${NODE_VERSION_FILE:-}" ] && NODE_VERSION_FILE="${REPO_ROOT}/.node-version"

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

[ -f "${DEPS_YAML}" ] || { echo "missing ${DEPS_YAML}" >&2; exit 1; }

# Preserve versions.env content so dry-run can verify non-mutation.
ORIGINAL_VERSIONS=""
[ "${DRY_RUN}" -eq 1 ] && ORIGINAL_VERSIONS="$(cat "${VERSIONS_ENV:-$(dirname "$DEPS_YAML")/versions.env}" 2>/dev/null || true)"

for b in "${BUMPS[@]}"; do
  dep="${b%%=*}"
  ver="${b##*=}"
  upper=$(echo "$dep" | tr '[:lower:]' '[:upper:]')

  # Validate dep exists in deps.yaml via targeted regex (preserves formatting).
  if ! python3 - "${DEPS_YAML}" "${dep}" <<'PY' >/dev/null 2>&1
import re, sys
text = open(sys.argv[1]).read()
if not re.search(r'\n  - name: '+re.escape(sys.argv[2])+r'\n', text):
    sys.exit(1)
PY
  then
    echo "bump.sh: no ${dep} in ${DEPS_YAML}" >&2
    exit 1
  fi

  if [ "${DRY_RUN}" -eq 1 ]; then
    echo "dry-run: would set ${dep} version to ${ver}"
  else
    # Targeted regex replacement: preserves formatting & comments.
    python3 - "${DEPS_YAML}" "${dep}" "${ver}" <<'PY'
import re, sys
path, dep, ver = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
pattern = rf'(\n  - name: {re.escape(dep)}\n    version: ")[^"]*(")'
if not re.search(pattern, text):
    print(f"bump.sh: failed to set {dep}={ver} (pattern not found)", file=sys.stderr)
    sys.exit(1)
text = re.sub(pattern, rf'\g<1>{ver}\g<2>', text)
open(path, 'w').write(text)
print(f"bumped {dep} -> {ver}")
PY
  fi
done

# D6: keep the CI runner's Node in sync with the vendored one.
if [ "${DRY_RUN}" -eq 0 ] && grep -q '^  - name: NODE' "${DEPS_YAML}"; then
  node_ver=$(python3 - "${DEPS_YAML}" <<'PY'
import sys, yaml
for d in yaml.safe_load(open(sys.argv[1]))['dependencies']:
    if d['name'] == 'NODE':
        print(d['version'])
PY
  )
  echo "${node_ver}" > "${NODE_VERSION_FILE}"
  echo "wrote .node-version -> ${node_ver}"
fi

# Regenerate versions.env from the now-updated deps.yaml.
if [ "${DRY_RUN}" -eq 0 ]; then
  "${REPO_ROOT}/scripts/sync-versions.sh"
fi

if [ "${DRY_RUN}" -eq 1 ]; then
  # Verify nothing was written to versions.env.
  if [ -n "${ORIGINAL_VERSIONS}" ]; then
    current="$(cat "${VERSIONS_ENV:-$(dirname "$DEPS_YAML")/versions.env}" 2>/dev/null || true)"
    if [ "${current}" != "${ORIGINAL_VERSIONS}" ]; then
      echo "bump.sh: BUG: --dry-run modified versions.env!" >&2
      exit 2
    fi
  fi
  echo "dry-run: no files modified."
  exit 0
fi

if [ "${OPEN_PR}" -eq 1 ]; then
  echo "bump.sh: --open-pr not yet implemented (skeleton)."
fi

echo "bump.sh complete."
exit 0