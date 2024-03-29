#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## allow return codes from sub-process to bubble up normally
trap '' ERR

if [ "$1" == "--notty" ]; then
	"${ROLL_DIR}/bin/roll" clinotty composer "${ROLL_PARAMS[@]}" "$@"
else
	"${ROLL_DIR}/bin/roll" cli composer "${ROLL_PARAMS[@]}" "$@"
fi
