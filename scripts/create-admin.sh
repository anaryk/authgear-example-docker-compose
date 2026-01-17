#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Default values
EMAIL=""
PASSWORD=""
APP_ID="accounts"
COMPOSE_FILE="docker-compose.production.yml"

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --email EMAIL          Admin email (required)"
    echo "  -p, --password PASSWORD    Admin password (required)"
    echo "  -a, --app-id APP_ID        App ID (default: accounts)"
    echo "  -f, --file COMPOSE_FILE    Docker compose file (default: docker-compose.production.yml)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --email admin@example.com --password MySecurePass123!"
    echo "  $0 -e admin@example.com -p MySecurePass123!"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -a|--app-id)
            APP_ID="$2"
            shift 2
            ;;
        -f|--file)
            COMPOSE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
    echo -e "${RED}Error: Email and password are required${NC}"
    echo ""
    usage
fi

# Load env to get AUTH_DOMAIN
set -a
source ./env
set +a

HOST_DOMAIN=${AUTHGEAR_ENDPOINT#https://}
HOST_DOMAIN=${HOST_DOMAIN%/}

echo -e "${GREEN}Creating admin user ($EMAIL)...${NC}"

# 0. Ensure Project Exists in Portal (REQUIRED for App to be recognized in some contexts, and for Portal access)
echo "Ensuring project '$APP_ID' exists in Portal..."
# We run these commands to register the app in the Portal's database.
# This corresponds to Step 6 in the README.
docker compose -f "$COMPOSE_FILE" run --rm authgear-portal authgear-portal internal configsource create /app || true
docker compose -f "$COMPOSE_FILE" run --rm authgear-portal authgear-portal internal domain create-default --default-domain-suffix "$APP_HOST_SUFFIX" || true

# 1. Create User via Admin API
# We use 'docker compose exec' to run inside the running authgear container
echo "Invoking Admin API to create user..."

# Prepare GraphQL Query and Variables
QUERY='mutation createUser($email: String!, $password: String!) { createUser(input: { definition: { loginID: { key: "email", value: $email } }, password: $password }) { user { id } } }'
VARS="{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"

# Run command
# Note: We use 127.0.0.1:3002 because we are executing INSIDE the container
OUTPUT=$(docker compose -f "$COMPOSE_FILE" exec -T authgear authgear internal admin-api invoke \
  --app-id "$APP_ID" \
  --endpoint "http://127.0.0.1:3002" \
  --host "$HOST_DOMAIN" \
  --query "$QUERY" \
  --variables-json "$VARS")

echo "API Response: $OUTPUT"

# 2. Extract and Decode User ID
# Extract ID from JSON (simple grep/cut to avoid jq dependency)
NODE_ID=$(echo "$OUTPUT" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$NODE_ID" ]; then
    echo "Error: Could not extract User ID from response."
    echo "Debug: Checking authgear.yaml content..."
    docker compose -f "$COMPOSE_FILE" exec -T authgear cat /app/authgear.yaml
    exit 1
fi

echo "Node ID: $NODE_ID"

# Decode Base64 (Portable way using python3 which is likely in the environment or container, 
# but let's use the container's tools if possible. Actually, let's use the host's python or openssl)
if command -v python3 &>/dev/null; then
    DECODED=$(echo "$NODE_ID" | python3 -c "import sys, base64; print(base64.urlsafe_b64decode(sys.stdin.read().strip() + '==').decode('utf-8'))")
else
    # Fallback to openssl (standard base64) - might fail if url-safe chars are used (-_)
    # Authgear uses URL-safe base64.
    # Let's try to use a simple replacement for URL safe chars
    NORMALIZED=$(echo "$NODE_ID" | tr '-_' '+/')
    DECODED=$(echo "$NORMALIZED" | openssl base64 -d -A)
fi

# Format is "User:<UUID>"
USER_UUID=${DECODED#User:}

echo "User UUID: $USER_UUID"

# 2.5 Ensure Project Exists in Portal
# (Moved to step 0)

# 3. Grant Collaborator Role
echo "Granting 'owner' role to user..."
docker compose -f "$COMPOSE_FILE" run --rm authgear-portal authgear-portal internal collaborator add \
  --app-id "$APP_ID" \
  --user-id "$USER_UUID" \
  --role owner

echo
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Admin user created successfully! 🚀${NC}"
echo -e "${GREEN}============================================${NC}"
echo "Login URL: https://${PORTAL_DOMAIN:-portal.maxadmin.io}"
echo "Email:     $EMAIL"
echo "Password:  $PASSWORD"
echo
