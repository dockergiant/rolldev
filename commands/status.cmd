#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

assertDockerRunning

rollNetworkName=$(grep -A3 'networks:' "${ROLL_DIR}/docker/docker-compose.yml" | tail -n1 | sed -e 's/[[:blank:]]*name:[[:blank:]]*//g')
rollNetworkId=$(docker network ls -q --filter name="${rollNetworkName}")

if [[ -z "${rollNetworkId}" ]]; then
    echo -e "[\033[33;1m!!\033[0m] \033[31mRollDev is not currently running.\033[0m Run \033[36mroll svc up\033[0m to start RollDev core services."
fi

OLDIFS="$IFS"
IFS=$'\n'
if command -v mapfile >/dev/null 2>&1; then
    mapfile -t projectNetworkList < <(docker network ls --format '{{.Name}}' -q --filter "label=dev.roll.environment.name")
else
    projectNetworkList=()
    while IFS= read -r net; do
        projectNetworkList+=("$net")
    done < <(docker network ls --format '{{.Name}}' -q --filter "label=dev.roll.environment.name")
fi
IFS="$OLDIFS"

messageList=()
lastIdx=$(( ${#projectNetworkList[@]} - 1 ))
lastNetwork="${projectNetworkList[$lastIdx]}"
for projectNetwork in "${projectNetworkList[@]}"; do
    [[ -z "${projectNetwork}" || "${projectNetwork}" == "${rollNetworkName}" ]] && continue # Skip empty project network names (if any)

    prefix="${projectNetwork%_default}"
    prefixLen="${#prefix}"
    ((prefixLen+=1))
    projectContainers=$(docker network inspect --format '{{ range $k,$v := .Containers }}{{ $nameLen := len $v.Name }}{{ if gt $nameLen '"${prefixLen}"' }}{{ $prefix := slice $v.Name 0 '"${prefixLen}"' }}{{ if eq $prefix "'"${prefix}-"'" }}{{ println $v.Name }}{{end}}{{end}}{{end}}' "${projectNetwork}")
    container=$(echo "$projectContainers" | head -n1)

    [[ -z "${container}" ]] && continue # Project is not running, skip it

    projectDir=$(docker container inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir"}}' "$container")
    projectName=$(grep -m1 '^ROLL_ENV_NAME=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    projectType=$(grep -m1 '^ROLL_ENV_TYPE=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    traefikDomain=$(grep -m1 '^TRAEFIK_DOMAIN=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    traefikSubDomain=$(grep -m1 '^TRAEFIK_SUBDOMAIN=' "${projectDir}/.env.roll" | cut -d '=' -f2- | tr -d '\r')
    containerCount=$(echo "$projectContainers" | wc -l | tr -d ' ')

    messageList+=("    \033[1;35m${projectName}\033[0m a \033[36m${projectType}\033[0m project")
    messageList+=("       Project Directory: \033[33m${projectDir}\033[0m")
    messageList+=("       Project URL: \033[94mhttps://${traefikSubDomain}.${traefikDomain}\033[0m")
    messageList+=("       Docker Network: \033[33m${projectNetwork}\033[0m")
    messageList+=("       Containers Running: \033[33m${containerCount}\033[0m")

    [[ "$projectNetwork" != "$lastNetwork" ]] && messageList+=("")
done

if (( ${#messageList[@]} > 0 )); then
    if [[ -z "${rollNetworkId}" ]]; then
        echo -e "Found the following \033[32mrunning\033[0m projects; however, \033[31mRollDev core services are currently not running\033[0m:"
    else
        echo -e "Found the following \033[32mrunning\033[0m environments:"
    fi
    for line in "${messageList[@]}"; do
        echo -e "$line"
    done
else
    echo "No running environments found."
fi

if [[ -n "${rollNetworkId}" ]]; then
    echo
    echo -e "RollDev Services (enabled -> running):"

    portainerEnabled=0
    startpageEnabled=1
    if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
        portainerEnabled=$(grep -m1 '^ROLL_SERVICE_PORTAINER=' "${ROLL_HOME_DIR}/.env" | cut -d '=' -f2- | tr -d '\r')
        startpageEnabled=$(grep -m1 '^ROLL_SERVICE_STARTPAGE=' "${ROLL_HOME_DIR}/.env" | cut -d '=' -f2- | tr -d '\r')
    fi
    portainerEnabled=${portainerEnabled:-0}
    startpageEnabled=${startpageEnabled:-1}

    services=(traefik dnsmasq mailhog tunnel)
    [[ "${portainerEnabled}" == 1 ]] && services+=(portainer)
    [[ "${startpageEnabled}" == 1 ]] && services+=(startpage)

    printf '  %-12s %-10s %-20s %s\n' "NAME" "STATE" "STATUS" "PORTS"
    for svc in "${services[@]}"; do
        name=$(docker ps --filter "name=^${svc}$" --format '{{.Names}}')
        state=$(docker ps --filter "name=^${svc}$" --format '{{.State}}')
        status=$(docker ps --filter "name=^${svc}$" --format '{{.Status}}')
        ports=$(docker ps --filter "name=^${svc}$" --format '{{.Ports}}')
        if [[ -z "${name}" ]]; then
            printf '  %-12s %-10s %-20s -\n' "${svc}" "stopped" "Exited"
        else
            printf '  %-12s %-10s %-20s %s\n' "${name}" "${state}" "${status}" "${ports}"
        fi
    done
fi
