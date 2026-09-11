#!/usr/bin/env sh
# lib/knowledge-symlinks.sh — Phase 23: dev-mode knowledge symlink wiring
# Sourced by boot.sh (and install.sh for post-install dev setup).
#
# In dev mode (git checkout with skills/ + wiki/), the knowledge assets stay
# in the repo and ~/.minions/{skills,wiki,mnemon,memories} become symlinks to
# MINIONS_REPO_ROOT. In standalone mode no symlinks are created — the assets
# were copied by install.sh.

# setup_knowledge_symlinks MINIONS_HOME MINIONS_REPO_ROOT MODE
#   MINIONS_HOME       install root (usually ${HOME}/.minions)
#   MINIONS_REPO_ROOT  dev checkout root (from knowledge.env; empty in standalone)
#   MODE               "dev" or "standalone"
#
# Creates ~/.minions/<dir> -> $MINIONS_REPO_ROOT/<dir> for each of
# skills, wiki, mnemon, memories — but ONLY in dev mode with a valid repo root.
# Safe to call repeatedly (idempotent): removes any existing path first.
setup_knowledge_symlinks() {
    _MINIONS_HOME="$1"
    _MINIONS_REPO_ROOT="$2"
    _MODE="$3"

    if [ "${_MODE}" != "dev" ] || [ -z "${_MINIONS_REPO_ROOT}" ]; then
        return 0
    fi

    for _dir in skills wiki mnemon memories; do
        _src="${_MINIONS_REPO_ROOT}/${_dir}"
        _dst="${_MINIONS_HOME}/${_dir}"
        if [ -d "${_src}" ]; then
            rm -rf "${_dst}"
            ln -sfn "${_src}" "${_dst}"
            log_info "Linked ${_dst} -> ${_src}"
        fi
    done
}

# setup_hermes_skill_link HERMES_HOME SKILLS_TARGET
#   HERMES_HOME    the Hermes home dir (default ${HOME}/.hermes)
#   SKILLS_TARGET  the directory Hermes should load as the "minions" skills
#                  (repo skills in dev mode, ~/.minions/skills in standalone)
#
# Creates ~/.hermes/skills/minions -> SKILLS_TARGET — the "hermes-codespace pattern":
# a named subdirectory symlink so Hermes discovers the .minions skills alongside any
# user/bundled skills, and edits in dev mode flow straight into the git checkout.
# Idempotent: re-points only when the target differs; preserves other user skills.
setup_hermes_skill_link() {
    _HERMES_HOME="${1:-${HOME}/.hermes}"
    _SKILLS_TARGET="${2:-}"

    if [ -z "${_SKILLS_TARGET}" ] || [ ! -d "${_SKILLS_TARGET}" ]; then
        log_warn "setup_hermes_skill_link: no skills target dir (${_SKILLS_TARGET:-unset})"
        return 0
    fi

    _HERMES_SKILLS_DIR="${_HERMES_HOME}/skills"
    _MINIONS_SKILLS_LINK="${_HERMES_SKILLS_DIR}/minions"

    # Never clobber a real directory at the link path — only re-point a symlink.
    if [ -d "${_MINIONS_SKILLS_LINK}" ] && [ ! -L "${_MINIONS_SKILLS_LINK}" ]; then
        log_warn "setup_hermes_skill_link: ${_MINIONS_SKILLS_LINK} is a real dir; leaving it (remove manually if intended)"
        return 0
    fi

    mkdir -p "${_HERMES_SKILLS_DIR}"

    if [ -L "${_MINIONS_SKILLS_LINK}" ] && [ "$(readlink "${_MINIONS_SKILLS_LINK}")" = "${_SKILLS_TARGET}" ]; then
        log_info "Hermes skills link already correct: ${_MINIONS_SKILLS_LINK} -> ${_SKILLS_TARGET}"
    else
        rm -rf "${_MINIONS_SKILLS_LINK}" 2>/dev/null || true
        ln -sfn "${_SKILLS_TARGET}" "${_MINIONS_SKILLS_LINK}"
        log_info "Linked ${_MINIONS_SKILLS_LINK} -> ${_SKILLS_TARGET}"
    fi
}

# setup_hermes_memories_link HERMES_HOME MEMORIES_TARGET
#   HERMES_HOME      the Hermes home dir (default ${HOME}/.hermes)
#   MEMORIES_TARGET  the dir with MEMORY.md/USER.md (repo memories in dev,
#                    ~/.minions/memories in standalone)
#
# Creates ~/.hermes/memories -> MEMORIES_TARGET so Hermes' persistent memory files
# (MEMORY.md/USER.md) are git-tracked in dev mode and survive reinstalls. The
# Hermes install creates an EMPTY real ~/.hermes/memories dir — this re-points it
# only when it's an empty dir or a wrong symlink (never clobbers user content).
setup_hermes_memories_link() {
    _HERMES_HOME="${1:-${HOME}/.hermes}"
    _MEMORIES_TARGET="${2:-}"

    if [ -z "${_MEMORIES_TARGET}" ] || [ ! -d "${_MEMORIES_TARGET}" ]; then
        log_warn "setup_hermes_memories_link: no memories target dir (${_MEMORIES_TARGET:-unset})"
        return 0
    fi

    _HERMES_MEMORIES_LINK="${_HERMES_HOME}/memories"

    # Never clobber a real dir with user content — only re-point a symlink,
    # or an empty dir that Hermes' installer created.
    if [ -d "${_HERMES_MEMORIES_LINK}" ] && [ ! -L "${_HERMES_MEMORIES_LINK}" ]; then
        if [ -n "$(ls -A "${_HERMES_MEMORIES_LINK}" 2>/dev/null)" ]; then
            log_warn "setup_hermes_memories_link: ${_HERMES_MEMORIES_LINK} has content; leaving it"
            return 0
        fi
        rmdir "${_HERMES_MEMORIES_LINK}" 2>/dev/null || true
    fi

    mkdir -p "${_HERMES_HOME}"

    if [ -L "${_HERMES_MEMORIES_LINK}" ] && [ "$(readlink "${_HERMES_MEMORIES_LINK}")" = "${_MEMORIES_TARGET}" ]; then
        log_info "Hermes memories link already correct: ${_HERMES_MEMORIES_LINK} -> ${_MEMORIES_TARGET}"
    else
        rm -rf "${_HERMES_MEMORIES_LINK}" 2>/dev/null || true
        ln -sfn "${_MEMORIES_TARGET}" "${_HERMES_MEMORIES_LINK}"
        log_info "Linked ${_HERMES_MEMORIES_LINK} -> ${_MEMORIES_TARGET}"
    fi
}