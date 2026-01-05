#!/usr/bin/env bash
#
# Authgear - Clean Restart Script
# Tento skript zastaví kontejnery, smaže volumes a restartuje celou instalaci
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

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

# Hlavní funkce
main() {
    log_warn "⚠️  POZOR: Tento skript smaže VŠECHNA DATA!"
    log_warn "⚠️  Budou smazány všechny Docker volumes a konfigurace!"
    echo
    read -rp "Opravdu chcete pokračovat? Napište 'ano' pro potvrzení: "
    
    if [[ "$REPLY" != "ano" ]]; then
        log_info "Operace zrušena"
        exit 0
    fi
    
    echo
    log_info "Zastavuji kontejnery..."
    docker compose down -v || true
    
    log_info "Mažu volumes..."
    docker volume rm authgear-example-docker-compose_db_data 2>/dev/null || true
    docker volume rm authgear-example-docker-compose_redis_data 2>/dev/null || true
    docker volume rm authgear-example-docker-compose_minio_data 2>/dev/null || true
    docker volume rm db_data 2>/dev/null || true
    docker volume rm redis_data 2>/dev/null || true
    docker volume rm minio_data 2>/dev/null || true
    
    log_info "Čistím var adresář..."
    rm -rf ./var/*
    
    log_info "Čistím accounts adresář..."
    rm -rf ./accounts/*
    touch ./accounts/.gitkeep
    
    log_info "Mažu env soubor..."
    rm -f env
    rm -f .env
    
    echo
    log_info "✅ Vyčištění dokončeno!"
    echo
    log_info "Nyní můžete spustit znovu instalaci pomocí:"
    echo "  ./scripts/install.sh          (pro produkční instalaci)"
    echo "  docker compose up -d          (pro vývojové prostředí)"
}

main "$@"
