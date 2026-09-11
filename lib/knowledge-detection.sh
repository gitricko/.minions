#!/usr/bin/env sh
# lib/knowledge-detection.sh — shared two-mode detection (dev vs standalone)
# Sourced by install.sh and boot.sh so detection is byte-identical (F13).
#
# Modes:
#   dev        — running inside a .minions git checkout (has skills/ + wiki/, .git)
#                → knowledge assets live in the repo; boot.sh symlinks them
#   standalone — installed via curl|bash or tarball (no .git)
#                → knowledge assets are copied into MINIONS_HOME by install.sh
#
# Sets (exported): MINIONS_HOME, MINIONS_REPO_ROOT (dev only), MODE

detect_knowledge_mode() {
    MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"
    MINIONS_REPO_ROOT=""

    # 1) Persisted repo root (written by install.sh in dev mode) — lets boot.sh
    #    detect dev even when run from ~/.minions/boot.sh (no .git in sight).
    if [ -f "${MINIONS_HOME}/etc/knowledge.env" ]; then
        # shellcheck disable=SC1091
        . "${MINIONS_HOME}/etc/knowledge.env" 2>/dev/null || true
        if [ -n "${MINIONS_REPO_ROOT:-}" ] && [ -d "${MINIONS_REPO_ROOT}/skills" ]; then
            MODE="dev"
            log_info "Knowledge mode: ${MODE} (from ${MINIONS_HOME}/etc/knowledge.env)"
            export MINIONS_HOME MINIONS_REPO_ROOT MODE
            return 0
        fi
        MINIONS_REPO_ROOT=""
    fi

    # 2) Detect from script location / cwd: a git checkout with skills/ + wiki/
    _SEARCH_DIR="$(pwd)"
    if [ -n "${SCRIPT_DIR:-}" ] && [ -d "${SCRIPT_DIR}/lib" ]; then
        _SEARCH_DIR="${SCRIPT_DIR}"
    elif [ -n "${0:-}" ] && [ -f "$0" ]; then
        _SEARCH_DIR="$(cd "$(dirname "$0")" && pwd)"
    fi

    if git -C "${_SEARCH_DIR}" rev-parse --show-toplevel >/dev/null 2>&1; then
        _GIT_ROOT="$(git -C "${_SEARCH_DIR}" rev-parse --show-toplevel)"
        if [ -d "${_GIT_ROOT}/skills" ] && [ -d "${_GIT_ROOT}/wiki" ]; then
            MINIONS_REPO_ROOT="${_GIT_ROOT}"
        fi
    fi

    MODE="dev"
    [ -z "${MINIONS_REPO_ROOT}" ] && MODE="standalone"
    log_info "Knowledge mode: ${MODE}"
    export MINIONS_HOME MINIONS_REPO_ROOT MODE
}