#!/usr/bin/env bash
# check-updates.sh — read-only dependency freshness report.
# Reads the current pin from etc/deps.yaml (the single source of truth),
# queries upstream via source-specific adapters, and reports outdated deps.
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

python3 - "${DEPS_YAML}" "${OFFLINE}" <<'PY'
import sys, yaml, json, urllib.request, urllib.parse, re
from urllib.error import URLError, HTTPError

deps_yaml, offline = sys.argv[1], sys.argv[2] == "1"
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

def latest_github_tag(repo, selector=None):
    """Query GitHub API tags for repo. Filter by selector (glob). Return latest version string."""
    url = f"https://api.github.com/repos/{repo}/tags?per_page=100"
    tags = fetch_json(url)
    if not tags:
        return None
    names = [t.get('name','') for t in tags if isinstance(t, dict)]
    if selector:
        # Simple glob: convert 'v20*' to regex 'v20.*'
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

print(json.dumps({'catalog': deps_yaml, 'outdated': report}, indent=2))
PY

exit 0