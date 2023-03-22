#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?

## set defaults for this command which can be overridden either using exports in the user
## profile or setting them in the .env.roll configuration on a per-project basis
ROLL_ENV_DEBUG_COMMAND=${ROLL_ENV_DEBUG_COMMAND:-bash}
ROLL_ENV_DEBUG_CONTAINER=${ROLL_ENV_DEBUG_CONTAINER:-php-debug}
ROLL_ENV_DEBUG_HOST=${ROLL_ENV_DEBUG_HOST:-}

if [[ ${ROLL_ENV_DEBUG_HOST} == "" ]]; then
    if [[ $OSTYPE =~ ^darwin ]] || grep -sqi microsoft /proc/sys/kernel/osrelease; then
        ROLL_ENV_DEBUG_HOST=host.docker.internal
    else
        ROLL_ENV_DEBUG_HOST=$(
            docker container inspect $(roll env ps -q php-debug) \
                --format '{{range .NetworkSettings.Networks}}{{println .Gateway}}{{end}}' | head -n1
        )
    fi
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

"${ROLL_DIR}/bin/roll" env exec -u www-data -e "XDEBUG_REMOTE_HOST=${ROLL_ENV_DEBUG_HOST}" \
    "${ROLL_ENV_DEBUG_CONTAINER}" "${ROLL_ENV_DEBUG_COMMAND}" "${ROLL_PARAMS[@]}" "$@"
