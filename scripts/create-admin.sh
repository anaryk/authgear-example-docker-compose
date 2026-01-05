#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

PROJECT_DIR=$(pwd)

# Default credentials
EMAIL=${1:-admin@maxadmin.io}
PASSWORD=${2:-Start123}

echo -e "${GREEN}Creating admin user...${NC}"
echo "Email: $EMAIL"
echo "Password: $PASSWORD"

docker compose -f docker-compose.production.yml run --rm authgear \
  authgear internal user create \
  --email "$EMAIL" \
  --password "$PASSWORD"

echo
echo -e "${GREEN}User created successfully!${NC}"
echo "You can now log in at https://portal.maxadmin.io"
