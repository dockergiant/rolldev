#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## status takes any args so --format reaches it, which means flags arrive in "$@" and not ROLL_PARAMS
STATUS_FORMAT="human"
while (( "$#" )); do
    case "$1" in
        -h|--help)
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --format=*)
            STATUS_FORMAT="${1#*=}"
            shift
            ;;
        --format)
            ## shift 2 fails under set -e when --format is the last argument
            STATUS_FORMAT="${2:-}"
            shift
            (( $# )) && shift
            ;;
        *)
            fatal "Unsupported argument $1"
            ;;
    esac
done

if [[ "${STATUS_FORMAT}" != "human" && "${STATUS_FORMAT}" != "json" ]]; then
    fatal "Unsupported --format value '${STATUS_FORMAT}' (expected: human, json)"
fi

assertDockerRunning

## networks.default.name in docker/docker-compose.yml
rollNetworkName="roll"
rollNetworkId=$(docker network ls -q --filter name="^${rollNetworkName}$")

if [[ -z "${rollNetworkId}" && "${STATUS_FORMAT}" != "json" ]]; then
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

jsonProjectNames=()
jsonProjectTypes=()
jsonProjectDirs=()
jsonProjectUrls=()
jsonProjectNetworks=()
jsonProjectContainerCounts=()

messageList=()
if (( ${#projectNetworkList[@]} > 0 )); then
    lastIdx=$(( ${#projectNetworkList[@]} - 1 ))
    lastNetwork="${projectNetworkList[$lastIdx]}"
else
    lastNetwork=""
fi
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
    projectUrl="https://${traefikSubDomain}.${traefikDomain}"

    jsonProjectNames+=("${projectName}")
    jsonProjectTypes+=("${projectType}")
    jsonProjectDirs+=("${projectDir}")
    jsonProjectUrls+=("${projectUrl}")
    jsonProjectNetworks+=("${projectNetwork}")
    jsonProjectContainerCounts+=("${containerCount}")

    messageList+=("    \033[1;35m${projectName}\033[0m a \033[36m${projectType}\033[0m project")
    messageList+=("       Project Directory: \033[33m${projectDir}\033[0m")
    messageList+=("       Project URL: \033[94m${projectUrl}\033[0m")
    messageList+=("       Docker Network: \033[33m${projectNetwork}\033[0m")
    messageList+=("       Containers Running: \033[33m${containerCount}\033[0m")

    [[ "$projectNetwork" != "$lastNetwork" ]] && messageList+=("")
done

jsonServiceNames=()
jsonServiceStates=()

if [[ "${STATUS_FORMAT}" != "json" ]]; then
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
fi

if [[ -n "${rollNetworkId}" ]]; then
    if [[ "${STATUS_FORMAT}" != "json" ]]; then
        echo
        echo -e "RollDev Services (enabled -> running):"
    fi

    portainerEnabled=0
    startpageEnabled=1
    if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
        portainerEnabled=$(grep -m1 '^ROLL_SERVICE_PORTAINER=' "${ROLL_HOME_DIR}/.env" | cut -d '=' -f2- | tr -d '\r') || true
        startpageEnabled=$(grep -m1 '^ROLL_SERVICE_STARTPAGE=' "${ROLL_HOME_DIR}/.env" | cut -d '=' -f2- | tr -d '\r') || true
    fi
    portainerEnabled=${portainerEnabled:-0}
    startpageEnabled=${startpageEnabled:-1}

    services=(traefik dnsmasq mailhog tunnel)
    [[ "${portainerEnabled}" == 1 ]] && services+=(portainer)
    [[ "${startpageEnabled}" == 1 ]] && services+=(startpage)

    if [[ "${STATUS_FORMAT}" != "json" ]]; then
        tableNew
        tableHeader "NAME" "STATE" "STATUS" "PORTS"
    fi
    for svc in "${services[@]}"; do
        name=$(docker ps --filter "name=^${svc}$" --format '{{.Names}}')
        state=$(docker ps --filter "name=^${svc}$" --format '{{.State}}')
        status=$(docker ps --filter "name=^${svc}$" --format '{{.Status}}')
        ports=$(docker ps --filter "name=^${svc}$" --format '{{.Ports}}')

        jsonServiceNames+=("${svc}")
        if [[ -z "${name}" ]]; then
            jsonServiceStates+=("stopped")
            [[ "${STATUS_FORMAT}" != "json" ]] && tableRow "${svc}" "$(tableColor red stopped)" "Exited" "-"
        elif [[ "${state}" == "running" ]]; then
            jsonServiceStates+=("running")
            [[ "${STATUS_FORMAT}" != "json" ]] && tableRow "${name}" "$(tableColor green "${state}")" "${status}" "${ports}"
        else
            jsonServiceStates+=("stopped")
            [[ "${STATUS_FORMAT}" != "json" ]] && tableRow "${name}" "$(tableColor red "${state}")" "${status}" "${ports}"
        fi
    done
    if [[ "${STATUS_FORMAT}" != "json" ]]; then
        tableRender
    fi
fi

if [[ "${STATUS_FORMAT}" == "json" ]]; then
    out="{\"running\":$([[ -n "${rollNetworkId}" ]] && echo true || echo false),\"projects\":["
    i=0
    while [[ $i -lt ${#jsonProjectNames[@]} ]]; do
        (( i > 0 )) && out+=","
        out+="{"
        out+="\"name\":\"$(jsonEscape "${jsonProjectNames[$i]}")\","
        out+="\"type\":\"$(jsonEscape "${jsonProjectTypes[$i]}")\","
        out+="\"dir\":\"$(jsonEscape "${jsonProjectDirs[$i]}")\","
        out+="\"url\":\"$(jsonEscape "${jsonProjectUrls[$i]}")\","
        out+="\"network\":\"$(jsonEscape "${jsonProjectNetworks[$i]}")\","
        out+="\"containers\":${jsonProjectContainerCounts[$i]}"
        out+="}"
        i=$((i + 1))
    done
    out+="],\"services\":["
    i=0
    while [[ $i -lt ${#jsonServiceNames[@]} ]]; do
        (( i > 0 )) && out+=","
        out+="{\"name\":\"$(jsonEscape "${jsonServiceNames[$i]}")\",\"status\":\"${jsonServiceStates[$i]}\"}"
        i=$((i + 1))
    done
    out+="]}"
    printf '%s\n' "${out}"
fi
