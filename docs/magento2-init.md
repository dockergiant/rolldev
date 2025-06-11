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

### Magento 2.4.8+
- **PHP**: 8.3
- **Database**: MariaDB 11.4
- **Search**: OpenSearch 2.19 (with Elasticsearch 7.17 fallback)
- **Cache**: Valkey 8 (Redis fork)
- **Queue**: RabbitMQ 4.1
- **HTTP Cache**: Varnish 7.7
- **Package Manager**: Composer 2
- **JavaScript**: Node.js 19

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
- Configures OpenSearch version 2.19
- Uses `opensearch` hostname for connections

### Fallback Mechanism
If OpenSearch installation fails:
- Automatically falls back to Elasticsearch 7.17
- Provides manual configuration instructions
- Maintains full functionality with fallback

### Manual OpenSearch Configuration
To manually switch to OpenSearch after installation:

```bash
roll shell
bin/magento config:set catalog/search/engine opensearch
bin/magento config:set catalog/search/opensearch_server_hostname opensearch
bin/magento config:set catalog/search/opensearch_server_port 9200
bin/magento indexer:reindex catalogsearch_fulltext
```

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

#### Search Engine Fallback
**Warning**: `Installation used Elasticsearch fallback`
**Info**: This is normal for OpenSearch configurations that fail. The project will work with Elasticsearch. You can manually configure OpenSearch later using the provided commands.

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

# Import database dump
pv dump.sql.gz | gunzip -c | roll db import

# Export database
roll db export > backup.sql
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