#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Default values
EMAIL=""
APP_ID="accounts"
COMPOSE_FILE="docker-compose.production.yml"

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --email EMAIL          User email to make admin (required)"
    echo "  -a, --app-id APP_ID        App ID (default: accounts)"
    echo "  -f, --file COMPOSE_FILE    Docker compose file (default: docker-compose.production.yml)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --email user@example.com"
    echo "  $0 -e user@example.com"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            EMAIL="$2"
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
if [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: Email is required${NC}"
    echo ""
    usage
fi

# Load env
set -a
source ./env
set +a

HOST_DOMAIN=${AUTHGEAR_ENDPOINT#https://}
HOST_DOMAIN=${HOST_DOMAIN%/}

echo -e "${GREEN}Making user admin: $EMAIL${NC}"

# 1. Find user by email via Admin API
echo "Searching for user..."

QUERY='query { users(first: 100) { edges { node { id standardAttributes } } } }'

OUTPUT=$(docker compose -f "$COMPOSE_FILE" exec -T authgear authgear internal admin-api invoke \
  --app-id "$APP_ID" \
  --endpoint "http://127.0.0.1:3002" \
  --host "$HOST_DOMAIN" \
  --query "$QUERY")

echo -e "${YELLOW}API Response: $OUTPUT${NC}"

# 2. Extract Node ID - find the user with matching email in standardAttributes
# This is a simple grep that looks for email in the JSON output
NODE_ID=$(echo "$OUTPUT" | grep -B5 "\"email\":\"$EMAIL\"" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$NODE_ID" ]; then
    echo "Error: User not found with email: $EMAIL"
    echo "Available users:"
    echo "$OUTPUT" | grep -o '"email":"[^"]*"' | cut -d'"' -f4 | sort -u
    exit 1
fi

echo "Node ID: $NODE_ID"

# 3. Decode Base64 to get UUID
if command -v python3 &>/dev/null; then
    DECODED=$(echo "$NODE_ID" | python3 -c "import sys, base64; print(base64.urlsafe_b64decode(sys.stdin.read().strip() + '==').decode('utf-8'))")
else
    NORMALIZED=$(echo "$NODE_ID" | tr '-_' '+/')
    DECODED=$(echo "$NORMALIZED" | openssl base64 -d -A)
fi

USER_UUID=${DECODED#User:}
echo "User UUID: $USER_UUID"

# 4. Ensure project exists in Portal
echo "Ensuring project '$APP_ID' exists in Portal..."
docker compose -f "$COMPOSE_FILE" run --rm authgear-portal authgear-portal internal configsource create /app || true
docker compose -f "$COMPOSE_FILE" run --rm authgear-portal authgear-portal internal domain create-default --default-domain-suffix "$APP_HOST_SUFFIX" || true

# 5. Grant owner role
echo "Granting 'owner' role..."
docker compose -f "$COMPOSE_FILE" run --rm authgear-portal authgear-portal internal collaborator add \
  --app-id "$APP_ID" \
  --user-id "$USER_UUID" \
  --role owner

echo
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}User is now an admin! 🚀${NC}"
echo -e "${GREEN}============================================${NC}"
echo "Email: $EMAIL"
echo "Portal: https://${PORTAL_DOMAIN:-portal.maxadmin.io}"
echo
