#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function locateEnvPath () {
    local ROLL_ENV_PATH="$(pwd -P)"
    while [[ "${ROLL_ENV_PATH}" != "/" ]]; do
        if [[ -f "${ROLL_ENV_PATH}/.env.roll" ]] \
            && grep "^ROLL_ENV_NAME" "${ROLL_ENV_PATH}/.env.roll" >/dev/null \
            && grep "^ROLL_ENV_TYPE" "${ROLL_ENV_PATH}/.env.roll" >/dev/null
        then
            break
        fi
        ROLL_ENV_PATH="$(dirname "${ROLL_ENV_PATH}")"
    done

    if [[ "${ROLL_ENV_PATH}" = "/" ]]; then
        >&2 echo -e "\033[31mEnvironment config could not be found. Please run \"roll env-init\" and try again!\033[0m"
        return 1
    fi

    ## Resolve .env.roll symlink should it exist in project sub-directory allowing sub-stacks to use relative link to parent
    ROLL_ENV_PATH="$(
        cd "$(
            dirname "$(
                (readlink "${ROLL_ENV_PATH}/.env.roll" || echo "${ROLL_ENV_PATH}/.env.roll")
            )"
        )" >/dev/null \
        && pwd
    )"

    echo "${ROLL_ENV_PATH}"
}

# Legacy function - now uses centralized config system
function loadEnvConfig () {
    local ROLL_ENV_PATH="${1}"
    
    # Load new centralized configuration
    if ! loadRollConfig "${ROLL_ENV_PATH}"; then
        return 1
    fi
    
    # Set global environment path for backward compatibility
    export ROLL_ENV_PATH="${ROLL_ENV_PATH}"
    
    return 0
}

function renderEnvNetworkName() {
    echo "${ROLL_ENV_NAME}_default" | tr '[:upper:]' '[:lower:]'
}

function renderEnvType() {
    ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
    loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
    echo "${ROLL_ENV_TYPE:-}"
}

function fetchEnvInitFile () {
    local envInitPath=""

    for ENV_INIT_PATH in \
        "${ROLL_DIR}/environments/${ROLL_ENV_TYPE}/init.env" \
        "${ROLL_HOME_DIR}/environments/${ROLL_ENV_TYPE}/init.env" \
        "${ROLL_ENV_PATH}/.roll/environments/${ROLL_ENV_TYPE}/init.env"
    do
        if [[ -f "${ENV_INIT_PATH}" ]]; then
            envInitPath="${ENV_INIT_PATH}"
        fi
    done

    echo $envInitPath
}

function fetchValidEnvTypes () {
    echo $(
        ls -1 "${ROLL_DIR}/environments/"*/*".base.yml" \
            | sed -E "s#^${ROLL_DIR}/environments/##" \
            | cut -d/ -f1 | sort | grep -v includes | uniq
    )
}

function assertValidEnvType () {
    if [[ ! -f "${ROLL_DIR}/environments/${ROLL_ENV_TYPE}/${ROLL_ENV_TYPE}.base.yml" ]]; then
        >&2 echo -e "\033[31mInvalid environment type \"${ROLL_ENV_TYPE}\" specified.\033[0m"
        return 1
    fi
}

function appendEnvPartialIfExists () {
    local PARTIAL_NAME="${1}"
    local PARTIAL_PATH=""
    local PARTIAL_DIR=""
    local SUFFIX=""

    local PARTIAL_DIRS=(
        "${ROLL_DIR}/environments/includes"
        "${ROLL_DIR}/environments/${ROLL_ENV_TYPE}"
        "${ROLL_HOME_DIR}/environments/includes"
        "${ROLL_HOME_DIR}/environments/${ROLL_ENV_TYPE}"
    )

    ## WSL2 is Linux and needs the .linux.yml fragments too; .wsl.yml comes last so it can override them
    local SUFFIXES=("base" "${ROLL_ENV_SUBT}")
    if [[ "${ROLL_ENV_SUBT}" == "wsl" ]]; then
        SUFFIXES=("base" "linux" "wsl")
    fi

    for PARTIAL_DIR in "${PARTIAL_DIRS[@]}"; do
        for SUFFIX in "${SUFFIXES[@]}"; do
            PARTIAL_PATH="${PARTIAL_DIR}/${PARTIAL_NAME}.${SUFFIX}.yml"
            if [[ -f "${PARTIAL_PATH}" ]]; then
                DOCKER_COMPOSE_ARGS+=("-f" "${PARTIAL_PATH}")
            fi
        done
    done
}
