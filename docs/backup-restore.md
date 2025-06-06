# Backup and Restore

RollDev provides powerful backup and restore capabilities for your development environments. The system automatically detects enabled services and creates comprehensive backups with integrity verification, metadata tracking, and flexible restoration options.

> **Quick Reference**: See the [Backup & Restore Quick Reference](backup-restore-quick-reference.md) for a command cheat sheet.

## Overview

The backup and restore system supports:
- **Automatic Service Detection**: Detects all enabled services in your environment
- **Multiple Compression Formats**: gzip, xz, lz4, or no compression
- **Encryption Support**: GPG encryption with passphrase protection
- **Progress Tracking**: Real-time progress indicators
- **Integrity Verification**: Automatic checksum generation and verification
- **Rich Metadata**: JSON metadata with environment and service information
- **Selective Operations**: Backup/restore specific services only
- **Legacy Compatibility**: Works with old backup formats

## Supported Services

The backup system automatically detects and supports:

| Service | Description | Volume Name |
|---------|-------------|-------------|
| Database | MySQL, MariaDB, PostgreSQL | `dbdata` |
| Redis | Redis cache | `redis` |
| Dragonfly | Dragonfly cache | `dragonfly` |
| Elasticsearch | Search engine | `esdata` |
| OpenSearch | Search engine | `osdata` |
| MongoDB | Document database | `mongodb` |
| RabbitMQ | Message queue | `rabbitmq` |
| Varnish | HTTP cache | `varnish` |

## Backup Commands

### Basic Usage

```bash
# Backup all enabled services (default)
roll backup

# Backup all services explicitly
roll backup all

# Backup specific services
roll backup db                    # Database only
roll backup redis                 # Redis only
roll backup elasticsearch         # Elasticsearch only
roll backup mongodb               # MongoDB only
roll backup config                # Configuration files only
```

### Advanced Options

```bash
# Compression options
roll backup --compression=gzip    # Default compression
roll backup --compression=xz      # High compression
roll backup --compression=lz4     # Fast compression
roll backup --no-compression      # No compression

# Include additional data
roll backup --include-source      # Include source code
roll backup --include-logs        # Include log files (excluded by default)

# Encryption
roll backup --encrypt=mypassword  # Encrypt with GPG

# Named backups
roll backup --name="pre-upgrade" --description="Before major update"

# Quiet operation
roll backup --quiet

# Retention management
roll backup --retention=7         # Auto-cleanup after 7 days
```

### Management Commands

```bash
# List available backups
roll backup list

# Show backup information
roll backup info 1672531200

# Clean up old backups
roll backup clean 30              # Remove backups older than 30 days
```

## Restore Commands

### Basic Usage

```bash
# Restore latest backup (all services)
roll restore

# Restore specific backup by timestamp
roll restore 1672531200

# Restore with explicit backup ID
roll restore --backup-id=1672531200
```

### Selective Restoration

```bash
# Restore specific services only
roll restore --services=db,redis

# Restore without configuration files
roll restore --no-config

# Restore specific backup with service selection
roll restore 1672531200 --services=db
```

### Advanced Options

```bash
# Preview what would be restored
roll restore --dry-run

# Force overwrite existing volumes
roll restore --force

# Decrypt encrypted backup
roll restore --decrypt=mypassword

# Quiet operation
roll restore --quiet

# Skip integrity verification
roll restore --no-verify

# Skip legacy migration
roll restore --no-legacy-migration
```

## Full Environment Restore

A full backup created with `roll backup --include-source` can be restored
directly using the `restore-full` command. If you don't specify an output
directory, the archive is extracted in the current path.

```bash
# Restore to the current directory
roll restore-full backup_envname_1672531200.tar.gz

# Restore to a new environment path
roll restore-full backup_envname_1672531200.tar.gz /path/to/newenv

# Quiet forced restore of a specific archive
roll restore-full --quiet --force backup_envname_1672531200.tar.gz /path/to/env

# Restore encrypted backup with password
roll restore-full --decrypt=mypassword backup_envname_1672531200.tar.gz /path/to/env

# Restore encrypted backup with prompt
roll restore-full --decrypt backup_envname_1672531200.tar.gz
```

## Backup Structure

RollDev creates organized backup archives with the following structure:

```
.roll/backups/
├── 1672531200/                    # Timestamp-based directory
│   ├── volumes/                   # Service volume backups
│   │   ├── db.tar.gz
│   │   ├── redis.tar.gz
│   │   └── elasticsearch.tar.gz
│   ├── config/                    # Configuration files
│   │   ├── .env.roll
│   │   ├── app/etc/env.php
│   │   └── auth.json
│   └── metadata/                  # Backup metadata
│       ├── backup.json            # Rich metadata
│       └── checksums.sha256       # Integrity checksums
├── backup_envname_1672531200.tar.gz  # Final compressed archive
└── latest.tar.gz -> backup_envname_1672531200.tar.gz
```

## Configuration Files

The system automatically backs up relevant configuration files:

### Framework-Agnostic Files
- `.env.roll` - RollDev environment configuration
- `.env` - Application environment file
- `composer.json` and `composer.lock` - PHP dependencies
- `auth.json` - Composer authentication

### Magento-Specific Files
- `app/etc/env.php` - Magento configuration
- `.roll/roll-env.yml` - Docker Compose overrides

### Framework-Specific Files
- `config/database.yml` - Rails database configuration
- Other framework-specific configuration files

## Metadata and Integrity

Each backup includes comprehensive metadata:

```json
{
  "timestamp": 1672531200,
  "date": "2023-01-01T12:00:00+00:00",
  "environment": "myproject",
  "version": "0.2.6.5",
  "services": ["db:mysql:dbdata", "redis:redis:redis"],
  "compression": "gzip",
  "encrypted": false,
  "name": "pre-upgrade",
  "description": "Before major update",
  "include_source": false,
  "exclude_logs": true,
  "docker_compose_version": "2.36.2",
  "platform": "Darwin",
  "architecture": "arm64"
}
```

## Examples

### Daily Development Backup

```bash
# Quick backup of current state
roll backup --quiet --name="daily-$(date +%Y%m%d)"
```

### Pre-Deployment Backup

```bash
# Comprehensive backup before deployment
roll backup all --include-source --name="pre-deploy-v2.1" \
  --description="Full backup before version 2.1 deployment"
```

### Database Migration Backup

```bash
# Database-only backup before migration
roll backup db --name="pre-migration" --compression=xz
```

### Emergency Restore

```bash
# Quick restore of latest backup
roll restore --force

# Restore specific service only
roll restore --services=db --force

# Preview restore without changes
roll restore --dry-run
```

### Encrypted Backup for Production Data

```bash
# Create encrypted backup
roll backup --encrypt=secretpassword --compression=xz \
  --name="production-data"

# Restore encrypted backup
roll restore --decrypt=secretpassword --backup-id=1672531200
```

## Automation

### Scheduled Backups

Add to your crontab for automated backups:

```bash
# Daily backup at 2 AM with 7-day retention
0 2 * * * cd /path/to/project && roll backup --quiet --retention=7

# Weekly full backup with source code
0 2 * * 0 cd /path/to/project && roll backup --include-source --quiet \
  --name="weekly-$(date +%Y%W)" --retention=30
```

### CI/CD Integration

```bash
# Pre-deployment backup in CI/CD
roll backup --name="pre-deploy-${CI_COMMIT_SHA:0:8}" --quiet

# Post-deployment verification
roll backup info $(roll backup list | tail -1 | awk '{print $9}' | grep -o '[0-9]\{10\}')
```

## Troubleshooting

### Common Issues

**Backup fails with permission errors:**
```bash
# Ensure Docker is running and accessible
docker system info

# Check volume permissions
docker volume inspect ${ROLL_ENV_NAME}_dbdata
```

**Restore fails with existing volumes:**
```bash
# Use force flag to overwrite
roll restore --force

# Or remove volumes manually
docker volume rm ${ROLL_ENV_NAME}_dbdata
```

**Encrypted backup won't decrypt:**
```bash
# Ensure GPG is installed
which gpg

# Verify passphrase
roll restore --decrypt=yourpassword --dry-run
```

### Best Practices

1. **Regular Backups**: Create automated daily backups with retention policies
2. **Test Restores**: Periodically test restore procedures in development
3. **Use Descriptive Names**: Name backups with meaningful descriptions
4. **Verify Integrity**: Always verify backup integrity before critical operations
5. **Secure Passwords**: Use strong passphrases for encrypted backups
6. **Monitor Storage**: Keep an eye on backup storage usage
7. **Document Procedures**: Document your backup and restore procedures for your team

### Performance Tips

1. **Exclude Logs**: Use `--exclude-logs` (default) to reduce backup size
2. **Choose Compression**: Use `lz4` for speed, `xz` for size, `gzip` for balance
3. **Selective Backups**: Backup only what you need with service selection
4. **Parallel Operations**: Enable parallel operations for faster backups (default)
5. **Local Storage**: Keep backups on fast local storage for quick access

## Legacy Migration

The restore command automatically handles migration from legacy formats:

- **Warden to Roll**: Automatically converts Warden environments to Roll format
- **Old Backup Format**: Supports backups created with the previous backup system
- **Configuration Migration**: Updates configuration files during restoration

This ensures seamless upgrades and backward compatibility with existing backup archives.

# Encryption Support

RollDev supports GPG encryption for backup files using AES256 cipher with passphrase protection:

```bash
# Create encrypted backup with explicit password
roll backup --encrypt=mypassword

# Create encrypted backup with interactive prompt (recommended)
roll backup --encrypt

# Restore encrypted backup with explicit password
roll restore --decrypt=mypassword

# Restore encrypted backup with interactive prompt (recommended)
roll restore --decrypt

# Automatic detection - encrypted backups prompt for password automatically
roll restore 1672531200
```

## Encryption Behavior

- **File Encryption**: All `.tar.gz` files are encrypted to `.tar.gz.gpg` format
- **Checksum Updates**: Checksums are automatically recalculated for encrypted files
- **Verification**: Integrity verification works seamlessly with encrypted backups
- **Security**: Uses GPG with AES256 cipher and compression
- **Auto-Detection**: Restore automatically detects encrypted backups and prompts for password
- **Interactive Prompts**: Use `--encrypt` or `--decrypt` without password to avoid command history

## Security Best Practices

```bash
# Recommended: Use interactive prompts to avoid passwords in command history
roll backup --encrypt                    # Will prompt securely for password
roll restore --decrypt                   # Will prompt securely for password

# Avoid: Passwords visible in command history and process lists
roll backup --encrypt=mysecretpassword   # NOT recommended for production
```

## Troubleshooting Encryption

If you encounter issues with encrypted backups:

```bash
# Skip verification for problematic encrypted backups
roll backup --encrypt --no-verify

# Check GPG availability
which gpg

# Restore with explicit decryption
roll restore --decrypt=password --backup-id=1672531200

# Test decryption in dry-run mode
roll restore --decrypt --dry-run
```

**Note**: Encrypted backups require the same passphrase for restoration. Store your passphrase securely!

## Backup Structure 