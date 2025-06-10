# Backup & Restore Quick Reference

## Quick Commands Cheat Sheet

### Backup Commands
```bash
# Basic backups
roll backup                    # Backup all enabled services
roll backup db                 # Database only
roll backup redis              # Redis only
roll backup config             # Configuration files only

# Advanced backups
roll backup --quiet                           # Silent operation
roll backup --compression=xz                  # High compression
roll backup --encrypt=password                # Encrypted backup
roll backup --include-source                  # Include source code
roll backup --name="pre-upgrade"              # Named backup
roll backup --retention=7                     # Auto-cleanup after 7 days

# Management
roll backup list               # List all backups
roll backup info 1672531200    # Show backup details
roll backup clean 30           # Remove backups older than 30 days
```

### Restore Commands
```bash
# Basic restore
roll restore                   # Restore latest backup
roll restore 1672531200        # Restore specific backup

# Advanced restore
roll restore --dry-run                        # Preview only
roll restore --force                          # Overwrite existing
roll restore --services=db,redis              # Selective restore
roll restore --no-config                      # Skip configuration
roll restore --decrypt=password               # Decrypt backup
roll restore --quiet                          # Silent operation
```

### Full Environment Restore
```bash
# Restore into a new directory
roll restore-full backup.tar.gz /path/newenv

# Restore encrypted backup with password
roll restore-full --decrypt=password backup.tar.gz /path/newenv

# Restore encrypted backup with prompt
roll restore-full --decrypt backup.tar.gz /path/newenv
```

## Common Use Cases

### Daily Development
```bash
# Quick backup before major changes
roll backup --name="pre-refactor" --quiet

# Database backup before migration
roll backup db --compression=xz
```

### Emergency Recovery
```bash
# Quick restore with force
roll restore --force

# Preview what would be restored
roll restore --dry-run

# Restore only database
roll restore --services=db --force
```

### Production Data
```bash
# Encrypted backup
roll backup --encrypt=strongpassword --compression=xz

# Restore encrypted backup
roll restore --decrypt=strongpassword
```

## Backup Information

### Service Types
- `db` - Database (MySQL/MariaDB/PostgreSQL)
- `redis` - Redis cache
- `dragonfly` - Dragonfly cache  
- `elasticsearch` - Elasticsearch
- `opensearch` - OpenSearch
- `mongodb` - MongoDB
- `rabbitmq` - RabbitMQ
- `varnish` - Varnish cache
- `config` - Configuration files

### Compression Options
- `gzip` - Default, good balance
- `xz` - Best compression, slower
- `lz4` - Fastest, larger files
- `none` - No compression

### File Locations
- Backups: `.roll/backups/`
- Latest: `.roll/backups/latest.tar.gz`
- Archives: `backup_<env>_<timestamp>.tar.gz`

## Tips & Tricks

### Automation
```bash
# Add to crontab for daily backups
0 2 * * * cd /path/to/project && roll backup --quiet --retention=7
```

### Size Optimization
```bash
# Small backup (no logs, high compression)
roll backup --compression=xz

# Minimal backup (config only)
roll backup config
```

### Safety Checks
```bash
# Always test restore first
roll restore --dry-run

# Verify backup integrity
roll backup info <timestamp>
```
