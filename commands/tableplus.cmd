#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Update commands check.
"${ROLL_DIR}/bin/roll" cli-tools-update-check
clear

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_DB:-1} -eq 0 ]]; then
  fatal "Database environment is not used (ROLL_DB=0)."
fi

### load connection information for the mysql service
DB_CONTAINER=$(roll env ps -q db)
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service."
fi

eval "$(
    docker container inspect ${DB_CONTAINER} --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^MYSQL_"
)"

eval "MYSQL_HOST=$(docker container inspect ${DB_CONTAINER} --format='{{.Name}}' | cut -c2-)"

query="mariadb+ssh://user@tunnel.roll.test:2222/${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}/${MYSQL_DATABASE}?statusColor=686B6F&enviroment=local&name=${ROLL_ENV_NAME}%20DOCKER&tLSMode=0&usePrivateKey=true&safeModeLevel=0&advancedSafeModeLevel=0"
open "$query" -a "/Applications/TablePlus.app/Contents/MacOS/TablePlus"
