#!/usr/bin/env bash
# bump.sh — deterministic dependency bump (no agent).
# Edits etc/deps.yaml (the single source of truth), then regenerates
# etc/versions.env via scripts/sync-versions.sh. Also regenerates .node-version
# for NODE_VERSION.
#
# SHA integrity (D8): tarball deps (NODE/UV) get their real SHA256 fetched
# from upstream during --open-pr (the real self-update path). Bare bumps
# (used by hermetic tests) leave sha256 untouched. Guardrails:
#   - npm deps + MINIONS/HERMES use sha_source: none (no fetch).
#   - Platform -> asset naming is embedded; override base via SHA_FETCH_BASE.
#
# Usage: scripts/bump.sh DEP=VERSION [DEP2=VERSION ...] [--dry-run] [--open-pr]
# Env overrides (for hermetic tests): VERSIONS_ENV, DEPS_YAML, NODE_VERSION_FILE, SHA_FETCH_BASE.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -z "${DEPS_YAML:-}" ] && DEPS_YAML="${REPO_ROOT}/etc/deps.yaml"
[ -z "${VERSIONS_ENV:-}" ] && VERSIONS_ENV="${REPO_ROOT}/etc/versions.env"
[ -z "${NODE_VERSION_FILE:-}" ] && NODE_VERSION_FILE="${REPO_ROOT}/.node-version"

OPEN_PR=0
DRY_RUN=0
BUMPS=()

# populate_shas <dep> — fetch real SHA256 for tarball deps (NODE/UV)
# from upstream and update deps.yaml's sha256 map. Runs only in --open-pr
# mode (real self-update). base_override (SHA_FETCH_BASE) lets hermetic
# tests read from a local fixture dir instead of the network.
#
# sha_source behaviour:
#   shasums        -> NODE: parse SHASUMS256.txt for node-v{V}-{os}-{arch}.tar.xz
#   release_assets -> UV: read `{asset}.sha256` (whole file is the digest)
#   none           -> no fetch
populate_shas() {
  local dep="$1" sha_source base
  sha_source=$(python3 - "${DEPS_YAML}" "${dep}" <<'PY'
import sys, yaml
for d in yaml.safe_load(open(sys.argv[1]))['dependencies']:
    if d['name'] == sys.argv[2]:
        print(d.get('sha_source', 'none')); break
PY
)
  if [ -z "${sha_source}" ] || [ "${sha_source}" = "none" ]; then
    return 0
  fi
  base="${SHA_FETCH_BASE:-}"
  python3 - "${DEPS_YAML}" "${dep}" "${base}" <<'PY'
import re, sys, urllib.request, yaml
path, dep, base_override = sys.argv[1], sys.argv[2], sys.argv[3]

def load(rel):
    # rel is the file basename (e.g. SHASUMS256.txt or uv-X.tar.gz.sha256).
    # In test mode base_override maps it to a local fixture; else fetch upstream.
    if base_override:
        with open(base_override.rstrip('/') + '/' + rel) as f:
            return f.read()
    return urllib.request.urlopen(release_url + rel, timeout=30).read().decode()

# platform key -> (os_segment, asset_file) resolved from deps.yaml release_url
depdata = next(d for d in yaml.safe_load(open(path))['dependencies'] if d['name'] == dep)
ver = depdata['version']
sha_source = depdata['sha_source']
release_url = depdata.get('release_url', '').replace('{{VERSION}}', ver)
platforms = depdata.get('platforms', [])

# platform key (e.g. linux_x64, macos_arm64) -> node os segment
def node_os(plat):
    return 'darwin' if plat.startswith('macos') else 'linux'
# platform key -> uv rust target (must match lib/detect.sh get_download_url)
UV_TARGET = {
    'linux_x64': 'x86_64-unknown-linux-gnu',
    'linux_arm64': 'aarch64-unknown-linux-gnu',
    'macos_x64': 'x86_64-apple-darwin',
    'macos_arm64': 'aarch64-apple-darwin',
}

result = {}
for plat in platforms:
    arch = plat.split('_', 1)[1]
    try:
        if sha_source == 'shasums':
            fname = f"node-v{ver}-{node_os(plat)}-{arch}.tar.xz"
            text = load('SHASUMS256.txt')
            m = re.search(r'^([0-9a-f]{64})\s+' + re.escape(fname) + r'$', text, re.M)
            if not m:
                print(f"bump.sh: SHA not found for {plat} ({fname})", file=sys.stderr)
                continue
            result[plat] = m.group(1)
        elif sha_source == 'release_assets':
            target = UV_TARGET.get(plat)
            if not target:
                continue
            asset = f"uv-{target}.tar.gz"
            text = load(asset + '.sha256')
            m = re.match(r'^([0-9a-f]{64})', text)
            if not m:
                print(f"bump.sh: SHA not parsed for {plat} ({asset})", file=sys.stderr)
                continue
            result[plat] = m.group(1)
        else:
            break
    except Exception as e:
        print(f"bump.sh: SHA fetch failed for {plat}: {e}", file=sys.stderr)

if not result:
    print(f"bump.sh: could not fetch SHAs for {dep} {ver}; leaving placeholder", file=sys.stderr)
    sys.exit(1)

# Update deps.yaml sha256 map for this dep, preserving formatting (region edit).
text = open(path).read()
sm = re.search(rf'\n  - name: {re.escape(dep)}\n', text)
if not sm:
    print(f"bump.sh: deps.yaml entry for {dep} missing before sha write", file=sys.stderr)
    sys.exit(1)
start = sm.end()
em = re.search(r'\n  - name: ', text[start:])
end = start + em.start() if em else len(text)
block = text[start:end]
# ensure a `sha256:` map exists
if not re.search(r'\n    sha256:\n', block):
    block += '\n    sha256:\n'
for plat, sha in result.items():
    pm = re.search(rf'\n      {re.escape(plat)}: "[^"]*"', block)
    if pm:
        block = block[:pm.start()] + f'\n      {plat}: "{sha}"' + block[pm.end():]
    else:
        block = block.rstrip('\n') + f'\n      {plat}: "{sha}"\n'
text = text[:start] + block + text[end:]
open(path, 'w').write(text)
print(f"bump.sh: wrote SHA256 for {dep} {ver} ({len(result)} platforms)")
PY
}

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

  # D8: in --open-pr (real self-update) mode, fetch real SHAs for tarball deps.
  if [ "${OPEN_PR}" -eq 1 ]; then
    if ! populate_shas "${dep}"; then
      echo "bump.sh: SHA fetch failed for ${dep}; aborting (leaves PR for fix-loop/human)" >&2
      exit 1
    fi
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
  echo "bump.sh: opened PR not yet implemented (see self-update.yml)."
fi

echo "bump.sh complete."
exit 0