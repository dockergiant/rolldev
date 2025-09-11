# New Relic Monitoring

New Relic may be enabled on all environment types to provide application performance monitoring for PHP applications.

New Relic integration provides:
- **PHP APM** - Application Performance Monitoring for PHP applications with distributed tracing
- **Conditional Loading** - Zero performance impact when disabled  
- **Local Development Optimized** - Raw SQL queries and enhanced debugging for local development

## Configuration Levels

### Global Configuration (One-time setup)

Set your New Relic license key globally in `~/.roll/.env`:

```
NEWRELIC_LICENSE_KEY=your_license_key_here
```

### Project Configuration

New Relic may be enabled by adding the following to the project's `.env` file:

```
ROLL_NEWRELIC=1

# Optional: Set custom app name (defaults to "RollDev-LocalEnv-{project-name}")
NEWRELIC_APP_NAME=my-awesome-app

# Optional: Override global license key for this project  
NEWRELIC_LICENSE_KEY=project_specific_key
```

**Note**: All environment `init.env` files include a commented example of the license key variable with instructions about global configuration:

```
# New Relic license key (can be set globally in $HOME/.roll/.env)
# NEWRELIC_LICENSE_KEY=your_license_key_here
```

## Usage Examples

### Enable New Relic with Global License Key

1. Set global license key (one-time setup):
   ```bash
   echo "NEWRELIC_LICENSE_KEY=your_license_key" >> ~/.roll/.env
   ```

2. Enable for specific project:
   ```bash
   echo "ROLL_NEWRELIC=1" >> .env
   echo "NEWRELIC_APP_NAME=my-project" >> .env
   ```

3. Start/restart containers:
   ```bash
   roll up
   # or
   roll restart
   ```

### Disable New Relic

```bash
# Disable for current project  
echo "ROLL_NEWRELIC=0" >> .env
roll restart
```

## How It Works

### PHP Agent
- **Installed but not loaded** by default in all PHP-FPM containers  
- **Conditionally loaded** only when `ROLL_NEWRELIC=1`
- **Zero overhead** when disabled
- **Configuration**: Uses template at `/usr/local/etc/php/conf.d/newrelic.ini.template`
- **Auto App Naming**: Automatically generates app names using `RollDev-LocalEnv-{project-name}` pattern
- **Local Development**: Optimized with raw SQL queries, 1ms threshold, and enhanced debugging

### Configuration Precedence
1. **Project `.env`** (highest priority)
2. **Global `$HOME/.roll/.env`** (fallback) 
3. **Default values** (disabled)

## Troubleshooting

### Check if New Relic is Enabled

```bash
# Check PHP configuration
roll exec php-fpm php -m | grep newrelic

# Check environment variables  
roll exec php-fpm env | grep NEWRELIC

# Check New Relic logs
roll exec php-fpm tail -f /var/log/newrelic/php_agent.log

# Check daemon logs
roll exec php-fpm tail -f /var/log/newrelic/newrelic-daemon.log
```

### Common Issues

**"New Relic enabled but no license key"**
- Ensure `NEWRELIC_LICENSE_KEY` is set in project `.env` or global `~/.roll/.env`

**"PHP extension not loading"**  
- Verify `ROLL_NEWRELIC=1` in project `.env`
- Restart containers: `roll restart`

**"Transaction data too large"**
- New Relic daemon shows "maximum message size exceeded" errors
- This is normal for large database queries with many segments
- Data is still captured but trace details may be limited

## Environment Variables Reference

| Variable | Scope | Default | Description |
|----------|-------|---------|-------------|
| `ROLL_NEWRELIC` | Project | `0` | Enable/disable New Relic (0/1) |
| `NEWRELIC_LICENSE_KEY` | Global/Project | - | New Relic license key |
| `NEWRELIC_APP_NAME` | Project | `RollDev-LocalEnv-{project-name}` | Application name in New Relic |

## PHP Versions Supported

New Relic PHP agent is installed using the reliable `install-php-extensions` tool:

| PHP Version | Status |
|-------------|---------|
| 8.4+ | ✅ Supported |
| 8.3+ | ✅ Supported |
| 8.2 | ✅ Supported |
| 8.1 | ✅ Supported |
| 8.0 | ✅ Supported |
| 7.4 | ✅ Supported |
| 7.3 | ✅ Supported |
| 7.2 | ✅ Supported |
| 7.1 | ✅ Supported |
| 7.0 | ✅ Supported |
| < 7.0 | ❌ Not Supported |

## Architecture

```
Project Level:
├── .env (ROLL_NEWRELIC=1, NEWRELIC_APP_NAME=app)
│
Global Level:
├── ~/.roll/.env (NEWRELIC_LICENSE_KEY=xxx)
│
Docker Stack:
├── PHP-FPM (conditional New Relic PHP extension)
├── PHP-Debug (conditional New Relic PHP extension)
└── Environment Templates (ROLL_NEWRELIC=0 by default)
```

This integration follows Roll Docker Stack patterns for optional services while providing PHP application performance monitoring capabilities optimized for local development debugging.