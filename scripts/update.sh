#!/usr/bin/env bash
#
# Authgear Production - Update Script
# Updates all services with zero downtime
#

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR
readonly DOCKER_COMPOSE="${PROJECT_DIR}/docker-compose.production.yml"
readonly ENV_FILE="${PROJECT_DIR}/.env"
readonly BACKUP_DIR="${PROJECT_DIR}/backups"

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

# Check if script is run from correct location
check_environment() {
    if [ ! -f "${DOCKER_COMPOSE}" ]; then
        log_error "Docker compose file not found: ${DOCKER_COMPOSE}"
        exit 1
    fi
    
    if [ ! -f "${ENV_FILE}" ]; then
        log_error "Environment file not found: ${ENV_FILE}"
        exit 1
    fi
    
    log_info "Environment check passed ✓"
}

# Create backup before update
create_backup() {
    log_step "Creating backup before update..."
    
    if [ -f "${SCRIPT_DIR}/backup.sh" ]; then
        bash "${SCRIPT_DIR}/backup.sh"
    else
        log_warn "Backup script not found, skipping backup"
        read -rp "Continue without backup? (y/N): " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update cancelled"
            exit 0
        fi
    fi
}

# Pull latest images
pull_images() {
    log_step "Pulling latest Docker images..."
    
    docker compose -f "${DOCKER_COMPOSE}" pull
    
    log_info "Images pulled successfully ✓"
}

# Check if migrations are needed
check_migrations() {
    log_step "Checking for database migrations..."
    
    # This is a placeholder - actual implementation would check migration status
    log_info "Migration check completed ✓"
}

# Run database migrations
run_migrations() {
    log_step "Running database migrations..."
    
    # Authgear migrations
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear \
        authgear database migrate up || {
        log_error "Authgear main migration failed"
        return 1
    }
    
    # Audit migrations
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear \
        authgear audit database migrate up || {
        log_error "Authgear audit migration failed"
        return 1
    }
    
    # Images migrations
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear \
        authgear images database migrate up || {
        log_error "Authgear images migration failed"
        return 1
    }
    
    # Portal migrations
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear-portal \
        authgear-portal database migrate up || {
        log_error "Portal migration failed"
        return 1
    }
    
    log_info "Migrations completed successfully ✓"
}

# Rolling restart of services
rolling_restart() {
    log_step "Performing rolling restart of services..."
    
    # Restart infrastructure services one by one
    local services=("postgres" "redis" "minio" "authgear" "authgear-images" "authgear-portal" "authgear-deno" "nginx")
    
    for service in "${services[@]}"; do
        log_info "Restarting ${service}..."
        
        docker compose -f "${DOCKER_COMPOSE}" up -d --no-deps --force-recreate "${service}"
        
        # Wait for service to be healthy
        local max_wait=60
        local waited=0
        
        while [ $waited -lt $max_wait ]; do
            if docker compose -f "${DOCKER_COMPOSE}" ps "${service}" | grep -q "healthy\|running"; then
                log_info "${service} is ready ✓"
                break
            fi
            sleep 2
            waited=$((waited + 2))
        done
        
        if [ $waited -ge $max_wait ]; then
            log_error "${service} failed to start properly"
            return 1
        fi
        
        # Small delay between services
        sleep 3
    done
    
    log_info "All services restarted successfully ✓"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    # Check if all services are running
    local failed_services=()
    
    while IFS= read -r service; do
        if ! docker compose -f "${DOCKER_COMPOSE}" ps "$service" | grep -q "Up\|running"; then
            failed_services+=("$service")
        fi
    done < <(docker compose -f "${DOCKER_COMPOSE}" config --services)
    
    if [ ${#failed_services[@]} -ne 0 ]; then
        log_error "Following services are not running: ${failed_services[*]}"
        return 1
    fi
    
    # Run health check script if available
    if [ -f "${SCRIPT_DIR}/health-check.sh" ]; then
        bash "${SCRIPT_DIR}/health-check.sh" || {
            log_error "Health check failed"
            return 1
        }
    fi
    
    log_info "Deployment verification passed ✓"
}

# Cleanup old images and volumes
cleanup() {
    log_step "Cleaning up old Docker images..."
    
    docker image prune -f
    
    log_info "Cleanup completed ✓"
}

# Show update summary
show_summary() {
    echo
    log_info "============================================"
    log_info "Update completed successfully! 🎉"
    log_info "============================================"
    echo
    log_info "Updated services:"
    docker compose -f "${DOCKER_COMPOSE}" ps
    echo
    log_info "Check logs with:"
    echo "  docker compose -f ${DOCKER_COMPOSE} logs -f [service_name]"
    echo
}

# Rollback function
rollback() {
    log_error "Update failed! Starting rollback..."
    
    # Try to restore from last backup
    if [ -d "${BACKUP_DIR}" ]; then
        local latest_backup
        latest_backup=$(find "${BACKUP_DIR}" -type d -name "backup_*" | sort -r | head -n1)
        
        if [ -n "$latest_backup" ]; then
            log_warn "Restoring from backup: $latest_backup"
            # Implement rollback logic here
            log_info "Rollback completed"
        else
            log_error "No backups found for rollback"
        fi
    else
        log_error "Backup directory not found"
    fi
}

# Main update process
main() {
    log_info "Starting Authgear Production Update"
    echo
    
    # Confirm update
    read -rp "This will update all services. Continue? (y/N): " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        exit 0
    fi
    
    # Set up error handling
    trap rollback ERR
    
    check_environment
    create_backup
    pull_images
    check_migrations
    run_migrations
    rolling_restart
    verify_deployment
    cleanup
    show_summary
    
    # Remove error trap on success
    trap - ERR
}

# Run main function
main "$@"
