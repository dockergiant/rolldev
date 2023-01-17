#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-process to bubble up normally
trap '' ERR

if [ -z "${ROLL_PARAMS[*]}" ]; then
	"${ROLL_DIR}/bin/roll" add-php-ext --help
	exit 0
fi

ROLL_ENV_SHELL_CONTAINER=${ROLL_ENV_SHELL_CONTAINER:-php-fpm}
ROLL_ENV_SHELL_DEBUG_CONTAINER=${ROLL_ENV_SHELL_DEBUG_CONTAINER:-php-debug}

"${ROLL_DIR}/bin/roll" env exec -u root -T "${ROLL_ENV_SHELL_CONTAINER}" install-php-extensions "${ROLL_PARAMS[@]}"
"${ROLL_DIR}/bin/roll" env exec -u root -T "${ROLL_ENV_SHELL_DEBUG_CONTAINER}" install-php-extensions "${ROLL_PARAMS[@]}"