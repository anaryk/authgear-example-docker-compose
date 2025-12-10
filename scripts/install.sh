#!/usr/bin/env bash
#
# Authgear Production Deployment - Installation Script
# This script performs initial installation and configuration
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly PROJECT_DIR
readonly ENV_FILE="${PROJECT_DIR}/.env"
readonly ENV_EXAMPLE="${PROJECT_DIR}/.env.example"
readonly DOCKER_COMPOSE="${PROJECT_DIR}/docker-compose.production.yml"

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Generate secure random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-"${length}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_commands=()
    
    if ! command_exists docker; then
        missing_commands+=("docker")
    fi
    
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        missing_commands+=("docker-compose")
    fi
    
    if ! command_exists openssl; then
        missing_commands+=("openssl")
    fi
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing dependencies and try again."
        exit 1
    fi
    
    log_info "All prerequisites satisfied ✓"
}

# Initialize environment file
init_env_file() {
    log_info "Initializing environment file..."
    
    if [ -f "${ENV_FILE}" ]; then
        log_warn "Environment file already exists at ${ENV_FILE}"
        read -rp "Do you want to regenerate it? This will overwrite existing passwords! (y/N): " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing environment file"
            return 0
        fi
        # Backup existing file
        cp "${ENV_FILE}" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing environment file"
    fi
    
    if [ ! -f "${ENV_EXAMPLE}" ]; then
        log_error "Template file ${ENV_EXAMPLE} not found"
        exit 1
    fi
    
    # Copy template
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    
    # Generate passwords
    log_info "Generating secure passwords..."
    local postgres_password
    local redis_password
    local minio_password
    
    postgres_password=$(generate_password 32)
    redis_password=$(generate_password 32)
    minio_password=$(generate_password 32)
    
    # Replace passwords in .env file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD_HERE|POSTGRES_PASSWORD=${postgres_password}|g" "${ENV_FILE}"
        sed -i '' "s|REDIS_PASSWORD=CHANGE_ME_REDIS_PASSWORD_HERE|REDIS_PASSWORD=${redis_password}|g" "${ENV_FILE}"
        sed -i '' "s|MINIO_ROOT_PASSWORD=CHANGE_ME_MINIO_PASSWORD_HERE|MINIO_ROOT_PASSWORD=${minio_password}|g" "${ENV_FILE}"
    else
        # Linux
        sed -i "s|POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD_HERE|POSTGRES_PASSWORD=${postgres_password}|g" "${ENV_FILE}"
        sed -i "s|REDIS_PASSWORD=CHANGE_ME_REDIS_PASSWORD_HERE|REDIS_PASSWORD=${redis_password}|g" "${ENV_FILE}"
        sed -i "s|MINIO_ROOT_PASSWORD=CHANGE_ME_MINIO_PASSWORD_HERE|MINIO_ROOT_PASSWORD=${minio_password}|g" "${ENV_FILE}"
    fi
    
    log_info "Environment file created successfully ✓"
    log_warn "IMPORTANT: Review and customize ${ENV_FILE} before proceeding"
    log_warn "Especially set the correct domain names!"
}

# Prompt for domain configuration
configure_domains() {
    log_info "Domain Configuration"
    echo
    
    read -rp "Enter your authentication domain (e.g., auth.maximal-limit.cz): " auth_domain
    read -rp "Enter your portal domain (e.g., portal.maximal-limit.cz): " portal_domain
    
    if [ -z "$auth_domain" ] || [ -z "$portal_domain" ]; then
        log_error "Domain names cannot be empty"
        exit 1
    fi
    
    # Update domains in .env file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|AUTH_DOMAIN=auth.maximal-limit.cz|AUTH_DOMAIN=${auth_domain}|g" "${ENV_FILE}"
        sed -i '' "s|PORTAL_DOMAIN=portal.maximal-limit.cz|PORTAL_DOMAIN=${portal_domain}|g" "${ENV_FILE}"
    else
        sed -i "s|AUTH_DOMAIN=auth.maximal-limit.cz|AUTH_DOMAIN=${auth_domain}|g" "${ENV_FILE}"
        sed -i "s|PORTAL_DOMAIN=portal.maximal-limit.cz|PORTAL_DOMAIN=${portal_domain}|g" "${ENV_FILE}"
    fi
    
    log_info "Domains configured: Auth=${auth_domain}, Portal=${portal_domain} ✓"
}

# Build custom images
build_images() {
    log_info "Building custom Docker images..."
    
    docker build -t ghcr.io/anaryk/authgear-postgres:latest "${PROJECT_DIR}/postgres"
    
    log_info "Docker images built successfully ✓"
}

# Start infrastructure services
start_infrastructure() {
    log_info "Starting infrastructure services (PostgreSQL, Redis, MinIO)..."
    
    docker compose -f "${DOCKER_COMPOSE}" up -d postgres redis minio
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Check PostgreSQL
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if docker compose -f "${DOCKER_COMPOSE}" exec -T postgres pg_isready -U authgear_user >/dev/null 2>&1; then
            log_info "PostgreSQL is ready ✓"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "PostgreSQL failed to start"
        exit 1
    fi
    
    log_info "Infrastructure services started ✓"
}

# Run database migrations
run_migrations() {
    log_info "Running database migrations..."
    
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear authgear database migrate up
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear authgear audit database migrate up
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear authgear images database migrate up
    docker compose -f "${DOCKER_COMPOSE}" run --rm authgear-portal authgear-portal database migrate up
    
    log_info "Database migrations completed ✓"
}

# Create MinIO buckets
create_buckets() {
    log_info "Creating MinIO buckets..."
    
    # Wait for MinIO to be ready
    sleep 5
    
    # Source environment variables
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
    
    # Create buckets using MinIO client
    docker compose -f "${DOCKER_COMPOSE}" exec -T minio sh -c "
        mc alias set local http://localhost:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' &&
        mc mb --ignore-existing local/authgear-images &&
        mc mb --ignore-existing local/authgear-userexport &&
        mc anonymous set download local/authgear-images
    "
    
    log_info "MinIO buckets created ✓"
}

# Initialize Authgear project
init_authgear_project() {
    log_info "Initializing Authgear project..."
    
    # Source environment variables
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
    
    # Check if already initialized
    if [ -f "${PROJECT_DIR}/var/authgear.yaml" ]; then
        log_info "Authgear project already initialized, updating secrets..."
        
        # Update authgear.secrets.yaml with correct passwords
        # shellcheck disable=SC2153
        cat > "${PROJECT_DIR}/var/authgear.secrets.yaml" <<EOF
secrets:
- key: db
  data:
    database_schema: public
    database_url: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
- key: audit.db
  data:
    database_schema: public
    database_url: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
- key: images.db
  data:
    database_schema: public
    database_url: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
- key: redis
  data:
    redis_url: "redis://:${REDIS_PASSWORD}@redis:6379/0"
- key: analytic.redis
  data:
    redis_url: "redis://:${REDIS_PASSWORD}@redis:6379/1"
EOF
        log_info "Secrets updated ✓"
        return 0
    fi
    
    # Initialize project configuration
    # shellcheck disable=SC2153
    docker compose -f "${DOCKER_COMPOSE}" run --rm --workdir "/work" \
        -v "${PROJECT_DIR}/var:/work" \
        authgear authgear init --interactive=false \
        --purpose=portal \
        --for-helm-chart=true \
        --app-id="accounts" \
        --public-origin="https://${AUTH_DOMAIN}" \
        --portal-origin="https://${PORTAL_DOMAIN}" \
        --portal-client-id=portal \
        --phone-otp-mode=sms \
        --disable-email-verification=false \
        --search-implementation=postgresql \
        -o /work
    
    # Update authgear.secrets.yaml with correct passwords
    # shellcheck disable=SC2153
    cat > "${PROJECT_DIR}/var/authgear.secrets.yaml" <<EOF
secrets:
- key: db
  data:
    database_schema: public
    database_url: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
- key: audit.db
  data:
    database_schema: public
    database_url: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
- key: images.db
  data:
    database_schema: public
    database_url: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
- key: redis
  data:
    redis_url: "redis://:${REDIS_PASSWORD}@redis:6379/0"
- key: analytic.redis
  data:
    redis_url: "redis://:${REDIS_PASSWORD}@redis:6379/1"
EOF
    
    # Create project in database
    docker compose -f "${DOCKER_COMPOSE}" run --rm --workdir "/work" \
        -v "${PROJECT_DIR}/var:/work" \
        authgear-portal authgear-portal internal configsource create /work
    
    # Create default domain
    docker compose -f "${DOCKER_COMPOSE}" run --rm \
        authgear-portal authgear-portal internal domain create-default \
        --default-domain-suffix=".${AUTH_DOMAIN}"
    
    log_info "Authgear project initialized ✓"
}

# Start all services
start_all_services() {
    log_info "Starting all services..."
    
    docker compose -f "${DOCKER_COMPOSE}" up -d
    
    log_info "All services started ✓"
}

# Display next steps
show_next_steps() {
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a
    
    # Get VM IP for display
    local vm_ip
    vm_ip=$(hostname -I | awk '{print $1}' || echo "192.168.x.x")
    
    echo
    log_info "============================================"
    log_info "Installation completed successfully! 🎉"
    log_info "============================================"
    echo
    log_info "Next steps:"
    echo
    echo "1. Configure DNS records (see docs/DNS-SETUP.md)"
    echo "   - A record for ${AUTH_DOMAIN} pointing to your proxy server PUBLIC IP"
    echo "   - A record for ${PORTAL_DOMAIN} pointing to your proxy server PUBLIC IP"
    echo
    echo "2. Set up the reverse proxy server (see docs/PROXY-SETUP.md)"
    echo
    log_warn "   IMPORTANT - Proxy Port Configuration:"
    echo "   ┌─────────────────────────────────────────────────────────────┐"
    echo "   │ Domain                     → Forward to VM IP:PORT          │"
    echo "   ├─────────────────────────────────────────────────────────────┤"
    echo "   │ ${AUTH_DOMAIN}   → ${vm_ip}:3100      │"
    echo "   │ ${PORTAL_DOMAIN} → ${vm_ip}:8010      │"
    echo "   └─────────────────────────────────────────────────────────────┘"
    echo
    log_warn "   CRITICAL - Firewall Setup (Proxy on different VM):"
    echo "   Allow only proxy server IP to access ports:"
    echo
    echo "   $ sudo ufw allow from <PROXY_IP> to any port 3100"
    echo "   $ sudo ufw allow from <PROXY_IP> to any port 8010"
    echo "   $ sudo ufw deny 3100"
    echo "   $ sudo ufw deny 8010"
    echo "   $ sudo ufw allow ssh"
    echo "   $ sudo ufw enable"
    echo
    echo "   In proxy-server-nginx.conf replace:"
    echo "   - YOUR_VM_LOCAL_IP with: ${vm_ip}"
    echo "   - Port 3100 for auth domain"
    echo "   - Port 8010 for portal domain"
    echo
    echo "3. Verify services are listening on correct ports:"
    echo "   ss -tlnp | grep -E ':(3100|8010)'"
    echo
    echo "4. Create your admin account:"
    echo "   Visit https://${PORTAL_DOMAIN} and sign up"
    echo
    echo "5. Check service health:"
    echo "   ./scripts/health-check.sh"
    echo
    echo "6. Set up automated backups:"
    echo "   Add ./scripts/backup.sh to cron"
    echo
    log_warn "IMPORTANT: Keep ${ENV_FILE} secure - it contains sensitive credentials!"
    echo
    log_info "Services are listening on:"
    echo "   - Auth Service:   http://${vm_ip}:3100"
    echo "   - Portal Service: http://${vm_ip}:8010"
    echo
}

# Main installation process
main() {
    log_info "Starting Authgear Production Installation"
    echo
    
    check_prerequisites
    init_env_file
    configure_domains
    
    read -rp "Proceed with installation? (y/N): " -n 1
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    build_images
    start_infrastructure
    run_migrations
    create_buckets
    init_authgear_project
    start_all_services
    show_next_steps
}

# Run main function
main "$@"
