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