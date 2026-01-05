#!/usr/bin/env bash
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Color codes
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

echo -e "${RED}============================================================${NC}"
echo -e "${RED}   DANGER: FULL REINSTALLATION INITIATED${NC}"
echo -e "${RED}============================================================${NC}"
echo
echo -e "${YELLOW}This action will:${NC}"
echo "1. Stop all running containers"
echo "2. DELETE all Docker volumes (Database, Redis, MinIO data will be lost)"
echo "3. DELETE generated configuration files (env, keys)"
echo "4. Re-generate new passwords and secrets"
echo "5. Re-initialize the entire stack"
echo
echo -e "${YELLOW}Make sure you have backups if you care about the data!${NC}"
echo

read -rp "Type 'delete-everything' to confirm: " confirm

if [[ "$confirm" != "delete-everything" ]]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo
echo "Starting fresh installation..."
echo

# Execute install.sh with --reinstall flag
"${SCRIPT_DIR}/install.sh" --reinstall
