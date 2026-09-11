#!/usr/bin/env sh
# .minions bootstrap installer
# One-liner: curl -fsSL https://minions.sh/install.sh | bash
# (minions.sh domain pending; GitHub raw URL works: https://github.com/gitricko/.minions/raw/refs/heads/main/install.sh)
#
# This script:
#   1. Detects OS/arch
#   2. Creates ~/.minions directory structure
#   3. Checks/installs prerequisites (Node, uv)
#   4. Vendors/installs: Hermes, Pi-Agent, OmniRoute, ModelRelay, Mnemon
#   4. Copies config templates to standard locations with port interpolation
#   5. Fixes macOS quarantine where needed
#
# Usage:
#   install.sh [--no-hermes] [--no-omniroute] [--no-modelrelay]
#
# Environment (set in ~/.bashrc BEFORE running):
#   OMNIROUTE_PORT=20128   (default)
#   MODELRELAY_PORT=7352   (default)
#   BOOTSTRAP_URL=...       (override tarball source, default: main.tar.gz)

# Phase 22.5: Bootstrap preamble for curl|bash one-liner
# Runs ONLY when install.sh is piped (stdin). Detects piped mode, fetches
# the repo tarball, extracts to scratch, and re-execs install.sh from there.
# This fixes SCRIPT_DIR resolution and stdin collision (exit 141).
#
# Piped detection: $0 is bash, -, /dev/fd/*, /dev/stdin, or non-existent file.
# Re-exec gives a real $0 with proper SCRIPT_DIR, free stdin, and full asset tree.

# Only run bootstrap when NOT already in a re-exec (flag: MINIONS_BOOTSTRAPPED=1)
if [ -z "${MINIONS_BOOTSTRAPPED:-}" ]; then
    case "$0" in
        bash|-|/dev/fd/*|/dev/stdin)
            PIPED=1
            ;;
        *)
            if [ ! -f "$0" ]; then
                PIPED=1
            fi
            ;;
    esac

    if [ "${PIPED:-0}" -eq 1 ]; then
        # Bootstrap: fetch repo tarball and re-exec from extracted checkout
        log_info() { echo "[INFO] $*"; }
        log_warn() { echo "[WARN] $*" >&2; }
        log_error() { echo "[ERROR] $*" >&2; }

        log_info "Bootstrap: piped install detected, fetching repository..."

        # Resolve bootstrap URL (overrideable)
        # Allow INSTALL_URL to be set (raw URL of install.sh) and auto-derive BOOTSTRAP_URL
        # Example: INSTALL_URL=https://github.com/gitricko/.minions/raw/refs/heads/fix/dev-mode-hermes-wiring/install.sh
        # Derives:  https://github.com/gitricko/.minions/archive/refs/heads/fix/dev-mode-hermes-wiring.tar.gz
        if [ -n "${INSTALL_URL:-}" ] && [ -z "${BOOTSTRAP_URL:-}" ]; then
            # Transform: /raw/ -> /archive/, /install.sh -> .tar.gz
            BOOTSTRAP_URL=$(echo "$INSTALL_URL" | sed 's|/raw/|/archive/|; s|/install\.sh$|.tar.gz|')
            log_info "Bootstrap: derived BOOTSTRAP_URL from INSTALL_URL -> $BOOTSTRAP_URL"
        fi
        BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://github.com/gitricko/.minions/archive/refs/heads/main.tar.gz}"

        # Create scratch dir
        SCRATCH="$(mktemp -d -t minions-bootstrap.XXXXXX)"
        trap 'rm -rf "$SCRATCH"' EXIT INT TERM

        # Fetch + extract (curl + tar; git clone fallback if curl fails)
        if ! curl -fsSL "$BOOTSTRAP_URL" | tar xz -C "$SCRATCH" 2>/dev/null; then
            log_warn "Tarball fetch failed, trying git clone..."
            if ! git clone --depth 1 --branch main https://github.com/gitricko/.minions "$SCRATCH" 2>/dev/null; then
                log_error "Both tarball and git clone failed"
                exit 1
            fi
        fi

        # Find extracted dir (tarball creates .minions-main/, git clone creates .minions/)
        EXTRACTED="$(find "$SCRATCH" -maxdepth 1 -type d -name '.minions*' | head -1)"
        if [ -z "$EXTRACTED" ] || [ ! -f "$EXTRACTED/install.sh" ]; then
            log_error "Extracted install.sh not found"
            exit 1
        fi

        log_info "Bootstrap: re-executing from $EXTRACTED/install.sh"

        # Re-exec with flag to skip bootstrap + preserve all args + env
        # Pass MINIONS_BOOTSTRAPPED so detect_knowledge_mode() skips the stale
        # persisted knowledge.env fallback (the tarball has no .git — we must
        # not read a dev-mode knowledge.env left by a prior install).
        unset MINIONS_HOME
        MINIONS_BOOTSTRAPPED=1 exec "$EXTRACTED/install.sh" "$@"
    fi
fi

set -e
set -u

# Defaults - no MINIONS_HOME override, fixed at ~/.minions
MINIONS_HOME="${HOME}/.minions"
INSTALL_HERMES=1
INSTALL_OMNIROUTE=1
INSTALL_MODELRELAY=1

# Port configuration (env-overridable with defaults)
OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"
MODELRELAY_PORT="${MODELRELAY_PORT:-7352}"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --no-hermes)
            INSTALL_HERMES=0
            shift
            ;;
        --no-omniroute)
            INSTALL_OMNIROUTE=0
            shift
            ;;
        --no-modelrelay)
            INSTALL_MODELRELAY=0
            shift
            ;;
        -h|--help)
            echo "Usage: install.sh [--no-hermes] [--no-omniroute] [--no-modelrelay]"
            echo ""
            echo "Environment variables (set before running):"
            echo "  OMNIROUTE_PORT=20128  (default)"
            echo "  MODELRELAY_PORT=7352  (default)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
    esac
done

# Color output (only if interactive)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

log_info() { echo "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo "${RED}[ERROR]${NC} $*" >&2; }

# Source lib functions (relative to script location)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Phase 22: two-mode knowledge detection (shared with boot.sh)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/knowledge-detection.sh"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/install-mnemon-plugin.sh"
detect_knowledge_mode

# Detect platform FIRST (needs detect.sh)
if [ -d "${SCRIPT_DIR}/lib" ]; then
    LIB_DIR="${SCRIPT_DIR}/lib"
else
    LIB_DIR="${MINIONS_HOME}/lib"
fi

# shellcheck disable=SC1091
. "${LIB_DIR}/detect.sh"

# Detect platform
if ! detect_platform; then
    log_error "Failed to detect platform"
    exit 1
fi

log_info "Platform: ${PLATFORM}"
log_info "Installing to: ${MINIONS_HOME}"
log_info "Ports: omniroute=${OMNIROUTE_PORT}, modelrelay=${MODELRELAY_PORT}"

# Step 1: Create directory structure
log_info "Creating directory structure at ${MINIONS_HOME}"
mkdir -p "${MINIONS_HOME}/lib"
mkdir -p "${MINIONS_HOME}/etc"
mkdir -p "${MINIONS_HOME}/var/run"
mkdir -p "${MINIONS_HOME}/var/log"
mkdir -p "${MINIONS_HOME}/bin"
mkdir -p "${MINIONS_HOME}/workspace"
mkdir -p "${MINIONS_HOME}/var/cache"

# Copy lib scripts (code, not config - force overwrite so fixes propagate)
if [ -d "${SCRIPT_DIR}/lib" ]; then
    log_info "Copying lib scripts..."
    cp -f "${SCRIPT_DIR}"/lib/*.sh "${MINIONS_HOME}/lib/" 2>/dev/null || true
    cp -f "${SCRIPT_DIR}"/boot.sh "${MINIONS_HOME}/boot.sh" 2>/dev/null || true
    cp -f "${SCRIPT_DIR}"/stop.sh "${MINIONS_HOME}/stop.sh" 2>/dev/null || true
    cp -f "${SCRIPT_DIR}"/status.sh "${MINIONS_HOME}/status.sh" 2>/dev/null || true
fi

# Copy versions.env so lib scripts can source it from MINIONS_HOME
if [ -f "${SCRIPT_DIR}/etc/versions.env" ]; then
    cp -f "${SCRIPT_DIR}/etc/versions.env" "${MINIONS_HOME}/etc/versions.env"
    log_info "Copied versions.env to ${MINIONS_HOME}/etc/"
fi

# Copy Mnemon seed templates so setup_mnemon_all can import them from MINIONS_HOME/etc
cp -f "${SCRIPT_DIR}"/etc/mnemon-seed-*.json "${MINIONS_HOME}/etc/" 2>/dev/null || true

# NOW source lib functions (from installed location)
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/download.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/node.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/uv.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/pi.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/hermes.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/npm_packages.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/omniroute.sh"
# shellcheck disable=SC1091
. "${MINIONS_HOME}/lib/mnemon.sh"

# Step 2: Source versions
if [ -f "${SCRIPT_DIR}/etc/versions.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${SCRIPT_DIR}/etc/versions.env"
fi

# Step 3: Install prerequisites
log_info "Installing prerequisites..."
ensure_uv

# Install vendored Node.js 22.22.2 for npm packages (OmniRoute, ModelRelay, Pi)
# These packages have compatibility issues with Node 24+
log_info "Installing vendored Node.js ${NODE_VERSION} for npm packages..."
ensure_node_v22

# Step 4: Install components
# Install Mnemon FIRST so it's available for Pi/Hermes plugin setup
log_info "Setting up Mnemon (memory layer)..."
ensure_mnemon "${MINIONS_HOME}"
setup_mnemon_all "${MINIONS_HOME}"

log_info "Installing Pi-Agent..."
ensure_pi

log_info "Installing OmniRoute..."
if [ "${INSTALL_OMNIROUTE}" -eq 1 ]; then
    ensure_omniroute
fi

log_info "Installing ModelRelay..."
if [ "${INSTALL_MODELRELAY}" -eq 1 ]; then
    ensure_modelrelay
fi

if [ "${INSTALL_HERMES}" -eq 1 ]; then
    log_info "Installing Hermes..."
    ensure_hermes
fi

# Phase 22: install mnemon plugin (idempotent)
install_mnemon_plugin

# Phase 22: knowledge asset copy
#   dev        → skip (assets live in repo; boot.sh will symlink)
#   standalone → copy skills/wiki/memories/mnemon into MINIONS_HOME
if [ "${MODE}" = "standalone" ]; then
    log_info "Knowledge mode: standalone — copying knowledge assets to ${MINIONS_HOME}"
    mkdir -p "${MINIONS_HOME}/skills" "${MINIONS_HOME}/wiki" \
             "${MINIONS_HOME}/memories" "${MINIONS_HOME}/mnemon"
    # Skills + wiki + mnemon: force-copy (code/config, fixes propagate)
    cp -r "${SCRIPT_DIR}/skills/." "${MINIONS_HOME}/skills/" 2>/dev/null || true
    cp -r "${SCRIPT_DIR}/wiki/." "${MINIONS_HOME}/wiki/" 2>/dev/null || true
    cp -r "${SCRIPT_DIR}/mnemon/." "${MINIONS_HOME}/mnemon/" 2>/dev/null || true
    # Memories: copy only if absent — USER.md/MEMORY.md survive reinstall
    for m in MEMORY.md USER.md; do
        if [ -f "${SCRIPT_DIR}/memories/${m}" ] && [ ! -f "${MINIONS_HOME}/memories/${m}" ]; then
            cp -f "${SCRIPT_DIR}/memories/${m}" "${MINIONS_HOME}/memories/${m}"
        fi
    done
    log_info "Knowledge assets copied (skills/wiki/mnemon; memories preserved)"
else
    log_info "Knowledge mode: dev — assets live in repo, symlinked at boot"
fi

# Persist knowledge mode for boot.sh (it may run from ${MINIONS_HOME} with no .git)
{
    echo "# Generated by install.sh — don't edit"
    echo "MINIONS_HOME=${MINIONS_HOME}"
    echo "MODE=${MODE}"
    echo "MINIONS_REPO_ROOT=${MINIONS_REPO_ROOT}"
} > "${MINIONS_HOME}/etc/knowledge.env"
log_info "Knowledge mode persisted to ${MINIONS_HOME}/etc/knowledge.env"

# Phase 23: dev-mode symlinks (so dev users get them immediately after install)
# Source the lib and run symlink setup
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib/knowledge-symlinks.sh"
setup_knowledge_symlinks "${MINIONS_HOME}" "${MINIONS_REPO_ROOT:-}" "${MODE}"

# Hermes user-skills link: ~/.hermes/skills/minions -> repo skills (dev) or
# ~/.minions/skills (standalone) — so Hermes discovers the .minions skills
# immediately after install (before the first boot).
if [ "${MODE}" = "dev" ]; then
    _HERMES_SKILL_TARGET="${MINIONS_REPO_ROOT}/skills"
else
    _HERMES_SKILL_TARGET="${MINIONS_HOME}/skills"
fi
setup_hermes_skill_link "${HOME}/.hermes" "${_HERMES_SKILL_TARGET}"

# Hermes memories link: ~/.hermes/memories -> repo memories (dev) or
# ~/.minions/memories (standalone) — so MEMORY.md/USER.md are git-tracked.
if [ "${MODE}" = "dev" ]; then
    _HERMES_MEM_TARGET="${MINIONS_REPO_ROOT}/memories"
else
    _HERMES_MEM_TARGET="${MINIONS_HOME}/memories"
fi
setup_hermes_memories_link "${HOME}/.hermes" "${_HERMES_MEM_TARGET}"

# Step 5: Copy and interpolate config templates
log_info "Copying and configuring templates..."

# Create Pi agent config directory
mkdir -p "${HOME}/.pi/agent"

# Copy pi.toml with port interpolation
if [ -f "${SCRIPT_DIR}/etc/pi.toml" ]; then
    sed -e "s|{{OMNIROUTE_PORT}}|${OMNIROUTE_PORT}|g" \
        -e "s|{{MODELRELAY_PORT}}|${MODELRELAY_PORT}|g" \
        "${SCRIPT_DIR}/etc/pi.toml" > "${HOME}/.pi/agent/pi.toml"
    log_info "Created ~/.pi/agent/pi.toml"
fi

# Copy models.json with port interpolation
if [ -f "${SCRIPT_DIR}/etc/models.json" ]; then
    sed -e "s|{{OMNIROUTE_PORT}}|${OMNIROUTE_PORT}|g" \
        -e "s|{{MODELRELAY_PORT}}|${MODELRELAY_PORT}|g" \
        "${SCRIPT_DIR}/etc/models.json" > "${HOME}/.pi/agent/models.json"
    log_info "Created ~/.pi/agent/models.json"
fi

# Copy settings.json is not used; Pi-Agent reads pi.toml + models.json.

# Create Hermes config.yaml
log_info "Creating ~/.hermes/config.yaml..."
mkdir -p "${HOME}/.hermes"
cat > "${HOME}/.hermes/config.yaml" << YAMLEOF
model:
  provider: omniroute
  default: auto-fastest
providers:
  omniroute:
    base_url: http://127.0.0.1:${OMNIROUTE_PORT}/v1
    api_key: no-key-needed
  modelrelay:
    base_url: http://127.0.0.1:${MODELRELAY_PORT}/v1
    api_key: no-key-needed
fallback_providers:
  - provider: modelrelay
    model: auto-fastest
approvals:
  mode: "off"
memory:
  memory_enabled: true
  user_profile_enabled: true
  provider: mnemon
agent:
  max_turns: 120
kanban:
  failure_limit: 3
display:
  busy_input_mode: steer
terminal:
  cwd: ${HOME}
YAMLEOF
log_info "Created ~/.hermes/config.yaml with ports omniroute=${OMNIROUTE_PORT}, modelrelay=${MODELRELAY_PORT}"

# (Mnemon seeds were already imported by setup_mnemon_all during install.)

# Step 6: Install pi-failover extension (CLI only, no proxy needed)
log_info "Installing pi-failover extension..."
if "${MINIONS_HOME}/bin/pi" install git:github.com/gitricko/pi-failover@hermes-impl 2>/dev/null; then
    log_info "pi-failover extension installed"
else
    log_warn "pi-failover extension install failed (may not exist yet or needs retry at boot)"
fi

# Step 7: Preconfigure OmniRoute default password and disable login (so boot is seamless)
log_info "Preconfiguring OmniRoute defaults..."
export PATH="${MINIONS_HOME}/lib/node/bin:${MINIONS_HOME}/lib/omniroute/npm/lib/node_modules/.bin:${PATH}"
export NODE_PATH="${MINIONS_HOME}/lib/omniroute/npm/lib/node_modules"
# NOTE: login-off is a direct sqlite write (requireLogin=false) — the documented
# mechanism that works WITHOUT a running server at install time. The REST api
# calls (`post-api-auth-login`, `post-api-settings-require-login`) that were here
# before silently failed (`|| true`) because no omniroute server is up during
# install, leaving requireLogin=true — which makes /v1/models return 401 on the
# booted stack (real-install CI failure). setup --non-interactive creates the DB;
# the UPDATE then flips the flag. Verified in DTS: requireLogin=false -> GET
# /v1/models returns 200 keyless.
"${MINIONS_HOME}/bin/omniroute" setup --non-interactive --password 'minions123' >/dev/null 2>&1 || true
# Disable login by writing the flag directly to the storage DB (needs no server).
OR_DB="${HOME}/.omniroute/storage.sqlite"
if [ -f "${OR_DB}" ]; then
    if sqlite3 "${OR_DB}" "UPDATE key_value SET value='false' WHERE key='requireLogin';" >/dev/null 2>&1; then
        log_info "OmniRoute login disabled (requireLogin=false)"
    else
        log_warn "Could not disable OmniRoute login (sqlite update failed)"
    fi
else
    log_warn "OmniRoute storage DB not found at ${OR_DB}; login not disabled"
fi

# Step 8: Set up PATH snippet
# shellcheck disable=SC2016
PATH_SNIPPET='
# .minions - added by installer
export MINIONS_HOME="${HOME}/.minions"
export PATH="${MINIONS_HOME}/bin:${PATH}"
'

# Add to shell rc files (only if not already present)
for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    if [ -f "${rc}" ] && ! grep -q "MINIONS_HOME" "${rc}"; then
        log_info "Adding MINIONS_HOME to ${rc}"
        printf '%s\n' "${PATH_SNIPPET}" >> "${rc}"
    fi
done

# Step 8: Print summary
echo ""
log_info "Installation complete!"
echo ""
echo "  Components installed to: ${MINIONS_HOME}"
echo "    - Pi-Agent:    ${MINIONS_HOME}/bin/pi (version ${PI_VERSION:-unknown})"
echo "    - OmniRoute:   ${MINIONS_HOME}/bin/omniroute (version ${OMNIROUTE_VERSION:-unknown})"
echo "    - ModelRelay:  ${MINIONS_HOME}/bin/modelrelay (version ${MODELRELAY_VERSION:-unknown})"
if [ "${INSTALL_HERMES}" -eq 1 ]; then
    echo "    - Hermes:      ${MINIONS_HOME}/bin/hermes (version ${HERMES_VERSION:-unknown})"
fi
echo "    - Mnemon:      ${MINIONS_HOME}/bin/mnemon (if available)"
echo ""
echo "  Next step: run '${MINIONS_HOME}/boot.sh' to start the stack"
if [ -t 1 ]; then
    echo "  Or open a new shell / source your rc file: source ~/.bashrc"
fi
echo ""

# Create a quick-start note
cat > "${MINIONS_HOME}/QUICKSTART.md" << 'EOF'
# .minions Quickstart

Start the full stack:
    ~/.minions/boot.sh

Stop the stack:
    ~/.minions/stop.sh

Check status:
    ~/.minions/status.sh

Switch LLM proxy to ModelRelay:
    export MINIONS_LLM_BASE_URL=http://localhost:7352/v1
    ~/.minions/boot.sh
EOF