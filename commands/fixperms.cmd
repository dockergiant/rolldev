#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## allow return codes from sub-process to bubble up normally
trap '' ERR

echo "Fixing filesystem permissions..."

if [ -z  "${ROLL_PARAMS[@]}" ]; then
  "${ROLL_DIR}/bin/roll" clinotty find var vendor pub/static pub/media app/etc \( -type f -or -type d \) -exec chmod u+w {} +;
  "${ROLL_DIR}/bin/roll" clinotty chmod u+x bin/magento
else
  "${ROLL_DIR}/bin/roll" clinotty find "${ROLL_PARAMS[@]}" \( -type f -or -type d \) -exec chmod u+w {} +;
fi

echo "Filesystem permissions fixed."
