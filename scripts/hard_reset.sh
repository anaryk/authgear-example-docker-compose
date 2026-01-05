#!/bin/bash
set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}WARNING: This script will perform a HARD RESET of the database.${NC}"
echo -e "${YELLOW}It will DELETE ALL DATA and rebuild the database container.${NC}"
echo "Press Ctrl+C to cancel within 5 seconds..."
sleep 5

echo -e "${GREEN}Stopping services...${NC}"
docker compose -f docker-compose.production.yml down

echo -e "${GREEN}Removing volumes (Force)...${NC}"
# Remove known volumes
docker volume rm authgear-example-docker-compose_postgres_data 2>/dev/null || true
docker volume rm authgear-example-docker-compose_redis_data 2>/dev/null || true
docker volume rm authgear-example-docker-compose_minio_data 2>/dev/null || true

# Also use compose down -v to be sure
docker compose -f docker-compose.production.yml down -v

echo -e "${GREEN}Forcing rebuild of Postgres image...${NC}"
# We force build to ensure we are NOT using the broken ghcr.io image
docker compose -f docker-compose.production.yml build --no-cache postgres

echo -e "${GREEN}Starting services...${NC}"
docker compose -f docker-compose.production.yml up -d

echo -e "${GREEN}Waiting for Postgres to initialize...${NC}"
sleep 10

echo -e "${GREEN}Checking Postgres logs...${NC}"
docker compose -f docker-compose.production.yml logs --tail=20 postgres

echo -e "${GREEN}Done! Services should be running.${NC}"
