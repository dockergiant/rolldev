#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1


ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_BROWSERSYNC:-0} -eq 0 ]]; then
  fatal "Browsersync is not used (set ROLL_BROWSERSYNC=1 in .env.roll to enable)."
fi

### load connection information for the mysql service
PHP_FPM_CONTAINER=$(roll env ps -q php-fpm)
if [[ ! ${PHP_FPM_CONTAINER} ]]; then
    fatal "No container found for php-fpm service."
fi

BROWSERSYNC_PORT="$(docker container inspect ${PHP_FPM_CONTAINER} --format '{{(index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort}}')"
BROWSERSYNC_UI="$(docker container inspect ${PHP_FPM_CONTAINER} --format '{{(index (index .NetworkSettings.Ports "3001/tcp") 0).HostPort}}')"

BROWSERSYNC_URL="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}"

if [[ -n $BROWSERSYNC_PORT && -n $BROWSERSYNC_UI ]]; then
  boxsuccess "Browsersync info:" \
  "" \
  "Web Url: $BROWSERSYNC_URL:$BROWSERSYNC_PORT " \
  "UI Url: $BROWSERSYNC_URL:$BROWSERSYNC_UI"
else
  boxerror "Browsersync port or Browsersync UI port is not available"
fi