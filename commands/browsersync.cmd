#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_BROWSERSYNC:-0} -eq 0 ]]; then
  fatal "Browsersync is not used (set ROLL_BROWSERSYNC=1 in .env.roll to enable)."
fi

if [[ "${ROLL_PARAMS[0]}" == "freeport" ]]; then
  case "${ROLL_PARAMS[1]}" in
      ui)
           netstat -aln | awk '
                     $6 == "LISTEN" {
                       if ($4 ~ "[.:][0-9]+$") {
                         split($4, a, /[:.]/);
                         port = a[length(a)];
                         p[port] = 1
                       }
                     }
                     END {
                       for (i = 3250; i < 3500 && p[i]; i++){};
                       if (i == 3500) {exit 1};
                       print i
                     }
                   '
                   exit 0
          ;;
      *)
           netstat -aln | awk '
                     $6 == "LISTEN" {
                       if ($4 ~ "[.:][0-9]+$") {
                         split($4, a, /[:.]/);
                         port = a[length(a)];
                         p[port] = 1
                       }
                     }
                     END {
                       for (i = 3000; i < 3249 && p[i]; i++){};
                       if (i == 3249) {exit 1};
                       print i
                     }
                   '
                   exit 0
          ;;
  esac
fi

### load connection information for the mysql service
PHP_FPM_CONTAINER=$(roll env ps -q php-fpm)
if [[ ! ${PHP_FPM_CONTAINER} ]]; then
    fatal "No container found for php-fpm service."
fi

eval "$(
    docker container inspect ${PHP_FPM_CONTAINER} --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "BROWSERSYNC_PORT_"
)"

BROWSERSYNC_URL="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}"

echo $BROWSERSYNC_PORT_WEB

if [[ -n $BROWSERSYNC_PORT_WEB && -n $BROWSERSYNC_PORT_UI ]]; then
  boxsuccess "Browsersync info:" \
  "" \
  "Web Url: $BROWSERSYNC_URL:$BROWSERSYNC_PORT_WEB " \
  "UI Url: $BROWSERSYNC_URL:$BROWSERSYNC_PORT_UI"
else
  boxerror "Browsersync port or Browsersync UI port is not available"
fi