#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Configuration Management System
## Compatible with Bash 3.2+ (macOS default)
## Cross-platform: Linux, macOS, WSL

# Configuration cache using simple arrays instead of associative arrays for Bash 3.2 compatibility
ROLL_CONFIG_CACHE_KEYS=()
ROLL_CONFIG_CACHE_VALUES=()
ROLL_CONFIG_LOADED_FILES=()

# Configuration schema using indexed arrays
ROLL_CONFIG_SCHEMA_KEYS=()
ROLL_CONFIG_SCHEMA_VALUES=()

## Helper function to find index of key in array
function findConfigIndex() {
    local key="$1"
    local i=0
    for cached_key in "${ROLL_CONFIG_CACHE_KEYS[@]}"; do
        if [[ "$cached_key" == "$key" ]]; then
            echo $i
            return 0
        fi
        i=$((i + 1))
    done
    echo -1
}

## Helper function to find schema index
function findSchemaIndex() {
    local key="$1"
    local i=0
    for schema_key in "${ROLL_CONFIG_SCHEMA_KEYS[@]}"; do
        if [[ "$schema_key" == "$key" ]]; then
            echo $i
            return 0
        fi
        i=$((i + 1))
    done
    echo -1
}

## Helper function to check if file is loaded
function isFileLoaded() {
    local file="$1"
    local loaded_file
    for loaded_file in "${ROLL_CONFIG_LOADED_FILES[@]}"; do
        if [[ "$loaded_file" == "$file" ]]; then
            return 0
        fi
    done
    return 1
}

# Initialize configuration schema
function initConfigSchema() {
    # Skip if already initialized
    if [[ ${#ROLL_CONFIG_SCHEMA_KEYS[@]} -gt 0 ]]; then
        return 0
    fi
    
    # Core Roll configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_NAME); ROLL_CONFIG_SCHEMA_VALUES+=("string:required")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_TYPE); ROLL_CONFIG_SCHEMA_VALUES+=("string:required")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SUBT); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Service toggles (boolean with defaults)
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_NGINX); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_DB); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_REDIS); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_DRAGONFLY); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_VARNISH); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ELASTICSEARCH); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_OPENSEARCH); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ELASTICVUE); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_REDISINSIGHT); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_RABBITMQ); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_MONGODB); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_BROWSERSYNC); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SELENIUM); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SELENIUM_DEBUG); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_TEST_DB); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ALLURE); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_MAGEPACK); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_INCLUDE_GIT); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    
    # Traefik configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(TRAEFIK_DOMAIN); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(TRAEFIK_SUBDOMAIN); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(TRAEFIK_LISTEN); ROLL_CONFIG_SCHEMA_VALUES+=("string:127.0.0.1")
    
    # PHP configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(PHP_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:8.1")
    ROLL_CONFIG_SCHEMA_KEYS+=(PHP_XDEBUG_3); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(PHP_MEMORY_LIMIT); ROLL_CONFIG_SCHEMA_VALUES+=("string:2G")
    
    # Composer configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(COMPOSER_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Database configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(DB_DISTRIBUTION); ROLL_CONFIG_SCHEMA_VALUES+=("string:mariadb")
    ROLL_CONFIG_SCHEMA_KEYS+=(DB_DISTRIBUTION_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:10.4")
    ROLL_CONFIG_SCHEMA_KEYS+=(MYSQL_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:8.0")
    ROLL_CONFIG_SCHEMA_KEYS+=(MARIADB_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:10.4")
    
    # Service version configurations
    ROLL_CONFIG_SCHEMA_KEYS+=(ELASTICSEARCH_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:7.17")
    ROLL_CONFIG_SCHEMA_KEYS+=(RABBITMQ_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:3.11")
    ROLL_CONFIG_SCHEMA_KEYS+=(REDIS_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:7.0")
    ROLL_CONFIG_SCHEMA_KEYS+=(DRAGONFLY_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:latest")
    ROLL_CONFIG_SCHEMA_KEYS+=(VARNISH_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:7.0")
    ROLL_CONFIG_SCHEMA_KEYS+=(OPENSEARCH_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:2.5")
    ROLL_CONFIG_SCHEMA_KEYS+=(MONGO_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:6.0")
    ROLL_CONFIG_SCHEMA_KEYS+=(NGINX_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:1.24")
    ROLL_CONFIG_SCHEMA_KEYS+=(MAGEPACK_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:2.3")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SELENIUM_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:3.141.59")
    
    # Node configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(NODE_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:18")
    
    # Nginx configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(NGINX_TEMPLATE); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(NGINX_PUBLIC); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Magento specific
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ADMIN_AUTOLOGIN); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_MAGENTO_STATIC_CACHING); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:0")
    
    # Environment paths and directories
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_WEB_ROOT); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SYNC_IGNORE); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_CHOWN_DIR_LIST); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Extensions and customizations
    ROLL_CONFIG_SCHEMA_KEYS+=(ADD_PHP_EXT); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # Container configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SHELL_CONTAINER); ROLL_CONFIG_SCHEMA_VALUES+=("string:php-fpm")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SHELL_COMMAND); ROLL_CONFIG_SCHEMA_VALUES+=("string:bash")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_ENV_SHELL_DEBUG_CONTAINER); ROLL_CONFIG_SCHEMA_VALUES+=("string:php-debug")
    
    # Global service configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SERVICE_STARTPAGE); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SERVICE_PORTAINER); ROLL_CONFIG_SCHEMA_VALUES+=("boolean:1")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_SERVICE_DOMAIN); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    
    # XDebug configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(XDEBUG_CONNECT_BACK_HOST); ROLL_CONFIG_SCHEMA_VALUES+=("string:optional")
    ROLL_CONFIG_SCHEMA_KEYS+=(XDEBUG_VERSION); ROLL_CONFIG_SCHEMA_VALUES+=("string:debug")
    
    # System configuration
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_RESTART_POLICY); ROLL_CONFIG_SCHEMA_VALUES+=("string:always")
    ROLL_CONFIG_SCHEMA_KEYS+=(ROLL_IMAGE_REPOSITORY); ROLL_CONFIG_SCHEMA_VALUES+=("string:ghcr.io/dockergiant")
}

## Get schema for a key
function getSchema() {
    local key="$1"
    local index=$(findSchemaIndex "$key")
    if [[ $index -ge 0 ]]; then
        echo "${ROLL_CONFIG_SCHEMA_VALUES[$index]}"
    fi
}

## Validate configuration value against schema
function validateConfigValue() {
    local key="$1"
    local value="$2"
    local schema="$(getSchema "$key")"
    
    if [[ -z "$schema" ]]; then
        # Unknown configuration key - allow but warn
        warning "Unknown configuration key: $key"
        return 0
    fi
    
    local type="${schema%%:*}"
    local constraint="${schema##*:}"
    
    case "$type" in
        boolean)
            if [[ "$value" != "0" && "$value" != "1" ]]; then
                error "Configuration $key must be 0 or 1, got: $value"
                return 1
            fi
            ;;
        string)
            if [[ "$constraint" == "required" && -z "$value" ]]; then
                error "Configuration $key is required but empty"
                return 1
            fi
            ;;
        integer)
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                error "Configuration $key must be an integer, got: $value"
                return 1
            fi
            ;;
    esac
    
    return 0
}

## Set default value for configuration if not set
function setConfigDefault() {
    local key="$1"
    local schema="$(getSchema "$key")"
    
    if [[ -z "$schema" ]]; then
        return 0
    fi
    
    local constraint="${schema##*:}"
    
    # Skip if already set or no default available
    local index=$(findConfigIndex "$key")
    if [[ $index -ge 0 || "$constraint" == "required" || "$constraint" == "optional" ]]; then
        return 0
    fi
    
    # Set default value
    ROLL_CONFIG_CACHE_KEYS+=("$key")
    ROLL_CONFIG_CACHE_VALUES+=("$constraint")
    export "$key"="$constraint"
}

## Load configuration from file with validation
function loadConfigFromFile() {
    local config_file="$1"
    local validate_only="${2:-false}"
    
    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if already loaded
    if isFileLoaded "$config_file" && [[ "$validate_only" == "false" ]]; then
        return 0
    fi
    
    local line_num=0
    local errors=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Remove Windows line endings
        line="${line%$'\r'}"
        
        # Parse key=value pairs
        if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi
            
            # Validate configuration
            if ! validateConfigValue "$key" "$value"; then
                error "Invalid configuration at $config_file:$line_num"
                errors=$((errors + 1))
                continue
            fi
            
            # Store in cache and export if not validation-only
            if [[ "$validate_only" == "false" ]]; then
                local index=$(findConfigIndex "$key")
                if [[ $index -ge 0 ]]; then
                    # Update existing
                    ROLL_CONFIG_CACHE_VALUES[$index]="$value"
                else
                    # Add new
                    ROLL_CONFIG_CACHE_KEYS+=("$key")
                    ROLL_CONFIG_CACHE_VALUES+=("$value")
                fi
                export "$key"="$value"
            fi
            
        elif [[ "$line" =~ ^[[:space:]]*[^=]+$ ]]; then
            warning "Invalid configuration line at $config_file:$line_num: $line"
        fi
        
    done < "$config_file"
    
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
    
    # Mark as loaded
    if [[ "$validate_only" == "false" ]]; then
        ROLL_CONFIG_LOADED_FILES+=("$config_file")
    fi
    
    return 0
}

## Load Roll environment configuration
function loadRollConfig() {
    local config_path="$1"
    
    if [[ -z "$config_path" ]]; then
        config_path="$(locateEnvPath 2>/dev/null)" || {
            error "Could not locate environment configuration"
            return 1
        }
    fi
    
    local config_file="$config_path/.env.roll"
    
    # Initialize schema if not done
    initConfigSchema
    
    # Load global configuration first from ROLL_HOME_DIR
    local global_config_loaded=0
    
    # Check for new-style global config file
    if [[ -f "${ROLL_HOME_DIR}/.env.roll" ]]; then
        if loadConfigFromFile "${ROLL_HOME_DIR}/.env.roll"; then
            global_config_loaded=1
        else
            warning "Failed to load global configuration from ${ROLL_HOME_DIR}/.env.roll"
        fi
    fi
    
    # Check for legacy global config file
    if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
        if loadConfigFromFile "${ROLL_HOME_DIR}/.env"; then
            global_config_loaded=1
        else
            warning "Failed to load global configuration from ${ROLL_HOME_DIR}/.env"
        fi
    fi
    
    # Load project-specific configuration (this will override global settings)
    if ! loadConfigFromFile "$config_file"; then
        return 1
    fi
    
    # Set OS-specific defaults
    case "${OSTYPE:-undefined}" in
        darwin*)
            setConfigValue "ROLL_ENV_SUBT" "darwin"
            ;;
        linux*)
            setConfigValue "ROLL_ENV_SUBT" "linux"
            
            # Check for WSL
            if grep -sqi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
                setConfigValue "ROLL_ENV_SUBT" "wsl"
            fi
            ;;
        *)
            error "Unsupported OSTYPE '${OSTYPE:-undefined}'"
            return 1
            ;;
    esac
    
    # Set system-specific exports
    export USER_ID="$(id -u)"
    export GROUP_ID="$(id -g)"
    export OSTYPE="${OSTYPE}"
    
    # Set defaults for unset values
    local i=0
    while [[ $i -lt ${#ROLL_CONFIG_SCHEMA_KEYS[@]} ]]; do
        setConfigDefault "${ROLL_CONFIG_SCHEMA_KEYS[$i]}"
        i=$((i + 1))
    done
    
    # Validate environment type
    if ! assertValidEnvType; then
        return 1
    fi
    
    # Post-processing for specific configurations
    postProcessConfig
    
    return 0
}

## Set configuration value
function setConfigValue() {
    local key="$1"
    local value="$2"
    
    local index=$(findConfigIndex "$key")
    if [[ $index -ge 0 ]]; then
        # Update existing
        ROLL_CONFIG_CACHE_VALUES[$index]="$value"
    else
        # Add new
        ROLL_CONFIG_CACHE_KEYS+=("$key")
        ROLL_CONFIG_CACHE_VALUES+=("$value")
    fi
    export "$key"="$value"
}

## Post-process configuration after loading
function postProcessConfig() {
    # Set PHP variant based on environment type
    if [[ "${ROLL_ENV_TYPE}" =~ ^magento ]] || [[ "${ROLL_ENV_TYPE}" =~ ^wordpress ]]; then
        export ROLL_SVC_PHP_VARIANT="-${ROLL_ENV_TYPE}"
    fi
    
    # Set Node.js variant
    if [[ "${NODE_VERSION}" != "0" ]]; then
        export ROLL_SVC_PHP_NODE="-node${NODE_VERSION}"
    fi
    
    # Database distribution defaults
    if [[ -z "${DB_DISTRIBUTION_VERSION}" ]]; then
        if [[ "${DB_DISTRIBUTION}" == "mysql" ]]; then
            export DB_DISTRIBUTION_VERSION="${MYSQL_VERSION:-8.0}"
        else
            export DB_DISTRIBUTION_VERSION="${MARIADB_VERSION:-10.4}"
        fi
    fi
    
    # XDebug version configuration
    if [[ "${PHP_XDEBUG_3}" == "1" ]]; then
        export XDEBUG_VERSION="xdebug3"
    else
        export XDEBUG_VERSION="debug"
    fi
    
    # WSL XDebug host configuration
    if [[ "${ROLL_ENV_SUBT}" == "wsl" && -z "${XDEBUG_CONNECT_BACK_HOST}" ]]; then
        export XDEBUG_CONNECT_BACK_HOST="host.docker.internal"
    fi
    
    # Linux SSH auth sock path
    if [[ "${ROLL_ENV_SUBT}" == "linux" && "$(id -u)" == "1000" ]]; then
        export SSH_AUTH_SOCK_PATH_ENV="/run/host-services/ssh-auth.sock"
    fi
    
    # Environment-specific defaults
    if [[ "${ROLL_ENV_TYPE}" != "local" ]]; then
        export ROLL_NGINX="${ROLL_NGINX:-1}"
        export ROLL_DB="${ROLL_DB:-1}"
        export ROLL_REDIS="${ROLL_REDIS:-1}"
        
        # Bash history and SSH directories
        export CHOWN_DIR_LIST="/bash_history /home/www-data/.ssh ${ROLL_CHOWN_DIR_LIST:-}"
    fi
    
    # Magento 1 specific configuration
    if [[ "${ROLL_ENV_TYPE}" == "magento1" ]]; then
        if [[ -f "${ROLL_ENV_PATH}/.modman/.basedir" ]]; then
            export NGINX_PUBLIC="/$(cat "${ROLL_ENV_PATH}/.modman/.basedir")"
        fi
        
        if [[ "${ROLL_MAGENTO_STATIC_CACHING}" == "1" ]]; then
            export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento1.conf}"
        else
            export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento1-dev.conf}"
        fi
    fi
    
    # Magento 2 specific configuration
    if [[ "${ROLL_ENV_TYPE}" == "magento2" ]]; then
        export ROLL_VARNISH="${ROLL_VARNISH:-1}"
        export ROLL_ELASTICSEARCH="${ROLL_ELASTICSEARCH:-1}"
        export ROLL_RABBITMQ="${ROLL_RABBITMQ:-1}"
        
        if [[ "${ROLL_MAGENTO_STATIC_CACHING}" == "1" ]]; then
            if [[ "${ROLL_ADMIN_AUTOLOGIN}" == "1" ]]; then
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2-autologin.conf}"
            else
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2.conf}"
            fi
        else
            if [[ "${ROLL_ADMIN_AUTOLOGIN}" == "1" ]]; then
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2-dev-autologin.conf}"
            else
                export NGINX_TEMPLATE="${NGINX_TEMPLATE:-magento2-dev.conf}"
            fi
        fi
    fi
}

## Validate configuration file without loading
function validateConfig() {
    local config_file="$1"
    
    if [[ -z "$config_file" ]]; then
        config_file="$(locateEnvPath)/.env.roll"
    fi
    
    # Initialize schema if not done
    initConfigSchema
    
    loadConfigFromFile "$config_file" "true"
}

## Get configuration value
function getConfig() {
    local key="$1"
    local default_value="$2"
    
    local index=$(findConfigIndex "$key")
    if [[ $index -ge 0 ]]; then
        echo "${ROLL_CONFIG_CACHE_VALUES[$index]}"
    elif [[ -n "${!key}" ]]; then
        echo "${!key}"
    else
        echo "${default_value}"
    fi
}

## Set configuration value
function setConfig() {
    local key="$1"
    local value="$2"
    
    if validateConfigValue "$key" "$value"; then
        setConfigValue "$key" "$value"
        return 0
    else
        return 1
    fi
}

## Display configuration summary
function showConfig() {
    local filter="${1:-}"
    
    echo -e "\033[33mRoll Configuration:\033[0m"
    echo "Environment: ${ROLL_ENV_NAME:-<not set>} (${ROLL_ENV_TYPE:-<not set>})"
    echo "Platform: ${ROLL_ENV_SUBT:-<not set>}"
    
    # Show loaded configuration files
    if [[ ${#ROLL_CONFIG_LOADED_FILES[@]} -gt 0 ]]; then
        echo ""
        echo -e "\033[33mLoaded configuration files:\033[0m"
        local loaded_file
        for loaded_file in "${ROLL_CONFIG_LOADED_FILES[@]}"; do
            if [[ "$loaded_file" =~ ${ROLL_HOME_DIR} ]]; then
                echo "  ${loaded_file} (global)"
            else
                echo "  ${loaded_file} (project)"
            fi
        done
    fi
    
    echo ""
    
    local i=0
    while [[ $i -lt ${#ROLL_CONFIG_CACHE_KEYS[@]} ]]; do
        local key="${ROLL_CONFIG_CACHE_KEYS[$i]}"
        local value="${ROLL_CONFIG_CACHE_VALUES[$i]}"
        
        if [[ -n "$filter" && ! "$key" =~ $filter ]]; then
            i=$((i + 1))
            continue
        fi
        
        printf "  %-30s = %s\n" "$key" "$value"
        i=$((i + 1))
    done
}

## Check for configuration conflicts
function checkConfigConflicts() {
    local errors=0
    
    # Redis vs Dragonfly conflict
    if [[ "$(getConfig ROLL_REDIS 0)" == "1" && "$(getConfig ROLL_DRAGONFLY 0)" == "1" ]]; then
        error "Configuration conflict: ROLL_REDIS and ROLL_DRAGONFLY cannot both be enabled"
        errors=$((errors + 1))
    fi
    
    # Environment type specific validations
    if [[ "${ROLL_ENV_TYPE}" == "magento2" ]]; then
        if [[ "$(getConfig ROLL_ELASTICSEARCH 0)" == "1" && "$(getConfig ROLL_OPENSEARCH 0)" == "1" ]]; then
            warning "Both Elasticsearch and OpenSearch are enabled - this may cause conflicts"
        fi
    fi
    
    # Database distribution validation
    local db_dist="$(getConfig DB_DISTRIBUTION mariadb)"
    if [[ "$db_dist" != "mysql" && "$db_dist" != "mariadb" ]]; then
        error "DB_DISTRIBUTION must be either 'mysql' or 'mariadb', got: $db_dist"
        errors=$((errors + 1))
    fi
    
    return $errors
}

## Legacy compatibility wrapper - replace old loadEnvConfig calls
function loadEnvConfig() {
    local env_path="$1"
    loadRollConfig "$env_path"
} 