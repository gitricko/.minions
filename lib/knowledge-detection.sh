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

    # 1) Probe the live environment FIRST: script location / cwd — a git checkout
    #    with skills/ + wiki/ is authoritative (dev). This also recovers from a
    #    STALE persisted root (checkout moved, re-run from the new location).
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

    # 2) If the live probe found NO repo (e.g. boot.sh run from ~/.minions/boot.sh
    #    with no .git in cwd), FALL BACK to the persisted knowledge.env written by
    #    install.sh — it remembered dev mode + repo root for exactly this case.
    #    BUT when invoked via the curl|bash bootstrap re-exec (MINIONS_BOOTSTRAPPED=1
    #    and running from a tarball extract with no .git), NEVER trust a stale
    #    knowledge.env — a prior dev-mode install must not hijack the standalone path.
    if [ -z "${MINIONS_REPO_ROOT}" ] && [ "${MINIONS_BOOTSTRAPPED:-0}" != "1" ] \
        && [ -f "${MINIONS_HOME}/etc/knowledge.env" ]; then
        # shellcheck disable=SC1091
        . "${MINIONS_HOME}/etc/knowledge.env" 2>/dev/null || true
        if [ -n "${MINIONS_REPO_ROOT:-}" ] && [ -d "${MINIONS_REPO_ROOT}/skills" ]; then
            log_info "Knowledge mode: dev (from ${MINIONS_HOME}/etc/knowledge.env)"
            export MINIONS_HOME MINIONS_REPO_ROOT MODE
            return 0
        fi
        MINIONS_REPO_ROOT=""
    fi

    MODE="dev"
    [ -z "${MINIONS_REPO_ROOT}" ] && MODE="standalone"
    log_info "Knowledge mode: ${MODE}"
    export MINIONS_HOME MINIONS_REPO_ROOT MODE
}