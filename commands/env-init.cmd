#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(pwd -P)"

# Prompt user if there is an extant .env.roll file to ensure they intend to overwrite
if test -f "${ROLL_ENV_PATH}/.env.roll"; then
  while true; do
    read -p $'\033[32mA roll env file already exists at '"${ROLL_ENV_PATH}/.env.roll"$'; would you like to overwrite? y/n\033[0m ' resp
    case $resp in
      [Yy]*) echo "Overwriting extant .env.roll file"; break;;
      [Nn]*) exit;;
      *) echo "Please answer (y)es or (n)o";;
    esac
  done
fi

ROLL_ENV_NAME="${ROLL_PARAMS[0]:-}"

# If roll environment name was not provided, prompt user for it
while [ -z "${ROLL_ENV_NAME}" ]; do
  read -p $'\033[32mAn environment name was not provided; please enter one:\033[0m ' ROLL_ENV_NAME
done

ROLL_ENV_TYPE="${ROLL_PARAMS[1]:-}"

# If roll environment type was not provided, prompt user for it
if [ -z "${ROLL_ENV_TYPE}" ]; then
  while true; do
    read -p $'\033[32mAn environment type was not provided; please choose one of ['"$(fetchValidEnvTypes)"$']:\033[0m ' ROLL_ENV_TYPE
    assertValidEnvType && break
  done
fi

# Verify the auto-select and/or type path resolves correctly before setting it
assertValidEnvType || exit $?

# Write the .env.roll file to current working directory
cat > "${ROLL_ENV_PATH}/.env.roll" <<EOF
ROLL_ENV_NAME=${ROLL_ENV_NAME}
ROLL_ENV_TYPE=${ROLL_ENV_TYPE}
ROLL_WEB_ROOT=/

TRAEFIK_DOMAIN=${ROLL_ENV_NAME}.test
TRAEFIK_SUBDOMAIN=app
EOF

ENV_INIT_FILE=$(fetchEnvInitFile)
if [[ ! -z $ENV_INIT_FILE ]]; then
  export ROLL_ENV_NAME
  export GENERATED_APP_KEY="base64:$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64)"
  envsubst '$ROLL_ENV_NAME:$GENERATED_APP_KEY' < "${ENV_INIT_FILE}" >> "${ROLL_ENV_PATH}/.env.roll"
fi