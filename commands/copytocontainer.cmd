#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-processes (docker cp, etc.) to bubble up normally
trap '' ERR

## fixowns and fixperms only exist for magento2
function fixCopiedFiles() {
  [[ "${ROLL_ENV_TYPE}" == "magento2" ]] || return 0
  "${ROLL_DIR}/bin/roll" fixowns "$@"
  "${ROLL_DIR}/bin/roll" fixperms "$@"
}

## check flags in "$@" before ROLL_PARAMS: this command takes any args, so --all never reaches ROLL_PARAMS
case "$1" in
  -h|--help)
    source "${ROLL_DIR}/commands/usage.cmd"
    ;;
  --all)
    docker cp "${ROLL_ENV_PATH}/./" "$(roll env ps -q php-fpm)":/var/www/html/
    success "Completed copying all files from host to container."
    fixCopiedFiles
    ;;
  *)
    if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
      source "${ROLL_DIR}/commands/usage.cmd"
    fi
    FILE_OR_FOLDER="${ROLL_PARAMS[0]}"
    ## docker cp <src> <dst>/ puts src inside dst, and does not create a missing dst parent
    CONTAINER_ID="$(roll env ps -q php-fpm)"
    DEST_PARENT="/var/www/html/$(dirname -- "${FILE_OR_FOLDER}")"
    docker exec "${CONTAINER_ID}" mkdir -p -- "${DEST_PARENT}"
    docker cp "${ROLL_ENV_PATH}/${FILE_OR_FOLDER}" "${CONTAINER_ID}":"${DEST_PARENT}"/
    success "Completed copying ${FILE_OR_FOLDER} from host to container."
    fixCopiedFiles "${FILE_OR_FOLDER}"
    ;;
esac
