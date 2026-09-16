#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if [[ "${OSTYPE}" != darwin* ]]; then
    error "roll tableplus needs TablePlus, which is macOS-only."
    fatal "On Linux use \`roll db connect\`, or point your own client at the tunnel on localhost:2222."
fi

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${ROLL_DB:-1} -eq 0 ]]; then
    fatal "Database environment is not used (ROLL_DB=0)."
fi

TABLEPLUS_APP=""
for candidate in "/Applications/TablePlus.app" "/Applications/Setapp/TablePlus.app" "${HOME}/Applications/TablePlus.app"; do
    if [[ -d "${candidate}" ]]; then
        TABLEPLUS_APP="${candidate}"
        break
    fi
done

if [[ -z "${TABLEPLUS_APP}" ]]; then
    fatal "TablePlus was not found in /Applications, /Applications/Setapp or ~/Applications."
fi

### load connection information for the mysql service
DB_CONTAINER="$(roll env ps -q db)" || true
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service. Is the environment running?"
fi

eval "$(
    docker container inspect "${DB_CONTAINER}" --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^MYSQL_"
)"

MYSQL_HOST="$(docker container inspect "${DB_CONTAINER}" --format='{{.Name}}' | cut -c2-)"

TABLEPLUS_URI="mariadb+ssh://user@tunnel.roll.test:2222/${MYSQL_USER}:${MYSQL_PASSWORD}@${MYSQL_HOST}/${MYSQL_DATABASE}?statusColor=686B6F&enviroment=local&name=${ROLL_ENV_NAME}%20DOCKER&tLSMode=0&usePrivateKey=true&safeModeLevel=0&advancedSafeModeLevel=0"

openInTablePlus "${TABLEPLUS_URI}"
