#!/usr/bin/env sh
# lib/pi-settings.sh — Phase 24: Pi-Agent settings.json shared-skills wiring
# Sourced by install.sh (after pi.toml/models.json templating) and boot.sh
# (idempotent re-assert on every boot).
#
# Adds the mode-appropriate shared skills dir to Pi's settings.json so the
# `pi` CLI discovers the SAME skills/ that Hermes loads via its symlink:
#   dev         -> <repo>/skills        (MINIONS_REPO_ROOT)
#   standalone  -> ~/.minions/skills    (MINIONS_HOME)
#
# Pi reads "skills": ["<path>"] from ~/.pi/agent/settings.json as extra skill
# dirs (pi 0.85.1 loadSkills(): resolve -> must exist -> recursive SKILL.md
# scan). The merge is done with python3 (already an install.sh dependency) so
# existing keys — e.g. the pi-failover "packages" entry — are preserved.

# wire_pi_skills_path SETTINGS_FILE SKILLS_PATH
#   SETTINGS_FILE  the Pi settings.json to modify (e.g. ${HOME}/.pi/agent/settings.json)
#   SKILLS_PATH    absolute path to the shared skills dir (dev or standalone)
#
# Creates the file if missing, sets/keeps "skills": ["<SKILLS_PATH>"] (deduped),
# preserves all other keys. Idempotent — safe to call on every boot.
wire_pi_skills_path() {
    _PI_SETTINGS_FILE="$1"
    _PI_SKILLS_PATH="$2"

    if [ -z "${_PI_SKILLS_PATH}" ] || [ ! -d "${_PI_SKILLS_PATH}" ]; then
        log_warn "wire_pi_skills_path: no skills dir (${_PI_SKILLS_PATH:-unset})"
        return 0
    fi

    mkdir -p "$(dirname "${_PI_SETTINGS_FILE}")"

    python3 - "${_PI_SETTINGS_FILE}" "${_PI_SKILLS_PATH}" <<'PYEOF'
import json
import sys

settings_file, skills_path = sys.argv[1], sys.argv[2]

try:
    with open(settings_file, "r", encoding="utf-8") as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

skills = data.get("skills", [])
if skills_path not in skills:
    skills.append(skills_path)
data["skills"] = skills

with open(settings_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF

    log_info "Wired Pi skills path: ${_PI_SKILLS_PATH} -> ${_PI_SETTINGS_FILE}"
}