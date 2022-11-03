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

function loadEnvConfig () {
    local ROLL_ENV_PATH="${1}"
    eval "$(cat "${ROLL_ENV_PATH}/.env.roll" | sed 's/\r$//g' | grep "^ROLL_")"
    eval "$(cat "${ROLL_ENV_PATH}/.env.roll" | sed 's/\r$//g' | grep "^TRAEFIK_")"
    eval "$(cat "${ROLL_ENV_PATH}/.env.roll" | sed 's/\r$//g' | grep "^PHP_")"
    eval "$(cat "${ROLL_ENV_PATH}/.env.roll" | sed 's/\r$//g' | grep "^NGINX_")"

    ROLL_ENV_NAME="${ROLL_ENV_NAME:-}"
    ROLL_ENV_TYPE="${ROLL_ENV_TYPE:-}"
    ROLL_ENV_SUBT=""

    case "${OSTYPE:-undefined}" in
        darwin*)
            ROLL_ENV_SUBT=darwin
        ;;
        linux*)
            ROLL_ENV_SUBT=linux
        ;;
        *)
            fatal "Unsupported OSTYPE '${OSTYPE:-undefined}'"
        ;;
    esac

    assertValidEnvType
}

function renderEnvNetworkName() {
    echo "${ROLL_ENV_NAME}_default" | tr '[:upper:]' '[:lower:]'
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

    for PARTIAL_PATH in \
        "${ROLL_DIR}/environments/includes/${PARTIAL_NAME}.base.yml" \
        "${ROLL_DIR}/environments/includes/${PARTIAL_NAME}.${ROLL_ENV_SUBT}.yml" \
        "${ROLL_DIR}/environments/${ROLL_ENV_TYPE}/${PARTIAL_NAME}.base.yml" \
        "${ROLL_DIR}/environments/${ROLL_ENV_TYPE}/${PARTIAL_NAME}.${ROLL_ENV_SUBT}.yml" \
        "${ROLL_HOME_DIR}/environments/includes/${PARTIAL_NAME}.base.yml" \
        "${ROLL_HOME_DIR}/environments/includes/${PARTIAL_NAME}.${ROLL_ENV_SUBT}.yml" \
        "${ROLL_HOME_DIR}/environments/${ROLL_ENV_TYPE}/${PARTIAL_NAME}.base.yml" \
        "${ROLL_HOME_DIR}/environments/${ROLL_ENV_TYPE}/${PARTIAL_NAME}.${ROLL_ENV_SUBT}.yml"
    do
        if [[ -f "${PARTIAL_PATH}" ]]; then
            DOCKER_COMPOSE_ARGS+=("-f" "${PARTIAL_PATH}")
        fi
    done
}
