#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## local project directory if running within one; don't fail if it can't be found
ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)" || true

if [[ -n "$ROLL_ENV_PATH" ]];then
	loadEnvConfig "${ROLL_ENV_PATH}" || true
	if [[ -n "$ROLL_ENV_TYPE" && -f "${ROLL_DIR}/commands/${ROLL_ENV_TYPE}/usage.help" ]]; then
    source "${ROLL_DIR}/commands/${ROLL_ENV_TYPE}/usage.help"
  fi
fi


## load usage info for the given command falling back on default usage text
if [[ -f "${ROLL_CMD_HELP}" ]]; then
  source "${ROLL_CMD_HELP}"
elif [[ -f "${HOME}/.roll/reclu/usage.help" ]]; then
  source "${HOME}/.roll/reclu/usage.help"
else
  source "${ROLL_DIR}/commands/usage.help"
fi

echo -e "${ROLL_USAGE}"
exit 1
