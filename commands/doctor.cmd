#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## doctor (and env) take any args so --format and --ignore-services reach this file, which means
## flags arrive in "$@"
DOCTOR_FORMAT="human"
DOCTOR_IGNORE_SERVICES=""
doctorArgs=("$@")
i=0
while [[ $i -lt ${#doctorArgs[@]} ]]; do
    case "${doctorArgs[$i]}" in
        -h|--help)
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --format=*)
            DOCTOR_FORMAT="${doctorArgs[$i]#*=}"
            ;;
        --format)
            i=$((i + 1))
            DOCTOR_FORMAT="${doctorArgs[$i]:-}"
            ;;
        --ignore-services=*)
            ## appended, so repeating the flag adds to the list
            DOCTOR_IGNORE_SERVICES="${DOCTOR_IGNORE_SERVICES},${doctorArgs[$i]#*=}"
            ;;
        --ignore-services)
            i=$((i + 1))
            DOCTOR_IGNORE_SERVICES="${DOCTOR_IGNORE_SERVICES},${doctorArgs[$i]:-}"
            ;;
        *)
            fatal "Unsupported argument ${doctorArgs[$i]}"
            ;;
    esac
    i=$((i + 1))
done

if [[ "${DOCTOR_FORMAT}" != "human" && "${DOCTOR_FORMAT}" != "json" ]]; then
    fatal "Unsupported --format value '${DOCTOR_FORMAT}' (expected: human, json)"
fi

DOCTOR_IGNORE_SERVICES="${DOCTOR_IGNORE_SERVICES// /}"

## doctorServiceIgnored <service-name>
function doctorServiceIgnored() {
    local needle="$1"
    ## the list can hold empty elements (leading or trailing commas), which must not match an empty name
    [[ -z "${needle}" ]] && return 1
    [[ -z "${DOCTOR_IGNORE_SERVICES}" ]] && return 1
    case ",${DOCTOR_IGNORE_SERVICES}," in
        *",${needle},"*) return 0 ;;
    esac
    return 1
}

CHECK_NAMES=()
CHECK_OK=()
CHECK_DETAILS=()

## recordCheck <name> <0|1|skip> <detail>
function recordCheck() {
    CHECK_NAMES+=("$1")
    CHECK_OK+=("$2")
    CHECK_DETAILS+=("$3")
    return 0
}

## recordIgnoredCheck <name> <service>
function recordIgnoredCheck() {
    recordCheck "$1" "skip" "Skipped: $2 is in --ignore-services."
    return 0
}

## The result goes into a global: a function returning non-zero at the top level would trip set -e
DOCTOR_ANY_FAILED=0
function renderDoctorReport() {
    DOCTOR_ANY_FAILED=0
    local idx=0
    while [[ $idx -lt ${#CHECK_OK[@]} ]]; do
        [[ "${CHECK_OK[$idx]}" == "0" ]] && DOCTOR_ANY_FAILED=1
        idx=$((idx + 1))
    done

    if [[ "${DOCTOR_FORMAT}" == "json" ]]; then
        local out="{\"checks\":["
        idx=0
        while [[ $idx -lt ${#CHECK_NAMES[@]} ]]; do
            [[ $idx -gt 0 ]] && out+=","
            ## null for a skipped check, so a consumer can tell "passed" from "not looked at"
            local okWord="false"
            [[ "${CHECK_OK[$idx]}" == "1" ]] && okWord="true"
            [[ "${CHECK_OK[$idx]}" == "skip" ]] && okWord="null"
            out+="{\"check\":\"$(jsonEscape "${CHECK_NAMES[$idx]}")\","
            out+="\"ok\":${okWord},"
            out+="\"detail\":\"$(jsonEscape "${CHECK_DETAILS[$idx]}")\"}"
            idx=$((idx + 1))
        done
        out+="],\"ok\":$([[ ${DOCTOR_ANY_FAILED} -eq 0 ]] && echo true || echo false)}"
        printf '%s\n' "${out}"
    else
        local skipped=0
        tableNew
        tableTitle "roll env doctor: ${ROLL_ENV_NAME:-environment}"
        tableHeader "STATUS" "CHECK" "DETAIL"
        idx=0
        while [[ $idx -lt ${#CHECK_NAMES[@]} ]]; do
            case "${CHECK_OK[$idx]}" in
                1) tableRow "$(tableColor green OK)" "${CHECK_NAMES[$idx]}" "${CHECK_DETAILS[$idx]}" ;;
                skip)
                    tableRow "$(tableColor yellow SKIP)" "${CHECK_NAMES[$idx]}" "${CHECK_DETAILS[$idx]}"
                    skipped=$((skipped + 1))
                    ;;
                *) tableRow "$(tableColor red FAIL)" "${CHECK_NAMES[$idx]}" "${CHECK_DETAILS[$idx]}" ;;
            esac
            idx=$((idx + 1))
        done

        local skipNote=""
        [[ ${skipped} -gt 0 ]] && skipNote=" (${skipped} skipped)"

        if [[ ${DOCTOR_ANY_FAILED} -eq 0 ]]; then
            tableSpan "$(tableColor green "All checks passed${skipNote}.")"
        else
            tableSpan "$(tableColor red "One or more checks failed${skipNote}.")"
        fi
        tableRender
    fi

    return 0
}

## A config that fails to load is reported as a check instead of ending the command on a bare error
doctorEnvPathStatus=0
ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)" || doctorEnvPathStatus=$?

if [[ ${doctorEnvPathStatus} -ne 0 || -z "${ROLL_ENV_PATH}" ]]; then
    recordCheck "env-config" 0 "No .env.roll found in this directory or its parents. Run 'roll env-init' first."
    renderDoctorReport
    exit "${DOCTOR_ANY_FAILED}"
fi

doctorLoadConfigStatus=0
loadEnvConfig "${ROLL_ENV_PATH}" || doctorLoadConfigStatus=$?

if [[ ${doctorLoadConfigStatus} -ne 0 ]]; then
    recordCheck "env-config" 0 "Failed to load ${ROLL_ENV_PATH}/.env.roll."
    renderDoctorReport
    exit "${DOCTOR_ANY_FAILED}"
fi

recordCheck "env-config" 1 "Environment '${ROLL_ENV_NAME}' (${ROLL_ENV_TYPE}) loaded from ${ROLL_ENV_PATH}/.env.roll."

if docker system info >/dev/null 2>&1; then
    recordCheck "docker" 1 "Docker daemon is reachable."
else
    recordCheck "docker" 0 "Docker daemon is not reachable. Start Docker and try again."
fi

## Reads the compose healthchecks rather than probing each service again; one docker ps and one
## docker inspect for the whole project
function checkContainerHealth() {
    local containerIds=() containerNames=() containerServices=() containerStates=()
    local cId cName cService cState
    while IFS='|' read -r cId cName cService cState; do
        [[ -z "${cId}" ]] && continue
        containerIds+=("${cId}")
        containerNames+=("${cName}")
        containerServices+=("${cService}")
        containerStates+=("${cState}")
    done < <(docker ps -a \
        --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
        --format '{{.ID}}|{{.Names}}|{{.Label "com.docker.compose.service"}}|{{.State}}' 2>/dev/null)

    if [[ ${#containerIds[@]} -eq 0 ]]; then
        recordCheck "containers" 0 "No containers found for '${ROLL_ENV_NAME}'. Is the environment running ('roll env up')?"
        return 0
    fi

    local healthNames=() healthStatuses=()
    local healthName healthStatus
    while IFS='~' read -r healthName healthStatus; do
        [[ -z "${healthName}" ]] && continue
        healthNames+=("${healthName#/}")
        healthStatuses+=("${healthStatus}")
    done < <(docker inspect \
        --format '{{.Name}}~{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "${containerIds[@]}" 2>/dev/null)

    local idx=0 health=""
    while [[ $idx -lt ${#containerIds[@]} ]]; do
        health=""
        local hIdx=0
        while [[ $hIdx -lt ${#healthNames[@]} ]]; do
            if [[ "${healthNames[$hIdx]}" == "${containerNames[$idx]}" ]]; then
                health="${healthStatuses[$hIdx]}"
                break
            fi
            hIdx=$((hIdx + 1))
        done

        if doctorServiceIgnored "${containerServices[$idx]}"; then
            recordIgnoredCheck "container:${containerServices[$idx]}" "${containerServices[$idx]}"
        elif [[ "${containerStates[$idx]}" != "running" ]]; then
            recordCheck "container:${containerServices[$idx]}" 0 "${containerNames[$idx]} is ${containerStates[$idx]}, not running."
        elif [[ "${health}" == "healthy" ]]; then
            recordCheck "container:${containerServices[$idx]}" 1 "${containerNames[$idx]} is running and healthy."
        elif [[ "${health}" == "none" || -z "${health}" ]]; then
            recordCheck "container:${containerServices[$idx]}" 1 "${containerNames[$idx]} is running (no healthcheck configured)."
        elif [[ "${health}" == "starting" ]]; then
            recordCheck "container:${containerServices[$idx]}" 0 "${containerNames[$idx]} is running but its healthcheck is still starting."
        else
            recordCheck "container:${containerServices[$idx]}" 0 "${containerNames[$idx]} is running but reports health '${health}'."
        fi
        idx=$((idx + 1))
    done
    return 0
}
checkContainerHealth

## Projects publish no ports of their own; they depend on the ports of the global traefik and
## dnsmasq containers. Docker refuses to start those on a taken port, so only probe when they are down.
function checkGlobalPort() {
    local port="$1" proto="$2" containerName="$3" label="$4"

    if doctorServiceIgnored "${containerName}"; then
        recordIgnoredCheck "port-${port}" "${containerName}"
        return 0
    fi

    local state=""
    state="$(docker ps --filter "name=^${containerName}$" --format '{{.State}}' 2>/dev/null)" || true

    if [[ "${state}" == "running" ]]; then
        recordCheck "port-${port}" 1 "${label} (${port}/${proto}) is bound by the running ${containerName} container."
        return 0
    fi

    local occupied=0 probed=0
    if [[ "${proto}" == "tcp" ]]; then
        ## bash opens the connection itself: no lsof needed (Ubuntu lacks it), and unlike lsof without
        ## root it also sees listeners owned by other users
        probed=1
        if (exec 3<>"/dev/tcp/${DOCTOR_LISTEN_ADDRESS}/${port}") 2>/dev/null; then
            occupied=1
        fi
    elif command -v ss >/dev/null 2>&1; then
        probed=1
        if [[ -n "$(ss -Hlun "sport = :${port}" 2>/dev/null)" ]]; then
            occupied=1
        fi
    elif command -v lsof >/dev/null 2>&1; then
        probed=1
        if lsof -nP -iUDP@"${DOCTOR_LISTEN_ADDRESS}":"${port}" >/dev/null 2>&1; then
            occupied=1
        fi
    fi

    if [[ ${probed} -eq 0 ]]; then
        recordCheck "port-${port}" "skip" "${label} (${port}/${proto}) not checked: ${containerName} is not running and neither ss nor lsof is installed."
    elif [[ ${occupied} -eq 1 ]]; then
        recordCheck "port-${port}" 0 "${label} (${port}/${proto}) is occupied by another process and ${containerName} is not running."
    else
        recordCheck "port-${port}" 1 "${label} (${port}/${proto}) is free (${containerName} is not currently running)."
    fi
    return 0
}
## traefik publishes on TRAEFIK_LISTEN; 0.0.0.0 is reachable through the loopback address
DOCTOR_LISTEN_ADDRESS="${TRAEFIK_LISTEN:-127.0.0.1}"
if [[ "${DOCTOR_LISTEN_ADDRESS}" == "0.0.0.0" ]]; then
    DOCTOR_LISTEN_ADDRESS="127.0.0.1"
fi

checkGlobalPort 80 tcp traefik "Traefik HTTP"
checkGlobalPort 443 tcp traefik "Traefik HTTPS"
checkGlobalPort 53 udp dnsmasq "dnsmasq DNS"

if [[ "${ROLL_BROWSERSYNC:-0}" == "1" && "${ROLL_PUBLISH_PORTS:-1}" == "1" ]]; then
    if doctorServiceIgnored "browsersync"; then
        recordIgnoredCheck "port-browsersync" "browsersync"
    else
        ## browsersync.base.yml publishes its ports on php-fpm; there is no browsersync container
        browsersyncContainer="$(docker ps \
            --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
            --filter "label=com.docker.compose.service=php-fpm" \
            --filter "status=running" \
            --format '{{.Names}}' 2>/dev/null | head -n1)" || true
        if [[ -n "${browsersyncContainer}" ]]; then
            recordCheck "port-browsersync" 1 "BrowserSync ports are bound by the running ${browsersyncContainer} container."
        else
            recordCheck "port-browsersync" 1 "BrowserSync is enabled but php-fpm is not running yet; ports are assigned at 'roll env up'."
        fi
    fi
fi

## A green cluster can still refuse writes (disk watermark, read-only index), so a throwaway index
## is written as well. Reached through traefik like every other project URL.
function checkSearchEngine() {
    local engine="$1"

    ## before the probes: each curl can wait 5s for an engine the caller already knows is unreachable
    if doctorServiceIgnored "${engine}"; then
        recordIgnoredCheck "search-engine:${engine}" "${engine}"
        return 0
    fi

    local engineLabel=""
    engineLabel="$(capitalize "${engine}")"
    local baseUrl="https://${engine}.${TRAEFIK_DOMAIN}"
    ## only macOS gets a .test resolver from roll install, so point curl at traefik directly
    local resolve="${engine}.${TRAEFIK_DOMAIN}:443:${DOCTOR_LISTEN_ADDRESS}"

    local health="" status=""
    health="$(curl -sk -m 5 --resolve "${resolve}" "${baseUrl}/_cluster/health" 2>/dev/null)" || true
    status="$(printf '%s' "${health}" | grep -o '"status":"[a-z]*"' | cut -d'"' -f4)" || true

    if [[ -z "${status}" ]]; then
        recordCheck "search-engine:${engine}" 0 "${engineLabel} did not answer at ${baseUrl}/_cluster/health."
        return 0
    fi

    if [[ "${status}" == "red" ]]; then
        recordCheck "search-engine:${engine}" 0 "${engineLabel} cluster health is red at ${baseUrl}."
        return 0
    fi

    recordCheck "search-engine:${engine}" 1 "${engineLabel} cluster health is ${status} at ${baseUrl}."

    ## the PID keeps a leftover index from an interrupted run from failing the PUT
    local probeIndex="roll-doctor-probe-$$"
    local writeCode=""
    writeCode="$(curl -sk -m 5 --resolve "${resolve}" -o /dev/null -w '%{http_code}' -X PUT "${baseUrl}/${probeIndex}" \
        -H 'Content-Type: application/json' -d '{}' 2>/dev/null)" || true

    if [[ "${writeCode}" == "200" || "${writeCode}" == "201" ]]; then
        curl -sk -m 5 --resolve "${resolve}" -o /dev/null -X DELETE "${baseUrl}/${probeIndex}" 2>/dev/null || true
        recordCheck "search-engine-write:${engine}" 1 "${engineLabel} accepted a throwaway index write at ${baseUrl}/${probeIndex}."
    else
        recordCheck "search-engine-write:${engine}" 0 "${engineLabel} rejected a throwaway index write at ${baseUrl}/${probeIndex} (HTTP ${writeCode:-no response})."
    fi
    return 0
}

if [[ "${ROLL_OPENSEARCH:-0}" == "1" ]]; then
    checkSearchEngine "opensearch"
fi
if [[ "${ROLL_ELASTICSEARCH:-0}" == "1" ]]; then
    checkSearchEngine "elasticsearch"
fi
if [[ "${ROLL_OPENSEARCH:-0}" != "1" && "${ROLL_ELASTICSEARCH:-0}" != "1" ]]; then
    recordCheck "search-engine" 1 "No search engine enabled for this environment."
fi

## Under Docker Desktop and OrbStack the data root sits inside a VM, so fall back to df inside a
## running project container, which sees the real backing storage
function checkDiskHeadroom() {
    local dockerRoot="" dockerOs="" dfLine=""
    dockerRoot="$(docker system info --format '{{.DockerRootDir}}' 2>/dev/null)" || true
    dockerOs="$(docker system info --format '{{.OperatingSystem}}' 2>/dev/null)" || true

    ## a host directory with that path under Docker Desktop (WSL) is a leftover, not the VM disk
    if [[ "${dockerOs}" == *"Docker Desktop"* || "${dockerOs}" == *"OrbStack"* ]]; then
        dockerRoot=""
    fi

    if [[ -n "${dockerRoot}" && -d "${dockerRoot}" ]]; then
        dfLine="$(df -Pk "${dockerRoot}" 2>/dev/null | tail -n1)"
    fi

    if [[ -z "${dfLine}" ]]; then
        local probeContainer=""
        probeContainer="$(docker ps \
            --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" \
            --filter "status=running" \
            --format '{{.Names}}' 2>/dev/null | head -n1)"
        if [[ -n "${probeContainer}" ]]; then
            dfLine="$(docker exec "${probeContainer}" df -Pk / 2>/dev/null | tail -n1)"
        fi
    fi

    if [[ -z "${dfLine}" ]]; then
        recordCheck "disk" 0 "Could not determine Docker data root disk usage (no running container to probe and the Docker data root is not reachable from the host)."
        return 0
    fi

    local availKb="" usePercent="" availGb="" minGb=5
    availKb="$(echo "${dfLine}" | awk '{print $4}')"
    usePercent="$(echo "${dfLine}" | awk '{print $5}')"
    availGb=$(( ${availKb:-0} / 1024 / 1024 ))

    if [[ ${availGb} -lt ${minGb} ]]; then
        recordCheck "disk" 0 "Only ${availGb}GB free on the Docker data root (${usePercent} used) - below the ${minGb}GB minimum."
    else
        recordCheck "disk" 1 "${availGb}GB free on the Docker data root (${usePercent} used)."
    fi
    return 0
}
checkDiskHeadroom

renderDoctorReport
exit "${DOCTOR_ANY_FAILED}"
