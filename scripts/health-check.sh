#!/usr/bin/env bash
#
# Authgear Production - Health Check Script
# Monitors the health status of all services
#

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR
readonly DOCKER_COMPOSE="${PROJECT_DIR}/docker-compose.production.yml"

# Health check results
declare -A SERVICE_STATUS

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

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_failure() {
    echo -e "${RED}✗${NC} $*"
}

# Check if service is running
check_service_running() {
    local service=$1
    
    if docker compose -f "${DOCKER_COMPOSE}" ps "${service}" 2>/dev/null | grep -q "Up\|running"; then
        SERVICE_STATUS[$service]="running"
        return 0
    else
        SERVICE_STATUS[$service]="stopped"
        return 1
    fi
}

# Check service health
check_service_health() {
    local service=$1
    
    local health_status
    health_status=$(docker compose -f "${DOCKER_COMPOSE}" ps "${service}" 2>/dev/null | tail -n1 | awk '{print $(NF-1)}')
    
    case $health_status in
        "healthy")
            return 0
            ;;
        "unhealthy")
            return 1
            ;;
        "starting")
            return 2
            ;;
        *)
            return 3
            ;;
    esac
}

# Check PostgreSQL
check_postgres() {
    local service="postgres"
    
    if ! check_service_running "$service"; then
        log_failure "PostgreSQL: Not running"
        return 1
    fi
    
    # Test database connection
    if docker compose -f "${DOCKER_COMPOSE}" exec -T postgres pg_isready >/dev/null 2>&1; then
        log_success "PostgreSQL: Running and accepting connections"
        return 0
    else
        log_failure "PostgreSQL: Running but not accepting connections"
        return 1
    fi
}

# Check Redis
check_redis() {
    local service="redis"
    
    if ! check_service_running "$service"; then
        log_failure "Redis: Not running"
        return 1
    fi
    
    # Test Redis ping
    if docker compose -f "${DOCKER_COMPOSE}" exec -T redis redis-cli ping >/dev/null 2>&1; then
        log_success "Redis: Running and responding"
        return 0
    else
        log_failure "Redis: Running but not responding"
        return 1
    fi
}

# Check MinIO
check_minio() {
    local service="minio"
    
    if ! check_service_running "$service"; then
        log_failure "MinIO: Not running"
        return 1
    fi
    
    # Test MinIO health
    if docker compose -f "${DOCKER_COMPOSE}" exec -T minio curl -f http://localhost:9000/minio/health/live >/dev/null 2>&1; then
        log_success "MinIO: Running and healthy"
        return 0
    else
        log_failure "MinIO: Running but unhealthy"
        return 1
    fi
}

# Check Authgear services
check_authgear() {
    local service="authgear"
    
    if ! check_service_running "$service"; then
        log_failure "Authgear: Not running"
        return 1
    fi
    
    check_service_health "$service"
    local health_code=$?
    
    case $health_code in
        0)
            log_success "Authgear: Running and healthy"
            return 0
            ;;
        1)
            log_failure "Authgear: Running but unhealthy"
            return 1
            ;;
        2)
            log_warn "Authgear: Starting..."
            return 2
            ;;
        *)
            log_warn "Authgear: Health status unknown"
            return 3
            ;;
    esac
}

# Check Authgear Portal
check_portal() {
    local service="authgear-portal"
    
    if ! check_service_running "$service"; then
        log_failure "Portal: Not running"
        return 1
    fi
    
    check_service_health "$service"
    local health_code=$?
    
    case $health_code in
        0)
            log_success "Portal: Running and healthy"
            return 0
            ;;
        1)
            log_failure "Portal: Running but unhealthy"
            return 1
            ;;
        2)
            log_warn "Portal: Starting..."
            return 2
            ;;
        *)
            log_warn "Portal: Health status unknown"
            return 3
            ;;
    esac
}

# Check Authgear Images
check_images() {
    local service="authgear-images"
    
    if ! check_service_running "$service"; then
        log_failure "Images Service: Not running"
        return 1
    fi
    
    check_service_health "$service"
    local health_code=$?
    
    case $health_code in
        0)
            log_success "Images Service: Running and healthy"
            return 0
            ;;
        1)
            log_failure "Images Service: Running but unhealthy"
            return 1
            ;;
        2)
            log_warn "Images Service: Starting..."
            return 2
            ;;
        *)
            log_warn "Images Service: Health status unknown"
            return 3
            ;;
    esac
}

# Check Nginx
check_nginx() {
    local service="nginx"
    
    if ! check_service_running "$service"; then
        log_failure "Nginx: Not running"
        return 1
    fi
    
    # Test Nginx health endpoint
    if docker compose -f "${DOCKER_COMPOSE}" exec -T nginx wget -q -O- http://localhost:8010/healthz >/dev/null 2>&1; then
        log_success "Nginx: Running and healthy"
        return 0
    else
        log_failure "Nginx: Running but health check failed"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    log_info "Checking disk space..."
    
    local usage
    usage=$(df -h "${PROJECT_DIR}" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$usage" -lt 80 ]; then
        log_success "Disk space: ${usage}% used"
        return 0
    elif [ "$usage" -lt 90 ]; then
        log_warn "Disk space: ${usage}% used (Warning threshold)"
        return 1
    else
        log_error "Disk space: ${usage}% used (Critical threshold)"
        return 2
    fi
}

# Check Docker volumes
check_volumes() {
    log_info "Checking Docker volumes..."
    
    local volumes=("postgres_data" "redis_data" "minio_data")
    local all_ok=true
    
    for volume in "${volumes[@]}"; do
        if docker volume inspect "authgear-example-docker-compose_${volume}" >/dev/null 2>&1; then
            log_success "Volume ${volume}: OK"
        else
            log_failure "Volume ${volume}: Missing"
            all_ok=false
        fi
    done
    
    if $all_ok; then
        return 0
    else
        return 1
    fi
}

# Check container logs for errors
check_logs() {
    log_info "Checking recent logs for errors..."
    
    local services=("authgear" "authgear-portal" "authgear-images")
    local error_count=0
    
    for service in "${services[@]}"; do
        local errors
        errors=$(docker compose -f "${DOCKER_COMPOSE}" logs --tail=100 "${service}" 2>/dev/null | grep -c -i "error\|fatal\|panic" || true)
        
        if [ "$errors" -gt 0 ]; then
            log_warn "${service}: Found ${errors} error(s) in recent logs"
            error_count=$((error_count + errors))
        fi
    done
    
    if [ "$error_count" -eq 0 ]; then
        log_success "No critical errors in recent logs"
        return 0
    else
        log_warn "Total errors found: ${error_count}"
        return 1
    fi
}

# Display summary
show_summary() {
    echo
    echo "=========================================="
    echo "Health Check Summary"
    echo "=========================================="
    echo
    
    local total_checks=0
    local passed_checks=0
    
    # Count results
    for status in "${SERVICE_STATUS[@]}"; do
        total_checks=$((total_checks + 1))
        if [ "$status" = "running" ]; then
            passed_checks=$((passed_checks + 1))
        fi
    done
    
    echo "Services Running: ${passed_checks}/${total_checks}"
    echo
    
    if [ "$passed_checks" -eq "$total_checks" ]; then
        log_success "All systems operational!"
        return 0
    else
        log_error "Some services are not running properly"
        return 1
    fi
}

# Main health check
main() {
    local exit_code=0
    
    echo "Authgear Production Health Check"
    echo "=================================="
    echo "Timestamp: $(date)"
    echo
    
    # Run all checks
    check_postgres || exit_code=1
    check_redis || exit_code=1
    check_minio || exit_code=1
    check_authgear || exit_code=1
    check_portal || exit_code=1
    check_images || exit_code=1
    check_nginx || exit_code=1
    
    echo
    check_disk_space || exit_code=1
    check_volumes || exit_code=1
    check_logs || exit_code=1
    
    show_summary || exit_code=1
    
    exit $exit_code
}

# Run main function
main "$@"
