#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  roll env --help || exit $? && exit $?
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

## define source repository
if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
  eval "$(cat "${ROLL_HOME_DIR}/.env" | sed 's/\r$//g' | grep "^ROLL_")"
fi
export ROLL_IMAGE_REPOSITORY="${ROLL_IMAGE_REPOSITORY:-"docker.io/rollupdev"}"

## configure environment type defaults
if [[ ${ROLL_ENV_TYPE} =~ ^magento ]]; then
    export ROLL_SVC_PHP_VARIANT=-${ROLL_ENV_TYPE}
fi

## configure xdebug version
export XDEBUG_VERSION="debug" # xdebug2 image
if [[ ${PHP_XDEBUG_3} -eq 1 ]]; then
    export XDEBUG_VERSION="xdebug3"
fi

if [[ ${ROLL_ENV_TYPE} != local ]]; then
    ROLL_NGINX=${ROLL_NGINX:-1}
    ROLL_DB=${ROLL_DB:-1}
    ROLL_REDIS=${ROLL_REDIS:-1}

    # define bash history folder for changing permissions
    ROLL_CHOWN_DIR_LIST="/bash_history /home/www-data/.ssh ${ROLL_CHOWN_DIR_LIST:-}"
fi
export CHOWN_DIR_LIST=${ROLL_CHOWN_DIR_LIST:-}

if [[ ${ROLL_ENV_TYPE} == "magento1" && -f "${ROLL_ENV_PATH}/.modman/.basedir" ]]; then
  export NGINX_PUBLIC='/'$(cat "${ROLL_ENV_PATH}/.modman/.basedir")
fi

if [[ ${ROLL_ENV_TYPE} == "magento2" ]]; then
    ROLL_VARNISH=${ROLL_VARNISH:-1}
    ROLL_ELASTICSEARCH=${ROLL_ELASTICSEARCH:-1}
    ROLL_RABBITMQ=${ROLL_RABBITMQ:-1}
fi

## WSL1/WSL2 are GNU/Linux env type but still run Docker Desktop
if [[ ${XDEBUG_CONNECT_BACK_HOST} == '' ]] && grep -sqi microsoft /proc/sys/kernel/osrelease; then
    export XDEBUG_CONNECT_BACK_HOST=host.docker.internal
fi

## For linux, if UID is 1000, there is no need to use the socat proxy.
if [[ ${ROLL_ENV_SUBT} == "linux" && $UID == 1000 ]]; then
    export SSH_AUTH_SOCK_PATH_ENV=/run/host-services/ssh-auth.sock
fi

## configure docker-compose files
DOCKER_COMPOSE_ARGS=()

appendEnvPartialIfExists "networks"

if [[ ${ROLL_ENV_TYPE} != local ]]; then
    appendEnvPartialIfExists "php-fpm"
fi

[[ ${ROLL_NGINX} -eq 1 ]] \
    && appendEnvPartialIfExists "nginx"

[[ ${ROLL_DB} -eq 1 ]] \
    && appendEnvPartialIfExists "db"

[[ ${ROLL_ELASTICSEARCH} -eq 1 ]] \
    && appendEnvPartialIfExists "elasticsearch"

[[ ${ROLL_VARNISH} -eq 1 ]] \
    && appendEnvPartialIfExists "varnish"

[[ ${ROLL_RABBITMQ} -eq 1 ]] \
    && appendEnvPartialIfExists "rabbitmq"

[[ ${ROLL_REDIS} -eq 1 ]] \
    && appendEnvPartialIfExists "redis"

appendEnvPartialIfExists "${ROLL_ENV_TYPE}"

[[ ${ROLL_TEST_DB} -eq 1 ]] \
    && appendEnvPartialIfExists "${ROLL_ENV_TYPE}.tests"

[[ ${ROLL_SPLIT_SALES} -eq 1 ]] \
    && appendEnvPartialIfExists "${ROLL_ENV_TYPE}.splitdb.sales"

[[ ${ROLL_SPLIT_CHECKOUT} -eq 1 ]] \
    && appendEnvPartialIfExists "${ROLL_ENV_TYPE}.splitdb.checkout"

if [[ ${ROLL_BLACKFIRE} -eq 1 ]]; then
    appendEnvPartialIfExists "blackfire"
    appendEnvPartialIfExists "${ROLL_ENV_TYPE}.blackfire"
fi

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

if [[ -f "${ROLL_ENV_PATH}/.roll/roll-env.${ROLL_ENV_SUBT}.yml" ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${ROLL_ENV_PATH}/.roll/roll-env.${ROLL_ENV_SUBT}.yml")
fi

if [[ ${ROLL_SELENIUM_DEBUG} -eq 1 ]]; then
    export ROLL_SELENIUM_DEBUG="-debug"
else
    export ROLL_SELENIUM_DEBUG=
fi

## disconnect peered service containers from environment network
if [[ "${ROLL_PARAMS[0]}" == "down" ]]; then
    disconnectPeeredServices "$(renderEnvNetworkName)"
fi

## connect peered service containers to environment network
if [[ "${ROLL_PARAMS[0]}" == "up" ]]; then
    ## create environment network for attachments if it does not already exist
    if [[ $(docker network ls -f "name=$(renderEnvNetworkName)" -q) == "" ]]; then
        docker-compose \
            --project-directory "${ROLL_ENV_PATH}" -p "${ROLL_ENV_NAME}" \
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

## pass ochestration through to docker-compose
docker-compose \
    --project-directory "${ROLL_ENV_PATH}" -p "${ROLL_ENV_NAME}" \
    "${DOCKER_COMPOSE_ARGS[@]}" "${ROLL_PARAMS[@]}" "$@"

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
