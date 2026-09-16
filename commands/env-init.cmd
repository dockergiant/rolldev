#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(pwd -P)"

# Prompt user if there is an extant .env.roll file to ensure they intend to overwrite
if test -f "${ROLL_ENV_PATH}/.env.roll" && [[ "${ROLL_ENV_INIT_FORCE:-0}" == "1" ]]; then
  echo "Overwriting extant .env.roll file"
elif test -f "${ROLL_ENV_PATH}/.env.roll"; then
  while true; do
    ## answers may be piped in, so only running out of input is fatal, not a missing terminal
    if ! read -p $'\033[32mA roll env file already exists at '"${ROLL_ENV_PATH}/.env.roll"$'; would you like to overwrite? y/n\033[0m ' resp; then
      fatal "A roll env file already exists at ${ROLL_ENV_PATH}/.env.roll; set ROLL_ENV_INIT_FORCE=1 to overwrite it without a prompt."
    fi
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
  if ! read -p $'\033[32mAn environment name was not provided; please enter one:\033[0m ' ROLL_ENV_NAME; then
    fatal "An environment name was not provided: roll env-init <project_name> <environment_type>"
  fi
done

# The name becomes the Compose project name; catch an invalid one now rather than on the first env up
while [[ ! "${ROLL_ENV_NAME}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; do
  if [[ ! -t 0 ]]; then
    fatal "Environment name \"${ROLL_ENV_NAME}\" is invalid: it becomes the Docker Compose project name, which must match ^[a-z0-9][a-z0-9_-]*\$ (lowercase letters, digits, hyphens and underscores, starting with a letter or digit)."
  fi
  if ! read -p $'\033[31mInvalid environment name; use lowercase letters, digits, hyphens and underscores, starting with a letter or digit:\033[0m ' ROLL_ENV_NAME; then
    fatal "Environment name is invalid and no new name was entered."
  fi
done

ROLL_ENV_TYPE="${ROLL_PARAMS[1]:-}"

# If roll environment type was not provided, prompt user for it
if [ -z "${ROLL_ENV_TYPE}" ]; then
  while true; do
    if ! read -p $'\033[32mAn environment type was not provided; please choose one of ['"$(fetchValidEnvTypes)"$']:\033[0m ' ROLL_ENV_TYPE; then
      fatal "An environment type was not provided; choose one of: $(fetchValidEnvTypes)"
    fi
    assertValidEnvType && break
  done
fi

# Verify the auto-select and/or type path resolves correctly before setting it
assertValidEnvType || exit $?

## checked before writing anything, so a missing envsubst does not leave a half-written .env.roll
ENV_INIT_FILE=$(fetchEnvInitFile)
if [[ -n $ENV_INIT_FILE ]] && ! command -v envsubst >/dev/null 2>&1; then
  fatal "envsubst is required to create .env.roll (macOS: brew install gettext; Debian/Ubuntu: apt install gettext-base)"
fi

# Write the .env.roll file to current working directory
cat > "${ROLL_ENV_PATH}/.env.roll" <<EOF
ROLL_ENV_NAME=${ROLL_ENV_NAME}
ROLL_ENV_TYPE=${ROLL_ENV_TYPE}
ROLL_WEB_ROOT=/

TRAEFIK_DOMAIN=${ROLL_ENV_NAME}.test
TRAEFIK_SUBDOMAIN=app
EOF

if [[ -n $ENV_INIT_FILE ]]; then
  export ROLL_ENV_NAME
  export GENERATED_APP_KEY="base64:$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64)"
  envsubst '$ROLL_ENV_NAME:$GENERATED_APP_KEY' < "${ENV_INIT_FILE}" >> "${ROLL_ENV_PATH}/.env.roll"
fi