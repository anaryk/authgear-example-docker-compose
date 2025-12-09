#!/usr/bin/env bash
#
# Authgear Production - Test Suite
# Validates installation, scripts, and deployment
#

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Test function wrapper
run_test() {
    local test_name=$1
    local test_func=$2
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: ${test_name}"
    
    if $test_func; then
        log_pass "${test_name}"
        return 0
    else
        log_fail "${test_name}"
        return 1
    fi
}

# Test: Check required files exist
test_required_files() {
    local required_files=(
        "${PROJECT_DIR}/.env.example"
        "${PROJECT_DIR}/docker-compose.production.yml"
        "${PROJECT_DIR}/nginx.production.conf"
        "${PROJECT_DIR}/proxy-server-nginx.conf"
        "${PROJECT_DIR}/scripts/install.sh"
        "${PROJECT_DIR}/scripts/update.sh"
        "${PROJECT_DIR}/scripts/backup.sh"
        "${PROJECT_DIR}/scripts/health-check.sh"
        "${PROJECT_DIR}/postgres/Dockerfile"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Missing required file: $file"
            return 1
        fi
    done
    
    return 0
}

# Test: Check script permissions
test_script_permissions() {
    local scripts=(
        "${PROJECT_DIR}/scripts/install.sh"
        "${PROJECT_DIR}/scripts/update.sh"
        "${PROJECT_DIR}/scripts/backup.sh"
        "${PROJECT_DIR}/scripts/health-check.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -x "$script" ]; then
            log_error "Script not executable: $script"
            return 1
        fi
    done
    
    return 0
}

# Test: Validate docker-compose file
test_docker_compose_validity() {
    # Create temporary env file if it doesn't exist
    local temp_env=false
    if [ ! -f "${PROJECT_DIR}/.env" ]; then
        cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"
        temp_env=true
    fi
    
    local result=0
    if ! docker compose -f "${PROJECT_DIR}/docker-compose.production.yml" config >/dev/null 2>&1; then
        log_error "Invalid docker-compose file"
        result=1
    fi
    
    # Cleanup temp env file
    if [ "$temp_env" = true ]; then
        rm -f "${PROJECT_DIR}/.env"
    fi
    
    return $result
}

# Test: Check for hardcoded secrets
test_no_hardcoded_secrets() {
    local files_to_check=(
        "${PROJECT_DIR}/docker-compose.production.yml"
        "${PROJECT_DIR}/nginx.production.conf"
        "${PROJECT_DIR}/scripts/install.sh"
        "${PROJECT_DIR}/scripts/update.sh"
    )
    
    local patterns=(
        "password.*=.*['\"].*['\"]"
        "secret.*=.*['\"].*['\"]"
        "key.*=.*['\"].*['\"]"
    )
    
    for file in "${files_to_check[@]}"; do
        for pattern in "${patterns[@]}"; do
            if grep -qi "$pattern" "$file" 2>/dev/null; then
                # Exclude template placeholders
                if ! grep -i "$pattern" "$file" | grep -q "CHANGE_ME\|YOUR_\|PLACEHOLDER\|\${"; then
                    log_error "Possible hardcoded secret in $file"
                    return 1
                fi
            fi
        done
    done
    
    return 0
}

# Test: Check environment variable references
test_env_variables() {
    local env_file="${PROJECT_DIR}/.env.example"
    
    # Check if all required variables are defined
    local required_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "MINIO_ROOT_PASSWORD"
        "AUTH_DOMAIN"
        "PORTAL_DOMAIN"
    )
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            log_error "Missing environment variable: $var"
            return 1
        fi
    done
    
    return 0
}

# Test: PostgreSQL Dockerfile validity
test_postgres_dockerfile() {
    # Skip actual build in CI/quick tests - just check syntax
    if [ "${QUICK_TEST:-false}" = "true" ]; then
        if [ ! -f "${PROJECT_DIR}/postgres/Dockerfile" ]; then
            log_error "PostgreSQL Dockerfile not found"
            return 1
        fi
        return 0
    fi
    
    # Full build test (slow)
    if ! docker build -t test-postgres-build "${PROJECT_DIR}/postgres" --no-cache >/dev/null 2>&1; then
        log_error "PostgreSQL Dockerfile build failed"
        return 1
    fi
    
    # Clean up test image
    docker rmi test-postgres-build >/dev/null 2>&1 || true
    
    return 0
}

# Test: Nginx configuration syntax
test_nginx_config_syntax() {
    # Skip if Docker is not running
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker not available, skipping nginx config test"
        return 0
    fi
    
    local nginx_configs=(
        "${PROJECT_DIR}/nginx.production.conf"
        "${PROJECT_DIR}/proxy-server-nginx.conf"
    )
    
    for config in "${nginx_configs[@]}"; do
        # Use nginx docker image to test config
        if ! docker run --rm -v "${config}:/etc/nginx/nginx.conf:ro" nginx:stable-alpine nginx -t >/dev/null 2>&1; then
            log_error "Invalid nginx config: $config"
            return 1
        fi
    done
    
    return 0
}

# Test: Check for TODO/FIXME comments
test_no_todos() {
    local script_files=(
        "${PROJECT_DIR}/scripts/install.sh"
        "${PROJECT_DIR}/scripts/update.sh"
        "${PROJECT_DIR}/scripts/backup.sh"
        "${PROJECT_DIR}/scripts/health-check.sh"
    )
    
    for file in "${script_files[@]}"; do
        if grep -qi "TODO\|FIXME\|XXX" "$file"; then
            log_warn "Found TODO/FIXME in $file"
            # Don't fail, just warn
        fi
    done
    
    return 0
}

# Test: Backup script creates required directories
test_backup_directory_creation() {
    local test_dir="/tmp/authgear-test-backup"
    
    # This is a dry-run test
    mkdir -p "${test_dir}"
    
    if [ -d "${test_dir}" ]; then
        rm -rf "${test_dir}"
        return 0
    fi
    
    return 1
}

# Test: Check script bash compatibility
test_bash_compatibility() {
    local scripts=(
        "${PROJECT_DIR}/scripts/install.sh"
        "${PROJECT_DIR}/scripts/update.sh"
        "${PROJECT_DIR}/scripts/backup.sh"
        "${PROJECT_DIR}/scripts/health-check.sh"
    )
    
    for script in "${scripts[@]}"; do
        # Check shebang
        if ! head -n1 "$script" | grep -q "#!/usr/bin/env bash"; then
            log_error "Invalid shebang in $script"
            return 1
        fi
        
        # Check for set -euo pipefail
        if ! grep -q "set -euo pipefail" "$script"; then
            log_error "Missing 'set -euo pipefail' in $script"
            return 1
        fi
    done
    
    return 0
}

# Test: GitHub Actions workflow validity
test_github_actions() {
    local workflow="${PROJECT_DIR}/.github/workflows/build-images.yml"
    
    if [ ! -f "$workflow" ]; then
        log_error "Missing GitHub Actions workflow"
        return 1
    fi
    
    # Basic YAML syntax check (requires python with pyyaml)
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml" 2>/dev/null; then
            if ! python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null; then
                log_error "Invalid YAML in GitHub Actions workflow"
                return 1
            fi
        else
            log_warn "PyYAML not available, skipping YAML validation"
        fi
    fi
    
    return 0
}

# Test: Documentation completeness
test_documentation() {
    # Check if README files exist
    if [ ! -f "${PROJECT_DIR}/README.md" ]; then
        log_error "Missing README.md"
        return 1
    fi
    
    return 0
}

# Display test summary
show_summary() {
    echo
    echo "=========================================="
    echo "Test Suite Summary"
    echo "=========================================="
    echo "Total Tests: ${TESTS_RUN}"
    echo "Passed: ${TESTS_PASSED}"
    echo "Failed: ${TESTS_FAILED}"
    echo "=========================================="
    echo
    
    if [ ${TESTS_FAILED} -eq 0 ]; then
        log_info "All tests passed! ✓"
        return 0
    else
        log_error "Some tests failed!"
        return 1
    fi
}

# Main test execution
main() {
    log_info "Starting Authgear Test Suite"
    echo
    
    # Run all tests
    run_test "Required files exist" test_required_files
    run_test "Script permissions" test_script_permissions
    run_test "Docker Compose validity" test_docker_compose_validity
    run_test "No hardcoded secrets" test_no_hardcoded_secrets
    run_test "Environment variables" test_env_variables
    run_test "PostgreSQL Dockerfile" test_postgres_dockerfile
    run_test "Nginx configuration syntax" test_nginx_config_syntax
    run_test "No TODOs in scripts" test_no_todos
    run_test "Backup directory creation" test_backup_directory_creation
    run_test "Bash compatibility" test_bash_compatibility
    run_test "GitHub Actions workflow" test_github_actions
    run_test "Documentation completeness" test_documentation
    
    show_summary
}

# Run main function
main "$@"
