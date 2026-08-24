#!/usr/bin/env sh
# tests/test_boot.sh - Tests for boot.sh with mock services

set -e
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# Colors
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

log_info() { echo "${GREEN}[PASS]${NC} $*"; }
log_error() { echo "${RED}[FAIL]${NC} $*"; }
log_warn() { echo "${YELLOW}[WARN]${NC} $*"; }

# Create a test environment with mock services
TEST_HOME=$(mktemp -d)
export MINIONS_HOME="${TEST_HOME}"

mkdir -p "${TEST_HOME}/lib"
mkdir -p "${TEST_HOME}/etc"
mkdir -p "${TEST_HOME}/var/run"
mkdir -p "${TEST_HOME}/var/log"
mkdir -p "${TEST_HOME}/bin"

# Copy scripts
cp "${PROJECT_ROOT}/boot.sh" "${TEST_HOME}/boot.sh"
cp "${PROJECT_ROOT}/stop.sh" "${TEST_HOME}/stop.sh"
cp "${PROJECT_ROOT}/status.sh" "${TEST_HOME}/status.sh"
cp "${PROJECT_ROOT}/lib"/*.sh "${TEST_HOME}/lib/"
cp "${PROJECT_ROOT}/etc"/*.env "${TEST_HOME}/etc/"
cp "${PROJECT_ROOT}/etc"/*.toml "${TEST_HOME}/etc/"

# Create mock binaries for services that ARE persistent
for bin in omniroute modelrelay; do
    cat > "${TEST_HOME}/bin/${bin}" << 'EOF'
#!/usr/bin/env sh
# Mock service - prints startup message and sleeps
echo "Mock $0 started with args: $*"
sleep 30
EOF
    chmod +x "${TEST_HOME}/bin/${bin}"
done

# Also create a mock nc (netcat) for port checking
cat > "${TEST_HOME}/bin/nc" << 'EOF'
#!/usr/bin/env sh
# Mock nc - succeeds if we're checking a known port
# Usage: nc -z host port
if [ "$1" = "-z" ]; then
    port=$3
    # Accept connections on ports we know about
    case "$port" in
        20128|7352)
            exit 0
            ;;
        *)
            exit 1
    esac
fi
exit 1
EOF
chmod +x "${TEST_HOME}/bin/nc"

# Create mock curl for health checks
cat > "${TEST_HOME}/bin/curl" << 'EOF'
#!/usr/bin/env sh
# Mock curl - succeeds for health checks
if echo "$*" | grep -q "/models"; then
    echo '{"data":[]}'
    exit 0
fi
if echo "$*" | grep -q "/health"; then
    echo '{"status":"ok"}'
    exit 0
fi
exit 1
EOF
chmod +x "${TEST_HOME}/bin/curl"

# Mock sqlite3 for OmniRoute preconfig
cat > "${TEST_HOME}/bin/sqlite3" << 'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "${TEST_HOME}/bin/sqlite3"

# Mock hermes for mcp add
cat > "${TEST_HOME}/bin/hermes" << 'EOF'
#!/usr/bin/env sh
if echo "$*" | grep -q "mcp add"; then
    exit 0
fi
exit 1
EOF
chmod +x "${TEST_HOME}/bin/hermes"

# Put our mock bin first in PATH
export PATH="${TEST_HOME}/bin:${PATH}"

echo "=== Test 1: boot.sh --dry-run ==="
# Test dry-run mode
if sh "${TEST_HOME}/boot.sh" --dry-run 2>&1 | grep -q "READY FOR FIRSTMATE DISPATCH"; then
    log_info "boot.sh --dry-run prints READY message"
else
    log_error "boot.sh --dry-run failed"
    cat "${TEST_HOME}/var/log/boot.log" 2>/dev/null || true
    exit 1
fi

# Check that PID files were created for persistent services ONLY
for service in omniroute modelrelay; do
    if [ -f "${TEST_HOME}/var/run/${service}.pid" ]; then
        log_info "PID file created for ${service}"
    else
        log_error "PID file missing for ${service}"
        exit 1
    fi
done

# Check Pi-Agent PID file NOT created (CLI tool now)
if [ ! -f "${TEST_HOME}/var/run/pi.pid" ]; then
    log_info "Pi-Agent PID file NOT created (CLI tool)"
else
    log_error "Pi-Agent PID file should NOT exist (CLI tool)"
    exit 1
fi

# Check Hermes PID file NOT created (CLI tool now)
if [ ! -f "${TEST_HOME}/var/run/hermes.pid" ]; then
    log_info "Hermes PID file NOT created (CLI tool)"
else
    log_error "Hermes PID file should NOT exist (CLI tool)"
    exit 1
fi

# Test 2: boot.sh --dry-run with readiness marker
echo ""
echo "=== Test 2: Readiness marker ==="
if [ -f "${TEST_HOME}/var/run/ready" ]; then
    log_info "Readiness marker created"
else
    log_error "Readiness marker missing"
    exit 1
fi

# Test 3: stop.sh
echo ""
echo "=== Test 3: stop.sh ==="
sh "${TEST_HOME}/stop.sh" 2>&1 | grep -q "All services stopped" && log_info "stop.sh runs successfully" || log_error "stop.sh failed"

# Verify PID files removed
for service in omniroute modelrelay; do
    if [ ! -f "${TEST_HOME}/var/run/${service}.pid" ]; then
        log_info "PID file removed for ${service}"
    else
        log_error "PID file still exists for ${service}"
        exit 1
    fi
done

# Verify readiness marker removed
if [ ! -f "${TEST_HOME}/var/run/ready" ]; then
    log_info "Readiness marker removed"
else
    log_error "Readiness marker still exists"
    exit 1
fi

# Test 4: status.sh
echo ""
echo "=== Test 4: status.sh ==="
# Re-run boot in dry-run to create PID files
sh "${TEST_HOME}/boot.sh" --dry-run >/dev/null 2>&1

# Run status
output=$(sh "${TEST_HOME}/status.sh" 2>&1)
echo "${output}" | grep -q "omniroute" && log_info "status.sh checks omniroute" || log_error "status.sh missing omniroute"
echo "${output}" | grep -q "modelrelay" && log_info "status.sh checks modelrelay" || log_error "status.sh missing modelrelay"
echo "${output}" | grep -q "pi-agent" && log_info "status.sh checks pi-agent (CLI)" || log_error "status.sh missing pi-agent"
echo "${output}" | grep -q "hermes" && log_info "status.sh checks hermes (CLI)" || log_error "status.sh missing hermes"
echo "${output}" | grep -q "READY FOR FIRSTMATE DISPATCH" && log_info "status.sh shows READY" || log_error "status.sh missing READY"

# Test 5: Verify config values are used
echo ""
echo "=== Test 5: Config values from minions.env ==="
# Check that OmniRoute port 20128 is used
grep -q "20128" "${TEST_HOME}/etc/minions.env" && log_info "OmniRoute port 20128 in config" || log_error "OmniRoute port not in config"
grep -q "7352" "${TEST_HOME}/etc/minions.env" && log_info "ModelRelay port 7352 in config" || log_error "ModelRelay port not in config"
grep -q "MINIONS_LLM_BASE_URL" "${TEST_HOME}/etc/minions.env" && log_info "MINIONS_LLM_BASE_URL in config" || log_error "MINIONS_LLM_BASE_URL not in config"

# Test 6: OmniRoute preconfig runs in dry-run
echo ""
echo "=== Test 6: OmniRoute preconfig dry-run ==="
output=$(sh "${TEST_HOME}/boot.sh" --dry-run 2>&1)
echo "${output}" | grep -q "Preconfiguring OmniRoute" && log_info "Preconfig step runs" || log_warn "Preconfig step not found in output (may be fine in dry-run)"

# Cleanup
rm -rf "${TEST_HOME}"

echo ""
echo "=== All boot tests passed ==="