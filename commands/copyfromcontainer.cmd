#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-processes (docker cp, etc.) to bubble up normally
trap '' ERR

case "$1" in
  -h|--help)
    source "${ROLL_DIR}/commands/usage.cmd"
    ;;
  --all)
    docker cp "$(roll env ps -q php-fpm)":/var/www/html/./ "${ROLL_ENV_PATH}/"
    success "Completed copying all files from container to host."
    ;;
  --cachegrind)
    CACHEGRIND_FILE="${2:-}"
    if [[ -z "${CACHEGRIND_FILE}" ]]; then
      if ! isInteractive; then
        fatalNoTty "a cachegrind file" "roll copyfromcontainer --cachegrind <file>"
      fi
      CACHEGRIND_FILES=()
      while IFS= read -r line; do
        [[ -n "${line}" ]] && CACHEGRIND_FILES+=("${line}")
      done < <(docker exec "$(roll env ps -q php-debug)" ls /tmp | grep cachegrind)
      (( ${#CACHEGRIND_FILES[@]} == 0 )) && fatal "No cachegrind files found in /tmp inside php-debug."
      promptChoose CACHEGRIND_FILE "roll copyfromcontainer --cachegrind <file>" "Select a cachegrind file to copy to host:" "${CACHEGRIND_FILES[@]}"
    fi
    mkdir -p "${ROLL_ENV_PATH}/tmp/profiles"
    docker cp "$(roll env ps -q php-debug)":/tmp/"${CACHEGRIND_FILE}" "${ROLL_ENV_PATH}/tmp/profiles/"
    success "Completed copying /tmp/${CACHEGRIND_FILE} from container to host tmp/profiles folder."
    ;;
  --traces)
    TRACE_FILE="${2:-}"
    if [[ -z "${TRACE_FILE}" ]]; then
      if ! isInteractive; then
        fatalNoTty "a trace file" "roll copyfromcontainer --traces <file>"
      fi
      TRACE_FILES=()
      while IFS= read -r line; do
        [[ -n "${line}" ]] && TRACE_FILES+=("${line}")
      done < <(docker exec "$(roll env ps -q php-debug)" ls /tmp | grep trace)
      (( ${#TRACE_FILES[@]} == 0 )) && fatal "No trace files found in /tmp inside php-debug."
      promptChoose TRACE_FILE "roll copyfromcontainer --traces <file>" "Select a trace file to copy to host:" "${TRACE_FILES[@]}"
    fi
    mkdir -p "${ROLL_ENV_PATH}/tmp/traces"
    docker cp "$(roll env ps -q php-debug)":/tmp/"${TRACE_FILE}" "${ROLL_ENV_PATH}/tmp/traces/"
    success "Completed copying /tmp/${TRACE_FILE} from container to host tmp/traces folder."
    ;;
  --realpath)
    REALPATH_FILE="${2:-}"
    [[ -z "${REALPATH_FILE}" ]] && fatal "roll copyfromcontainer --realpath requires a file path."
    ## the path only exists inside the container, so it lands flat in the project tmp folder
    mkdir -p "${ROLL_ENV_PATH}/tmp"
    docker cp "$(roll env ps -q php-fpm)":"${REALPATH_FILE}" "${ROLL_ENV_PATH}/tmp/"
    success "Completed copying ${REALPATH_FILE} from container to host tmp folder: ${ROLL_ENV_PATH}/tmp/$(basename -- "${REALPATH_FILE}")"
    ;;
  *)
    if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
      source "${ROLL_DIR}/commands/usage.cmd"
    fi
    FILE_OR_FOLDER="${ROLL_PARAMS[0]}"
    if [[ -f "${FILE_OR_FOLDER}" ]]; then
      docker cp "$(roll env ps -q php-fpm)":/var/www/html/"${FILE_OR_FOLDER}" "${ROLL_ENV_PATH}/${FILE_OR_FOLDER}"
    else
      docker cp "$(roll env ps -q php-fpm)":/var/www/html/"${FILE_OR_FOLDER}" "${ROLL_ENV_PATH}/$(dirname -- "${FILE_OR_FOLDER}")"
    fi
    success "Completed copying ${FILE_OR_FOLDER} from container to host."
    ;;
esac
