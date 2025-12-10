#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?

# Colors
GREEN='\033[32m'
RED='\033[31m'
CYAN='\033[36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Get container status (returns "running" or "stopped")
get_status_text() {
    local service=$1
    local container="${ROLL_ENV_NAME}-${service}-1"
    local status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
    if [[ "$status" == "running" ]]; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Print status with color
print_status() {
    local status=$1
    if [[ "$status" == "running" ]]; then
        printf "${GREEN}%-8s${NC}" "running"
    else
        printf "${RED}%-8s${NC}" "stopped"
    fi
}

# Table dimensions
W=95

# Horizontal lines
line_top() {
    printf "${CYAN}┌"
    printf '─%.0s' $(seq 1 $((W-2)))
    printf "┐${NC}\n"
}

line_mid() {
    printf "${CYAN}├"
    printf '─%.0s' $(seq 1 14)
    printf "┼"
    printf '─%.0s' $(seq 1 10)
    printf "┼"
    printf '─%.0s' $(seq 1 45)
    printf "┼"
    printf '─%.0s' $(seq 1 22)
    printf "┤${NC}\n"
}

line_bot() {
    printf "${CYAN}└"
    printf '─%.0s' $(seq 1 14)
    printf "┴"
    printf '─%.0s' $(seq 1 10)
    printf "┴"
    printf '─%.0s' $(seq 1 45)
    printf "┴"
    printf '─%.0s' $(seq 1 22)
    printf "┘${NC}\n"
}

# Header row
header_row() {
    printf "${CYAN}│${NC} ${BOLD}%-12s${NC} ${CYAN}│${NC} ${BOLD}%-8s${NC} ${CYAN}│${NC} ${BOLD}%-43s${NC} ${CYAN}│${NC} ${BOLD}%-20s${NC} ${CYAN}│${NC}\n" "$1" "$2" "$3" "$4"
}

# Data row with status
data_row() {
    local name=$1
    local status=$2
    local url=$3
    local info=$4
    printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} " "$name"
    print_status "$status"
    printf " ${CYAN}│${NC} %-43s ${CYAN}│${NC} %-20s ${CYAN}│${NC}\n" "$url" "$info"
}

# Sub row (continuation, no status)
sub_row() {
    printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} %-8s ${CYAN}│${NC} ${DIM}%-43s${NC} ${CYAN}│${NC} %-20s ${CYAN}│${NC}\n" "" "" "$1" "$2"
}

# Info row (spans columns)
info_row() {
    printf "${CYAN}│${NC} ${BOLD}%-12s${NC} ${CYAN}│${NC} %-76s ${CYAN}│${NC}\n" "$1" "$2"
}

# Text row (spans columns, for URLs)
text_row() {
    printf "${CYAN}│${NC} %-12s ${CYAN}│${NC} %-76s ${CYAN}│${NC}\n" "" "$1"
}

echo ""

# Header box
line_top
printf "${CYAN}│${NC} ${BOLD}Project:${NC} %-83s ${CYAN}│${NC}\n" "${ROLL_ENV_NAME} ${ROLL_ENV_PATH}"
printf "${CYAN}│${NC} ${BOLD}Domain:${NC}  %-83s ${CYAN}│${NC}\n" "https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN}"
printf "${CYAN}│${NC} ${BOLD}Type:${NC}    %-83s ${CYAN}│${NC}\n" "${ROLL_ENV_TYPE} PHP ${PHP_VERSION:-8.2} | Node ${NODE_VERSION:-18}"
printf "${CYAN}│${NC} ${BOLD}Router:${NC}  %-83s ${CYAN}│${NC}\n" "traefik"
line_mid

# Table header
header_row "SERVICE" "STATUS" "URL/PORT" "INFO"
line_mid

# Services
data_row "nginx" "$(get_status_text nginx)" "https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN}" "${ROLL_ENV_TYPE}"
sub_row "InDocker: nginx:80,443" "Server: nginx-fpm"

data_row "php-fpm" "$(get_status_text php-fpm)" "InDocker: php-fpm:9000" "PHP ${PHP_VERSION:-8.2}"

if [[ "${ROLL_XDEBUG:-0}" == "1" ]] || [[ "${PHP_XDEBUG_3:-0}" == "1" ]]; then
    data_row "php-debug" "$(get_status_text php-debug)" "InDocker: php-debug:9000" "Xdebug 3"
fi

if [[ "${ROLL_DB:-1}" == "1" ]]; then
    DB_TYPE="${DB_DISTRIBUTION:-mariadb}:${DB_DISTRIBUTION_VERSION:-10.4}"
    data_row "db" "$(get_status_text db)" "InDocker: db:3306" "${DB_TYPE}"
    sub_row "" "magento/magento"
fi

if [[ "${ROLL_REDIS:-0}" == "1" ]]; then
    data_row "redis" "$(get_status_text redis)" "InDocker: redis:6379" "Redis ${REDIS_VERSION:-7.2}"
fi

if [[ "${ROLL_REDISINSIGHT:-0}" == "1" ]]; then
    data_row "redisinsight" "$(get_status_text redisinsight)" "https://insight.${TRAEFIK_DOMAIN}" ""
fi

if [[ "${ROLL_ELASTICSEARCH:-0}" == "1" ]]; then
    data_row "elasticsearch" "$(get_status_text elasticsearch)" "InDocker: elasticsearch:9200" "ES ${ELASTICSEARCH_VERSION:-7.17}"
fi

if [[ "${ROLL_OPENSEARCH:-0}" == "1" ]]; then
    data_row "opensearch" "$(get_status_text opensearch)" "InDocker: opensearch:9200" "OS ${OPENSEARCH_VERSION:-2.5}"
fi

if [[ "${ROLL_RABBITMQ:-0}" == "1" ]]; then
    data_row "rabbitmq" "$(get_status_text rabbitmq)" "https://rabbitmq.${TRAEFIK_DOMAIN}" "Management UI"
fi

if [[ "${ROLL_VARNISH:-0}" == "1" ]]; then
    data_row "varnish" "$(get_status_text varnish)" "InDocker: varnish:80" ""
fi

if docker ps -a --format '{{.Names}}' | grep -q "${ROLL_ENV_NAME}-mailhog-1"; then
    data_row "mailhog" "$(get_status_text mailhog)" "https://mailhog.${TRAEFIK_DOMAIN}" "Mail catcher"
fi

line_mid

# Project URLs
if [[ -f "${ROLL_ENV_PATH}/.roll/stores.json" ]] && command -v jq &> /dev/null; then
    info_row "Project URLs" ""

    # Main URL
    text_row "https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN}"

    # Store URLs
    jq -r '.stores | keys[]' "${ROLL_ENV_PATH}/.roll/stores.json" 2>/dev/null | while read hostname; do
        text_row "https://${hostname}"
    done
fi

line_bot
echo ""
