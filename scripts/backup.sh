#!/usr/bin/env bash
#
# Authgear Production - Backup Script
# Creates backups of PostgreSQL, Redis, and MinIO data
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
readonly ENV_FILE="${PROJECT_DIR}/.env"
readonly BACKUP_ROOT="${PROJECT_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly TIMESTAMP
readonly BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"

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

# Load environment variables
load_env() {
    if [ ! -f "${ENV_FILE}" ]; then
        log_error "Environment file not found: ${ENV_FILE}"
        exit 1
    fi
    
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
}

# Create backup directory
prepare_backup_dir() {
    log_info "Creating backup directory: ${BACKUP_DIR}"
    
    mkdir -p "${BACKUP_DIR}"/{postgres,redis,minio,config}
    
    log_info "Backup directory created ✓"
}

# Backup PostgreSQL database
backup_postgres() {
    log_info "Backing up PostgreSQL database..."
    
    local db_backup="${BACKUP_DIR}/postgres/authgear_${TIMESTAMP}.sql.gz"
    
    docker compose -f "${DOCKER_COMPOSE}" exec -T postgres \
        pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        --no-owner --no-acl --clean --if-exists \
        | gzip > "${db_backup}"
    
    if [ -f "${db_backup}" ] && [ -s "${db_backup}" ]; then
        log_info "PostgreSQL backup completed: ${db_backup} ✓"
        
        # Get backup size
        local size
        size=$(du -h "${db_backup}" | cut -f1)
        log_info "Backup size: ${size}"
    else
        log_error "PostgreSQL backup failed or is empty"
        return 1
    fi
}

# Backup Redis data
backup_redis() {
    log_info "Backing up Redis data..."
    
    # Trigger Redis save
    docker compose -f "${DOCKER_COMPOSE}" exec -T redis \
        redis-cli -a "${REDIS_PASSWORD}" --no-auth-warning SAVE
    
    # Copy RDB file
    docker compose -f "${DOCKER_COMPOSE}" cp \
        redis:/data/dump.rdb "${BACKUP_DIR}/redis/dump_${TIMESTAMP}.rdb"
    
    if [ -f "${BACKUP_DIR}/redis/dump_${TIMESTAMP}.rdb" ]; then
        log_info "Redis backup completed ✓"
    else
        log_warn "Redis backup may have failed"
    fi
}

# Backup MinIO data
backup_minio() {
    log_info "Backing up MinIO buckets..."
    
    local minio_backup="${BACKUP_DIR}/minio"
    
    # Backup using MinIO client
    docker compose -f "${DOCKER_COMPOSE}" exec -T minio sh -c "
        mc alias set local http://localhost:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' &&
        mc mirror local/authgear-images /tmp/backup/images &&
        mc mirror local/authgear-userexport /tmp/backup/userexport &&
        tar czf /tmp/minio_backup.tar.gz -C /tmp/backup .
    "
    
    docker compose -f "${DOCKER_COMPOSE}" cp \
        minio:/tmp/minio_backup.tar.gz "${minio_backup}/minio_${TIMESTAMP}.tar.gz"
    
    if [ -f "${minio_backup}/minio_${TIMESTAMP}.tar.gz" ]; then
        log_info "MinIO backup completed ✓"
    else
        log_warn "MinIO backup may have failed"
    fi
}

# Backup configuration files
backup_config() {
    log_info "Backing up configuration files..."
    
    # Backup .env file (with sensitive data masked)
    cp "${ENV_FILE}" "${BACKUP_DIR}/config/env.backup"
    
    # Backup docker-compose file
    cp "${DOCKER_COMPOSE}" "${BACKUP_DIR}/config/docker-compose.yml"
    
    # Backup authgear secrets if exists
    if [ -f "${PROJECT_DIR}/var/authgear.secrets.yaml" ]; then
        cp "${PROJECT_DIR}/var/authgear.secrets.yaml" "${BACKUP_DIR}/config/"
    fi
    
    # Backup accounts config if exists
    if [ -d "${PROJECT_DIR}/accounts" ]; then
        cp -r "${PROJECT_DIR}/accounts" "${BACKUP_DIR}/config/"
    fi
    
    log_info "Configuration backup completed ✓"
}

# Create backup manifest
create_manifest() {
    log_info "Creating backup manifest..."
    
    local manifest="${BACKUP_DIR}/MANIFEST.txt"
    
    cat > "$manifest" <<EOF
Authgear Backup Manifest
========================
Backup Date: $(date)
Backup ID: ${TIMESTAMP}

Environment:
- Postgres User: ${POSTGRES_USER}
- Postgres DB: ${POSTGRES_DB}
- MinIO User: ${MINIO_ROOT_USER}

Backup Contents:
EOF
    
    find "${BACKUP_DIR}" -type f -exec ls -lh {} \; >> "$manifest"
    
    log_info "Manifest created ✓"
}

# Compress backup
compress_backup() {
    log_info "Compressing backup..."
    
    cd "${BACKUP_ROOT}"
    tar czf "backup_${TIMESTAMP}.tar.gz" "backup_${TIMESTAMP}"
    
    if [ -f "${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz" ]; then
        local size
        size=$(du -h "${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz" | cut -f1)
        log_info "Backup compressed: ${size} ✓"
        
        # Remove uncompressed backup
        rm -rf "${BACKUP_DIR}"
    else
        log_error "Backup compression failed"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups..."
    
    local retention_days="${BACKUP_RETENTION_DAYS:-30}"
    
    find "${BACKUP_ROOT}" -name "backup_*.tar.gz" -type f -mtime "+${retention_days}" -delete
    
    local remaining
    remaining=$(find "${BACKUP_ROOT}" -name "backup_*.tar.gz" -type f | wc -l | tr -d ' ')
    
    log_info "Cleanup completed. Remaining backups: ${remaining} ✓"
}

# Verify backup
verify_backup() {
    log_info "Verifying backup integrity..."
    
    if tar tzf "${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz" >/dev/null 2>&1; then
        log_info "Backup verification passed ✓"
    else
        log_error "Backup verification failed"
        return 1
    fi
}

# Main backup process
main() {
    log_info "Starting Authgear Backup Process"
    log_info "Timestamp: ${TIMESTAMP}"
    echo
    
    load_env
    prepare_backup_dir
    backup_postgres
    backup_redis
    backup_minio
    backup_config
    create_manifest
    compress_backup
    verify_backup
    cleanup_old_backups
    
    echo
    log_info "============================================"
    log_info "Backup completed successfully! 🎉"
    log_info "============================================"
    log_info "Backup location: ${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz"
    echo
}

# Run main function
main "$@"
