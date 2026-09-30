#!/usr/bin/env bash
# sync-readme-badges.sh — rewrite shields.io version pills in README.md from
# etc/deps.yaml. deps.yaml is the SINGLE SOURCE OF TRUTH, so the README never
# drifts from the installed versions after an admin-update.sh run.
#
# Usage: scripts/sync-readme-badges.sh [--check]
#   --check: exit non-zero if README badges would differ (CI guard).
#
# Deps with no matching badge are left untouched (e.g. MINIONS, which has no
# pill of its own). Versions render without a leading "v" (deps.yaml may pin
# "v2026.9.24").

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_YAML="${DEPS_YAML:-${REPO_ROOT}/etc/deps.yaml}"
README="${README:-${REPO_ROOT}/README.md}"

[ -f "${DEPS_YAML}" ] || { echo "missing ${DEPS_YAML}" >&2; exit 1; }
[ -f "${README}" ] || { echo "missing ${README}" >&2; exit 1; }

if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "sync-readme-badges.sh: python3 + pyyaml required (install python3-yaml)" >&2
  exit 1
fi

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

python3 - "${DEPS_YAML}" "${README}" "${CHECK}" <<'PY'
import re, sys, yaml

deps = yaml.safe_load(open(sys.argv[1]))
path = sys.argv[2]
check = sys.argv[3] == "1"
readme = open(path).read()
drift = []

# dep name -> shields.io badge label
LABELS = {
    'HERMES': 'Hermes%20Agent',
    'PI': 'PI%20Agent',
    'OMNIROUTE': 'OmniRoute',
    'NINEROUTER': '9Router',
    'MNEMON': 'Mnemon',
    'NODE': 'Node.js',
    'UV': 'uv',
}

for dep in deps['dependencies']:
    label = LABELS.get(dep['name'])
    if not label:
        continue
    version = dep['version'].lstrip('v')
    pattern = re.compile(r'(badge/%s-)([^-]+)(-)' % re.escape(label))
    new_readme, n = pattern.subn(lambda m: m.group(1) + version + m.group(3), readme)
    if n:
        if new_readme != readme:
            drift.append((dep['name'], version))
        readme = new_readme
    else:
        print(f'  {dep["name"]}: no badge found, skipped', file=sys.stderr)

if check:
    if drift:
        for name, version in drift:
            print(f'  {name} badge should read {version}')
        print('README badges are out of date — run sync-readme-badges.sh', file=sys.stderr)
        sys.exit(1)
    print('README badges match deps.yaml')
else:
    for name, version in drift:
        print(f'  {name} badge -> {version}')
    open(path, 'w').write(readme)
PY
rc=$?

# In --check mode the python block owns the exit status; the guard below must
# not clobber it (a false `if` would otherwise make the script exit 0).
if [ "$CHECK" -ne 1 ]; then
  echo "Synced README.md badges from ${DEPS_YAML}"
fi

exit "$rc"
