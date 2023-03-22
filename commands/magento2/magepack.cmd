#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-process to bubble up normally
trap '' ERR

if [ -z "${ROLL_PARAMS[*]}" ]; then
	"${ROLL_DIR}/bin/roll" env exec magepack "magepack bundle"
	exit 0
fi

echo "Roll params: ${ROLL_PARAMS[@]}"
echo "================================================"
echo "Other params: $@"

exit 1

"${ROLL_DIR}/bin/roll" env exec magepack generate "${ROLL_PARAMS[@]}"