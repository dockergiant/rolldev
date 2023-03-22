#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?

if (( ${#ROLL_PARAMS[@]} == 0 )); then
  fatal "This command has required params; use --help for details."
fi

## disable sync command on non-darwin environments where it should not be used
if [[ ${ROLL_ENV_SUBT} != "darwin" ]]; then
  fatal "Mutagen sync sessions are not used on \"${ROLL_ENV_SUBT}\" host environments."
fi

## attempt to install mutagen if not already present
if ! which mutagen >/dev/null; then
  echo -e "\033[33mMutagen could not be found; attempting install via brew.\033[0m"
  brew install havoc-io/mutagen/mutagen
fi

## verify mutagen version constraint
MUTAGEN_VERSION=$(mutagen version 2>/dev/null) || true
MUTAGEN_REQUIRE=0.11.8
if [[ $OSTYPE =~ ^darwin ]] && ! test $(version ${MUTAGEN_VERSION}) -ge $(version ${MUTAGEN_REQUIRE}); then
  error "Mutagen version ${MUTAGEN_REQUIRE} or greater is required (version ${MUTAGEN_VERSION} is installed)."
  >&2 printf "\nPlease update Mutagen:\n\n  brew upgrade havoc-io/mutagen/mutagen\n\n"
  exit 1
fi

if [[ $OSTYPE =~ ^darwin && -z "${MUTAGEN_SYNC_FILE}" ]]; then
    export MUTAGEN_SYNC_FILE="${ROLL_DIR}/environments/${ROLL_ENV_TYPE}/${ROLL_ENV_TYPE}.mutagen.yml"

    if [[ -f "${ROLL_ENV_PATH}/.roll/mutagen.yml" ]]; then
        export MUTAGEN_SYNC_FILE="${ROLL_ENV_PATH}/.roll/mutagen.yml"
    fi
fi

## if no mutagen configuration file exists for the environment type, exit with error
if [[ ! -f "${MUTAGEN_SYNC_FILE}" ]]; then
  fatal "Mutagen configuration does not exist for environment type \"${ROLL_ENV_TYPE}\""
fi

## sub-command execution
case "${ROLL_PARAMS[0]}" in
    start)
        ## terminate any existing sessions with matching env label
        mutagen sync terminate --label-selector "roll-sync=${ROLL_ENV_NAME}"

        ## create sync session based on environment type configuration
        mutagen sync create -c "${MUTAGEN_SYNC_FILE}" --default-owner-beta="www-data" --default-group-beta="www-data" \
            --label "roll-sync=${ROLL_ENV_NAME}" --ignore "${ROLL_SYNC_IGNORE:-}" \
            "${ROLL_ENV_PATH}${ROLL_WEB_ROOT:-}" "docker://$(roll env ps -q php-fpm)/var/www/html"

        ## wait for sync session to complete initial sync before exiting
        echo "Waiting for initial synchronization to complete"
        while ! mutagen sync list --label-selector "roll-sync=${ROLL_ENV_NAME}" \
            | grep -i 'watching for changes'>/dev/null;
                do
                		info=$(mutagen sync list --label-selector "roll-sync=${ROLL_ENV_NAME}")
                    if echo "$info" \
                        | grep -i 'Last error' > /dev/null; then
                        MUTAGEN_ERROR=$(echo "$info" \
                            | sed -n 's/Last error: \(.*\)/\1/p')
                        fatal "Mutagen encountered an error during sync: ${MUTAGEN_ERROR}"
                    fi
                    genstatus=$(echo "$info" | grep "Status") || echo ""
                    progress=$(echo "$info" | grep "Staging progress" |  sed 's/%/%%/') || progress="Done syncing"
                    printf "\r\033[K[\033[0;31m${genstatus}\033[0m] ${progress}"; sleep 1; done;
        printf "\r\033[K[\033[0;31mDone syncing\033[0m]\n\n"
        ;;
    stop)
        mutagen sync terminate --label-selector "roll-sync=${ROLL_ENV_NAME}"
        ;;
    list|flush|monitor|pause|reset|resume)
        mutagen sync "${ROLL_PARAMS[@]}" "${@}" --label-selector "roll-sync=${ROLL_ENV_NAME}"
        ;;
    *)
        fatal "The command \"${ROLL_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
