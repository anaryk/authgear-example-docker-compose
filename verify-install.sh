#!/usr/bin/env bash
#
# Authgear Installation Verification Script
# Checks if all required files and configurations are in place
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0

# Logging functions
log_info() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

check_pass() {
    log_info "$1"
    ((CHECKS_PASSED++))
}

check_fail() {
    log_error "$1"
    ((CHECKS_FAILED++))
}

echo "🔍 Authgear Installation Verification"
echo "======================================"
echo

# Check var/authgear.yaml
if [ -f "./var/authgear.yaml" ]; then
    check_pass "var/authgear.yaml exists"
else
    check_fail "var/authgear.yaml is MISSING"
fi

# Check var/authgear.secrets.yaml
if [ -f "./var/authgear.secrets.yaml" ]; then
    check_pass "var/authgear.secrets.yaml exists"
    
    # Check for images.db section
    if grep -q "images.db" "./var/authgear.secrets.yaml"; then
        check_pass "authgear.secrets.yaml contains images.db configuration"
    else
        check_fail "authgear.secrets.yaml is MISSING images.db configuration"
    fi
else
    check_fail "var/authgear.secrets.yaml is MISSING"
fi

# Check .env file
if [ -f ".env" ]; then
    check_pass ".env file exists"
else
    check_fail ".env file is MISSING"
fi

# Check docker-compose.production.yml
if [ -f "docker-compose.production.yml" ]; then
    check_pass "docker-compose.production.yml exists"
else
    check_fail "docker-compose.production.yml is MISSING"
fi

# Check if Docker is running
if docker info >/dev/null 2>&1; then
    check_pass "Docker is running"
else
    check_fail "Docker is NOT running"
fi

# Check if containers are running
echo
echo "Container Status:"
echo "-----------------"
docker compose -f docker-compose.production.yml ps 2>/dev/null || echo "Cannot get container status"

echo
echo "======================================"
echo "Summary: ${CHECKS_PASSED} passed, ${CHECKS_FAILED} failed"
echo "======================================"

if [ ${CHECKS_FAILED} -gt 0 ]; then
    echo
    log_error "Some checks failed! Please fix the issues above."
    exit 1
else
    echo
    log_info "All checks passed! ✨"
    exit 0
fi
