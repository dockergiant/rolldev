# Magento 2 Init - Quick Reference

## Basic Commands

```bash
# Create project with latest version
roll magento2-init mystore

# Create with specific version
roll magento2-init mystore 2.4.7

# Create with patch version
roll magento2-init mystore 2.4.7-p3

# Create with OpenSearch (2.4.8+)
roll magento2-init mystore 2.4.8

# Create in custom directory
roll magento2-init mystore 2.4.7 ~/Sites/
```

## Prerequisites Checklist

- [ ] RollDev services running: `roll svc up`
- [ ] Magento credentials configured:
  ```bash
  composer global config http-basic.repo.magento.com <public_key> <private_key>
  ```

## Post-Installation URLs

| Service | URL |
|---------|-----|
| Frontend | `https://app.<project>.test/` |
| Admin | `https://app.<project>.test/shopmanager/` |
| RabbitMQ | `https://rabbitmq.<project>.test/` |
| Search | `https://elasticsearch.<project>.test/` |

## Version Matrix (Auto-Selected)

| Magento | PHP | MariaDB | Search | Redis | RabbitMQ |
|---------|-----|---------|--------|-------|----------|
| 2.4.8+ | 8.3 | 11.4 | OpenSearch 2.19 | Valkey 8 | 4.1 |
| 2.4.7 | 8.3 | 10.6+ | Elasticsearch 7.17 | Redis 7.2 | 3.13 |
| 2.4.6 | 8.2 | 10.6 | Elasticsearch 7.17 | Redis 7.0+ | 3.9 |

## Common Post-Install Tasks

```bash
# Enter project directory
cd <project_name>

# Access shell
roll shell

# Check admin credentials
cat admin-credentials.txt

# Run Magento commands
roll cli bin/magento cache:flush
roll cli bin/magento indexer:reindex
```

## Troubleshooting

```bash
# Check service status
roll env ps

# View logs
roll env logs --tail 50

# Restart services
roll env restart

# Test connectivity
roll db connect -e "SELECT 1;"
roll redis ping
```

## OpenSearch Manual Config (if needed)

```bash
roll shell
bin/magento config:set catalog/search/engine opensearch
bin/magento config:set catalog/search/opensearch_server_hostname opensearch
bin/magento config:set catalog/search/opensearch_server_port 9200
bin/magento indexer:reindex catalogsearch_fulltext
```

## Help

```bash
# Command help
roll magento2-init --help

# Full documentation
https://rolldev.readthedocs.io/magento2-init/
``` 