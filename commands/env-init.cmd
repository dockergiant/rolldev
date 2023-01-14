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

if [[ "${ROLL_ENV_TYPE}" == "magento1" ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		ROLL_DB=1
		ROLL_REDIS=1

		MARIADB_VERSION=10.3
		NODE_VERSION=12
		COMPOSER_VERSION=1
		PHP_VERSION=7.2
		PHP_XDEBUG_3=1
		REDIS_VERSION=5.0

		ROLL_SELENIUM=0
		ROLL_SELENIUM_DEBUG=0

		# Uncomment to disable static content caching
    #ROLL_NO_STATIC_CACHING=1
	EOT
fi

if [[ "${ROLL_ENV_TYPE}" == "magento2" ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		ROLL_DB=1
		ROLL_ELASTICSEARCH=1
		ROLL_VARNISH=1
		ROLL_RABBITMQ=1
		ROLL_REDIS=1

		ELASTICSEARCH_VERSION=7.17
		MARIADB_VERSION=10.3
		NODE_VERSION=12
		COMPOSER_VERSION=2
		PHP_VERSION=7.4
		PHP_XDEBUG_3=1
		RABBITMQ_VERSION=3.8
		REDIS_VERSION=5.0
		VARNISH_VERSION=6.0

		ROLL_SYNC_IGNORE=

		# Comment to enable static content caching
        ROLL_NO_STATIC_CACHING=1

		ROLL_ALLURE=0
		ROLL_SELENIUM=0
		ROLL_SELENIUM_DEBUG=0
		ROLL_SPLIT_SALES=0
		ROLL_SPLIT_CHECKOUT=0
		ROLL_TEST_DB=0
	EOT
fi

if [[ "${ROLL_ENV_TYPE}" == "laravel" ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		MARIADB_VERSION=10.4
		NODE_VERSION=12
		COMPOSER_VERSION=1
		PHP_VERSION=7.4
		PHP_XDEBUG_3=1
		REDIS_VERSION=5.0

		ROLL_DB=1
		ROLL_REDIS=1

		## Laravel Config
		APP_URL=http://app.${ROLL_ENV_NAME}.test
		APP_KEY=base64:$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64)

		APP_ENV=local
		APP_DEBUG=true

		DB_CONNECTION=mysql
		DB_HOST=db
		DB_PORT=3306
		DB_DATABASE=laravel
		DB_USERNAME=laravel
		DB_PASSWORD=laravel

		CACHE_DRIVER=redis
		SESSION_DRIVER=redis

		REDIS_HOST=redis
		REDIS_PORT=6379

		MAIL_DRIVER=sendmail
	EOT
fi

if [[ "${ROLL_ENV_TYPE}" =~ ^symfony|shopware|typo3$ ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		ROLL_DB=1
		ROLL_REDIS=1
		ROLL_RABBITMQ=0
		ROLL_ELASTICSEARCH=0
		ROLL_VARNISH=0

		MARIADB_VERSION=10.4
		NODE_VERSION=12
		COMPOSER_VERSION=2
		PHP_VERSION=7.4
		PHP_XDEBUG_3=1
		RABBITMQ_VERSION=3.8
		REDIS_VERSION=5.0
		VARNISH_VERSION=6.0
	EOT
fi

if [[ "${ROLL_ENV_TYPE}" == "wordpress" ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		MARIADB_VERSION=10.4
		NODE_VERSION=12
		COMPOSER_VERSION=1
		PHP_VERSION=7.4
		PHP_XDEBUG_3=1

		ROLL_DB=1
		ROLL_REDIS=0

		APP_ENV=local
		APP_DEBUG=true

		DB_CONNECTION=mysql
		DB_HOST=db
		DB_PORT=3306
		DB_DATABASE=wordpress
		DB_USERNAME=wordpress
		DB_PASSWORD=wordpress
	EOT
fi

if [[ "${ROLL_ENV_TYPE}" == "php" ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		ROLL_DB=0
		ROLL_REDIS=0
		ROLL_VARNISH=0

		MARIADB_VERSION=10.4
		NODE_VERSION=12
		COMPOSER_VERSION=2
		PHP_VERSION=7.4
		PHP_XDEBUG_3=1
		REDIS_VERSION=5.0
	EOT
fi

if [[ "${ROLL_ENV_TYPE}" == "akeneo" ]]; then
  cat >> "${ROLL_ENV_PATH}/.env.roll" <<-EOT

		ELASTICSEARCH_VERSION=7.16
		NODE_VERSION=12
		COMPOSER_VERSION=2
		PHP_VERSION=8.0
		PHP_XDEBUG_3=1

		ROLL_DB=1
		ROLL_ELASTICSEARCH=1

		APP_ENV=local
		APP_DEBUG=true
		APP_DATABASE_HOST=db
		APP_DATABASE_PORT=null
		APP_DATABASE_NAME=akeneo
		APP_DATABASE_USER=akeneo
		APP_DATABASE_PASSWORD=akeneo
		APP_INDEX_HOSTS='elasticsearch:9200'
	EOT
fi
