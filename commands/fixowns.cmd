#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
		warning "This command is only working for Magento 2 projects" && exit 1
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

echo "Fixing filesystem ownerships..."

if [ -z  "${ROLL_PARAMS[@]}" ]; then
  "${ROLL_DIR}/bin/roll" rootnotty chown -R www-data:www-data /var/www
else
  "${ROLL_DIR}/bin/roll" rootnotty chown -R www-data:www-data /var/www/html/"${ROLL_PARAMS[@]}"
fi

echo "Filesystem ownerships fixed."
