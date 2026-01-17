#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_DIR=$(pwd)
ENV_FILE="${PROJECT_DIR}/env"

log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# Check env file
if [ ! -f "$ENV_FILE" ]; then
    log_error "env file not found!"
    exit 1
fi

# Load env
set -a
source "$ENV_FILE"
set +a

# Function to generate secrets safely
generate_secrets() {
    log_info "Generating configuration..."

    # Create directories
    mkdir -p "${PROJECT_DIR}/var/images"
    mkdir -p "${PROJECT_DIR}/var/portal"

    # 1. Initialize Authgear (generates authgear.yaml and authgear.secrets.yaml)
    if [ ! -f "${PROJECT_DIR}/var/authgear.yaml" ]; then
        log_info "Running authgear init..."
        
        # Define domains if not set
        AUTH_DOMAIN=${AUTH_DOMAIN:-auth.maximal-limit.cz}
        PORTAL_DOMAIN=${PORTAL_DOMAIN:-portal.maximal-limit.cz}
        
        # Use docker run directly to avoid read-only volume mount issues from docker-compose
        docker run --rm \
            -v "${PROJECT_DIR}/var:/app" \
            quay.io/theauthgear/authgear-server:2025-11-26.0 \
            authgear init --interactive=false \
            --purpose=portal \
            --for-helm-chart=true \
            --app-id="accounts" \
            --public-origin="https://${AUTH_DOMAIN}" \
            --portal-origin="https://${PORTAL_DOMAIN}" \
            --portal-client-id=portal \
            --phone-otp-mode=sms \
            --disable-email-verification=false \
            --search-implementation=postgresql \
            -o /app
            
        log_info "authgear init completed."
    else
        log_info "authgear.yaml already exists."
    fi

    # 2. Create authgear.secrets.yaml if missing
    if [ ! -f "${PROJECT_DIR}/var/authgear.secrets.yaml" ]; then
        echo "secrets: []" > "${PROJECT_DIR}/var/authgear.secrets.yaml"
    fi

    # 3. Distribute config to sub-services (images, portal)
    # We copy the BASE config (with generated keys) to sub-folders
    cp "${PROJECT_DIR}/var/authgear.yaml" "${PROJECT_DIR}/var/images/"
    cp "${PROJECT_DIR}/var/authgear.yaml" "${PROJECT_DIR}/var/portal/"
    
    cp "${PROJECT_DIR}/var/authgear.secrets.yaml" "${PROJECT_DIR}/var/images/"
    cp "${PROJECT_DIR}/var/authgear.secrets.yaml" "${PROJECT_DIR}/var/portal/"

    # 4. Append Database/Redis secrets (SAFE APPEND)
    # Main Server
    cat >> "${PROJECT_DIR}/var/authgear.secrets.yaml" <<EOF

- key: db
  data:
    database_schema: ${DATABASE_SCHEMA:-public}
    database_url: ${DATABASE_URL}
- key: audit.db
  data:
    database_schema: ${AUDIT_DATABASE_SCHEMA:-public}
    database_url: ${AUDIT_DATABASE_URL}
- key: search.db
  data:
    database_schema: ${SEARCH_DATABASE_SCHEMA:-public}
    database_url: ${SEARCH_DATABASE_URL}
- key: redis
  data:
    redis_url: ${REDIS_URL}
EOF

    # Images Service (Strict subset)
    cat >> "${PROJECT_DIR}/var/images/authgear.secrets.yaml" <<EOF

- key: db
  data:
    database_schema: ${DATABASE_SCHEMA:-public}
    database_url: ${DATABASE_URL}
- key: redis
  data:
    redis_url: ${REDIS_URL}
EOF

    # Portal Service (Strict subset)
    cat >> "${PROJECT_DIR}/var/portal/authgear.secrets.yaml" <<EOF

- key: db
  data:
    database_schema: ${DATABASE_SCHEMA:-public}
    database_url: ${DATABASE_URL}
- key: redis
  data:
    redis_url: ${REDIS_URL}
EOF

    log_info "Configuration generated."
}

# Main execution
if [ "$1" == "--reset" ]; then
    log_warn "RESETTING ALL DATA..."
    docker compose -f docker-compose.production.yml down -v
    rm -rf "${PROJECT_DIR}/var"
    mkdir -p "${PROJECT_DIR}/var"
    generate_secrets
elif [ ! -f "${PROJECT_DIR}/var/authgear.yaml" ]; then
    generate_secrets
fi

log_info "Starting services..."
docker compose -f docker-compose.production.yml up -d --build

log_info "Running database migrations..."
docker compose -f docker-compose.production.yml run --rm authgear authgear database migrate up
docker compose -f docker-compose.production.yml run --rm authgear-portal authgear-portal database migrate up

log_info "Waiting for services to be healthy..."
sleep 10
docker compose -f docker-compose.production.yml ps

echo
log_info "============================================"
log_info "Deployment completed successfully! 🚀"
log_info "============================================"
echo
log_info "Cloudflare Tunnel Configuration:"
echo "   ┌─────────────────────────────────────────────────────────────┐"
echo "   │ Domain                     → Service URL                    │"
echo "   ├─────────────────────────────────────────────────────────────┤"
echo "   │ ${AUTH_DOMAIN:-auth.maximal-limit.cz}   → http://localhost:3100          │"
echo "   │ ${PORTAL_DOMAIN:-portal.maximal-limit.cz} → http://localhost:8010          │"
echo "   └─────────────────────────────────────────────────────────────┘"
echo
