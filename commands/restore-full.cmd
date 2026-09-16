#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## restore-full is `restore --include-source`; the name stays because scripts and docs use it
ROLL_PARAMS=("--include-source" "${ROLL_PARAMS[@]}")
source "${ROLL_DIR}/commands/restore.cmd"
