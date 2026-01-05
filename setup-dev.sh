#!/usr/bin/env bash
#
# Authgear Development Setup Script
# This script performs the initial setup for local development
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

log_info "🚀 Authgear Development Setup"
echo

# Step 1: Start dependent services
log_info "Step 1: Starting dependent services (PostgreSQL, Redis, MinIO)..."
docker compose up -d postgres redis minio

log_info "Waiting for services to be ready..."
sleep 10

# Step 2: Run database migrations
log_info "Step 2: Running database migrations..."
docker compose run --rm authgear authgear database migrate up
docker compose run --rm authgear authgear audit database migrate up
docker compose run --rm authgear authgear images database migrate up
docker compose run --rm authgear-portal authgear-portal database migrate up

# Step 3: Create MinIO buckets
log_info "Step 3: Creating MinIO buckets..."
docker compose exec -T minio sh -c '
    mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
    mc mb --ignore-existing local/images
    mc mb --ignore-existing local/userexport
    mc anonymous set download local/images
'

# Step 4: Create project configuration for "accounts"
log_info "Step 4: Creating project configuration..."
if [ ! -f "${SCRIPT_DIR}/accounts/authgear.yaml" ]; then
    docker compose run --rm --workdir "/work" -v "$PWD/accounts:/work" authgear authgear init --interactive=false \
      --purpose=portal \
      --for-helm-chart=true \
      --app-id="accounts" \
      --public-origin="http://accounts.localhost:3100" \
      --portal-origin="http://portal.localhost:8010" \
      --portal-client-id=portal \
      --phone-otp-mode=sms \
      --disable-email-verification=true \
      --search-implementation=postgresql \
      -o /work
else
    log_info "Configuration already exists, skipping..."
fi

# Step 5: Create the project "accounts" in database
log_info "Step 5: Creating project in database..."
docker compose run --rm --workdir "/work" -v "$PWD/accounts:/work" authgear-portal authgear-portal internal configsource create /work || true
docker compose run --rm authgear-portal authgear-portal internal domain create-default --default-domain-suffix ".localhost" || true

# Step 6: Start all services
log_info "Step 6: Starting all Authgear services..."
docker compose up -d

echo
log_info "============================================"
log_info "✅ Setup completed successfully!"
log_info "============================================"
echo
log_info "Next steps:"
echo
echo "1. Wait for all services to start (about 30 seconds)"
echo "   Check status: docker compose ps"
echo
echo "2. Create your first user account:"
echo "   docker compose exec authgear authgear internal admin-api invoke \\"
echo "     --app-id accounts \\"
echo "     --endpoint \"http://127.0.0.1:3002\" \\"
echo "     --host \"accounts.localhost:3100\" \\"
echo "     --query '"
echo "       mutation createUser(\$email: String!, \$password: String!) {"
echo "         createUser(input: {"
echo "           definition: {"
echo "             loginID: {"
echo "               key: \"email\""
echo "               value: \$email"
echo "             }"
echo "           }"
echo "           password: \$password"
echo "         }) {"
echo "           user {"
echo "             id"
echo "           }"
echo "         }"
echo "       }"
echo "     ' \\"
echo "     --variables-json '{\"email\":\"admin@example.com\",\"password\":\"Admin123!\"}'"
echo
echo "3. Decode the user node ID from the output and grant portal access:"
echo "   echo \"<USER_NODE_ID>\" | basenc --base64url --decode"
echo "   docker compose run --rm authgear-portal authgear-portal internal collaborator add \\"
echo "     --app-id accounts --user-id <USER_RAW_ID> --role owner"
echo
echo "4. Visit the portal at: http://portal.localhost:8010"
echo
log_warn "Make sure you have these entries in /etc/hosts:"
echo "   127.0.0.1 accounts.localhost"
echo "   127.0.0.1 portal.localhost"
echo
