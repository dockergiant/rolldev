# Magento 2 Project Initialization

## Overview

The `magento2-init` command provides a fully automated way to scaffold new Magento 2 projects from scratch. Introduced in RollDev 3.2, this command eliminates the need for manual setup steps and ensures consistent, optimized project configurations.

## Quick Start

```bash
# Create a new Magento 2 project with default settings
roll magento2-init mystore

# Create with specific Magento version
roll magento2-init mystore 2.4.7-p3

# Create in specific directory
roll magento2-init mystore 2.4.8 ~/Sites/
```

## Command Syntax

```bash
roll magento2-init <project_name> [magento_version] [target_directory]
```

### Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| `project_name` | Yes | Name of the project (lowercase, alphanumeric, hyphens only) | - |
| `magento_version` | No | Magento version to install | `2.4.x` (latest) |
| `target_directory` | No | Directory to create project in | Current directory |

### Supported Magento Versions

- **2.4.6+** (minimum supported)
- **2.4.7** and patch versions (`2.4.7-p1`, `2.4.7-p3`, etc.)
- **2.4.8+** with OpenSearch support
- **2.4.x** for latest stable version

## Automated Setup Process

The command performs 12 automated steps:

### 1. Project Directory Creation
- Creates the project directory structure
- Validates project name format

### 2. Software Version Compatibility
- Automatically determines compatible software versions
- Configures PHP, MariaDB, search engine, Redis, RabbitMQ, Varnish versions

### 3. Environment Initialization  
- Creates `.env.roll` configuration file
- Sets up RollDev environment for Magento 2

### 4. Version-Specific Configuration
- Updates environment file with compatible software versions
- Configures OpenSearch for 2.4.8+ or Elasticsearch for older versions
- Sets up Redis/Valkey based on version requirements

### 5. SSL Certificate Generation
- Creates and signs SSL certificate for `<project>.test` domain
- Enables HTTPS for local development

### 6. Docker Services Startup
- Starts all required Docker containers
- Database, search engine, Redis, RabbitMQ, Varnish, web server

### 7. Service Health Checks
- Waits for database connectivity
- Verifies search engine cluster health  
- Confirms Redis availability

### 8. Magento Project Files
- Downloads Magento via Composer
- Uses `magento/project-community-edition` meta-package
- Sets proper file permissions

### 9. Magento Installation
- Runs `setup:install` with optimized parameters
- Configures database, Redis, search engine connections
- Sets up RabbitMQ for message queues

### 10. Application Configuration
- Sets base URLs for frontend and admin
- Configures SSL and security settings
- Optimizes cache and search settings

### 11. Initial Indexing
- Runs all Magento indexers
- Flushes cache for clean start

### 12. Admin User & 2FA Setup
- Creates admin user with random password
- Configures Two-Factor Authentication (2FA)
- Generates TOTP QR code for mobile authenticator apps

## Software Compatibility Matrix

The command automatically configures compatible software versions based on the Magento version:

### Magento 2.4.9+ (and the default `2.4.x`)
- **PHP**: 8.5
- **Database**: MariaDB 12.3
- **Search**: OpenSearch 3.5
- **Cache and sessions**: Valkey 9.0 (`REDIS_DISTRIBUTION=valkey`), installed with the `valkey` setup flags
- **Queue**: RabbitMQ 4.3
- **HTTP Cache**: Varnish 8.0
- **Package Manager**: Composer 2
- **JavaScript**: Node.js 24

### Magento 2.4.8
- **PHP**: 8.4
- **Database**: MariaDB 11.4
- **Search**: OpenSearch 3.5
- **Cache and sessions**: Valkey 8.1 (`REDIS_DISTRIBUTION=valkey`), installed with the `redis` setup flags because 2.4.8 has no `valkey` flags
- **Queue**: RabbitMQ 4.3
- **HTTP Cache**: Varnish 8.0
- **Package Manager**: Composer 2
- **JavaScript**: Node.js 24

### Magento 2.4.7
- **PHP**: 8.3
- **Database**: MariaDB 10.6+ (10.11 for p6+)
- **Search**: Elasticsearch 7.17
- **Cache**: Redis 7.2
- **Queue**: RabbitMQ 3.13
- **HTTP Cache**: Varnish 7.5+ (7.7 for p6+)
- **Package Manager**: Composer 2
- **JavaScript**: Node.js 19

### Magento 2.4.6
- **PHP**: 8.2
- **Database**: MariaDB 10.6
- **Search**: Elasticsearch 7.17
- **Cache**: Redis 7.0+ (7.2 for p8+)
- **Queue**: RabbitMQ 3.9
- **HTTP Cache**: Varnish 7.1+ (7.5 for p8+)
- **Package Manager**: Composer 2
- **JavaScript**: Node.js 19

## OpenSearch Support

For Magento 2.4.8 and later versions, the command automatically configures OpenSearch as the primary search engine:

### Automatic Configuration
- Sets `ROLL_OPENSEARCH=1` in environment
- Configures OpenSearch version 3.5
- Uses `opensearch` hostname for connections

### No Elasticsearch Fallback
If `setup:install` fails, the command stops and shows the error. It does not retry with Elasticsearch: Magento 2.4.8 and newer have no `elasticsearch7` engine, and an OpenSearch project runs no Elasticsearch service.

### Manual OpenSearch Configuration
To manually switch to OpenSearch after installation:

```bash
roll shell
bin/magento config:set catalog/search/engine opensearch
bin/magento config:set catalog/search/opensearch_server_hostname opensearch
bin/magento config:set catalog/search/opensearch_server_port 9200
bin/magento indexer:reindex catalogsearch_fulltext
```

## Mage-OS Projects

`roll mageos-init` installs [Mage-OS](https://mage-os.org) with the same steps and software stack as `magento2-init`:

```bash
# Latest Mage-OS 3.x
roll mageos-init mystore

# Specific version
roll mageos-init mystore 3.5.0
```

Each Mage-OS release is built on a Magento release, and `mageos-init` picks the software stack of that Magento version:

| Mage-OS | Built on Magento | Software stack |
|---------|------------------|----------------|
| 3.x | 2.4.9 | Same as Magento 2.4.9 |
| 1.1.0 - 2.x | 2.4.8 | Same as Magento 2.4.8 |
| 1.0.x | 2.4.6 / 2.4.7 | Not supported |

The only difference from `magento2-init`: packages come from `https://repo.mage-os.org/`, so no Magento Marketplace credentials are needed. Mage-OS includes the two-factor authentication module, so the admin user gets the same 2FA setup, with the QR code URL and backup codes in `admin-credentials.txt`.

### Migrating an Existing Magento Project to Mage-OS

`roll mageos-migrate` migrates a project you already run in RollDev, following the [Mage-OS migration guide](https://mage-os.org/get-started/migration-guide/). It takes a full backup first, so you can go back with one command.

```bash
# Check whether this project can migrate, change nothing
roll mageos-migrate --dry-run

# Back up, migrate, and finish the guide
roll mageos-migrate
```

Only run this against a local or staging environment, never against production.

**What it does:**

1. Starts the environment when it is down, because the checks run inside the php-fpm container.
2. Checks, before the backup, that `bin/magento --version` reports 2.4.9, that PHP is 8.3 or newer, that `app/etc/env.php` and `bin/magento` exist, and that the project runs in developer mode. It offers to switch the mode for you.
3. Downloads the official migration script and reports its origin, line count and sha256. The file stays in `.roll/tmp/`, so you can read what ran.
4. Runs `roll backup all`, which stops the environment, and reports the backup id.
5. Starts the environment again and waits for the healthchecks.
6. Runs the migration script as `www-data` in the php-fpm container. The script swaps every `magento/*` package for `mage-os/*`, reinstalls the base files, flushes Redis, clears `generated/` and the static files, and runs `setup:upgrade`.
7. Finishes step 3 of the guide: `setup:di:compile`, `setup:static-content:deploy -f`, `indexer:reindex` and `cache:flush`.
8. Reports the new version, which now says Mage-OS.

**Requirements the script itself sets:** Magento 2.4.9 exactly, any patch release, and PHP 8.3 or newer. A 2.4.8 project has to go to 2.4.9 first. The current script migrates to Mage-OS 3.5.0.

**If a step fails,** every message repeats the backup id, so you go back with `roll restore <backup-id>`. Once you have fixed the cause, `roll mageos-migrate --skip-backup` retries without making a second backup.

**Options:** `--dry-run`, `-y`, `--skip-backup`, `--no-security-blocking` (passed to the script when a composer advisory blocks the update), `--script-ref=<branch|tag|commit>` to pin the script version, `--script=<path>` to run your own copy, and `--developer-mode` to switch the mode without being asked. Run `roll mageos-migrate --help` for the full list.

## Prerequisites

### Required Setup
1. **RollDev Services**: Must be running (`roll svc up`)
2. **Magento Marketplace Credentials**: Configure globally:
   ```bash
   composer global config http-basic.repo.magento.com <username> <password>
   ```

### Magento Marketplace Authentication
To obtain credentials:
1. Visit [Magento Marketplace](https://marketplace.magento.com/)
2. Go to My Profile → Access Keys
3. Generate new Access Key
4. Use **Public Key** as username and **Private Key** as password

## Post-Installation

### Access URLs
After successful installation, your project will be available at:

- **Frontend**: `https://app.<project_name>.test/`
- **Admin Panel**: `https://app.<project_name>.test/shopmanager/`
- **RabbitMQ Management**: `https://rabbitmq.<project_name>.test/`
- **Elasticsearch/OpenSearch**: `https://elasticsearch.<project_name>.test/` or `https://opensearch.<project_name>.test/`

### Admin Credentials
Check the `admin-credentials.txt` file in your project root for:
- Admin username and password
- 2FA setup URL
- QR code URL for mobile authenticator apps
- Backup codes for emergency access

### 2FA Setup
1. Open the QR code URL in your browser
2. Scan with authenticator app (Google Authenticator, Authy, etc.)
3. Use generated codes to log into admin panel

## Examples

### Basic Project Creation
```bash
# Create with latest Magento version
roll magento2-init mystore
cd mystore
```

### Specific Version
```bash
# Create with Magento 2.4.7
roll magento2-init ecommerce-site 2.4.7
cd ecommerce-site
```

### Patch Version
```bash
# Create with specific patch version
roll magento2-init secure-shop 2.4.7-p3
cd secure-shop
```

### Custom Location
```bash
# Create in specific directory
roll magento2-init client-project 2.4.8 ~/Sites/clients/
cd ~/Sites/clients/client-project
```

### OpenSearch Project
```bash
# Create with OpenSearch (2.4.8+)
roll magento2-init modern-store 2.4.8
cd modern-store
```

## Troubleshooting

### Common Issues

#### Composer Authentication
**Error**: `Could not authenticate package information`
**Solution**: Configure Magento Marketplace credentials:
```bash
composer global config http-basic.repo.magento.com <public_key> <private_key>
```

#### Service Connectivity
**Error**: `Database/Redis/Search engine not ready`
**Solution**: Ensure services are running:
```bash
roll env up
roll env logs
```

#### Permission Issues
**Error**: `Permission denied` during installation
**Solution**: Check Docker permissions and volume mounts:
```bash
roll env restart
```

#### Installation Failed
**Error**: `Magento installation failed. Check the setup:install output above.`
**Solution**: The `setup:install` output above that line names the cause. Check that the search engine and cache are running:
```bash
roll env ps
roll env logs opensearch
roll redis ping
```

### Debug Commands

Check service status:
```bash
roll env ps
roll env logs --tail 50
```

Verify database connectivity:
```bash
roll db connect -e "SELECT 1;"
```

Check search engine health:
```bash
roll cli curl -f "http://elasticsearch:9200/_cluster/health"
roll cli curl -f "http://opensearch:9200/_cluster/health"
```

Test Redis connection:
```bash
roll redis ping
```

## Environment Management

### Starting/Stopping
```bash
# Start environment
roll env up

# Stop environment  
roll env stop

# Restart environment
roll env restart

# Remove environment completely
roll env down -v
```

### Shell Access
```bash
# Enter project shell
roll shell

# Run single command
roll cli bin/magento cache:flush
```

### Database Operations
```bash
# Connect to database
roll db connect

# Import database dump (pv shows progress; without it: gunzip -c dump.sql.gz | roll db import)
pv dump.sql.gz | gunzip -c | roll db import

# Export database
roll db dump > backup.sql
```

## Performance Tips

### Development Mode
The installation automatically sets developer mode for optimal development:
- Disables block and page cache
- Enables file-based generation
- Shows detailed error messages

### Production Simulation
To test production-like performance:
```bash
roll shell
bin/magento deploy:mode:set production
bin/magento static:content:deploy
bin/magento indexer:reindex
```

### Cache Management
```bash
# Flush all caches
roll cli bin/magento cache:flush

# Enable/disable specific caches
roll cli bin/magento cache:enable block_html
roll cli bin/magento cache:disable full_page
```

## Advanced Configuration

### Custom Environment Variables
Modify `.env.roll` after installation for custom configurations:

```bash
# Enable additional services
ROLL_BLACKFIRE=1
ROLL_MAGEPACK=1
ROLL_SELENIUM=1

# Adjust service versions
PHP_VERSION=8.4
ELASTICSEARCH_VERSION=8.0
```

### Multi-Store Setup
Configure additional domains after installation:
```bash
roll sign-certificate store2.test
# Configure stores in Magento admin
```

### Custom SSL Certificates
```bash
# Sign additional certificates
roll sign-certificate api.myproject.test
roll sign-certificate admin.myproject.test
```

---

*For more information about RollDev environments and customization, see the [Environment Types](environments/types.md) and [Customization](environments/customizing.md) documentation.* 