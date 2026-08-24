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

# Create mock binaries that just sleep (to simulate running services)
for bin in omniroute modelrelay pi hermes; do
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
        20128|7352|8080|8081)
            exit 0
            ;;
        *)
            exit 1
            ;;
    esac
fi
exit 1
EOF
chmod +x "${TEST_HOME}/bin/nc"

# Create mock curl for health checks
cat > "${TEST_HOME}/bin/curl" << 'EOF'
#!/usr/bin/env sh
# Mock curl - succeeds for health checks
if echo "$*" | grep -q "/health"; then
    echo '{"status":"ok"}'
    exit 0
fi
exit 1
EOF
chmod +x "${TEST_HOME}/bin/curl"

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

# Check that PID files were created
for service in omniroute modelrelay pi; do
    if [ -f "${TEST_HOME}/var/run/${service}.pid" ]; then
        log_info "PID file created for ${service}"
    else
        log_error "PID file missing for ${service}"
        exit 1
    fi
done

# Check Hermes not started (default off)
if [ ! -f "${TEST_HOME}/var/run/hermes.pid" ]; then
    log_info "Hermes not started (default off)"
else
    log_error "Hermes started unexpectedly"
    exit 1
fi

# Test 2: boot.sh with MINIONS_HERMES=on
echo ""
echo "=== Test 2: boot.sh --dry-run with MINIONS_HERMES=on ==="
MINIONS_HERMES=on sh "${TEST_HOME}/boot.sh" --dry-run 2>&1 | grep -q "hermes" && log_info "Hermes started when enabled" || log_error "Hermes not started when enabled"

if [ -f "${TEST_HOME}/var/run/hermes.pid" ]; then
    log_info "Hermes PID file created"
else
    log_error "Hermes PID file missing"
    exit 1
fi

# Test 3: stop.sh
echo ""
echo "=== Test 3: stop.sh ==="
sh "${TEST_HOME}/stop.sh" 2>&1 | grep -q "All services stopped" && log_info "stop.sh runs successfully" || log_error "stop.sh failed"

# Verify PID files removed
for service in omniroute modelrelay pi hermes; do
    if [ ! -f "${TEST_HOME}/var/run/${service}.pid" ]; then
        log_info "PID file removed for ${service}"
    else
        log_error "PID file still exists for ${service}"
        exit 1
    fi
done

# Test 4: status.sh
echo ""
echo "=== Test 4: status.sh ==="
# Re-run boot in dry-run to create PID files
sh "${TEST_HOME}/boot.sh" --dry-run >/dev/null 2>&1

# Run status
output=$(sh "${TEST_HOME}/status.sh" 2>&1)
echo "${output}" | grep -q "omniroute" && log_info "status.sh checks omniroute" || log_error "status.sh missing omniroute"
echo "${output}" | grep -q "modelrelay" && log_info "status.sh checks modelrelay" || log_error "status.sh missing modelrelay"
echo "${output}" | grep -q "pi-agent" && log_info "status.sh checks pi-agent" || log_error "status.sh missing pi-agent"

# Test 5: Verify config values are used
echo ""
echo "=== Test 5: Config values from minions.env ==="
# Check that OmniRoute port 20128 is used
grep -q "20128" "${TEST_HOME}/etc/minions.env" && log_info "OmniRoute port 20128 in config" || log_error "OmniRoute port not in config"
grep -q "7352" "${TEST_HOME}/etc/minions.env" && log_info "ModelRelay port 7352 in config" || log_error "ModelRelay port not in config"
grep -q "MINIONS_LLM_BASE_URL" "${TEST_HOME}/etc/minions.env" && log_info "MINIONS_LLM_BASE_URL in config" || log_error "MINIONS_LLM_BASE_URL not in config"

# Cleanup
rm -rf "${TEST_HOME}"

echo ""
echo "=== All boot tests passed ==="