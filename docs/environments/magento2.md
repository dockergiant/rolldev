# Installing Magento 2

## Quick Start with `magento2-init` (Recommended)

RollDev 3.2+ provides an automated `magento2-init` command that handles the complete Magento 2 setup process in a single command. This is the recommended approach for new projects.

### Basic Usage

```bash
roll magento2-init <project_name> [magento_version]
```

### Examples

```bash
# Create project with latest Magento version
roll magento2-init mystore

# Create project with specific version  
roll magento2-init mystore 2.4.7

# Create project with patch version
roll magento2-init mystore 2.4.7-p3

# Create project with OpenSearch (Magento 2.4.8+)
roll magento2-init mystore 2.4.8
```

### What it Does

The `magento2-init` command automates all the manual steps listed below:

1. **Environment Setup**: Creates `.env.roll` with optimized configuration for the specified Magento version
2. **Version Compatibility**: Automatically configures compatible PHP, MariaDB, Elasticsearch/OpenSearch, Redis, RabbitMQ, and Composer versions
3. **SSL Certificate**: Generates and signs SSL certificate for local development  
4. **Service Startup**: Starts all required Docker services (database, search, cache, etc.)
5. **Magento Installation**: Downloads and installs Magento via Composer
6. **Database Configuration**: Sets up database, Redis, and search engine connections
7. **Admin User**: Creates admin user with 2FA setup (for Magento 2.4.x)
8. **Developer Mode**: Configures development-optimized settings

### Software Version Matrix

The command automatically selects compatible software versions:

| Magento Version | PHP | MariaDB | Search Engine | Redis | RabbitMQ | Varnish |
|-----------------|-----|---------|---------------|-------|----------|---------|
| 2.4.8+ | 8.3 | 11.4 | OpenSearch 2.19 | Valkey 8 | 4.1 | 7.7 |
| 2.4.7 | 8.3 | 10.6+ | Elasticsearch 7.17 | Redis 7.2 | 3.13 | 7.5+ |
| 2.4.6 | 8.2 | 10.6 | Elasticsearch 7.17 | Redis 7.0+ | 3.9 | 7.1+ |

### Prerequisites

- RollDev services running: `roll svc up`
- Magento Marketplace credentials configured globally:
  ```bash
  composer global config http-basic.repo.magento.com <username> <password>
  ```

### Post-Installation Access

After successful installation:

- **Frontend**: `https://app.<project_name>.test/`
- **Admin Panel**: `https://app.<project_name>.test/shopmanager/`  
- **Admin Credentials**: Check `admin-credentials.txt` in project root
- **2FA QR Code**: Available via web interface for easy mobile setup

### OpenSearch vs Elasticsearch

For Magento 2.4.8+, the command automatically configures OpenSearch. If OpenSearch setup fails, it automatically falls back to Elasticsearch 7.17 with instructions for manual OpenSearch configuration.

---

## Manual Installation (Alternative)

If you prefer manual setup or need custom configuration, follow the detailed steps below.

The below example demonstrates the from-scratch setup of the Magento 2 application for local development. A similar process can easily be used to configure an environment of any other type. This assumes that RollDev has been previously started via `roll svc up` as part of the installation procedure.

1.  Create a new directory on your host machine at the location of your choice and then jump into the new directory to get started:

        mkdir -p ~/Sites/exampleproject
        cd ~/Sites/exampleproject

2.  From the root of your new project directory, run `env-init` to create the `.env.roll` file with configuration needed for RollDev and Docker to work with the project.

        roll env-init exampleproject magento2

    The result of this command is a `.env.roll` file in the project root (tip: commit this to your VCS to share the configuration with other team members) having the following contents:

        ROLL_ENV_NAME=exampleproject
        ROLL_ENV_TYPE=magento2
        ROLL_WEB_ROOT=/

        TRAEFIK_DOMAIN=exampleproject.test
        TRAEFIK_SUBDOMAIN=app

        ROLL_DB=1
        ROLL_ELASTICSEARCH=1
        ROLL_ELASTICHQ=0
        ROLL_VARNISH=1
        ROLL_RABBITMQ=1
        ROLL_REDIS=1

        ROLL_SYNC_IGNORE=

        ELASTICSEARCH_VERSION=7.6
        DB_DISTRIBUTION=mariadb
        DB_DISTRIBUTION_VERSION=10.3
        NODE_VERSION=12
        COMPOSER_VERSION=2.2
        PHP_VERSION=7.3
        PHP_XDEBUG_3=1
        RABBITMQ_VERSION=3.8
        REDIS_VERSION=5.0
        VARNISH_VERSION=6.0

        ROLL_ALLURE=0
        ROLL_SELENIUM=0
        ROLL_SELENIUM_DEBUG=0
        ROLL_BLACKFIRE=0
        ROLL_SPLIT_SALES=0
        ROLL_SPLIT_CHECKOUT=0
        ROLL_TEST_DB=0
        ROLL_MAGEPACK=0

        BLACKFIRE_CLIENT_ID=
        BLACKFIRE_CLIENT_TOKEN=
        BLACKFIRE_SERVER_ID=
        BLACKFIRE_SERVER_TOKEN=

3.  Sign an SSL certificate for use with the project (the input here should match the value of `TRAEFIK_DOMAIN` in the above `.env.roll` example file):

        roll sign-certificate exampleproject.test

4.  Next you'll want to start the project environment:

        roll env up

    :::{warning}
    If you encounter an error about ``Mounts denied``, follow the instructions in the error message and run ``roll env up`` again.
    :::

5.  Drop into a shell within the project environment. Commands following this step in the setup procedure will be run from within the `php-fpm` docker container this launches you into:

        roll shell

6.  Configure global Magento Marketplace credentials

    	composer global config http-basic.repo.magento.com <username> <password>

    :::{note}
    To locate your authentication keys for Magento 2 repository, `reference DevDocs <https://devdocs.magento.com/guides/v2.3/install-gde/prereq/connect-auth.html>`_.

    If you have previously configured global credentials, you may skip this step, as ``~/.composer/`` is mounted into the container from the host machine in order to share composer cache between projects, and also shares the global ``auth.json`` from the host machine.

    Use the **Public key** as your username and the **Private key** as your password.
    :::

7.  Initialize project source files using composer create-project and then move them into place:

        META_PACKAGE=magento/project-community-edition META_VERSION=2.4.x

        composer create-project --repository-url=https://repo.magento.com/ \
            "${META_PACKAGE}" /tmp/exampleproject "${META_VERSION}"

        rsync -a /tmp/exampleproject/ /var/www/html/
        rm -rf /tmp/exampleproject/

8.  Install the application and you should be all set:

    :::{note}
    If you are using OpenSearch instead of ElasticSearch, use `--elasticsearch-host=opensearch` instead of `--elasticsearch-host=elasticsearch`.
    :::

        ## Install Application
        bin/magento setup:install \
            --backend-frontname=backend \
            --amqp-host=rabbitmq \
            --amqp-port=5672 \
            --amqp-user=guest \
            --amqp-password=guest \
            --db-host=db \
            --db-name=magento \
            --db-user=magento \
            --db-password=magento \
            --search-engine=elasticsearch7 \
            --elasticsearch-host=elasticsearch \
            --elasticsearch-port=9200 \
            --elasticsearch-index-prefix=magento2 \
            --elasticsearch-enable-auth=0 \
            --elasticsearch-timeout=15 \
            --http-cache-hosts=varnish:80 \
            --session-save=redis \
            --session-save-redis-host=redis \
            --session-save-redis-port=6379 \
            --session-save-redis-db=2 \
            --session-save-redis-max-concurrency=20 \
            --cache-backend=redis \
            --cache-backend-redis-server=redis \
            --cache-backend-redis-db=0 \
            --cache-backend-redis-port=6379 \
            --page-cache=redis \
            --page-cache-redis-server=redis \
            --page-cache-redis-db=1 \
            --page-cache-redis-port=6379

        ## Configure Application
        bin/magento config:set --lock-env web/unsecure/base_url \
            "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"

        bin/magento config:set --lock-env web/secure/base_url \
            "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"

        bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto

        bin/magento config:set --lock-env web/secure/use_in_frontend 1
        bin/magento config:set --lock-env web/secure/use_in_adminhtml 1
        bin/magento config:set --lock-env web/seo/use_rewrites 1

        bin/magento config:set --lock-env system/full_page_cache/caching_application 2
        bin/magento config:set --lock-env system/full_page_cache/ttl 604800

        bin/magento config:set --lock-env catalog/search/enable_eav_indexer 1

        bin/magento config:set --lock-env dev/static/sign 0

        bin/magento deploy:mode:set -s developer
        bin/magento cache:disable block_html full_page

        bin/magento indexer:reindex
        bin/magento cache:flush

    :::{note}
    Prior to Magento ``2.4.x`` it was not required to enter search-engine and elasticsearch configuration during installation and these params to ``setup:install`` are not supported by Magento ``2.3.x``. These should be omitted on older versions where not supported and Elasticsearch configured via ``config:set`` instead:

    ```bash
        bin/magento config:set --lock-env catalog/search/engine elasticsearch7
        bin/magento config:set --lock-env catalog/search/elasticsearch7_server_hostname elasticsearch
        bin/magento config:set --lock-env catalog/search/elasticsearch7_server_port 9200
        bin/magento config:set --lock-env catalog/search/elasticsearch7_index_prefix magento2
        bin/magento config:set --lock-env catalog/search/elasticsearch7_enable_auth 0
        bin/magento config:set --lock-env catalog/search/elasticsearch7_server_timeout 15
    ```    
    :::

9.  Generate an admin user and configure 2FA for OTP

        ## Generate localadmin user
        ADMIN_PASS="$(pwgen -n1 16)"
        ADMIN_USER=admin

        bin/magento admin:user:create \
            --admin-password="${ADMIN_PASS}" \
            --admin-user="${ADMIN_USER}" \
            --admin-firstname="Local" \
            --admin-lastname="Admin" \
            --admin-email="${ADMIN_USER}@example.com"
        printf "u: %s\np: %s\n" "${ADMIN_USER}" "${ADMIN_PASS}"

        ## Configure 2FA provider
        OTPAUTH_QRI=
        TFA_SECRET=$(python -c "import base64; print base64.b32encode('$(pwgen -A1 128)'.encode()).decode().strip('='))")
        OTPAUTH_URL=$(printf "otpauth://totp/%s%%3Alocaladmin%%40example.com?issuer=%s&secret=%s" \
            "${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" "${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" "${TFA_SECRET}"
        )

        bin/magento config:set --lock-env twofactorauth/general/force_providers google
        bin/magento security:tfa:google:set-secret "${ADMIN_USER}" "${TFA_SECRET}"

        printf "%s\n\n" "${OTPAUTH_URL}"
        printf "2FA Authenticator Codes:\n%s\n" "$(oathtool -s 30 -w 10 --totp --base32 "${TFA_SECRET}")"

        segno "${OTPAUTH_URL}" -s 4 -o "pub/media/${ADMIN_USER}-totp-qr.png"
        QR_URL="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/media/${ADMIN_USER}-totp-qr.png?t=$(date +%s)"
        printf "%s\n\n" "$QR_URL"
        
        printf "\nScan this qr code or open url below for saving 2fa\n%s\n\n%s\n" "$QR_URL" "$(qrencode -t ANSI256UTF8 \"$OTPAUTH_URL\")"
    :::{note}
    Use of 2FA is mandatory on Magento ``2.4.x`` and setup of 2FA should be skipped when installing ``2.3.x`` or earlier. Where 2FA is setup manually via UI upon login rather than using the CLI commands above, the 2FA configuration email may be retrieved from `the Mailhog service <https://mailhog.roll.test/>`_.
    :::

10. Launch the application in your browser:

    - [https://app.exampleproject.test/](https://app.exampleproject.test/)
    - [https://app.exampleproject.test/backend/](https://app.exampleproject.test/backend/)
    - [https://rabbitmq.exampleproject.test/](https://rabbitmq.exampleproject.test/)
    - [https://elasticsearch.exampleproject.test/](https://elasticsearch.exampleproject.test/)

:::{note}
To completely destroy the ``exampleproject`` environment we just created, run ``roll env down -v`` to tear down the project's Docker containers, volumes, etc.
:::

---

## Multi-Store Configuration

RollDev provides the `multistore` command to easily manage Magento multi-store setups with multiple domains.

### Quick Setup

1. Create a configuration file at `.roll/stores.json`:

    ```json
    {
      "stores": {
        "store-nl.test": "store_nl",
        "store-be.test": "store_be",
        "store-de.test": "store_de"
      },
      "run_type": "store"
    }
    ```

2. Initialize the multi-store configuration:

    ```bash
    roll multistore init
    ```

3. Restart the environment:

    ```bash
    roll env up
    ```

### Configuration Options

The `.roll/stores.json` file supports the following options:

| Option | Description |
|--------|-------------|
| `stores` | Object mapping hostnames to Magento store/website codes |
| `run_type` | Either `"store"` or `"website"` (default: `"store"`) |

Use an empty string `""` for the store code to use the default store:

```json
{
  "stores": {
    "main-store.test": "",
    "secondary.test": "secondary_store"
  },
  "run_type": "store"
}
```

### Commands

| Command | Description |
|---------|-------------|
| `roll multistore init` | Generate configs and sign SSL certificates for all domains |
| `roll multistore refresh` | Regenerate configs without re-signing certificates |
| `roll multistore list` | Show current store configuration and status |

### Generated Files

The `multistore` command automatically generates:

- `.roll/roll-env.yml` - Traefik routing rules, nginx volume mounts, and extra_hosts
- `.roll/nginx/stores.map` - Nginx hostname-to-store-code mapping

### Updating Stores

When you need to add or modify stores:

1. Edit `.roll/stores.json`
2. Run `roll multistore refresh`
3. Restart nginx: `roll env restart nginx`

### Example: Complete Multi-Store Setup

```bash
# Create stores.json
cat > .roll/stores.json << 'EOF'
{
  "stores": {
    "mystore-nl.test": "nl_store",
    "mystore-be.test": "be_store",
    "mystore-de.test": "de_store"
  },
  "run_type": "store"
}
EOF

# Initialize (signs certificates and generates config)
roll multistore init

# Start environment
roll env up

# Verify configuration
roll multistore list
```

### Troubleshooting

If you encounter routing issues after adding new domains:

1. Verify certificates exist: `ls ~/.roll/ssl/certs/`
2. Check traefik config: `roll env config | grep -A5 traefik`
3. Restart traefik to reload certificates: `roll svc up traefik`
4. Restart the environment: `roll env down && roll env up`
