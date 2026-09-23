#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_ENV_TYPE}" != "magento1" ]]; then
    fatal "This command is only working for Magento 1 projects"
fi

# n98-magerun 2.3.0 lists no users on PHP 8.4 in developer mode, so ask the database
LOCALADMIN_COUNT="$("${ROLL_DIR}/bin/roll" db connect -N -e "SELECT COUNT(*) FROM admin_user WHERE username = 'localadmin'")" \
    || fatal "Could not read the admin users from the database."

if [[ "${LOCALADMIN_COUNT}" != "0" ]]; then
    info "Admin user localadmin already exists"
else
    info "Creating admin user localadmin..."
    if ! "${ROLL_DIR}/bin/roll" magerun --no-interaction admin:user:create \
        localadmin localadmin@roll.test admin123 Local Admin Administrators; then
        fatal "Failed to create admin user localadmin."
    fi
fi

boxsuccess "Admin user localadmin / admin123 is ready" \
    "" \
    "To log in automatically on the admin login page:" \
    "  1. Add ROLL_ADMIN_AUTOLOGIN=1 to .env.roll" \
    "  2. Run roll env up" \
    "  3. Open the admin URL"
