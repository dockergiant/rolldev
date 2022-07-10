#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

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
