# Environment Duplication

The `duplicate` command allows you to create a complete copy of your current Roll environment with a new name. This is useful for creating staging environments, testing upgrades, or setting up multiple development branches.

## Basic Usage

```bash
roll duplicate <new-environment-name>
```

**Example:**
```bash
roll duplicate moduleshop-staging
```

This creates a new environment called `moduleshop-staging` in a sibling directory with all data, source code, and configuration copied from the current environment.

## What Gets Duplicated

The duplication process includes:

- **Source Code**: All application files and directories
- **Database**: Complete database backup and restore
- **Configuration**: Environment configuration files (`.env.roll`, etc.)
- **SSL Certificates**: New wildcard certificates for the new domain
- **Container Volumes**: All persistent data volumes

## Command Options

### Basic Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help information |
| `-q, --quiet` | Suppress output messages |
| `-f, --force` | Overwrite existing target directory |
| `--dry-run` | Preview what would be done without executing |
| `--verbose` | Show detailed progress information |

### Duplication Control

| Option | Description |
|--------|-------------|
| `--no-source` | Don't copy source code (data-only duplication) |
| `--no-start` | Don't start the new environment automatically |
| `--no-urls` | Skip updating database URLs |
| `--no-magento-commands` | Skip running Magento post-duplication commands |

### Security Options

| Option | Description |
|--------|-------------|
| `--encrypt` | Encrypt backup with interactive password prompt |
| `--encrypt=password` | Encrypt backup with specified password |

## Examples

### Basic Duplication
```bash
roll duplicate my-project-staging
```
Creates a complete copy with automatic SSL certificate generation and URL updates.

### Encrypted Duplication
```bash
roll duplicate my-project-backup --encrypt
```
Creates an encrypted backup during duplication (prompts for password).

### Preview Mode
```bash
roll duplicate my-project-test --dry-run
```
Shows what would be done without actually performing the duplication.

### Data-Only Duplication
```bash
roll duplicate my-project-dataonly --no-source
```
Duplicates only the data (database, volumes) without copying source code.

### Force Overwrite
```bash
roll duplicate existing-project --force
```
Overwrites an existing environment directory.

## Duplication Process

The duplication process follows these steps:

1. **Create Backup**: Creates a backup of the current environment's data
2. **Setup Directory**: Creates new environment directory and copies source code
3. **Copy Backup**: Transfers backup files to the new environment
4. **Restore Data**: Restores database and volume data in the new environment
5. **Generate Certificates**: Creates new SSL certificates for the new domain
6. **Update URLs**: Updates database URLs to match the new environment
7. **Start Environment**: Starts the new environment (unless `--no-start` is used)

## Environment-Specific Behavior

### Magento 2

For Magento 2 environments, the duplication process includes:

- Updates `core_config_data` table for base URLs
- Updates `app/etc/env.php` configuration
- Runs post-duplication commands:
  - `app:config:import`
  - `setup:upgrade`
  - `setup:di:compile`
  - `cache:clean`
  - `cache:flush`

### Magento 1

Updates `core_config_data` table for base and secure URLs.

### WordPress

Updates `wp_options` table for `home` and `siteurl` options.

## Directory Structure

When you duplicate an environment, the new environment is created as a sibling directory:

```
parent-directory/
├── original-project/          # Current environment
└── new-environment-name/      # Duplicated environment
```

## URL Pattern

The new environment will be accessible at:
- **Default**: `https://app.new-environment-name.test`
- **Custom Domain**: Based on `TRAEFIK_DOMAIN` in `.env.roll`

## Excluded Files and Directories

The following are excluded from source code duplication:

- `.roll/backups/` (backup files)
- `var/cache/`, `var/log/`, `var/session/`, `var/tmp/` (Magento cache/logs)
- `storage/logs/`, `storage/framework/cache/` (Laravel cache/logs)
- `node_modules/` (Node.js dependencies)
- `vendor/bin/` (Composer binaries)
- `*.log` (Log files)

## Error Handling

The duplication process includes robust error handling:

- **Validation**: Checks environment name format and directory conflicts
- **Backup Verification**: Ensures backup creation succeeds before proceeding
- **Step-by-Step**: Each step is validated before continuing
- **Rollback**: Failed duplications can be cleaned up manually

## Best Practices

### Naming Conventions
Use descriptive names that indicate the purpose:
```bash
roll duplicate myproject-staging
roll duplicate myproject-upgrade-test
roll duplicate myproject-feature-branch
```

### Pre-Duplication Checks
1. Ensure your current environment is in a stable state
2. Stop any running processes that might interfere
3. Consider the disk space requirements (duplication roughly doubles space usage)

### Post-Duplication Tasks
1. Verify the new environment starts correctly
2. Test critical functionality
3. Update any hardcoded URLs or paths specific to your use case
4. Configure any additional services or integrations

## Troubleshooting

### Common Issues

**"Directory already exists" error:**
```bash
roll duplicate myproject-copy --force
```

**Backup creation fails:**
- Check disk space availability
- Ensure database is accessible
- Verify environment is properly started

**URL updates don't work:**
```bash
# Manually update URLs after duplication
cd ../new-environment-name
roll env up -d
roll db connect
# Run SQL updates manually
```

**SSL certificate issues:**
```bash
cd ../new-environment-name
roll sign-certificate "*.new-environment-name.test"
```

## Performance Considerations

- **Disk Space**: Duplication requires approximately 2x the original environment size
- **Duration**: Process time depends on database size and number of files
- **Memory**: Backup creation and restoration are memory-intensive operations
- **I/O**: Intensive disk operations during file copying and database operations

## Security Notes

- Use `--encrypt` for sensitive production data
- Review database contents before duplication (remove sensitive data if needed)
- Ensure proper file permissions on the duplicated environment
- Consider using `--no-source` if you only need data duplication

## Integration with Other Commands

The duplicate command works seamlessly with other Roll commands:

```bash
# After duplication, switch to new environment
cd ../new-environment-name

# Use all normal Roll commands
roll shell
roll env logs
roll magento cache:flush
roll backup create
``` 