#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# magento1ce-init sets MAGENTO1_DISTRIBUTION=ce before sourcing this script
MAGENTO1_DISTRIBUTION="${MAGENTO1_DISTRIBUTION:-openmage}"
if [[ "${MAGENTO1_DISTRIBUTION}" == "ce" ]]; then
    DISTRIBUTION_LABEL="Magento CE"
    DEFAULT_PACKAGE_VERSION="1.9.4.5"
    PHP_VERSION="7.2"
    DB_DISTRIBUTION_VERSION="10.3"
    REDIS_VERSION="5.0"
    COMPOSER_VERSION="1"
else
    DISTRIBUTION_LABEL="OpenMage LTS"
    DEFAULT_PACKAGE_VERSION="20.x"
    PHP_VERSION="8.4"
    DB_DISTRIBUTION_VERSION="10.11"
    REDIS_VERSION="7.2"
    COMPOSER_VERSION="2"
fi
NODE_VERSION="0"

PROJECT_NAME="${ROLL_PARAMS[0]:-}"
PACKAGE_VERSION="${ROLL_PARAMS[1]:-$DEFAULT_PACKAGE_VERSION}"
TARGET_DIR="${ROLL_PARAMS[2]:-}"

if [[ -z "${PROJECT_NAME}" ]]; then
    error "Project name is required."
    source "${ROLL_DIR}/commands/usage.cmd"
fi

if [[ ! "${PROJECT_NAME}" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
    fatal "Project name should contain only lowercase letters, numbers, and hyphens, and start and end with a letter or number."
fi

if [[ "${MAGENTO1_DISTRIBUTION}" == "ce" ]]; then
    if [[ ! "${PACKAGE_VERSION}" =~ ^1\.9\.4\.[0-5]$ ]]; then
        fatal "Magento CE ${PACKAGE_VERSION} is not supported; use 1.9.4.0 to 1.9.4.5."
    fi
# Composer reads a bare "20" as exactly 20.0.0, so a minor part is required
elif [[ ! "${PACKAGE_VERSION}" =~ ^20\.([0-9]+|x)(\.([0-9]+|x))?$ ]]; then
    fatal "OpenMage ${PACKAGE_VERSION} is not supported; use 20.x."
fi

if [[ -z "${TARGET_DIR}" ]]; then
    TARGET_DIR="$(pwd)/${PROJECT_NAME}"
else
    if [[ "${TARGET_DIR}" != /* ]]; then
        TARGET_DIR="$(pwd)/${TARGET_DIR}"
    fi
    TARGET_DIR="${TARGET_DIR}/${PROJECT_NAME}"
fi

if [[ -d "${TARGET_DIR}" ]]; then
    fatal "Directory ${TARGET_DIR} already exists."
fi

info "Initializing ${DISTRIBUTION_LABEL} ${PACKAGE_VERSION} project ${PROJECT_NAME} in ${TARGET_DIR}"

info "[1/11] Creating project directory..."
mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

info "[2/11] Software versions: PHP ${PHP_VERSION}, MariaDB ${DB_DISTRIBUTION_VERSION}, Redis ${REDIS_VERSION}, Composer ${COMPOSER_VERSION}"

info "[3/11] Initializing environment configuration..."
"${ROLL_DIR}/bin/roll" env-init "${PROJECT_NAME}" magento1

info "[4/11] Updating environment with compatible software versions..."
ENV_FILE="${TARGET_DIR}/.env.roll"

set_env_value() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "${ENV_FILE}"; then
        sed_inplace "s/^${key}=.*/${key}=${value}/" "${ENV_FILE}"
    else
        if [[ -n "$(tail -c 1 "${ENV_FILE}")" ]]; then
            echo >> "${ENV_FILE}"
        fi
        echo "${key}=${value}" >> "${ENV_FILE}"
    fi
    return 0
}

set_env_value PHP_VERSION "${PHP_VERSION}"
set_env_value DB_DISTRIBUTION_VERSION "${DB_DISTRIBUTION_VERSION}"
set_env_value REDIS_VERSION "${REDIS_VERSION}"
set_env_value COMPOSER_VERSION "${COMPOSER_VERSION}"
set_env_value NODE_VERSION "${NODE_VERSION}"

info "[5/11] Signing SSL certificate..."
"${ROLL_DIR}/bin/roll" sign-certificate "${PROJECT_NAME}.test"

info "[6/11] Starting project environment..."
"${ROLL_DIR}/bin/roll" env up

info "[7/11] Waiting for services to be ready..."

wait_for_service() {
    local label="$1"
    local limit="$2"
    local waited=0
    shift 2

    while [[ ${waited} -lt ${limit} ]]; do
        if "$@" >/dev/null 2>&1; then
            success "${label} is ready"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    fatal "${label} is not ready after ${limit} seconds."
}

wait_for_service Database 60 "${ROLL_DIR}/bin/roll" db connect -e "SELECT 1;"
wait_for_service Redis 30 "${ROLL_DIR}/bin/roll" redis ping

info "[8/11] Fetching the ${DISTRIBUTION_LABEL} code..."
if [[ "${MAGENTO1_DISTRIBUTION}" == "ce" ]]; then
    FETCH_COMMAND="curl -fsSL 'https://github.com/OpenMage/magento-mirror/archive/refs/tags/${PACKAGE_VERSION}.tar.gz' -o /tmp/${PROJECT_NAME}.tar.gz
    mkdir -p /tmp/${PROJECT_NAME}
    tar -xzf /tmp/${PROJECT_NAME}.tar.gz -C /tmp/${PROJECT_NAME} --strip-components=1
    rm -f /tmp/${PROJECT_NAME}.tar.gz"
else
    FETCH_COMMAND="composer create-project --no-interaction --no-dev openmage/magento-lts /tmp/${PROJECT_NAME} '${PACKAGE_VERSION}'"
fi

if ! "${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    ${FETCH_COMMAND}
    rsync -a /tmp/${PROJECT_NAME}/ /var/www/html/
    rm -rf /tmp/${PROJECT_NAME}/
    find /var/www/html -type f -exec chmod 644 {} \\;
    find /var/www/html -type d -exec chmod 755 {} \\;
"; then
    fatal "Could not fetch the ${DISTRIBUTION_LABEL} code. Check the output above."
fi

info "[9/11] Installing ${DISTRIBUTION_LABEL}..."

# install.php requests --url itself unless told not to, and app.<name>.test does not resolve to
# Traefik from inside the php-fpm container
if ! "${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    ADMIN_PASS=\"\$(pwgen -n1 16)\"
    php -f install.php -- \\
        --license_agreement_accepted yes \\
        --locale en_US --timezone Europe/Amsterdam --default_currency EUR \\
        --db_host db --db_name magento --db_user magento --db_pass magento \\
        --session_save db \\
        --url 'https://app.${PROJECT_NAME}.test/' --skip_url_validation yes \\
        --use_rewrites yes \\
        --use_secure yes --secure_base_url 'https://app.${PROJECT_NAME}.test/' --use_secure_admin yes \\
        --admin_frontname shopmanager \\
        --admin_firstname Local --admin_lastname Admin --admin_email admin@example.com \\
        --admin_username admin --admin_password \"\${ADMIN_PASS}\"

    cat > /var/www/html/admin-credentials.txt <<EOL
${DISTRIBUTION_LABEL} Admin Credentials
Username: admin
Password: \${ADMIN_PASS}
Admin Panel: https://app.${PROJECT_NAME}.test/shopmanager/
Frontend: https://app.${PROJECT_NAME}.test/
Generated on: \$(date)
EOL
"; then
    fatal "Magento installation failed. Check the install.php output above."
fi

info "[10/11] Configuring the Redis cache..."

# OpenMage enables Cm_RedisSession, which takes over database sessions and defaults to 127.0.0.1;
# Magento CE ships it disabled and ignores the redis_session block
"${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    php -r '
        \$xml = simplexml_load_file(\"app/etc/local.xml\");
        \$cache = \$xml->global->addChild(\"cache\");
        \$cache->addChild(\"backend\", \"Cm_Cache_Backend_Redis\");
        \$options = \$cache->addChild(\"backend_options\");
        \$options->addChild(\"server\", \"redis\");
        \$options->addChild(\"port\", \"6379\");
        \$options->addChild(\"database\", \"0\");
        \$options->addChild(\"compress_data\", \"1\");
        \$session = \$xml->global->addChild(\"redis_session\");
        \$session->addChild(\"host\", \"redis\");
        \$session->addChild(\"port\", \"6379\");
        \$session->addChild(\"db\", \"2\");
        \$xml->asXML(\"app/etc/local.xml\");
    '
    n98-magerun cache:flush
"

info "[11/11] Finished"
boxsuccess "${DISTRIBUTION_LABEL} project ${PROJECT_NAME} is ready" \
    "" \
    "Frontend:    https://app.${PROJECT_NAME}.test/" \
    "Admin:       https://app.${PROJECT_NAME}.test/shopmanager/" \
    "Credentials: ${TARGET_DIR}/admin-credentials.txt" \
    "" \
    "Shell:       cd ${TARGET_DIR} && roll shell" \
    "Destroy:     roll env down -v"
