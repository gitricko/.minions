#!/usr/bin/env sh
# lib/status-lib.sh — shared status probes for .minions (#66)
# POSIX sh, no bashisms, no set -e inside. Sourced by status.sh / boot.sh.
# Never calls exit; callers decide. Every probe is guarded so status_collect
# always returns 0 (signal is via status_exit_code only).
#
# Severity (exit code) — documented, matches self-check.sh 0/1/2 discipline:
#   omniroute, 9router  → critical (2) when port closed or pid missing
#   pi, hermes          → warn (1) when binary missing
#   ollama              → 0 when binary absent (not installed by choice)
#                       → warn (1) when binary present but API/pid down
#   mnemon              → warn (1) when binary missing or DB absent
#   tailscale           → 0 when neither bin present (not installed)
#                       → warn (1) when installed but not running (needs ts up)
#                       → 0 when status ok / daemon running (incl. Logged out. == reachable)
#   READY marker        → critical (2) when missing (boot incomplete)
# status_exit_code returns max severity (2 > 1 > 0).
#
# Version order: binary --version (timeout 2) → $MINIONS_HOME/etc/versions.env → unknown
# Distinguish not installed (binary absent) vs unknown (probe failed).
# Ordering is intentional: $MINIONS_HOME/etc/versions.env is the installed copy
# (written by install.sh from repo etc/versions.env); it survives even when
# boot.sh runs from $MINIONS_HOME with no repo present. Never read repo
# etc/versions.env here — lib may be sourced from $MINIONS_HOME/lib.

# Ports — respect env overrides, same defaults as status.sh/boot.sh
: "${OMNIROUTE_HOST:=127.0.0.1}"
: "${OMNIROUTE_PORT:=20128}"
: "${NINEROUTER_HOST:=127.0.0.1}"
: "${NINEROUTER_PORT:=7352}"

# ── low-level helpers (guarded, no set -e abort) ──

# _status_port_open host port — 0 if open, 1 if closed/unreachable
# Reuses lib/process.sh:186-193 verbatim (nc if present, else bash /dev/tcp).
# The old (echo > /dev/tcp/…) under dash is the bug — this is the fix.
_status_port_open() {
    _sph_host=$1
    _sph_port=$2
    if command -v nc >/dev/null 2>&1; then
        nc -z "${_sph_host}" "${_sph_port}" 2>/dev/null
        _sph_rc=$?
        unset _sph_host _sph_port
        return $_sph_rc
    elif command -v bash >/dev/null 2>&1; then
        bash -c "exec 3<>/dev/tcp/${_sph_host}/${_sph_port}" 2>/dev/null
        _sph_rc=$?
        unset _sph_host _sph_port
        return $_sph_rc
    else
        # Rare: no nc, no bash — degrade gracefully, don't crash
        # shellcheck disable=SC2034
        _sph_host="" _sph_port=""
        unset _sph_host _sph_port
        return 1
    fi
}

# _status_pid_alive name — 0 if pid file exists and pid alive (incl. sudo fallback)
# Mirrors lib/process.sh:is_service_running semantics.
# On success echoes the pid to stdout (caller captures); on failure echoes empty.
_status_pid_alive() {
    _spa_name=$1
    _spa_pid_file="${MINIONS_HOME:-${HOME}/.minions}/var/run/${_spa_name}.pid"
    _spa_pid=""
    if [ -f "${_spa_pid_file}" ]; then
        _spa_pid=$(cat "${_spa_pid_file}" 2>/dev/null || true)
    fi
    if [ -z "${_spa_pid:-}" ]; then
        unset _spa_name _spa_pid_file _spa_pid
        return 1
    fi
    if kill -0 "${_spa_pid}" 2>/dev/null; then
        printf '%s' "${_spa_pid}"
        unset _spa_name _spa_pid_file _spa_pid
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n kill -0 "${_spa_pid}" 2>/dev/null; then
        printf '%s' "${_spa_pid}"
        unset _spa_name _spa_pid_file _spa_pid
        return 0
    fi
    unset _spa_name _spa_pid_file _spa_pid
    return 1
}

# _status_version_from_versions_env VAR — echo value or empty
_status_version_from_versions_env() {
    _sv_var=$1
    _sv_file="${MINIONS_HOME:-${HOME}/.minions}/etc/versions.env"
    if [ -f "${_sv_file}" ]; then
        # shellcheck disable=SC1090
        # Only read the one var we need; don't source the whole file under set -u
        _sv_val=$(grep "^${_sv_var}=" "${_sv_file}" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'" | head -1 || true)
        if [ -n "${_sv_val:-}" ]; then
            printf '%s' "${_sv_val}"
            unset _sv_var _sv_file _sv_val
            return 0
        fi
    fi
    unset _sv_var _sv_file _sv_val
    return 1
}

# _status_normalize_version raw — strip common prefixes, first line only, 80 chars
_status_normalize_version() {
    _snv_raw=$1
    # First line only, strip leading/trailing whitespace
    _snv_raw=$(printf '%s' "${_snv_raw}" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # ollama: "ollama version is 0.40.3" -> "0.40.3"
    case "${_snv_raw}" in
        "ollama version is "*) _snv_raw=$(printf '%s' "${_snv_raw}" | sed 's/^ollama version is //') ;;
    esac
    # mnemon: "mnemon version 0.2.10" -> "0.2.10"
    case "${_snv_raw}" in
        "mnemon version "*) _snv_raw=$(printf '%s' "${_snv_raw}" | sed 's/^mnemon version //') ;;
    esac
    # tailscale: multi-line, first line "1.104.1 ..." -> "1.104.1"
    case "${_snv_raw}" in
        "tailscale version "*|"tailscale commit:"*) _snv_raw=$(printf '%s' "${_snv_raw}" | awk '{print $1}') ;;
    esac
    # hermes: "Hermes Agent v0.21.5 (2026.9.24) · upstream …" -> keep first line, truncate to 80
    if [ ${#_snv_raw} -gt 80 ]; then
        _snv_raw=$(printf '%s' "${_snv_raw}" | cut -c1-80)
    fi
    printf '%s' "${_snv_raw}"
    unset _snv_raw
}

# _status_cli_version bin_name version_var timeout
# Tries: MINIONS_HOME/bin/<bin> --version, then PATH, then versions.env fallback
# Echoes version string; distinguishes not installed vs unknown.
_status_cli_version() {
    _scv_bin=$1
    _scv_var=$2
    _scv_bin_path=""
    # Prefer MINIONS_HOME/bin
    if [ -x "${MINIONS_HOME:-${HOME}/.minions}/bin/${_scv_bin}" ]; then
        _scv_bin_path="${MINIONS_HOME:-${HOME}/.minions}/bin/${_scv_bin}"
    elif command -v "${_scv_bin}" >/dev/null 2>&1; then
        _scv_bin_path=$(command -v "${_scv_bin}" 2>/dev/null || true)
    fi
    if [ -z "${_scv_bin_path:-}" ]; then
        # Try versions.env fallback before giving up
        _scv_fallback=""
        _scv_fallback=$(_status_version_from_versions_env "${_scv_var}" 2>/dev/null || true)
        if [ -n "${_scv_fallback:-}" ]; then
            printf '%s' "not installed (expected ${_scv_fallback})"
            unset _scv_bin _scv_var _scv_bin_path _scv_fallback
            return 1
        fi
        printf '%s' "not installed"
        unset _scv_bin _scv_var _scv_bin_path _scv_fallback
        return 1
    fi
    # Probe with timeout 2 (pi bare version hangs; hermes multi-line)
    _scv_raw=""
    if command -v timeout >/dev/null 2>&1; then
        _scv_raw=$(timeout 2 "${_scv_bin_path}" --version 2>&1 | head -1 || true)
    else
        _scv_raw=$("${_scv_bin_path}" --version 2>&1 | head -1 || true)
    fi
    if [ -z "${_scv_raw:-}" ]; then
        _scv_fallback=""
        _scv_fallback=$(_status_version_from_versions_env "${_scv_var}" 2>/dev/null || true)
        if [ -n "${_scv_fallback:-}" ]; then
            printf '%s' "unknown (expected ${_scv_fallback})"
        else
            printf '%s' "unknown"
        fi
        unset _scv_bin _scv_var _scv_bin_path _scv_raw _scv_fallback
        return 1
    fi
    _scv_norm=$(_status_normalize_version "${_scv_raw}")
    if [ -z "${_scv_norm:-}" ]; then
        printf '%s' "unknown"
        unset _scv_bin _scv_var _scv_bin_path _scv_raw _scv_norm
        return 1
    fi
    printf '%s' "${_scv_norm}"
    unset _scv_bin _scv_var _scv_bin_path _scv_raw _scv_norm
    return 0
}

# ── per-component probes ──
# Each sets globals: STATUS_<NAME>, VERSION_<NAME>, DETAIL_<NAME>
# and returns 0 always (signal is STATUS_*, not return code — so status_collect
# can never abort boot.sh's set -e).
# STATUS values: ok | warn | critical | not_installed

# Globals initialized by status_collect
STATUS_OMNIROUTE=""
STATUS_9ROUTER=""
STATUS_OLLAMA=""
STATUS_PI=""
STATUS_HERMES=""
STATUS_MNEMON=""
STATUS_TAILSCALE=""
STATUS_READY=""
VERSION_OMNIROUTE=""
VERSION_9ROUTER=""
VERSION_OLLAMA=""
VERSION_PI=""
VERSION_HERMES=""
VERSION_MNEMON=""
VERSION_TAILSCALE=""
DETAIL_OMNIROUTE=""
DETAIL_9ROUTER=""
DETAIL_OLLAMA=""
DETAIL_PI=""
DETAIL_HERMES=""
DETAIL_MNEMON=""
DETAIL_TAILSCALE=""
DETAIL_READY=""
STATUS_EXIT_CODE=0

_status_probe_omniroute() {
    _spo_pid=""; _spo_pid=$(_status_pid_alive "omniroute" 2>/dev/null || true)
    _spo_port_ok=1; _status_port_open "${OMNIROUTE_HOST}" "${OMNIROUTE_PORT}" 2>/dev/null && _spo_port_ok=0 || true
    _spo_ver=""; _spo_ver=$(_status_cli_version "omniroute" "OMNIROUTE_VERSION" 2>/dev/null || true)
    VERSION_OMNIROUTE="${_spo_ver}"
    if [ -n "${_spo_pid:-}" ] && [ "${_spo_port_ok}" -eq 0 ]; then
        STATUS_OMNIROUTE="ok"
        DETAIL_OMNIROUTE="pid ${_spo_pid}, port open, ${_spo_ver}"
    elif [ -n "${_spo_pid:-}" ] || [ "${_spo_port_ok}" -eq 0 ]; then
        STATUS_OMNIROUTE="critical"
        if [ -n "${_spo_pid:-}" ]; then
            DETAIL_OMNIROUTE="pid ${_spo_pid} but port closed (${OMNIROUTE_HOST}:${OMNIROUTE_PORT}), ${_spo_ver}"
        else
            DETAIL_OMNIROUTE="port open but no pid, ${_spo_ver}"
        fi
    else
        STATUS_OMNIROUTE="critical"
        DETAIL_OMNIROUTE="down — no pid, port closed, ${_spo_ver}"
    fi
    unset _spo_pid _spo_port_ok _spo_ver
    return 0
}

_status_probe_9router() {
    _sp9_pid=""; _sp9_pid=$(_status_pid_alive "9router" 2>/dev/null || true)
    _sp9_port_ok=1; _status_port_open "${NINEROUTER_HOST}" "${NINEROUTER_PORT}" 2>/dev/null && _sp9_port_ok=0 || true
    _sp9_ver=""; _sp9_ver=$(_status_cli_version "9router" "NINEROUTER_VERSION" 2>/dev/null || true)
    VERSION_9ROUTER="${_sp9_ver}"
    if [ -n "${_sp9_pid:-}" ] && [ "${_sp9_port_ok}" -eq 0 ]; then
        STATUS_9ROUTER="ok"
        DETAIL_9ROUTER="pid ${_sp9_pid}, port open, ${_sp9_ver}"
    elif [ -n "${_sp9_pid:-}" ] || [ "${_sp9_port_ok}" -eq 0 ]; then
        STATUS_9ROUTER="critical"
        if [ -n "${_sp9_pid:-}" ]; then
            DETAIL_9ROUTER="pid ${_sp9_pid} but port closed (${NINEROUTER_HOST}:${NINEROUTER_PORT}), ${_sp9_ver}"
        else
            DETAIL_9ROUTER="port open but no pid, ${_sp9_ver}"
        fi
    else
        STATUS_9ROUTER="critical"
        DETAIL_9ROUTER="down — no pid, port closed, ${_sp9_ver}"
    fi
    unset _sp9_pid _sp9_port_ok _sp9_ver
    return 0
}

_status_probe_ollama() {
    _spo_ver=""; _spo_ver=$(_status_cli_version "ollama" "OLLAMA_VERSION" 2>/dev/null || true)
    VERSION_OLLAMA="${_spo_ver}"
    case "${_spo_ver}" in
        "not installed"* )
            STATUS_OLLAMA="not_installed"
            DETAIL_OLLAMA="not installed"
            unset _spo_ver
            return 0
            ;;
    esac
    # Binary present — check if API responds (port open) and pid
    _spo_pid=""; _spo_pid=$(_status_pid_alive "ollama" 2>/dev/null || true)
    _spo_port_ok=1; _status_port_open "127.0.0.1" "11434" 2>/dev/null && _spo_port_ok=0 || true
    # Also try HTTP probe if port open but pid missing (ollama may run outside pid file)
    if [ "${_spo_port_ok}" -eq 0 ]; then
        STATUS_OLLAMA="ok"
        if [ -n "${_spo_pid:-}" ]; then
            DETAIL_OLLAMA="${_spo_ver} (pid ${_spo_pid})"
        else
            DETAIL_OLLAMA="${_spo_ver}, http://localhost:11434"
        fi
    elif [ -n "${_spo_pid:-}" ]; then
        STATUS_OLLAMA="warn"
        DETAIL_OLLAMA="pid ${_spo_pid} but API not responding, ${_spo_ver}"
    else
        STATUS_OLLAMA="warn"
        DETAIL_OLLAMA="down — API not responding, ${_spo_ver}"
    fi
    unset _spo_ver _spo_pid _spo_port_ok
    return 0
}

_status_probe_pi() {
    _spp_ver=""; _spp_ver=$(_status_cli_version "pi" "PI_VERSION" 2>/dev/null || true)
    VERSION_PI="${_spp_ver}"
    case "${_spp_ver}" in
        "not installed"* )
            STATUS_PI="warn"
            DETAIL_PI="${_spp_ver}"
            ;;
        "unknown"* )
            STATUS_PI="warn"
            DETAIL_PI="${_spp_ver}"
            ;;
        *)
            STATUS_PI="ok"
            DETAIL_PI="${_spp_ver}"
            ;;
    esac
    unset _spp_ver
    return 0
}

_status_probe_hermes() {
    _sph_ver=""; _sph_ver=$(_status_cli_version "hermes" "HERMES_VERSION" 2>/dev/null || true)
    VERSION_HERMES="${_sph_ver}"
    case "${_sph_ver}" in
        "not installed"* )
            STATUS_HERMES="warn"
            DETAIL_HERMES="${_sph_ver}"
            ;;
        "unknown"* )
            STATUS_HERMES="warn"
            DETAIL_HERMES="${_sph_ver}"
            ;;
        *)
            STATUS_HERMES="ok"
            DETAIL_HERMES="${_sph_ver}"
            ;;
    esac
    unset _sph_ver
    return 0
}

_status_probe_mnemon() {
    _spm_ver=""; _spm_ver=$(_status_cli_version "mnemon" "MNEMON_VERSION" 2>/dev/null || true)
    VERSION_MNEMON="${_spm_ver}"
    case "${_spm_ver}" in
        "not installed"* )
            STATUS_MNEMON="warn"
            DETAIL_MNEMON="${_spm_ver}"
            unset _spm_ver
            return 0
            ;;
    esac
    # Check DB dir (like self-check.sh:178-185)
    _spm_db=""
    if [ -d "${HOME}/.mnemon" ]; then
        _spm_db="${HOME}/.mnemon"
    elif [ -d "${MINIONS_HOME:-${HOME}/.minions}/../.mnemon" ]; then
        _spm_db="${MINIONS_HOME:-${HOME}/.minions}/../.mnemon"
    fi
    # Also check MINIONS_HOME-adjacent .mnemon
    if [ -z "${_spm_db:-}" ]; then
        for _spm_try in "${HOME}/.mnemon" "${MINIONS_HOME:-${HOME}/.minions}/var/mnemon"; do
            if [ -d "${_spm_try}" ]; then _spm_db="${_spm_try}"; break; fi
        done
        unset _spm_try
    fi
    if [ -n "${_spm_db:-}" ]; then
        STATUS_MNEMON="ok"
        DETAIL_MNEMON="${_spm_ver}, db at ${_spm_db}"
    else
        STATUS_MNEMON="warn"
        DETAIL_MNEMON="${_spm_ver}, no .mnemon dir (created on first use)"
    fi
    unset _spm_ver _spm_db
    return 0
}

_status_probe_tailscale() {
    _spt_ver=""; _spt_ver=$(_status_cli_version "tailscale" "TAILSCALE_VERSION" 2>/dev/null || true)
    VERSION_TAILSCALE="${_spt_ver}"
    case "${_spt_ver}" in
        "not installed"* )
            STATUS_TAILSCALE="not_installed"
            DETAIL_TAILSCALE="not installed (install with install.sh --tailscale)"
            unset _spt_ver
            return 0
            ;;
    esac
    # Bin present — probe status (extracted from status.sh:44-108, same semantics)
    _spt_socket="${MINIONS_HOME:-${HOME}/.minions}/var/run/tailscaled.sock"
    _spt_cli=""
    if [ -x "${MINIONS_HOME:-${HOME}/.minions}/bin/tailscale" ]; then
        _spt_cli="${MINIONS_HOME:-${HOME}/.minions}/bin/tailscale"
    elif command -v tailscale >/dev/null 2>&1; then
        _spt_cli=$(command -v tailscale 2>/dev/null || true)
    fi
    _spt_mode="userspace"
    _spt_sock_uid=$(stat -c %u "${_spt_socket}" 2>/dev/null || stat -f %u "${_spt_socket}" 2>/dev/null || true)
    if [ -S "${_spt_socket}" ] && [ -n "${_spt_sock_uid:-}" ] && [ "${_spt_sock_uid}" != "$(id -u)" ]; then _spt_mode="kernel"; fi
    unset _spt_sock_uid
    # pidfile preferred
    _spt_pid=""
    if [ -f "${MINIONS_HOME:-${HOME}/.minions}/var/run/tailscaled.pid" ]; then
        _spt_pid=$(cat "${MINIONS_HOME:-${HOME}/.minions}/var/run/tailscaled.pid" 2>/dev/null || true)
        if [ -n "${_spt_pid:-}" ] && kill -0 "${_spt_pid}" 2>/dev/null; then
            if [ "${_spt_mode}" = "kernel" ]; then
                STATUS_TAILSCALE="ok"
                DETAIL_TAILSCALE="kernel, pid ${_spt_pid}, ${_spt_ver}"
            else
                if [ -f "${MINIONS_HOME:-${HOME}/.minions}/etc/tailscale.env" ]; then
                    STATUS_TAILSCALE="ok"
                    DETAIL_TAILSCALE="userspace, pid ${_spt_pid} -- proxy :1056, ${_spt_ver}"
                else
                    STATUS_TAILSCALE="ok"
                    DETAIL_TAILSCALE="pid ${_spt_pid}, ${_spt_ver}"
                fi
            fi
            unset _spt_socket _spt_cli _spt_mode _spt_pid
            return 0
        fi
        if [ -n "${_spt_pid:-}" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n kill -0 "${_spt_pid}" 2>/dev/null; then
            STATUS_TAILSCALE="ok"
            DETAIL_TAILSCALE="kernel, pid ${_spt_pid}, ${_spt_ver}"
            unset _spt_socket _spt_cli _spt_mode _spt_pid
            return 0
        fi
    fi
    if command -v pgrep >/dev/null 2>&1 && pgrep -f "[t]ailscaled" >/dev/null 2>&1; then
        if [ "${_spt_mode}" = "kernel" ]; then
            STATUS_TAILSCALE="ok"
            DETAIL_TAILSCALE="kernel, running, ${_spt_ver}"
        else
            STATUS_TAILSCALE="ok"
            DETAIL_TAILSCALE="running, ${_spt_ver}"
        fi
        unset _spt_socket _spt_cli _spt_mode _spt_pid
        return 0
    fi
    # Fallback: status probe guarded
    _spt_rc=1
    _spt_out=""
    # Use set +e style: run status but don't abort
    if [ -n "${_spt_socket:-}" ] && [ -S "${_spt_socket}" ]; then
        _spt_sock_uid2=$(stat -c %u "${_spt_socket}" 2>/dev/null || stat -f %u "${_spt_socket}" 2>/dev/null || true)
        if [ -n "${_spt_sock_uid2:-}" ] && [ "${_spt_sock_uid2}" != "$(id -u)" ] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            _spt_out=$(sudo -n "${_spt_cli}" --socket="${_spt_socket}" status 2>&1 || true)
            # Logged out. == reachable
            case "${_spt_out}" in *"Logged out."*) _spt_rc=0 ;; *) _spt_rc=1; if [ -n "${_spt_out}" ]; then _spt_rc=0; fi ;; esac
            # need exit code, not just output — re-run to get rc guard
            if [ "${_spt_rc}" != "0" ]; then
                sudo -n "${_spt_cli}" --socket="${_spt_socket}" status >/dev/null 2>&1; _spt_rc=$?
                case "${_spt_out}" in *"Logged out."*) _spt_rc=0 ;; esac
            fi
        else
            "${_spt_cli}" --socket="${_spt_socket}" status >/dev/null 2>&1; _spt_rc=$?
            _spt_out=$("${_spt_cli}" --socket="${_spt_socket}" status 2>&1 || true)
            case "${_spt_out}" in *"Logged out."*) _spt_rc=0 ;; esac
        fi
        unset _spt_sock_uid2
    else
        "${_spt_cli}" status >/dev/null 2>&1; _spt_rc=$?
        _spt_out=$("${_spt_cli}" status 2>&1 || true)
        case "${_spt_out}" in *"Logged out."*) _spt_rc=0 ;; esac
    fi
    if [ "${_spt_rc:-1}" -eq 0 ]; then
        STATUS_TAILSCALE="ok"
        if [ "${_spt_mode}" = "kernel" ]; then
            DETAIL_TAILSCALE="kernel, status ok, ${_spt_ver}"
        else
            if [ -f "${MINIONS_HOME:-${HOME}/.minions}/etc/tailscale.env" ]; then
                DETAIL_TAILSCALE="userspace, status ok -- proxy :1056, ${_spt_ver}"
            else
                DETAIL_TAILSCALE="status ok, ${_spt_ver}"
            fi
        fi
        unset _spt_socket _spt_cli _spt_mode _spt_pid _spt_rc _spt_out
        return 0
    fi
    STATUS_TAILSCALE="warn"
    DETAIL_TAILSCALE="installed but not running — run: ts up, ${_spt_ver}"
    unset _spt_socket _spt_cli _spt_mode _spt_pid _spt_rc _spt_out _spt_ver
    return 0
}

_status_probe_ready() {
    if [ -f "${MINIONS_HOME:-${HOME}/.minions}/var/run/ready" ]; then
        STATUS_READY="ok"
        DETAIL_READY="ready"
    else
        STATUS_READY="critical"
        DETAIL_READY="not ready"
    fi
    return 0
}

# ── aggregate ──

# status_collect — run all probes, compute STATUS_EXIT_CODE, always returns 0
status_collect() {
    _status_probe_omniroute || true
    _status_probe_9router || true
    _status_probe_ollama || true
    _status_probe_pi || true
    _status_probe_hermes || true
    _status_probe_mnemon || true
    _status_probe_tailscale || true
    _status_probe_ready || true
    # Compute max severity: critical(2) > warn(1) > ok/not_installed(0)
    STATUS_EXIT_CODE=0
    for _sce_s in "${STATUS_OMNIROUTE}" "${STATUS_9ROUTER}" "${STATUS_READY}"; do
        if [ "${_sce_s}" = "critical" ]; then STATUS_EXIT_CODE=2; break; fi
    done
    if [ "${STATUS_EXIT_CODE}" -eq 0 ]; then
        for _sce_s in "${STATUS_OMNIROUTE}" "${STATUS_9ROUTER}" "${STATUS_OLLAMA}" "${STATUS_PI}" "${STATUS_HERMES}" "${STATUS_MNEMON}" "${STATUS_TAILSCALE}" "${STATUS_READY}"; do
            if [ "${_sce_s}" = "warn" ]; then STATUS_EXIT_CODE=1; break; fi
            if [ "${_sce_s}" = "critical" ]; then STATUS_EXIT_CODE=2; break; fi
        done
        # Also treat warn from 9router/omniroute as critical if needed
        if [ "${STATUS_OMNIROUTE}" = "warn" ] || [ "${STATUS_9ROUTER}" = "warn" ]; then
            # Degraded proxy is at least warn; keep 1 unless already 2
            if [ "${STATUS_EXIT_CODE}" -eq 0 ]; then STATUS_EXIT_CODE=1; fi
        fi
    fi
    unset _sce_s
    return 0
}

# status_exit_code — echo 0/1/2
status_exit_code() {
    printf '%s' "${STATUS_EXIT_CODE:-0}"
    return 0
}

# ── render ──

_status_icon() {
    case "$1" in
        ok) printf '✅' ;;
        not_installed) printf '—' ;;
        warn) printf '⚠️' ;;
        critical) printf '❌' ;;
        *) printf '❌' ;;
    esac
}

_status_human_row() {
    _shr_label=$1
    _shr_endpoint=$2
    _shr_status=$3
    _shr_detail=$4
    _shr_icon=$(_status_icon "${_shr_status}")
    # Truncate detail to 80 for alignment when hermes verbose
    if [ ${#_shr_detail} -gt 80 ]; then
        _shr_detail=$(printf '%s' "${_shr_detail}" | cut -c1-80)
    fi
    # not_installed renders as — with detail, not ❌
    if [ "${_shr_status}" = "not_installed" ]; then
        printf '  %-11s %-28s %s %s\n' "${_shr_label}" "${_shr_endpoint}" "${_shr_icon}" "${_shr_detail}"
    elif [ "${_shr_status}" = "ok" ]; then
        printf '  %-11s %-28s %s (%s)\n' "${_shr_label}" "${_shr_endpoint}" "${_shr_icon}" "${_shr_detail}"
    else
        printf '  %-11s %-28s %s (%s)\n' "${_shr_label}" "${_shr_endpoint}" "${_shr_icon}" "${_shr_detail}"
    fi
    unset _shr_label _shr_endpoint _shr_status _shr_detail _shr_icon
}

status_render_human() {
    echo ".minions status:"
    echo ""
    # omniroute / 9router: show endpoint
    _status_human_row "omniroute" "http://${OMNIROUTE_HOST}:${OMNIROUTE_PORT}/v1" "${STATUS_OMNIROUTE}" "${DETAIL_OMNIROUTE}"
    _status_human_row "9router" "http://${NINEROUTER_HOST}:${NINEROUTER_PORT}/v1" "${STATUS_9ROUTER}" "${DETAIL_9ROUTER}"
    _status_human_row "ollama" "http://localhost:11434" "${STATUS_OLLAMA}" "${DETAIL_OLLAMA}"
    _status_human_row "pi-agent" "CLI" "${STATUS_PI}" "${DETAIL_PI}"
    _status_human_row "hermes" "CLI" "${STATUS_HERMES}" "${DETAIL_HERMES}"
    _status_human_row "mnemon" "memory layer" "${STATUS_MNEMON}" "${DETAIL_MNEMON}"
    _status_human_row "tailscale" "(opt-in)" "${STATUS_TAILSCALE}" "${DETAIL_TAILSCALE}"
    echo ""
    if [ "${STATUS_READY}" = "ok" ]; then
        echo "  READY FOR FIRSTMATE DISPATCH ✅"
    else
        echo "  NOT READY ❌"
    fi
    return 0
}
