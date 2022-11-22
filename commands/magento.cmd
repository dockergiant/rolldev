#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_ENV_TYPE}" != "magento2" && "${ROLL_ENV_TYPE}" != "magento1" ]]; then
		warning "This command is only working for Magento 2 or Magento 1 projects" && exit 1
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

"${ROLL_DIR}/bin/roll" cli "bin/magento" "${ROLL_PARAMS[@]}" "$@"
