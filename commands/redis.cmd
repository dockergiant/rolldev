#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_REDIS:-1} -eq 0 && ${ROLL_DRAGONFLY:-1} -eq 0 ]]; then
  fatal "Redis nor Dragonfly environment is not used (ROLL_REDIS=0|ROLL_DRAGONFLY=0)."
fi

## bare `roll redis` opens a session, and redis takes any args, so --help arrives in "$@"; -h with a
## value is redis-cli's host flag
if [[ "${ROLL_PARAMS[0]:-}" == "help" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" && $# -eq 1 ]]; then
  source "${ROLL_DIR}/commands/usage.cmd"
fi

## load connection information for the redis service
REDIS_CONTAINER=$(roll env ps -q redis)
if [[ ! ${REDIS_CONTAINER} ]]; then
    fatal "No container found for redis service."
fi

"${ROLL_DIR}/bin/roll" env exec redis redis-cli "${ROLL_PARAMS[@]}" "$@"
