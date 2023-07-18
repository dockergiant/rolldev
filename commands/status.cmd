#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

assertDockerRunning

rollNetworkName=$(cat ${ROLL_DIR}/docker/docker-compose.yml | grep -A3 'networks:' | tail -n1 | sed -e 's/[[:blank:]]*name:[[:blank:]]*//g')
rollNetworkId=$(docker network ls -q --filter name="${rollNetworkName}")

if [[ -z "${rollNetworkId}" ]]; then
    echo -e "[\033[33;1m!!\033[0m] \033[31mWarden is not currently running.\033[0m Run \033[36mroll svc up\033[0m to start Warden core services."
fi

OLDIFS="$IFS";
IFS=$'\n'
projectNetworkList=( $(docker network ls --format '{{.Name}}' -q --filter "label=dev.roll.environment.name") )
IFS="$OLDIFS"

messageList=()
for projectNetwork in "${projectNetworkList[@]}"; do
    [[ -z "${projectNetwork}" || "${projectNetwork}" == "${rollNetworkName}" ]] && continue # Skip empty project network names (if any)

    prefix="${projectNetwork%_default}"
    prefixLen="${#prefix}"
    ((prefixLen+=1))
    projectContainers=$(docker network inspect --format '{{ range $k,$v := .Containers }}{{ $nameLen := len $v.Name }}{{ if gt $nameLen '"${prefixLen}"' }}{{ $prefix := slice $v.Name 0 '"${prefixLen}"' }}{{ if eq $prefix "'"${prefix}-"'" }}{{ println $v.Name }}{{end}}{{end}}{{end}}' "${projectNetwork}")
    container=$(echo "$projectContainers" | head -n1)

    [[ -z "${container}" ]] && continue # Project is not running, skip it

    projectDir=$(docker container inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir"}}' "$container")
    projectName=$(cat "${projectDir}/.env.roll" | grep '^ROLL_ENV_NAME=' | sed -e 's/ROLL_ENV_NAME=[[:space:]]*//g' | tr -d -)
    projectType=$(cat "${projectDir}/.env.roll" | grep '^ROLL_ENV_TYPE=' | sed -e 's/ROLL_ENV_TYPE=[[:space:]]*//g' | tr -d -)
    traefikDomain=$(cat "${projectDir}/.env.roll" | grep '^TRAEFIK_DOMAIN=' | sed -e 's/TRAEFIK_DOMAIN=[[:space:]]*//g' | tr -d -)

    messageList+=("    \033[1;35m${projectName}\033[0m a \033[36m${projectType}\033[0m project")
    messageList+=("       Project Directory: \033[33m${projectDir}\033[0m")
    messageList+=("       Project URL: \033[94mhttps://${traefikDomain}\033[0m")

    [[ "$projectNetwork" != "${projectNetworkList[@]: -1:1}" ]] && messageList+=()
done

if [[ "${#messageList[@]}" > 0 ]]; then
    if [[ -z "${rollNetworkId}" ]]; then
        echo -e "Found the following \033[32mrunning\033[0m projects; however, \033[31mWarden core services are currently not running\033[0m:"
    else
        echo -e "Found the following \033[32mrunning\033[0m environments:"
    fi
    for line in "${messageList[@]}"; do
        echo -e "$line"
    done
else
    echo "No running environments found."
fi