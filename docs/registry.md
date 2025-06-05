# Command Registry System

The Roll Docker Stack includes a powerful command registry system that provides automatic command discovery, organization, and management capabilities. This system modernizes command handling while maintaining full backward compatibility.

## Overview

The registry system automatically discovers and catalogs all Roll commands from multiple directories, providing:

* **Automatic command discovery** from multiple search paths
* **Priority-based command resolution** for overrides and customization
* **Command categorization and metadata extraction**
* **Environment-specific command loading**
* **Comprehensive command inspection and validation tools**

## Registry Commands

All registry operations are accessed through the `roll registry` command:

```bash
roll registry <command> [options]
```

### List Commands

Display all registered commands:

```bash
roll registry list
```

Filter commands by name pattern:

```bash
roll registry list config
```

Filter commands by category:

```bash
roll registry list "" environment
```

### Browse by Category

View commands organized by category:

```bash
roll registry categories
```

Show commands in a specific category:

```bash
roll registry categories environment
```

### Command Information

Get detailed information about a specific command:

```bash
roll registry info config
```

This displays:
* Command file path
* Help file path
* Category
* Priority level
* Description

### Search Commands

Search commands by name or description:

```bash
roll registry search database
roll registry search ssl
```

### Registry Statistics

View registry statistics and command counts:

```bash
roll registry stats
```

### Validate Registry

Check registry integrity and validate all command files:

```bash
roll registry validate
```

This checks for:
* Missing command files
* Missing help files (warnings only)
* Registry consistency

### Export Commands

Export command list in various formats:

```bash
# Simple list (default)
roll registry export simple

# JSON format
roll registry export json

# CSV format
roll registry export csv
```

### View Search Paths

Display command search paths and their priorities:

```bash
roll registry paths
```

### Refresh Registry

Refresh the command registry cache:

```bash
roll registry refresh
```

## Command Discovery

The registry system searches for commands in multiple directories with priority-based resolution:

### Search Path Priority

1. **Priority 1**: Project-local commands (`.roll/commands` in project directory)
2. **Priority 1**: Environment-specific commands (`~/.roll/reclu/{env_type}`)
3. **Priority 2**: User home commands (`~/.roll/commands`)
4. **Priority 3**: User reclu commands (`~/.roll/reclu`)
5. **Priority 4**: System commands (`{roll_install}/commands`)

Lower priority numbers have higher precedence. This allows for easy command customization and overrides.

### Environment-Specific Discovery

The registry automatically includes environment-specific commands when an environment is loaded:

* Commands from `~/.roll/reclu/{environment_type}` (e.g., `~/.roll/reclu/magento2`)
* Commands from `{roll_install}/commands/{environment_type}`
* Project-local commands from `.roll/commands`

## Command Categories

Commands are automatically categorized based on their help file metadata or directory structure:

* **Environment Setup**: Installation and initialization commands
* **Environment Management**: Start, stop, configuration commands
* **Development Tools**: Database, debugging, shell access
* **Information**: Version, help, status commands
* **General**: Uncategorized commands

### Setting Command Category

Add a category comment to your command's help file:

```bash
#!/usr/bin/env bash
# Category: Development Tools

ROLL_USAGE=$(cat <<EOF
# Your help content here
EOF
)
```

## Command Metadata

The registry extracts metadata from command help files:

### Description Extraction

The registry attempts to extract command descriptions from help files by looking for content after the "Usage:" section.

### Category Detection

Categories are detected from:
1. `# Category: <name>` comments in help files
2. `# TYPE: <name>` comments in help files
3. Directory-based categorization

## Creating Custom Commands

### Command File Structure

Create a command file with the `.cmd` extension:

```bash
#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Your command logic here
echo "Hello from custom command!"
```

### Help File Structure

Create a corresponding `.help` file:

```bash
#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_USAGE=$(cat <<EOF
\033[33mUsage:\033[0m
  mycustom [options]

\033[33mDescription:\033[0m
  Description of what your command does.

\033[33mExamples:\033[0m
  roll mycustom             # Run the custom command

\033[33mOptions:\033[0m
  -h, --help        Display this help menu
EOF
)
```

### Command Placement

Place custom commands in:

* **Project-specific**: `.roll/commands/` in your project directory
* **User-specific**: `~/.roll/commands/` in your home directory
* **Environment-specific**: `~/.roll/reclu/{env_type}/` for environment overrides

## Registry Integration

### Automatic Registration

Commands are automatically registered when:
* Roll starts up
* Registry commands are executed
* The registry is explicitly refreshed

### Priority Resolution

When multiple commands exist with the same name:
1. Higher priority commands (lower numbers) take precedence
2. Commands can override system defaults
3. Project-local commands override global commands

### Backward Compatibility

The registry system maintains full backward compatibility:
* All existing commands continue to work
* No changes required to existing command files
* Legacy command discovery still functions as fallback

## Advanced Usage

### Custom Search Paths

The registry can be extended by modifying the search paths in `utils/registry.sh`:

```bash
ROLL_COMMAND_SEARCH_PATHS=(
    "2:${ROLL_HOME_DIR}/commands" 
    "3:${ROLL_HOME_DIR}/reclu"
    "4:${ROLL_DIR}/commands"
    "5:/custom/path/commands"  # Add custom paths
)
```

### Registry Cache

The registry caches command information in memory for performance. Use `roll registry refresh` to clear the cache and re-scan all directories.

### Integration with Scripts

Export command lists for use in other scripts:

```bash
# Get all commands as a simple list
commands=$(roll registry export simple)

# Get detailed command information as JSON
roll registry export json > commands.json
```

## Troubleshooting

### Registry Validation Fails

If `roll registry validate` shows errors:

1. Check that command files exist and are executable
2. Verify help files follow the correct format
3. Ensure directory permissions are correct

### Commands Not Found

If commands aren't being discovered:

1. Run `roll registry refresh` to clear the cache
2. Check `roll registry paths` to verify search directories
3. Verify file extensions are `.cmd` for commands and `.help` for help files

### Performance Issues

If command discovery is slow:

1. Reduce the number of directories in search paths
2. Remove unused command directories
3. Use `roll registry stats` to check command counts

## Migration from Legacy System

The registry system is fully backward compatible. No migration is required, but you can:

1. Run `roll registry validate` to check for missing help files
2. Add category metadata to help files for better organization
3. Use `roll registry stats` to understand your command inventory

For more information, run `roll registry --help` or `roll registry <command> --help` for specific command details. 