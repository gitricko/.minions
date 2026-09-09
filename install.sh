#!/usr/bin/env sh
# .minions bootstrap installer
# One-liner: curl -fsSL https://minions.sh/install.sh | bash
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

# Environment (set in ~/.bashrc BEFORE running):
#   OMNIROUTE_PORT=20128   (default)
#   MODELRELAY_PORT=7352   (default)

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
omniroute:
  login_required: false
custom_providers:
  - name: omniroute
    base_url: http://127.0.0.1:${OMNIROUTE_PORT}/v1
  - name: modelrelay
    base_url: http://127.0.0.1:${MODELRELAY_PORT}/v1
YAMLEOF
log_info "Created ~/.hermes/config.yaml with ports omniroute=${OMNIROUTE_PORT}, modelrelay=${MODELRELAY_PORT}"

# (Mnemon seeds were already imported by setup_mnemon_all during install.)

# Step 6: Install pi-failover extension (CLI only, no proxy needed)
log_info "Installing pi-failover extension..."
if "${MINIONS_HOME}/bin/pi" install git:github.com/gitricko/pi-failover@hermes-impl 2>/dev/null; then
    log_info "pi-failover extension installed"
    "${MINIONS_HOME}/bin/pi" extensions reload 2>/dev/null || true
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