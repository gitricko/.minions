#!/usr/bin/env bash
# docker-test.sh - Docker-based local testing for .minions
#
# Usage:
#   ./docker-test.sh test    # Full test: install + boot + status + CLI checks + LLM call
#   ./docker-test.sh shell   # Interactive: drop into shell after setup for debugging
#   ./docker-test.sh clean   # Cleanup: remove the test container

set -euo pipefail

# Color output
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }

# Configuration
DOCKER_IMAGE="${DOCKER_IMAGE:-ubuntu:24.04}"
CONTAINER_NAME="minions-test"
REPO_PATH="$(cd "$(dirname "$0")" && pwd)"
SRC_MOUNT="/src"

# Non-root user matching Codespace/runner (uid 1000, gid 1000)
CONTAINER_UID=1000
CONTAINER_GID=1000
CONTAINER_USER=""
CONTAINER_HOME=""

# Build docker exec environment flags for the non-root .minions user.
minions_env_flags() {
    local home="$1"
    local mh="${home}/.minions"
    local path="${mh}/bin:${mh}/lib/node/bin:${mh}/lib/uv:${PATH}"
    printf -- '--user %s:%s -e HOME=%s -e MINIONS_HOME=%s -e PATH=%s' \
        "${CONTAINER_UID}" "${CONTAINER_GID}" "${home}" "${mh}" "${path}"
}

# Record test results
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

record_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_pass "$1"
}

record_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
    log_fail "$1"
}

print_summary() {
    echo ""
    echo "=============================================="
    echo "  Test Summary"
    echo "=============================================="
    echo "  Passed: ${TESTS_PASSED}"
    echo "  Failed: ${TESTS_FAILED}"
    if [ ${TESTS_FAILED} -gt 0 ]; then
        echo ""
        echo "  Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "    - ${test}"
        done
    fi
    echo "=============================================="
}

# Docker helpers
docker_exec() {
    docker exec "${CONTAINER_NAME}" "$@"
}

# Run a command as the non-root .minions user inside the running container.
docker_exec_user() {
    local env_flags
    env_flags=$(minions_env_flags "${CONTAINER_HOME}")
    docker exec ${env_flags} "${CONTAINER_NAME}" bash -l -c "$1"
}

# Remove the test container if it exists (idempotent)
cleanup_container() {
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

# Resolve the non-root user (uid 1000) inside the container.
# ubuntu:24.04 ships with an 'ubuntu' user at uid/gid 1000; reuse it.
# Otherwise create a fresh 'runner' account.
resolve_user() {
    if docker_exec bash -c 'id ubuntu' >/dev/null 2>&1; then
        CONTAINER_USER=ubuntu
        CONTAINER_HOME=/home/ubuntu
    else
        docker_exec bash -c "groupadd -g 1000 runner 2>/dev/null || true; useradd -u 1000 -g 1000 -m -s /bin/bash runner"
        CONTAINER_USER=runner
        CONTAINER_HOME=/home/runner
    fi
    log_info "Using non-root user '${CONTAINER_USER}' with home '${CONTAINER_HOME}'"
}

# Mode: test mode
mode_test() {
    log_info "Starting test mode"
    echo ""

    setup_container
    run_install || true
    run_boot || true
    run_status || true
    verify_binaries
    verify_llm_call
    verify_pi_call

    print_summary

    if [ ${TESTS_FAILED} -gt 0 ]; then
        log_error "Some tests failed"
        exit 1
    else
        log_info "All tests passed!"
        exit 0
    fi
}

# Mode: shell mode
mode_shell() {
    log_info "Starting shell mode"
    echo ""

    setup_container
    run_install || true
    run_boot || true
    run_status || true
    verify_binaries

    log_info "Dropping into interactive shell (type 'exit' to leave container running)"
    log_info "Container will persist - use './docker-test.sh clean' to remove it"
    echo ""

    docker exec -it --user "${CONTAINER_UID}:${CONTAINER_GID}" \
        -e "HOME=${CONTAINER_HOME}" \
        -e "MINIONS_HOME=${CONTAINER_HOME}/.minions" \
        -e "PATH=${CONTAINER_HOME}/.minions/bin:${CONTAINER_HOME}/.minions/lib/node/bin:${CONTAINER_HOME}/.minions/lib/uv:${PATH}" \
        "${CONTAINER_NAME}" env bash -l
}

# Mode: clean mode
mode_clean() {
    log_info "Cleaning up test container"
    cleanup_container
    log_info "Done"
}

# Set up the container: pull image, create, user, deps
setup_container() {
    log_step "Pulling base image: ${DOCKER_IMAGE}"
    docker pull "${DOCKER_IMAGE}"

    log_step "Removing any existing container: ${CONTAINER_NAME}"
    cleanup_container

    log_step "Starting container: ${CONTAINER_NAME}"
    docker run -d \
        --name "${CONTAINER_NAME}" \
        -v "${REPO_PATH}:${SRC_MOUNT}" \
        "${DOCKER_IMAGE}" \
        sleep infinity

    # Wait for container to be ready
    sleep 2

    # Resolve non-root user (matching Codespace/runner: uid 1000)
    log_step "Resolving non-root user (uid=${CONTAINER_UID}, gid=${CONTAINER_GID})"
    resolve_user

    # Ensure the uid-1000 user owns the mounted source and their home dir
    docker_exec bash -c "
        chown -R ${CONTAINER_UID}:${CONTAINER_GID} ${SRC_MOUNT}
        mkdir -p ${CONTAINER_HOME}
        chown -R ${CONTAINER_UID}:${CONTAINER_GID} ${CONTAINER_HOME}
    "

    # Install minimal dependencies (bash for Hermes install, util-linux for
    # setsid, python3 for hermes config YAML manipulation)
    log_step "Installing minimal dependencies (curl, git, ca-certificates, bash, util-linux, python3)"
    docker_exec bash -c "apt-get update && apt-get install -y curl git ca-certificates bash util-linux python3 xz-utils g++ make"
}

# Run install.sh inside the container
run_install() {
    log_step "Running install.sh"
    if docker_exec_user "bash ${SRC_MOUNT}/install.sh"; then
        record_pass "install.sh completed successfully"
    else
        record_fail "install.sh failed"
        return 1
    fi
}

# Run boot.sh inside the container
run_boot() {
    log_step "Running boot.sh"
    if docker_exec_user "bash ${CONTAINER_HOME}/boot.sh"; then
        record_pass "boot.sh completed successfully"
    else
        record_fail "boot.sh failed"
        return 1
    fi
}

# Run status.sh inside the container
run_status() {
    log_step "Running status.sh"
    if docker_exec_user "bash ${CONTAINER_HOME}/status.sh"; then
        record_pass "status.sh completed successfully"
    else
        record_fail "status.sh failed"
        return 1
    fi
}

# Verify the key binaries exist and --version works
verify_binaries() {
    log_step "Verifying binaries"

    # hermes --version
    if docker_exec_user "hermes --version" >/dev/null 2>&1; then
        record_pass "hermes --version works"
    else
        record_fail "hermes --version failed"
    fi

    # pi --version
    if docker_exec_user "pi --version" >/dev/null 2>&1; then
        record_pass "pi --version works"
    else
        record_fail "pi --version failed"
    fi

    # mnemon --version
    if docker_exec_user "mnemon --version" >/dev/null 2>&1; then
        record_pass "mnemon --version works"
    else
        record_fail "mnemon --version failed"
    fi
}

# Verify actual LLM call through OmniRoute (keyless via free providers)
verify_llm_call() {
    log_step "Verifying LLM call through OmniRoute (keyless via free providers)"

    # Wait a bit for OmniRoute to be fully ready
    sleep 5

    # Test actual LLM call via OmniRoute (model=auto uses free providers, no API key needed)
    llm_out=$(docker_exec_user "hermes chat -q 'Reply with exactly: OK'" 2>&1) || true
    if printf '%s' "${llm_out}" | grep -qi "OK"; then
        record_pass "LLM call through OmniRoute works (keyless)"
    else
        log_warn "LLM call test - failing output was:"
        printf '%s\n' "${llm_out}" | head -20
        record_fail "LLM call through OmniRoute failed"
    fi
}

# Verify Pi-Agent call (requires provider config, expects failure without auth)
verify_pi_call() {
    log_step "Verifying Pi-Agent call (requires provider config)"

    # Test Pi-Agent call - this requires provider setup, so we expect it to fail without auth
    # but we verify the binary works and gives a meaningful error (not "command not found")
    pi_out=$(docker_exec_user "pi -p 'Reply with exactly: OK'" 2>&1) || true
    if printf '%s' "${pi_out}" | grep -qi "OK"; then
        record_pass "Pi-Agent call works (provider configured)"
    elif printf '%s' "${pi_out}" | grep -qi "API key\|login\|provider"; then
        record_pass "Pi-Agent binary works (provider config needed - expected without auth)"
    else
        log_warn "Pi-Agent call test - output was:"
        printf '%s\n' "${pi_out}" | head -20
        record_fail "Pi-Agent call failed unexpectedly"
    fi
}

# Main dispatcher
main() {
    mode="${1:-}"

    case "${mode}" in
        test)
            mode_test
            ;;
        shell)
            mode_shell
            ;;
        clean)
            mode_clean
            ;;
        *)
            echo "Usage: $0 {test|shell|clean}"
            echo ""
            echo "  test   - Full test: install + boot + status + CLI checks + LLM call"
            echo "  shell  - Interactive shell after setup for debugging"
            echo "  clean  - Remove the test container"
            echo ""
            echo "Environment variables:"
            echo "  DOCKER_IMAGE - Base Docker image (default: ubuntu:24.04)"
            exit 1
            ;;
    esac
}

main "$@"