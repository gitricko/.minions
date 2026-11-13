#!/usr/bin/env bash
# check-updates.sh — read-only dependency freshness report.
# Reads the current pin from etc/deps.yaml (the single source of truth),
# queries upstream via source-specific adapters, and reports outdated deps.
# Never writes, never opens a PR.
#
# Usage: scripts/check-updates.sh [--json] [--report] [--offline]
#   Output is always JSON; --json is accepted for CLI compatibility and
#   is a no-op. --offline skips upstream fetches (each "latest" => null).
#   Gating contract: --report exits 1 when any pin has an upstream update,
#   otherwise 0. CI advisory jobs and humans share this one rendering path
#   so reporting and gating can never disagree.
# Env override for hermetic tests: DEPS_YAML.

set -u
[ -z "${DEPS_YAML:-}" ] && DEPS_YAML="$(cd "$(dirname "$0")/../etc" && pwd)/deps.yaml"

OFFLINE=0
REPORT=0
for arg in "$@"; do
  case "$arg" in
    --json) ;; # output is always JSON; accepted for CLI compatibility
    --offline) OFFLINE=1 ;;
    --report) REPORT=1 ;;
    *) echo "usage: check-updates.sh [--json] [--report] [--offline]" >&2; exit 2 ;;
  esac
done

[ -f "${DEPS_YAML}" ] || { echo "missing ${DEPS_YAML}" >&2; exit 1; }

run_core() {
  local extra=${1:-}
  python3 - "${DEPS_YAML}" "${OFFLINE}" "${extra}" <<'PY'
import sys, yaml, json, urllib.request, urllib.parse, re
from urllib.error import URLError, HTTPError

deps_yaml, offline, report_mode = sys.argv[1], sys.argv[2] == "1", (sys.argv[3] == "report")
data = yaml.safe_load(open(deps_yaml))

def semver_tuple(v):
    """Normalize 'v1.2.3' -> (1,2,3) for comparison. Returns None if unparsable."""
    s = str(v).lstrip('v').strip()
    try:
        return tuple(int(x) for x in re.split(r'[.]', s)[:3])
    except (ValueError, TypeError):
        return None

def fetch_json(url):
    """Fetch a JSON URL via urllib. Returns None on failure."""
    if offline:
        return None
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'minions-self-update/1.0'})
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except (URLError, HTTPError, json.JSONDecodeError, Exception):
        return None

def fetch_text(url):
    """Fetch a text URL via urllib. Returns None on failure."""
    if offline:
        return None
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'minions-self-update/1.0'})
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read().decode()
    except Exception:
        return None

def latest_github_tag(repo, selector=None):
    """Query GitHub API tags for repo. Filter by selector (glob). Return latest version string."""
    url = f"https://api.github.com/repos/{repo}/tags?per_page=100"
    tags = fetch_json(url)
    if not tags:
        return None
    names = [t.get('name','') for t in tags if isinstance(t, dict)]
    if selector:
        # Simple glob: convert 'v0*' to regex 'v0.*'
        pattern = selector.replace('*', '.*').replace('?', '.')
        names = [n for n in names if re.fullmatch(pattern, n)]
    # Sort by semver tuple, take newest
    parsed = [(semver_tuple(n), n) for n in names if semver_tuple(n) is not None]
    parsed.sort(key=lambda x: x[0], reverse=True)
    return parsed[0][1] if parsed else (names[0] if names else None)

def latest_npm(package, channel):
    """Query npm registry for latest version of pkg@channel."""
    url = f"https://registry.npmjs.org/{urllib.parse.quote(package, safe='')}/{channel}"
    d = fetch_json(url)
    if not d:
        return None
    return d.get('version') or d.get('dist-tags', {}).get(channel)

def latest_release_tarball(repo, selector=None):
    """Release_tarball uses the same GitHub tags query as github_tag.
    When selector is None/empty, consider all tags (no filter)."""
    return latest_github_tag(repo, selector)

def latest_package_index(url, asset_pattern):
    """Return the newest semver embedded in a vendor package index."""
    text = fetch_text(url)
    if not text:
        return None
    versions = re.findall(asset_pattern, text)
    parsed = [(semver_tuple(v), v) for v in versions if semver_tuple(v) is not None]
    return max(parsed, key=lambda x: x[0])[1] if parsed else None

def is_outdated(current, latest):
    """Compare current vs latest version strings. Return True if latest > current."""
    if not latest or not current:
        return None
    c, l = semver_tuple(current), semver_tuple(latest)
    if c is None or l is None:
        return None
    return l > c

report = []
for dep in data['dependencies']:
    # Skip drift check for dependencies we control (e.g., MNEMON)
    if dep.get('drift_check') is False:
        continue
    name = dep['name']
    version = dep['version']
    source_type = dep['source_type']
    latest = None

    try:
        if source_type == 'github_tag':
            latest = latest_github_tag(dep['repo'], dep.get('selector'))
        elif source_type == 'npm':
            latest = latest_npm(dep['package'], dep.get('channel', 'latest'))
        elif source_type == 'release_tarball':
            if dep.get('latest_source') == 'package_index':
                latest = latest_package_index(
                    dep['latest_url'], dep['latest_asset_pattern'])
            else:
                latest = latest_release_tarball(dep['repo'], dep.get('selector'))
    except Exception as e:
        latest = None

    report.append({
        'name': name,
        'version': version,
        'source_type': source_type,
        'latest': latest,
        'outdated': is_outdated(version, latest)
    })

if report_mode:
    width = max((len(r['name']) for r in report), default=3)
    print(f'{"DEP".ljust(width)}  {"PINNED".ljust(16)}  {"LATEST".ljust(16)}  STATE')
    stale = []
    for r in report:
        if r['latest'] is None:
            state = 'UNKNOWN (upstream query failed)'
        elif r['outdated']:
            state = 'OUTDATED'
            stale.append(r)
        else:
            state = 'current'
        print(f'{r["name"].ljust(width)}  {str(r["version"]).ljust(16)}  {str(r["latest"]).ljust(16)}  {state}')
    if stale:
        print(f'\n{len(stale)} dependency/dependencies have upstream updates:')
        for r in stale:
            print(f'  {r["name"]}: {r["version"]} -> {r["latest"]}')
        print('\nThis job is advisory. To apply them: scripts/admin-update.sh')
    else:
        print('\nAll dependencies are current.')
    # Gating from the same computation as the table, not a grep of its text.
    sys.exit(1 if stale else 0)
else:
    print(json.dumps({'catalog': deps_yaml, 'outdated': report}, indent=2))
PY
}

if [ "${REPORT}" -eq 1 ]; then
  # One pass: python renders the table AND sets the exit code from the same
  # computation, so reporting and gating cannot disagree. Output streams
  # straight through — a traceback still reaches the CI log.
  run_core report
  exit $?
fi

run_core
exit 0