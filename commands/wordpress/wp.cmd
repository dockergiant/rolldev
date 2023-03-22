#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## allow return codes from sub-process to bubble up normally
trap '' ERR

if (( ${#ROLL_PARAMS[@]} == 0 )); then
  "${ROLL_DIR}/bin/roll" wp --help || exit $? && exit $?
fi

"${ROLL_DIR}/bin/roll" cli wp "${ROLL_PARAMS[@]}" "$@"
