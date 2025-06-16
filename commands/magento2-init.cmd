#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Default Magento version (minimum supported: 2.4.6)
DEFAULT_MAGENTO_VERSION="2.4.x"

# Extract parameters
PROJECT_NAME="${ROLL_PARAMS[0]:-}"
MAGENTO_VERSION="${ROLL_PARAMS[1]:-$DEFAULT_MAGENTO_VERSION}"
TARGET_DIR="${ROLL_PARAMS[2]:-}"

# Function to display usage information
show_usage() {
    echo -e "\033[33mUsage:\033[0m"
    echo "  roll magento2-init <project_name> [magento_version] [target_directory]"
    echo ""
    echo -e "\033[33mArguments:\033[0m"
    echo "  project_name       Name of the Magento 2 project"
    echo "  magento_version    Magento version to install (default: 2.4.x)"
    echo "                     Supports: 2.4.6+, 2.4.7, 2.4.7-p3, 2.4.8, etc."
    echo "                     Minimum supported version: 2.4.6"
    echo "  target_directory   Directory to create project in (default: current directory)"
    echo ""
    echo -e "\033[33mExamples:\033[0m"
    echo "  roll magento2-init myproject"
    echo "  roll magento2-init myproject 2.4.7"
    echo "  roll magento2-init myproject 2.4.7-p3"
    echo "  roll magento2-init myproject 2.4.8"
    echo "  roll magento2-init myproject 2.4.x ~/Sites/myproject"
    exit 1
}

# Validate project name
if [ -z "${PROJECT_NAME}" ]; then
    echo -e "\033[31mError: Project name is required.\033[0m"
    show_usage
fi

# Validate project name format
if [[ ! "${PROJECT_NAME}" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$ ]]; then
    echo -e "\033[31mError: Project name should contain only lowercase letters, numbers, and hyphens.\033[0m"
    echo -e "\033[31mIt should start and end with a letter or number.\033[0m"
    exit 1
fi

# Validate Magento version format and minimum version (2.4.6+)
if [[ ! "${MAGENTO_VERSION}" =~ ^2\.4(\.[6-9x]+)?(-p[0-9]+)?$ ]] && [[ ! "${MAGENTO_VERSION}" =~ ^2\.[5-9](\.[0-9x]+)?(-p[0-9]+)?$ ]]; then
    echo -e "\033[31mError: Invalid Magento version format.\033[0m"
    echo -e "\033[31mSupported formats: 2.4.6+, 2.4.7, 2.4.7-p3, 2.4.8, etc.\033[0m"
    exit 1
fi

# Check minimum version requirement (2.4.6+)
if [[ "${MAGENTO_VERSION}" =~ ^2\.4\.([0-5])($|-p) ]]; then
    echo -e "\033[31mError: Magento version ${MAGENTO_VERSION} is not supported.\033[0m"
    echo -e "\033[31mMinimum supported version is 2.4.6\033[0m"
    echo -e "\033[33mFor older Magento versions, please use manual installation or upgrade to 2.4.6+\033[0m"
    exit 1
fi

# Function to get compatible software versions based on Magento version (2.4.6+ only)
get_software_versions() {
    local magento_version="$1"
    local base_version
    local patch_version=""
    
    # Extract base version and patch version
    if [[ "${magento_version}" =~ ^([0-9]+\.[0-9]+\.[0-9x]+)(-p([0-9]+))?$ ]]; then
        base_version="${BASH_REMATCH[1]}"
        patch_version="${BASH_REMATCH[3]:-0}"
    else
        base_version="${magento_version}"
        patch_version="0"
    fi
    
    # Set default values for 2.4.6+
    PHP_VERSION="8.2"
    DB_DISTRIBUTION_VERSION="10.6"
    ELASTICSEARCH_VERSION="7.17"
    REDIS_VERSION="7.0"
    RABBITMQ_VERSION="3.9"
    VARNISH_VERSION="7.1"
    COMPOSER_VERSION="2"
    NODE_VERSION="19"
    
    # Version mapping based on Magento compatibility matrix (2.4.6+ only)
    case "${base_version}" in
        "2.4.9"*)
            PHP_VERSION="8.4"
            DB_DISTRIBUTION_VERSION="11.4"
            ELASTICSEARCH_VERSION="2.19"  # OpenSearch
            REDIS_VERSION="8.0"
            RABBITMQ_VERSION="4.1"
            VARNISH_VERSION="7.7"
            COMPOSER_VERSION="2"
            ;;
        "2.4.8"*)
            PHP_VERSION="8.3"
            DB_DISTRIBUTION_VERSION="11.4"
            ELASTICSEARCH_VERSION="2.19"  # OpenSearch
            REDIS_VERSION="8.0"
            RABBITMQ_VERSION="4.1"
            VARNISH_VERSION="7.7"
            COMPOSER_VERSION="2"
            ;;
        "2.4.7"*)
            PHP_VERSION="8.3"
            if [[ "${patch_version}" -ge 6 ]]; then
                DB_DISTRIBUTION_VERSION="10.11"
                REDIS_VERSION="7.2"
                VARNISH_VERSION="7.7"
                COMPOSER_VERSION="2"
            elif [[ "${patch_version}" -ge 3 ]]; then
                DB_DISTRIBUTION_VERSION="10.6"
                REDIS_VERSION="7.2"
                VARNISH_VERSION="7.5"
                COMPOSER_VERSION="2"
            else
                DB_DISTRIBUTION_VERSION="10.6"
                REDIS_VERSION="7.2"
                VARNISH_VERSION="7.5"
                COMPOSER_VERSION="2"
            fi
            ELASTICSEARCH_VERSION="7.17"
            RABBITMQ_VERSION="3.13"
            ;;
        "2.4.6"*)
            PHP_VERSION="8.2"
            DB_DISTRIBUTION_VERSION="10.6"
            ELASTICSEARCH_VERSION="7.17"
            REDIS_VERSION="7.0"
            RABBITMQ_VERSION="3.9"
            VARNISH_VERSION="7.1"
            COMPOSER_VERSION="2"
            if [[ "${patch_version}" -ge 8 ]]; then
                REDIS_VERSION="7.2"
                VARNISH_VERSION="7.5"
            fi
            ;;
        "2.4.x"|"2.4"*)
            # Default to latest stable versions for 2.4.x
            PHP_VERSION="8.3"
            DB_DISTRIBUTION_VERSION="10.6"
            ELASTICSEARCH_VERSION="7.17"
            REDIS_VERSION="7.2"
            RABBITMQ_VERSION="3.13"
            VARNISH_VERSION="7.5"
            COMPOSER_VERSION="2"
            ;;
    esac
    
    echo -e "\033[33mConfigured software versions for Magento ${magento_version}:\033[0m"
    echo -e "  PHP: ${PHP_VERSION}"
    echo -e "  MariaDB: ${DB_DISTRIBUTION_VERSION}"
    if [[ "${ELASTICSEARCH_VERSION}" == "2."* ]]; then
        echo -e "  Search Engine: OpenSearch ${ELASTICSEARCH_VERSION}"
    else
        echo -e "  Search Engine: Elasticsearch ${ELASTICSEARCH_VERSION}"
    fi
    echo -e "  Redis: ${REDIS_VERSION}"
    echo -e "  RabbitMQ: ${RABBITMQ_VERSION}"
    echo -e "  Varnish: ${VARNISH_VERSION}"
    echo -e "  Composer: ${COMPOSER_VERSION}"
    echo -e "  Node.js: ${NODE_VERSION}"
}

# Set target directory
if [ -z "${TARGET_DIR}" ]; then
    TARGET_DIR="$(pwd)/${PROJECT_NAME}"
else
    # Handle relative paths and ensure absolute path
    if [[ "${TARGET_DIR}" != /* ]]; then
        TARGET_DIR="$(pwd)/${TARGET_DIR}"
    fi
    TARGET_DIR="${TARGET_DIR}/${PROJECT_NAME}"
fi

echo -e "\033[32mInitializing Magento 2 project: ${PROJECT_NAME}\033[0m"
echo -e "\033[32mMagento version: ${MAGENTO_VERSION}\033[0m"
echo -e "\033[32mTarget directory: ${TARGET_DIR}\033[0m"

# Check if target directory already exists
if [ -d "${TARGET_DIR}" ]; then
    echo -e "\033[31mError: Directory ${TARGET_DIR} already exists.\033[0m"
    exit 1
fi

# Create project directory
echo -e "\033[36m[1/10] Creating project directory...\033[0m"
mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

# Get compatible software versions for this Magento version
echo -e "\033[36m[2/10] Determining compatible software versions...\033[0m"
get_software_versions "${MAGENTO_VERSION}"

# Initialize environment
echo -e "\033[36m[3/10] Initializing environment configuration...\033[0m"
"${ROLL_DIR}/bin/roll" env-init "${PROJECT_NAME}" magento2

# Update .env.roll with version-specific software versions
echo -e "\033[36m[4/10] Updating environment with compatible software versions...\033[0m"
ENV_FILE="${TARGET_DIR}/.env.roll"

# Update software versions in .env.roll file
sed -i.bak "s/^PHP_VERSION=.*/PHP_VERSION=${PHP_VERSION}/" "${ENV_FILE}"
sed -i.bak "s/^DB_DISTRIBUTION_VERSION=.*/DB_DISTRIBUTION_VERSION=${DB_DISTRIBUTION_VERSION}/" "${ENV_FILE}"
sed -i.bak "s/^COMPOSER_VERSION=.*/COMPOSER_VERSION=${COMPOSER_VERSION}/" "${ENV_FILE}"
sed -i.bak "s/^NODE_VERSION=.*/NODE_VERSION=${NODE_VERSION}/" "${ENV_FILE}"
sed -i.bak "s/^RABBITMQ_VERSION=.*/RABBITMQ_VERSION=${RABBITMQ_VERSION}/" "${ENV_FILE}"
sed -i.bak "s/^VARNISH_VERSION=.*/VARNISH_VERSION=${VARNISH_VERSION}/" "${ENV_FILE}"

# Handle search engine configuration (OpenSearch vs Elasticsearch)
if [[ "${ELASTICSEARCH_VERSION}" == "2."* ]]; then
    # Use OpenSearch for newer Magento versions (2.4.8+)
    OPENSEARCH_VERSION="${ELASTICSEARCH_VERSION}"
    sed -i.bak "s/^ROLL_ELASTICSEARCH=.*/ROLL_ELASTICSEARCH=0/" "${ENV_FILE}"
    sed -i.bak "s/^ROLL_OPENSEARCH=.*/ROLL_OPENSEARCH=1/" "${ENV_FILE}"
    # Replace ELASTICSEARCH_VERSION with OPENSEARCH_VERSION
    sed -i.bak "s/^ELASTICSEARCH_VERSION=.*/OPENSEARCH_VERSION=${OPENSEARCH_VERSION}/" "${ENV_FILE}"
    # Set actual search engine version for configuration
    ELASTICSEARCH_VERSION="7.17"  # Fallback version for installation compatibility
    echo -e "  OpenSearch: ${OPENSEARCH_VERSION} (primary)"
    echo -e "  Elasticsearch: ${ELASTICSEARCH_VERSION} (fallback)"
else
    # Use Elasticsearch for older versions
    sed -i.bak "s/^ROLL_ELASTICSEARCH=.*/ROLL_ELASTICSEARCH=1/" "${ENV_FILE}"
    sed -i.bak "s/^ROLL_OPENSEARCH=.*/ROLL_OPENSEARCH=0/" "${ENV_FILE}"
    sed -i.bak "s/^ELASTICSEARCH_VERSION=.*/ELASTICSEARCH_VERSION=${ELASTICSEARCH_VERSION}/" "${ENV_FILE}"
    # Ensure OpenSearch version is not present
    if grep -q "^OPENSEARCH_VERSION=" "${ENV_FILE}"; then
        sed -i.bak "/^OPENSEARCH_VERSION=/d" "${ENV_FILE}"
    fi
fi

# Handle Redis configuration (always use Redis for Magento 2)
# Magento 2 works best with traditional Redis, so we always use Redis regardless of version
    sed -i.bak "s/^ROLL_REDIS=.*/ROLL_REDIS=1/" "${ENV_FILE}"
    sed -i.bak "s/^ROLL_DRAGONFLY=.*/ROLL_DRAGONFLY=0/" "${ENV_FILE}"
    sed -i.bak "s/^REDIS_VERSION=.*/REDIS_VERSION=${REDIS_VERSION}/" "${ENV_FILE}"
# Ensure Dragonfly version is not present
if grep -q "^DRAGONFLY_VERSION=" "${ENV_FILE}"; then
    sed -i.bak "/^DRAGONFLY_VERSION=/d" "${ENV_FILE}"
fi

# Clean up backup file
rm -f "${ENV_FILE}.bak"

# Sign SSL certificate
echo -e "\033[36m[5/10] Signing SSL certificate...\033[0m"
"${ROLL_DIR}/bin/roll" sign-certificate "${PROJECT_NAME}.test"

# Start environment
echo -e "\033[36m[6/10] Starting project environment...\033[0m"
"${ROLL_DIR}/bin/roll" env up

# Wait for services to be ready
echo -e "\033[36m[7/10] Waiting for services to be ready...\033[0m"
echo -e "\033[33mChecking service status...\033[0m"

# Wait for database to be ready
echo -n "Waiting for database... "
timeout=60
while [ $timeout -gt 0 ]; do
    if "${ROLL_DIR}/bin/roll" db connect -e "SELECT 1;" >/dev/null 2>&1; then
        echo "✅ Ready"
        break
    fi
    echo -n "."
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Database not ready after 60 seconds"
    exit 1
fi

# Wait for search engine to be ready
echo -n "Waiting for search engine... "
timeout=60
SEARCH_HOST="elasticsearch"
SEARCH_PORT="9200"

# Determine search engine host based on configuration
# Check environment variables to see which service is actually enabled
if grep -q "^ROLL_OPENSEARCH=1" "${ENV_FILE}" 2>/dev/null; then
    SEARCH_HOST="opensearch"
    echo -n "(OpenSearch) "
else
    echo -n "(Elasticsearch) "
fi

while [ $timeout -gt 0 ]; do
    if "${ROLL_DIR}/bin/roll" cli bash -c "timeout 5 bash -c '</dev/tcp/${SEARCH_HOST}/${SEARCH_PORT}'" 2>/dev/null; then
        # Double check with HTTP request if port is open
        if "${ROLL_DIR}/bin/roll" cli curl -f -s "http://${SEARCH_HOST}:${SEARCH_PORT}/_cluster/health" >/dev/null 2>&1; then
            echo "✅ Ready"
            break
        fi
    fi
    echo -n "."
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Search engine not ready after 60 seconds"
    echo "Debug: Checking ${SEARCH_HOST}:${SEARCH_PORT}"
    "${ROLL_DIR}/bin/roll" cli bash -c "timeout 5 bash -c '</dev/tcp/${SEARCH_HOST}/${SEARCH_PORT}'" 2>&1 || echo "Port not accessible"
    echo "Tip: Make sure ${SEARCH_HOST} service is running with 'roll env up'"
    exit 1
fi

# Wait for Redis to be ready
echo -n "Waiting for Redis... "
timeout=30
while [ $timeout -gt 0 ]; do
    if "${ROLL_DIR}/bin/roll" redis ping 2>/dev/null | grep -q PONG; then
        echo "✅ Ready"
        break
    fi
    echo -n "."
    sleep 2
    timeout=$((timeout-2))
done

if [ $timeout -le 0 ]; then
    echo "❌ Redis not ready after 30 seconds"
    exit 1
fi

echo -e "\033[32m✅ All services are ready!\033[0m"

# Drop into shell for setup
echo -e "\033[36m[8/12] Setting up Magento project files...\033[0m"

# Check if composer global auth is configured
echo -e "\033[33mNote: This process requires Magento Marketplace credentials.\033[0m"
echo -e "\033[33mIf you haven't configured them globally, you'll be prompted during composer install.\033[0m"

# Meta package for Magento 2.4.6+
META_PACKAGE="magento/project-community-edition"

# Create project using composer inside container
"${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    
    echo 'Creating Magento project with composer...'
    composer create-project --repository-url=https://repo.magento.com/ \\
        '${META_PACKAGE}' /tmp/${PROJECT_NAME} '${MAGENTO_VERSION}'
    
    echo 'Moving files to web root...'
    rsync -a /tmp/${PROJECT_NAME}/ /var/www/html/
    rm -rf /tmp/${PROJECT_NAME}/
    
    echo 'Setting proper file permissions...'
    find /var/www/html -type f -exec chmod 644 {} \\;
    find /var/www/html -type d -exec chmod 755 {} \\;
    chmod u+x /var/www/html/bin/magento
"

# Apply Magento 2.4.4 patch for ReflectionUnionType::getName() error
if [[ "${MAGENTO_VERSION}" == "2.4.4"* ]]; then
    echo -e "\033[36m[8.5/12] Applying Magento 2.4.4 patches...\033[0m"
    echo -e "\033[33m🔧 Detected Magento 2.4.4 - applying ACSD-59280 patch for ReflectionUnionType issue\033[0m"
    
    "${ROLL_DIR}/bin/roll" cli bash -c "
        set -e
        
        echo 'Installing Quality Patches Tool...'
        if ! composer show magento/quality-patches >/dev/null 2>&1; then
            composer require magento/quality-patches --no-update
            composer update magento/quality-patches --no-dev
        fi
        
        echo 'Checking available patches...'
        if vendor/bin/magento-patches status | grep -q 'ACSD-59280'; then
            echo 'Applying ACSD-59280 patch for ReflectionUnionType issue...'
            vendor/bin/magento-patches apply ACSD-59280 || echo 'Patch may already be applied or not needed'
        else
            echo 'ACSD-59280 patch not found, may not be needed for this version'
        fi
        
        echo 'Clearing generated code after patching...'
        rm -rf generated/metadata generated/code var/generation
    "
    
    echo -e "\033[32m✅ Magento 2.4.4 patches applied successfully\033[0m"
fi

echo -e "\033[36m[9/12] Installing Magento application...\033[0m"

# Determine search engine parameters based on version (2.4.6+ only)
echo -e "\033[33mConfiguring search engine parameters...\033[0m"

# Determine search engine type based on environment configuration
if grep -q "^ROLL_OPENSEARCH=1" "${ENV_FILE}" 2>/dev/null; then
    # OpenSearch configuration for Magento 2.4.8+
    OPENSEARCH_VER=$(grep "^OPENSEARCH_VERSION=" "${ENV_FILE}" | cut -d'=' -f2 || echo "2.19")
    SEARCH_ENGINE_PARAMS="
        --search-engine=opensearch \\
        --opensearch-host=opensearch \\
        --opensearch-port=9200 \\
        --opensearch-index-prefix=magento2 \\
        --opensearch-enable-auth=0 \\
        --opensearch-timeout=15"
    echo -e "\033[33mUsing OpenSearch ${OPENSEARCH_VER} for Magento 2.4.8+\033[0m"
else
    # Elasticsearch configuration for Magento 2.4.6-2.4.7
    SEARCH_ENGINE_PARAMS="
        --search-engine=elasticsearch7 \\
        --elasticsearch-host=elasticsearch \\
        --elasticsearch-port=9200 \\
        --elasticsearch-index-prefix=magento2 \\
        --elasticsearch-enable-auth=0 \\
        --elasticsearch-timeout=15"
    echo -e "\033[33mUsing Elasticsearch ${ELASTICSEARCH_VERSION}\033[0m"
fi

# Debug: Show search engine parameters
echo -e "\033[33mSearch engine parameters:\033[0m"
echo "${SEARCH_ENGINE_PARAMS}"

# Install Magento with fallback mechanism
echo -e "\033[33mAttempting Magento installation with configured search engine...\033[0m"

# Build the installation command based on search engine type
if grep -q "^ROLL_OPENSEARCH=1" "${ENV_FILE}" 2>/dev/null; then
    # OpenSearch installation command
    INSTALL_COMMAND="bin/magento setup:install \\
            --backend-frontname=shopmanager \\
            --amqp-host=rabbitmq \\
            --amqp-port=5672 \\
            --amqp-user=guest \\
            --amqp-password=guest \\
            --db-host=db \\
            --db-name=magento \\
            --db-user=magento \\
            --db-password=magento \\
            --search-engine=opensearch \\
            --opensearch-host=opensearch \\
            --opensearch-port=9200 \\
            --opensearch-index-prefix=magento2 \\
            --opensearch-enable-auth=0 \\
            --opensearch-timeout=15 \\
            --http-cache-hosts=varnish:80 \\
            --session-save=redis \\
            --session-save-redis-host=redis \\
            --session-save-redis-port=6379 \\
            --session-save-redis-db=2 \\
            --session-save-redis-max-concurrency=20 \\
            --cache-backend=redis \\
            --cache-backend-redis-server=redis \\
            --cache-backend-redis-db=0 \\
            --cache-backend-redis-port=6379 \\
            --page-cache=redis \\
            --page-cache-redis-server=redis \\
            --page-cache-redis-db=1 \\
            --page-cache-redis-port=6379"
else
    # Elasticsearch installation command  
    INSTALL_COMMAND="bin/magento setup:install \\
            --backend-frontname=shopmanager \\
            --amqp-host=rabbitmq \\
            --amqp-port=5672 \\
            --amqp-user=guest \\
            --amqp-password=guest \\
            --db-host=db \\
            --db-name=magento \\
            --db-user=magento \\
            --db-password=magento \\
            --search-engine=elasticsearch7 \\
            --elasticsearch-host=elasticsearch \\
            --elasticsearch-port=9200 \\
            --elasticsearch-index-prefix=magento2 \\
            --elasticsearch-enable-auth=0 \\
            --elasticsearch-timeout=15 \\
            --http-cache-hosts=varnish:80 \\
            --session-save=redis \\
            --session-save-redis-host=redis \\
            --session-save-redis-port=6379 \\
            --session-save-redis-db=2 \\
            --session-save-redis-max-concurrency=20 \\
            --cache-backend=redis \\
            --cache-backend-redis-server=redis \\
            --cache-backend-redis-db=0 \\
            --cache-backend-redis-port=6379 \\
            --page-cache=redis \\
            --page-cache-redis-server=redis \\
            --page-cache-redis-db=1 \\
            --page-cache-redis-port=6379"
fi

if ! "${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    
    echo 'Installing Magento application...'
    echo 'Search engine parameters:'
    echo '${SEARCH_ENGINE_PARAMS}'
    ${INSTALL_COMMAND}
"; then
    echo -e "\033[33m⚠️  Primary search engine installation failed, trying fallback to Elasticsearch...\033[0m"
    
    # Fallback to Elasticsearch 7
    FALLBACK_COMMAND="bin/magento setup:install \\
            --backend-frontname=shopmanager \\
            --amqp-host=rabbitmq \\
            --amqp-port=5672 \\
            --amqp-user=guest \\
            --amqp-password=guest \\
            --db-host=db \\
            --db-name=magento \\
            --db-user=magento \\
            --db-password=magento \\
            --search-engine=elasticsearch7 \\
            --elasticsearch-host=elasticsearch \\
            --elasticsearch-port=9200 \\
            --elasticsearch-index-prefix=magento2 \\
            --elasticsearch-enable-auth=0 \\
            --elasticsearch-timeout=15 \\
            --http-cache-hosts=varnish:80 \\
            --session-save=redis \\
            --session-save-redis-host=redis \\
            --session-save-redis-port=6379 \\
            --session-save-redis-db=2 \\
            --session-save-redis-max-concurrency=20 \\
            --cache-backend=redis \\
            --cache-backend-redis-server=redis \\
            --cache-backend-redis-db=0 \\
            --cache-backend-redis-port=6379 \\
            --page-cache=redis \\
            --page-cache-redis-server=redis \\
            --page-cache-redis-db=1 \\
            --page-cache-redis-port=6379"
    
    "${ROLL_DIR}/bin/roll" cli bash -c "
        set -e
        
        echo 'Retrying with Elasticsearch 7 fallback...'
        ${FALLBACK_COMMAND}
    "
    
    echo -e "\033[32m✅ Installation completed with Elasticsearch fallback\033[0m"
    USED_FALLBACK=1
else
    echo -e "\033[32m✅ Installation completed with configured search engine\033[0m"
    USED_FALLBACK=0
fi

echo -e "\033[36m[10/12] Configuring Magento application...\033[0m"

# Configure Magento
"${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    
    echo 'Configuring base URLs...'
    bin/magento config:set --lock-env web/unsecure/base_url \\
        \"https://app.${PROJECT_NAME}.test/\"
    
    bin/magento config:set --lock-env web/secure/base_url \\
        \"https://app.${PROJECT_NAME}.test/\"
    
    bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto
    bin/magento config:set --lock-env web/secure/use_in_frontend 1
    bin/magento config:set --lock-env web/secure/use_in_adminhtml 1
    bin/magento config:set --lock-env web/seo/use_rewrites 1
    
    echo 'Configuring cache settings...'
    bin/magento config:set --lock-env system/full_page_cache/caching_application 2
    bin/magento config:set --lock-env system/full_page_cache/ttl 604800
    bin/magento config:set --lock-env catalog/search/enable_eav_indexer 1
    bin/magento config:set --lock-env dev/static/sign 0
    
    echo 'Setting developer mode...'
    bin/magento deploy:mode:set -s developer
    bin/magento cache:disable block_html full_page
"

# Configure search engine post-installation for OpenSearch fallback scenarios
if [[ "${USED_FALLBACK}" == "1" ]] && grep -q "^ROLL_OPENSEARCH=1" "${ENV_FILE}" 2>/dev/null; then
    echo -e "\033[36mInstallation used Elasticsearch fallback, but OpenSearch is configured for runtime...\033[0m"
    echo -e "\033[33m📝 Note: You can manually configure OpenSearch later using:\033[0m"
    echo -e "\033[33m  bin/magento config:set catalog/search/engine opensearch\033[0m"
    echo -e "\033[33m  bin/magento config:set catalog/search/opensearch_server_hostname opensearch\033[0m"
    echo -e "\033[33m  bin/magento config:set catalog/search/opensearch_server_port 9200\033[0m"
fi

echo -e "\033[36m[11/12] Running initial indexing...\033[0m"
"${ROLL_DIR}/bin/roll" cli bash -c "
    bin/magento indexer:reindex
    bin/magento cache:flush
"

echo -e "\033[36m[11/12] Creating admin user and configuring 2FA...\033[0m"

# Generate admin user and 2FA setup for Magento 2.4.6+ (all supported versions require 2FA)
"${ROLL_DIR}/bin/roll" cli bash -c "
    set -e
    
    # Generate admin credentials
    ADMIN_PASS=\"\$(pwgen -n1 16)\"
    ADMIN_USER=admin
    
    echo 'Creating admin user...'
    bin/magento admin:user:create \\
        --admin-password=\"\${ADMIN_PASS}\" \\
        --admin-user=\"\${ADMIN_USER}\" \\
        --admin-firstname=\"Local\" \\
        --admin-lastname=\"Admin\" \\
        --admin-email=\"\${ADMIN_USER}@example.com\"
    
    echo \"Admin Username: \${ADMIN_USER}\"
    echo \"Admin Password: \${ADMIN_PASS}\"
    
    # Configure 2FA
    echo 'Configuring 2FA...'
    TFA_SECRET=\$(python3 -c \"import base64; print(base64.b32encode('\$(pwgen -A1 128)'.encode()).decode().strip('='))\")
    OTPAUTH_URL=\$(printf \"otpauth://totp/%s%%3Alocaladmin%%40example.com?issuer=%s&secret=%s\" \\
        \"app.${PROJECT_NAME}.test\" \"app.${PROJECT_NAME}.test\" \"\${TFA_SECRET}\"
    )
    
    bin/magento config:set --lock-env twofactorauth/general/force_providers google
    bin/magento security:tfa:google:set-secret \"\${ADMIN_USER}\" \"\${TFA_SECRET}\"
    
    echo \"2FA Setup URL: \${OTPAUTH_URL}\"
    echo \"2FA Backup Codes:\"
    oathtool -s 30 -w 10 --totp --base32 \"\${TFA_SECRET}\"
    
    # Generate QR code
    segno \"\${OTPAUTH_URL}\" -s 4 -o \"pub/media/\${ADMIN_USER}-totp-qr.png\"
    QR_URL=\"https://app.${PROJECT_NAME}.test/media/\${ADMIN_USER}-totp-qr.png?t=\$(date +%s)\"
    echo \"QR Code URL: \${QR_URL}\"
    
    # Save credentials to file for user reference
    cat > /var/www/html/admin-credentials.txt << EOL
Magento Admin Credentials
========================
Username: \${ADMIN_USER}
Password: \${ADMIN_PASS}
2FA Setup URL: \${OTPAUTH_URL}
QR Code URL: \${QR_URL}

Admin Panel: https://app.${PROJECT_NAME}.test/shopmanager/
Frontend: https://app.${PROJECT_NAME}.test/

Generated on: \$(date)
EOL
    
    echo 'Admin credentials saved to admin-credentials.txt'
"

echo -e "\033[36m[12/12] Finalizing setup...\033[0m"

echo -e "\033[32m✅ Magento 2 project '${PROJECT_NAME}' has been successfully created!\033[0m"
echo ""
echo -e "\033[33m🔗 Access URLs:\033[0m"
echo -e "   Frontend: https://app.${PROJECT_NAME}.test/"
echo -e "   Admin:    https://app.${PROJECT_NAME}.test/shopmanager/"
echo -e "   RabbitMQ: https://rabbitmq.${PROJECT_NAME}.test/"
echo -e "   Elasticsearch: https://elasticsearch.${PROJECT_NAME}.test/"
echo ""
echo -e "\033[33m📁 Project Location:\033[0m"
echo -e "   ${TARGET_DIR}"
echo ""
echo -e "\033[33m🔑 Admin Credentials:\033[0m"
echo -e "   Check the file: admin-credentials.txt in your project root"
echo ""
echo -e "\033[33m💡 Next Steps:\033[0m"
echo -e "   1. Navigate to your project: cd ${TARGET_DIR}"
echo -e "   2. Access the shell: roll shell"
echo -e "   3. Open your browser to: https://app.${PROJECT_NAME}.test/"

if [[ "${USED_FALLBACK}" == "1" ]]; then
    echo ""
    echo -e "\033[33m⚠️  Installation Note:\033[0m"
    echo -e "   Installation used Elasticsearch fallback due to OpenSearch connectivity issues"
    echo -e "   OpenSearch is configured in your environment for future use"
    echo -e "   Check the manual configuration commands shown above to switch to OpenSearch"
fi

echo ""
echo -e "\033[33m🛑 To destroy this environment:\033[0m"
echo -e "   roll env down -v"
echo "" 