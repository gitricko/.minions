#!/usr/bin/env sh
# .minions bootstrap installer
# One-liner: curl -fsSL https://minions.sh/install.sh | bash
#
# This script:
#   1. Detects OS/arch
#   2. Creates ~/.minions directory structure
#   3. Checks/installs prerequisites (Node, uv, Bun-based Pi binary)
#   4. Vendors/installs: Hermes, Pi-Agent, OmniRoute, ModelRelay
#   5. Writes config files (versions.env, minions.env, pi.toml)
#   6. Fixes macOS quarantine where needed
#
# Usage:
#   install.sh [--dry-run] [--no-hermes] [--minions-home PATH]

set -e
set -u

# Defaults
MINIONS_HOME="${MINIONS_HOME:-${HOME}/.minions}"
DRY_RUN=0
INSTALL_HERMES=1

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --no-hermes)
            INSTALL_HERMES=0
            shift
            ;;
        --minions-home)
            MINIONS_HOME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: install.sh [--dry-run] [--no-hermes] [--minions-home PATH]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
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
log_dry() { echo "${YELLOW}[DRY-RUN]${NC} $*"; }

# Source lib functions (relative to script location)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Detect platform FIRST (needs detect.sh)
# If running from a checked-out repo, use repo's lib; otherwise from install location
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

# In dry-run mode, echo actions instead of executing them
if [ "${DRY_RUN}" -eq 1 ]; then
    log_dry "Running in dry-run mode - no actual changes will be made"
    # Override install functions to be no-ops that print
    download_file() {
        log_dry "Would download: $1 -> $2"
        # Create empty file so subsequent steps don't fail
        mkdir -p "$(dirname "$2")"
        touch "$2"
    }
    install_vendored_node() {
        log_dry "Would install vendored Node $1 to $2"
        mkdir -p "$2/bin"
        touch "$2/bin/node"
        chmod +x "$2/bin/node"
    }
    install_vendored_uv() {
        log_dry "Would install vendored uv $1 to $2"
        mkdir -p "$2"
        touch "$2/uv"
        chmod +x "$2/uv"
    }
    install_pi() {
        log_dry "Would install Pi-Agent $1 to $2"
        mkdir -p "$2"
        touch "$2/pi"
        chmod +x "$2/pi"
    }
    install_hermes() {
        log_dry "Would install Hermes $1 to $2"
        mkdir -p "$2"
        touch "$2/hermes"
        chmod +x "$2/hermes"
    }
    install_npm_package() {
        log_dry "Would install npm package $1@$2 to $3 ($4)"
        mkdir -p "$3"
        touch "$3/$4"
        chmod +x "$3/$4"
    }
    install_mnemon() {
        log_dry "Would install Mnemon to $1"
        mkdir -p "$1"
        touch "$1/mnemon"
        chmod +x "$1/mnemon"
    }
    ensure_mnemon() {
        log_dry "Would ensure Mnemon"
        install_mnemon "${MINIONS_HOME}/lib/mnemon"
    }
    setup_mnemon_all() {
        log_dry "Would setup Mnemon for all targets in $1"
    }
fi

# Step 1: Create directory structure
log_info "Creating directory structure at ${MINIONS_HOME}"
mkdir -p "${MINIONS_HOME}/lib"
mkdir -p "${MINIONS_HOME}/etc"
mkdir -p "${MINIONS_HOME}/var/run"
mkdir -p "${MINIONS_HOME}/var/log"
mkdir -p "${MINIONS_HOME}/bin"
mkdir -p "${MINIONS_HOME}/workspace"
mkdir -p "${MINIONS_HOME}/var/cache"

# Copy config templates if running from a repo checkout (always, even in dry-run for sourcing)
if [ -d "${SCRIPT_DIR}/etc" ]; then
    log_info "Copying config templates..."
    cp -n "${SCRIPT_DIR}"/etc/*.env "${SCRIPT_DIR}"/etc/*.toml "${SCRIPT_DIR}"/etc/*.json "${MINIONS_HOME}/etc/" 2>/dev/null || true
    cp -n "${SCRIPT_DIR}"/lib/*.sh "${MINIONS_HOME}/lib/" 2>/dev/null || true
    cp -n "${SCRIPT_DIR}"/boot.sh "${MINIONS_HOME}/boot.sh" 2>/dev/null || true
    cp -n "${SCRIPT_DIR}"/stop.sh "${MINIONS_HOME}/stop.sh" 2>/dev/null || true
    cp -n "${SCRIPT_DIR}"/status.sh "${MINIONS_HOME}/status.sh" 2>/dev/null || true
fi

# NOW source remaining lib functions (from installed location)
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
. "${MINIONS_HOME}/lib/mnemon.sh"

# Step 2: Source versions
if [ -f "${MINIONS_HOME}/etc/versions.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "${MINIONS_HOME}/etc/versions.env"
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
ensure_omniroute

log_info "Installing ModelRelay..."
ensure_modelrelay

if [ "${INSTALL_HERMES}" -eq 1 ]; then
    log_info "Installing Hermes (opt-in)..."
    # Preconfigure Hermes (set auto-fastest model, disable login)
    MINIONS_HERMES_PRECONFIG=1
    ensure_hermes
    
    # Update Hermes config with current ports
    if [ "${DRY_RUN}" -eq 0 ]; then
        # Set HERMES_HOME so hermes_update_config finds the right config
        export HERMES_HOME="${MINIONS_HOME}/lib/hermes/home"
        # shellcheck disable=SC1091
        . "${MINIONS_HOME}/etc/minions.env"
        hermes_update_config "${OMNIROUTE_PORT:-20128}" "${MODELRELAY_PORT:-7352}"
    fi
fi

# Update Pi config with current ports
if [ "${DRY_RUN}" -eq 0 ]; then
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/etc/minions.env"
    # shellcheck disable=SC1091
    . "${MINIONS_HOME}/lib/pi.sh"
    pi_update_config "${OMNIROUTE_PORT:-20128}" "${MODELRELAY_PORT:-7352}"
fi

# Step 5: Set up PATH snippet
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
        if [ "${DRY_RUN}" -eq 0 ]; then
            printf '%s\n' "${PATH_SNIPPET}" >> "${rc}"
        fi
    fi
done

# Step 6: Print summary
echo ""
log_info "Installation complete!"
echo ""
echo "  Components installed to: ${MINIONS_HOME}"
echo "    - Pi-Agent:    ${MINIONS_HOME}/lib/pi/pi (version ${PI_VERSION:-unknown})"
echo "    - OmniRoute:   ${MINIONS_HOME}/lib/omniroute/omniroute (version ${OMNIROUTE_VERSION:-unknown})"
echo "    - ModelRelay:  ${MINIONS_HOME}/lib/modelrelay/modelrelay (version ${MODELRELAY_VERSION:-unknown})"
if [ "${INSTALL_HERMES}" -eq 1 ]; then
    echo "    - Hermes:      ${MINIONS_HOME}/lib/hermes/hermes (version ${HERMES_VERSION:-unknown})"
fi
echo "    - Mnemon:      ${MINIONS_HOME}/lib/mnemon/mnemon (if available)"
echo ""
echo "  Next step: run '${MINIONS_HOME}/boot.sh' to start the stack"
if [ -t 1 ]; then
    echo "  Or open a new shell / source your rc file: source ~/.bashrc"
fi
echo ""

# Create a quick-start note
if [ "${DRY_RUN}" -eq 0 ]; then
    cat > "${MINIONS_HOME}/QUICKSTART.md" << 'EOF'
# .minions Quickstart

Start the full stack:
    ~/.minions/boot.sh

Stop the stack:
    ~/.minions/stop.sh

Check status:
    ~/.minions/status.sh

Enable Hermes gateway:
    export MINIONS_HERMES=on

Point Pi-Agent at ModelRelay instead of OmniRoute:
    export MINIONS_LLM_BASE_URL=http://localhost:7352/v1
EOF
fi