#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## describe (and env) take any args so --format reaches this file, which means flags arrive in "$@"
DESCRIBE_FORMAT="human"
describeArgs=("$@")
i=0
while [[ $i -lt ${#describeArgs[@]} ]]; do
    case "${describeArgs[$i]}" in
        -h|--help)
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --format=*)
            DESCRIBE_FORMAT="${describeArgs[$i]#*=}"
            ;;
        --format)
            i=$((i + 1))
            DESCRIBE_FORMAT="${describeArgs[$i]:-}"
            ;;
        *)
            fatal "Unsupported argument ${describeArgs[$i]}"
            ;;
    esac
    i=$((i + 1))
done

if [[ "${DESCRIBE_FORMAT}" != "human" && "${DESCRIBE_FORMAT}" != "json" ]]; then
    fatal "Unsupported --format value '${DESCRIBE_FORMAT}' (expected: human, json)"
fi

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?

# One docker ps for the whole project, keyed by compose service label: container names differ per
# Compose version and per service (redis is named after REDIS_DISTRIBUTION), and a lookup per row took ~9s
ROLL_DESCRIBE_SERVICES=()
ROLL_DESCRIBE_STATES=()
while IFS='=' read -r describe_service describe_state; do
    [[ -z "${describe_service}" ]] && continue
    ROLL_DESCRIBE_SERVICES+=("${describe_service}")
    ROLL_DESCRIBE_STATES+=("${describe_state}")
done < <(docker ps -a \
    --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
    --format '{{.Label "com.docker.compose.service"}}={{.State}}' 2>/dev/null)

# Get container status (returns "running" or "stopped")
get_status_text() {
    local service=$1
    local i=0

    while [[ $i -lt ${#ROLL_DESCRIBE_SERVICES[@]} ]]; do
        if [[ "${ROLL_DESCRIBE_SERVICES[$i]}" == "$service" ]]; then
            if [[ "${ROLL_DESCRIBE_STATES[$i]}" == "running" ]]; then
                echo "running"
            else
                echo "stopped"
            fi
            return 0
        fi
        i=$((i + 1))
    done

    echo "stopped"
}

jsonServiceNames=()
jsonServiceStates=()
jsonServiceUrls=()
jsonServiceInfos=()

# Table row for human output, collected for json output; the credential hint rows never reach json
service_row() {
    local name=$1
    local status=$2
    local url=$3
    local info=$4
    if [[ "${DESCRIBE_FORMAT}" == "json" ]]; then
        jsonServiceNames+=("${name}")
        jsonServiceStates+=("${status}")
        jsonServiceUrls+=("${url}")
        jsonServiceInfos+=("${info}")
    elif [[ "${status}" == "running" ]]; then
        tableRow "${name}" "$(tableColor green running)" "${url}" "${info}"
    else
        tableRow "${name}" "$(tableColor red stopped)" "${url}" "${info}"
    fi
}

## usage: hint_row <url column text> <info column text>
hint_row() {
    [[ "${DESCRIBE_FORMAT}" == "json" ]] && return 0
    tableRow "" "" "$(tableColor dim "$1")" "$2"
}

PROJECT_URL="https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN}"

if [[ "${DESCRIBE_FORMAT}" != "json" ]]; then
    tableNew
    tableTitle "$(tableColor bold "Project:") ${ROLL_ENV_NAME} ${ROLL_ENV_PATH}"
    tableTitle "$(tableColor bold "Domain:")  ${PROJECT_URL}"
    tableTitle "$(tableColor bold "Type:")    ${ROLL_ENV_TYPE} PHP ${PHP_VERSION:-8.2} | Node ${NODE_VERSION:-18}"
    tableTitle "$(tableColor bold "Router:")  traefik"
    tableHeader "SERVICE" "STATUS" "URL/PORT" "INFO"
fi

# Services
service_row "nginx" "$(get_status_text nginx)" "${PROJECT_URL}" "${ROLL_ENV_TYPE}"
hint_row "InDocker: nginx:80,443" "Server: nginx-fpm"

service_row "php-fpm" "$(get_status_text php-fpm)" "InDocker: php-fpm:9000" "PHP ${PHP_VERSION:-8.2}"

if [[ "${ROLL_XDEBUG:-0}" == "1" ]] || [[ "${PHP_XDEBUG_3:-0}" == "1" ]]; then
    service_row "php-debug" "$(get_status_text php-debug)" "InDocker: php-debug:9000" "Xdebug 3"
fi

if [[ "${ROLL_DB:-1}" == "1" ]]; then
    DB_TYPE="${DB_DISTRIBUTION:-mariadb}:${DB_DISTRIBUTION_VERSION:-10.4}"
    service_row "db" "$(get_status_text db)" "InDocker: db:3306" "${DB_TYPE}"
    hint_row "" "magento/magento"
fi

if [[ "${ROLL_REDIS:-0}" == "1" ]]; then
    service_row "redis" "$(get_status_text redis)" "InDocker: redis:6379" "${REDIS_DISTRIBUTION:-redis}:${REDIS_VERSION:-7.2}"
fi

if [[ "${ROLL_REDISINSIGHT:-0}" == "1" ]]; then
    service_row "redisinsight" "$(get_status_text redisinsight)" "https://insight.${TRAEFIK_DOMAIN}" ""
fi

if [[ "${ROLL_ELASTICSEARCH:-0}" == "1" ]]; then
    service_row "elasticsearch" "$(get_status_text elasticsearch)" "InDocker: elasticsearch:9200" "ES ${ELASTICSEARCH_VERSION:-7.17}"
fi

if [[ "${ROLL_OPENSEARCH:-0}" == "1" ]]; then
    service_row "opensearch" "$(get_status_text opensearch)" "InDocker: opensearch:9200" "OS ${OPENSEARCH_VERSION:-2.5}"
fi

if [[ "${ROLL_RABBITMQ:-0}" == "1" ]]; then
    service_row "rabbitmq" "$(get_status_text rabbitmq)" "https://rabbitmq.${TRAEFIK_DOMAIN}" "Management UI"
fi

if [[ "${ROLL_VARNISH:-0}" == "1" ]]; then
    service_row "varnish" "$(get_status_text varnish)" "InDocker: varnish:80" ""
fi

if docker ps -a --format '{{.Names}}' | grep -q "${ROLL_ENV_NAME}-mailhog-1"; then
    service_row "mailhog" "$(get_status_text mailhog)" "https://mailhog.${TRAEFIK_DOMAIN}" "Mail catcher"
fi

if [[ "${DESCRIBE_FORMAT}" == "json" ]]; then
    projectNetwork=$(docker network ls --filter "label=dev.roll.environment.name=${ROLL_ENV_NAME}" --format '{{.Name}}' 2>/dev/null | head -n1)

    runningContainerCount=0
    for describe_state in "${ROLL_DESCRIBE_STATES[@]}"; do
        [[ "${describe_state}" == "running" ]] && runningContainerCount=$((runningContainerCount + 1))
    done

    out="{"
    out+="\"name\":\"$(jsonEscape "${ROLL_ENV_NAME}")\","
    out+="\"type\":\"$(jsonEscape "${ROLL_ENV_TYPE}")\","
    out+="\"dir\":\"$(jsonEscape "${ROLL_ENV_PATH}")\","
    out+="\"url\":\"$(jsonEscape "${PROJECT_URL}")\","
    out+="\"network\":\"$(jsonEscape "${projectNetwork}")\","
    out+="\"containers\":${runningContainerCount},"
    out+="\"services\":["
    i=0
    while [[ $i -lt ${#jsonServiceNames[@]} ]]; do
        (( i > 0 )) && out+=","
        out+="{"
        out+="\"name\":\"$(jsonEscape "${jsonServiceNames[$i]}")\","
        out+="\"status\":\"$(jsonEscape "${jsonServiceStates[$i]}")\","
        out+="\"url\":\"$(jsonEscape "${jsonServiceUrls[$i]}")\","
        out+="\"info\":\"$(jsonEscape "${jsonServiceInfos[$i]}")\""
        out+="}"
        i=$((i + 1))
    done
    out+="]}"
    printf '%s\n' "${out}"
    exit 0
fi

# Project URLs
if [[ -f "${ROLL_ENV_PATH}/.roll/stores.json" ]] && command -v jq &> /dev/null; then
    tableSpan "$(tableColor bold "Project URLs")"
    tableSpan "${PROJECT_URL}"

    ## read from process substitution, not a pipe: rows added inside a pipe stay in its subshell
    while read -r hostname; do
        [[ -n "${hostname}" ]] && tableSpan "https://${hostname}"
    done < <(jq -r '.stores | keys[]' "${ROLL_ENV_PATH}/.roll/stores.json" 2>/dev/null)
fi

echo ""
tableRender
echo ""
