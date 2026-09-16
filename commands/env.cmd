#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  source "${ROLL_DIR}/commands/usage.cmd"
fi

if [[ ${ROLL_REDIS} -eq 1 && ${ROLL_DRAGONFLY} -eq 1 ]]; then
  fatal "In-memory db distribution collision detected. Redis and Dragonfly service can't run at the same time set one of them off with (ROLL_REDIS=0|ROLL_DRAGONFLY=0)."
fi

if [[ ${ROLL_REDIS} -eq 1 && "${REDIS_DISTRIBUTION:-redis}" == "valkey" ]] && [[ $(version "${REDIS_VERSION}") -lt $(version "8.0") ]]; then
  fatal "Valkey images are published from version 8.0, but REDIS_VERSION=${REDIS_VERSION}. Set REDIS_VERSION to 8.1 or 9.0 in .env.roll."
fi
## allow return codes from sub-process to bubble up normally
trap '' ERR

## loadEnvConfig already read ~/.roll/.env and derived the env-type defaults (utils/config.sh)
export ROLL_IMAGE_REPOSITORY="${ROLL_IMAGE_REPOSITORY:-"ghcr.io/dockergiant"}"

## configure docker-compose files
DOCKER_COMPOSE_ARGS=()

appendEnvPartialIfExists "networks"

if [[ ${ROLL_ENV_TYPE} != local ]]; then
    appendEnvPartialIfExists "php-fpm"
fi

if [[ ${ROLL_BROWSERSYNC} -eq 1 ]]; then
  export BROWSERSYNC_PORT_WEB=$(roll browsersync freeport web)
  export BROWSERSYNC_PORT_UI=$(roll browsersync freeport ui)
  if [[ ${ROLL_PUBLISH_PORTS} -eq 1 ]]; then
    appendEnvPartialIfExists "browsersync"
  else
    ## a ports block cannot be removed through interpolation, hence a separate fragment
    appendEnvPartialIfExists "browsersync.noports"
  fi
fi

[[ ${ROLL_INCLUDE_GIT} -eq 1 ]] \
    && appendEnvPartialIfExists "git"


[[ ${ROLL_NGINX} -eq 1 ]] \
    && appendEnvPartialIfExists "nginx"

[[ ${ROLL_DB} -eq 1 ]] \
    && appendEnvPartialIfExists "db"

[[ ${ROLL_MONGODB} -eq 1 ]] \
    && appendEnvPartialIfExists "mongodb"

[[ ${ROLL_ELASTICSEARCH} -eq 1 ]] \
    && appendEnvPartialIfExists "elasticsearch"

[[ ${ROLL_ELASTICVUE} -eq 1 ]] \
    && appendEnvPartialIfExists "elasticvue"

[[ ${ROLL_OPENSEARCH} -eq 1 ]] \
    && appendEnvPartialIfExists "opensearch"

[[ ${ROLL_VARNISH} -eq 1 ]] \
    && appendEnvPartialIfExists "varnish"

[[ ${ROLL_RABBITMQ} -eq 1 ]] \
    && appendEnvPartialIfExists "rabbitmq"

[[ ${ROLL_REDIS} -eq 1 ]] \
    && appendEnvPartialIfExists "redis"

[[ ${ROLL_REDISINSIGHT} -eq 1 ]] \
    && appendEnvPartialIfExists "redisinsight"

[[ ${ROLL_DRAGONFLY} -eq 1 ]] \
    && appendEnvPartialIfExists "dragonfly"

appendEnvPartialIfExists "${ROLL_ENV_TYPE}"

[[ ${ROLL_TEST_DB} -eq 1 ]] \
    && appendEnvPartialIfExists "${ROLL_ENV_TYPE}.tests"

[[ ${ROLL_ALLURE} -eq 1 ]] \
    && appendEnvPartialIfExists "allure"

[[ ${ROLL_SELENIUM} -eq 1 ]] \
    && appendEnvPartialIfExists "selenium"

[[ ${ROLL_MAGEPACK} -eq 1 ]] \
    && appendEnvPartialIfExists "${ROLL_ENV_TYPE}.magepack"

if [[ -f "${ROLL_ENV_PATH}/.roll/roll-env.yml" ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${ROLL_ENV_PATH}/.roll/roll-env.yml")
fi

## WSL loads the project linux override before its own, like the include fragments in utils/env.sh
ROLL_ENV_OVERRIDE_SUFFIXES=("${ROLL_ENV_SUBT}")
if [[ "${ROLL_ENV_SUBT}" == "wsl" ]]; then
    ROLL_ENV_OVERRIDE_SUFFIXES=("linux" "wsl")
fi
for ROLL_ENV_OVERRIDE_SUFFIX in "${ROLL_ENV_OVERRIDE_SUFFIXES[@]}"; do
    if [[ -f "${ROLL_ENV_PATH}/.roll/roll-env.${ROLL_ENV_OVERRIDE_SUFFIX}.yml" ]]; then
        DOCKER_COMPOSE_ARGS+=("-f")
        DOCKER_COMPOSE_ARGS+=("${ROLL_ENV_PATH}/.roll/roll-env.${ROLL_ENV_OVERRIDE_SUFFIX}.yml")
    fi
done

if [[ ${ROLL_SELENIUM_DEBUG} -eq 1 ]]; then
    export ROLL_SELENIUM_DEBUG="-debug"
else
    export ROLL_SELENIUM_DEBUG=
fi

## handle describe subcommand
if [[ "${ROLL_PARAMS[0]}" == "describe" ]]; then
    source "${ROLL_DIR}/commands/describe.cmd"
    exit $?
fi

## handle doctor subcommand
if [[ "${ROLL_PARAMS[0]}" == "doctor" ]]; then
    source "${ROLL_DIR}/commands/doctor.cmd"
    exit $?
fi

## sh <service> '<command>' runs through sh -c in the container, so redirects and pipes apply there
if [[ "${ROLL_PARAMS[0]}" == "sh" ]]; then
    if (( ${#ROLL_PARAMS[@]} < 3 )); then
        fatal "roll env sh requires a service name and command: roll env sh <service> '<command>'"
    fi
    ## running only the first word of an unquoted command is the confusion this subcommand removes
    if (( ${#ROLL_PARAMS[@]} > 3 )); then
        fatal "roll env sh takes a single quoted command: roll env sh ${ROLL_PARAMS[1]} '${ROLL_PARAMS[*]:2}'"
    fi
    ## env takes any args, so a dash-prefixed word stops roll's parser and lands in "$@"
    if (( $# > 0 )); then
        fatal "roll env sh takes a single quoted command: roll env sh ${ROLL_PARAMS[1]} '${ROLL_PARAMS[2]} $*'"
    fi
    ROLL_PARAMS=("exec" "-T" "${ROLL_PARAMS[1]}" "sh" "-c" "${ROLL_PARAMS[2]}")
fi

## disconnect peered service containers from environment network
if [[ "${ROLL_PARAMS[0]}" == "down" ]]; then
    disconnectPeeredServices "$(renderEnvNetworkName)"
fi

## connect peered service containers to environment network
if [[ "${ROLL_PARAMS[0]}" == "up" ]]; then

#		# update images if needed
#		roll env pull
    ## create environment network for attachments if it does not already exist
    if [[ -z "$(docker network ls -f "name=^$(renderEnvNetworkName)$" -q)" ]]; then

        docker compose \
            --env-file "${ROLL_ENV_PATH}/.env.roll" --project-directory "${ROLL_ENV_PATH}" -p "${ROLL_ENV_NAME}" \
            "${DOCKER_COMPOSE_ARGS[@]}" up --no-start
    fi

    ## connect globally peered services to the environment network
    connectPeeredServices "$(renderEnvNetworkName)"

    ## always execute env up using --detach mode
    if ! (containsElement "-d" "$@" || containsElement "--detach" "$@"); then
        ROLL_PARAMS=("${ROLL_PARAMS[@]:1}")
        ROLL_PARAMS=(up -d "${ROLL_PARAMS[@]}")
    fi
fi

## lookup address of traefik container on environment network
export TRAEFIK_ADDRESS="$(docker container inspect traefik \
    --format '
        {{- $network := index .NetworkSettings.Networks "'"$(renderEnvNetworkName)"'" -}}
        {{- if $network }}{{ $network.IPAddress }}{{ end -}}
    ' 2>/dev/null || true
)"

if [[ $OSTYPE =~ ^darwin ]]; then
    export MUTAGEN_SYNC_FILE="${ROLL_DIR}/environments/${ROLL_ENV_TYPE}/${ROLL_ENV_TYPE}.mutagen.yml"

    if [[ -f "${ROLL_ENV_PATH}/.roll/mutagen.yml" ]]; then
        export MUTAGEN_SYNC_FILE="${ROLL_ENV_PATH}/.roll/mutagen.yml"
    fi
fi

## pause mutagen sync if needed
if [[ "${ROLL_PARAMS[0]}" == "stop" ]] \
    && [[ $OSTYPE =~ ^darwin ]] && [[ -f "${MUTAGEN_SYNC_FILE}" ]]
then
    roll sync pause
fi

## pass orchestration through to docker-compose
docker compose \
    --env-file "${ROLL_ENV_PATH}/.env.roll" --project-directory "${ROLL_ENV_PATH}" -p "${ROLL_ENV_NAME}" \
    "${DOCKER_COMPOSE_ARGS[@]}" "${ROLL_PARAMS[@]}" "$@"

if [[ ("${ROLL_PARAMS[0]}" == "up" || "${ROLL_PARAMS[0]}" == "start") && -n "${ROLL_EXTRA_PHP_EXT}" ]]; then
  info "Adding additional PHP extension, This may take a while... (output hidden)"
  roll add-php-ext "${ROLL_EXTRA_PHP_EXT}" > /dev/null 2>&1
fi

## resume mutagen sync if available and php-fpm container id hasn't changed
if ([[ "${ROLL_PARAMS[0]}" == "up" ]] || [[ "${ROLL_PARAMS[0]}" == "start" ]]) \
    && [[ $OSTYPE =~ ^darwin ]] && [[ -f "${MUTAGEN_SYNC_FILE}" ]] \
    && [[ $(roll sync list | grep -i 'Status: \[Paused\]' | wc -l | awk '{print $1}') == "1" ]] \
    && [[ $(roll env ps -q php-fpm) ]] \
    && [[ $(docker container inspect $(roll env ps -q php-fpm) --format '{{ .State.Status }}') = "running" ]] \
    && [[ $(roll env ps -q php-fpm) = $(roll sync list | grep -i 'URL: docker' | awk -F'/' '{print $3}') ]]
then
    roll sync resume
fi

## start mutagen sync if needed
if ([[ "${ROLL_PARAMS[0]}" == "up" ]] || [[ "${ROLL_PARAMS[0]}" == "start" ]]) \
    && [[ $OSTYPE =~ ^darwin ]] && [[ -f "${MUTAGEN_SYNC_FILE}" ]] \
    && [[ $(roll sync list | grep -i 'Connection state: Connected' | wc -l | awk '{print $1}') != "2" ]] \
    && [[ $(roll env ps -q php-fpm) ]] \
    && [[ $(docker container inspect $(roll env ps -q php-fpm) --format '{{ .State.Status }}') = "running" ]]
then
    roll sync start
fi

## stop mutagen sync if needed
if [[ "${ROLL_PARAMS[0]}" == "down" ]] \
    && [[ $OSTYPE =~ ^darwin ]] && [[ -f "${MUTAGEN_SYNC_FILE}" ]]
then
    roll sync stop
fi
