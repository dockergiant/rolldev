#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?

## set defaults for this command which can be overridden either using exports in the user
## profile or setting them in the .env.roll configuration on a per-project basis
ROLL_ENV_SHELL_CONTAINER=${ROLL_ENV_SHELL_CONTAINER:-php-fpm}

## allow return codes from sub-process to bubble up normally
trap '' ERR

"${ROLL_DIR}/bin/roll" env exec -u www-data "${ROLL_ENV_SHELL_CONTAINER}" \
    "${ROLL_PARAMS[@]}" "$@"
