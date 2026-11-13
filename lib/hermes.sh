#!/usr/bin/env sh
# lib/hermes.sh - Hermes Agent installation
#
# Install Hermes using their official install script (git-based, mirrors hermes-codespace)
# Usage: install_hermes <version> <install_dir>

# Canonical absolute path. macOS BSD readlink has no -f, so fall back to a
# bounded symlink walk (repo pattern: uninstall.sh guards readlink -m).
canonical_path() {
    _cp_r=$(readlink -f "$1" 2>/dev/null || true)
    if [ -z "${_cp_r}" ] && command -v realpath >/dev/null 2>&1; then
        _cp_r=$(realpath "$1" 2>/dev/null || true)
    fi
    if [ -n "${_cp_r}" ]; then
        printf '%s\n' "${_cp_r}"
        return 0
    fi
    _cp=$1
    _cp_n=0
    while [ -L "${_cp}" ] && [ "${_cp_n}" -lt 32 ]; do
        _cp_t=$(readlink "${_cp}" 2>/dev/null || true)
        [ -z "${_cp_t}" ] && break
        case "${_cp_t}" in
            /*) _cp=${_cp_t} ;;
            *) _cp=$(dirname "${_cp}")/${_cp_t} ;;
        esac
        _cp_n=$((_cp_n + 1))
    done
    printf '%s/%s\n' "$(cd "$(dirname "${_cp}")" 2>/dev/null && pwd -P)" "$(basename "${_cp}")"
}

install_hermes() {
    version=$1
    install_dir=$2

    # Pin to exact version tag (e.g. v0.23.1)
    hermes_install_uri="https://raw.githubusercontent.com/NousResearch/hermes-agent/${version}/scripts/install.sh"
    hermes_fallback_uri="https://hermes-agent.nousresearch.com/install.sh"

    echo "Installing Hermes ${version} via official install script..."

    # Download install script + run with checkout pinned to the same tag.
    # Primary URI is the tagged installer (pre-PM, uv.lock for 3.11/3.12/3.13);
    # fallback URI serves the main installer (PM, needs pm/lock.json) — keep
    # it unpinned to avoid PM breakage.
    #
    # The installer's --commit pin requires the SHA to be an ancestor of the
    # installed branch (merge-base --is-ancestor, else "commit not on branch").
    # Its clone is blobless full history (no --depth), so ancestry resolves for
    # tag commits on main. Do NOT add flags beyond --skip-setup/--commit: the
    # parser exits 1 on any unknown option.
    tmp_script=$(mktemp)
    if curl -fsSL "${hermes_install_uri}" -o "${tmp_script}" 2>/dev/null; then
        hermes_commit=""
        if command -v git >/dev/null 2>&1; then
            hermes_commit=$(git ls-remote https://github.com/NousResearch/hermes-agent.git "refs/tags/${version}^{}" 2>/dev/null | cut -f1)
            [ -z "${hermes_commit}" ] && hermes_commit=$(git ls-remote https://github.com/NousResearch/hermes-agent.git "refs/tags/${version}" 2>/dev/null | cut -f1)
        fi
        if [ -n "${hermes_commit}" ]; then
            bash "${tmp_script}" --skip-setup --commit "${hermes_commit}" || {
                echo "ERROR: Hermes install script failed" >&2
                rm -f "${tmp_script}"
                return 1
            }
        else
            # git ls-remote unavailable/offline — hardcode known SHA for v0.23.1
            # to avoid --branch which breaks update/repair path (no origin/tag ref).
            if [ "${version}" = "v0.23.1" ]; then
                hermes_commit="3b421578588243f920886e6fe79a6faa87ea026e"
                bash "${tmp_script}" --skip-setup --commit "${hermes_commit}" || {
                    echo "ERROR: Hermes install script failed" >&2
                    rm -f "${tmp_script}"
                    return 1
                }
            else
                echo "ERROR: cannot resolve commit for ${version} and no fallback SHA" >&2
                rm -f "${tmp_script}"
                return 1
            fi
        fi
    else
        echo "Primary URI failed, trying fallback..."
        curl -fsSL "${hermes_fallback_uri}" -o "${tmp_script}" || {
            echo "ERROR: could not download Hermes install script" >&2
            return 1
        }
        # Fallback serves main installer (PM) — do NOT pin (no pm/lock.json in tag checkout)
        bash "${tmp_script}" --skip-setup || {
            echo "ERROR: Hermes install script failed" >&2
            rm -f "${tmp_script}"
            return 1
        }
    fi
    rm -f "${tmp_script}"

    # Find the installed hermes binary. Prefer the venv entrypoint (its shebang
    # points at the venv python, which has all deps incl. python-dotenv). The
    # source-tree `hermes` launcher uses `#!/usr/bin/env python3` and would pick
    # the system python (which lacks dotenv) -> ModuleNotFoundError.
    hermes_bin=$(find "${HOME}/.hermes/hermes-agent/venv/bin" -type f -name "hermes" 2>/dev/null | head -1)
    if [ -z "${hermes_bin}" ]; then
        hermes_bin=$(find "${HOME}/.hermes" "${HOME}/.local/bin" -type f -name "hermes" 2>/dev/null | head -1)
    fi
    if [ -z "${hermes_bin}" ]; then
        hermes_bin=$(command -v hermes 2>/dev/null || true)
    fi

    if [ -z "${hermes_bin}" ]; then
        echo "ERROR: Hermes binary not found after install" >&2
        return 1
    fi

    # The PM installer can drop the bundled ``locales/`` dir from ``installs/…/workspace``,
    # which makes every i18n key fall back to the bare key (``cli.tip_line`` instead of
    # ``"✦ Tip: …"``). ``agent.i18n`` honors HERMES_BUNDLED_LOCALES when it points at a
    # dir containing the catalogs, so wrap the launcher: resolve a locales dir (preferred
    # the git checkout, plus a find-based fallback) and export the override, then exec.
    write_hermes_wrapper "${hermes_bin}" "${install_dir}/hermes"


    # Fix macOS quarantine
    fix_macos_quarantine "${install_dir}"

    # Verify the binary works (bounded timeout)
    if timeout 30 "${install_dir}/hermes" --version >/dev/null 2>&1; then
        echo "Hermes ${version} installed and verified at ${install_dir}"
    else
        echo "WARNING: Hermes installed but binary verification (--version) failed or timed out" >&2
    fi
}

# Resolve a dir that ships the bundled locale catalogs (locales/en.yaml) and write an
# env-setting wrapper around hermes_bin at dest. No suitable dir found -> plain symlink
# (behavior unchanged). Idempotent: re-runnable after hermes updates.
write_hermes_wrapper() {
    hermes_src_bin=$1
    hermes_dest=$2

    # Never wrap a src that resolves back to dest: after ``rm dest`` + wrapper
    # write, the wrapper would exec a path pointing at the wrapper itself ->
    # infinite loop. Hit when venv/bin/hermes is missing (PM layout variant)
    # and ``command -v hermes`` resolves to our own bin/hermes symlink.
    if [ -L "${hermes_src_bin}" ] \
        && [ -n "$(canonical_path "${hermes_src_bin}")" ] \
        && [ "$(canonical_path "${hermes_src_bin}")" = "$(canonical_path "${hermes_dest}")" ]; then
        return 0
    fi

    # If ``dest`` is a *regular file* physically at the very entrypoint we
    # would exec, writing a self-executing wrapper there would loop. (A
    # symlink pointing to src is fine to replace with a wrapper file.)
    if [ -e "${hermes_dest}" ] && [ ! -L "${hermes_dest}" ] \
        && [ -n "$(canonical_path "${hermes_dest}")" ] \
        && [ "$(canonical_path "${hermes_dest}")" = "$(canonical_path "${hermes_src_bin}")" ]; then
        return 0
    fi

    # Prefer the PM install's own workspace locale directory (version-matched), then
    # the git checkout, and finally a bounded find fallback in ~/.hermes.
    hermes_ws=$(cd "$(dirname "$(dirname "$(dirname "${hermes_src_bin}")")")" 2>/dev/null && pwd)
    locales_dir=""
    for cand in "${hermes_ws}/workspace/locales" "${hermes_ws}/locales" "${HOME}/.hermes/hermes-agent/locales"; do
        if [ -f "${cand}/en.yaml" ]; then
            locales_dir="${cand}"
            break
        fi
    done
    if [ -z "${locales_dir}" ]; then
        locales_dir=$(find "${HOME}/.hermes" -maxdepth 5 -type f -path "*/locales/en.yaml" 2>/dev/null | head -1)
        [ -n "${locales_dir}" ] && locales_dir=$(dirname "${locales_dir}")
    fi
    if [ -z "${locales_dir}" ] || [ ! -f "${locales_dir}/en.yaml" ]; then
        # No usable bundled locale source: keep a direct symlink so a later repair
        # can swap the wrapper in. Warn so the raw-key symptom isn't a mystery.
        ln -sf "${hermes_src_bin}" "${hermes_dest}"
        echo "WARNING: no hermes bundled locales/ found; i18n will show raw keys (see write_hermes_wrapper in lib/hermes.sh)" >&2
        return 0
    fi

    # ``cat > dest`` writes THROUGH a symlink, clobbering the real entrypoint
    # e.g. venv/bin/hermes; drop the link first so the wrapper is standalone.
    if [ -L "${hermes_dest}" ]; then
        rm -f "${hermes_dest}"
    fi

    cat > "${hermes_dest}" <<EOF
#!/bin/sh
# .minions wrapper: force a bundled locales/ catalog (PM installer can drop it).
HERMES_BUNDLED_LOCALES="${locales_dir}"
export HERMES_BUNDLED_LOCALES
exec "${hermes_src_bin}" "\$@"
EOF
    chmod +x "${hermes_dest}"
}

# Ensure Hermes is available
ensure_hermes() {
    hermes_entry="${MINIONS_HOME}/bin/hermes"
    hermes_local="${MINIONS_HOME}/lib/hermes/hermes"
    if [ ! -e "${hermes_local}" ]; then
        hermes_local="${hermes_entry}"
    fi

    if [ -L "${hermes_local}" ]; then
        # Existing plain symlink (pre-wrapper or PM-installed): heal into a
        # locales-aware wrapper if this build is missing its bundled locales/.
        hermes_target=$(canonical_path "${hermes_local}")
        hermes_ws=$(cd "$(dirname "$(dirname "$(dirname "${hermes_target}")")")" 2>/dev/null && pwd)
        hermes_install_dir=$(dirname "${hermes_ws}")
        if [ -n "${hermes_ws}" ] && [ -n "${hermes_install_dir}" ] && [ -d "${hermes_ws}/venv" ]; then
            if [ ! -f "${hermes_ws}/workspace/locales/en.yaml" ] && [ -f "${HOME}/.hermes/hermes-agent/locales/en.yaml" ]; then
                echo "Hermes locales/ missing from ${hermes_ws}; healing wrapper at ${hermes_local}"
                write_hermes_wrapper "${hermes_target}" "${hermes_local}"
                [ "$(cd "$(dirname "${hermes_local}")" && pwd)" != "$(cd "$(dirname "${hermes_entry}")" && pwd)" ] && ln -sf "${hermes_local}" "${hermes_entry}"
            fi
        fi
    fi

    if [ -e "${hermes_local}" ]; then
        echo "Hermes found at ${hermes_local}"
        return 0
    fi

    echo "Hermes not found, installing..."
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/versions.env"
    mkdir -p "${MINIONS_HOME}/lib/hermes"
    install_hermes "${HERMES_VERSION}" "${MINIONS_HOME}/lib/hermes"

    # Create symlink in bin
    ln -sf "${MINIONS_HOME}/lib/hermes/hermes" "${MINIONS_HOME}/bin/hermes"
}

