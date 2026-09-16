#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## A missing command is an answer here, not an error, so bin/roll's ERR trap must stay quiet
trap '' ERR

if [[ ${#ROLL_PARAMS[@]} -eq 0 ]]; then
    exit 1
fi

initializeRegistry
isCommandRegistered "${ROLL_PARAMS[0]}"
exit $?
