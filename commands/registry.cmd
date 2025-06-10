#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  roll registry --help || exit $? && exit $?
fi

## Sub-command execution
case "${ROLL_PARAMS[0]}" in
    list)
        # List all available commands
        filter="${ROLL_PARAMS[1]:-}"
        category="${ROLL_PARAMS[2]:-}"
        
        initializeRegistry
        
        if [[ -n "$category" ]]; then
            echo -e "\033[33mCommands in '${category}' category:\033[0m"
            listRegisteredCommands "$filter" "$category"
        elif [[ -n "$filter" ]]; then
            echo -e "\033[33mCommands matching '${filter}':\033[0m"
            listRegisteredCommands "$filter"
        else
            echo -e "\033[33mAll registered commands:\033[0m"
            listRegisteredCommands
        fi
        ;;
        
    categories)
        # List commands organized by category
        category="${ROLL_PARAMS[1]:-}"
        
        initializeRegistry
        
        if [[ -n "$category" ]]; then
            echo -e "\033[33m${category^} Commands:\033[0m"
            listCommandsByCategory "$category"
        else
            listCommandsByCategory
        fi
        ;;
        
    info)
        # Show detailed information about a specific command
        if [[ ${#ROLL_PARAMS[@]} -lt 2 ]]; then
            error "Usage: roll registry info <command>"
            exit 1
        fi
        
        command="${ROLL_PARAMS[1]}"
        
        initializeRegistry
        
        if ! isCommandRegistered "$command"; then
            error "Command '$command' not found in registry"
            exit 1
        fi
        
        echo -e "\033[33mCommand Information: $command\033[0m"
        echo "  Path:        $(getCommandInfo "$command" "path")"
        echo "  Help File:   $(getCommandInfo "$command" "help")"
        echo "  Category:    $(getCommandInfo "$command" "category")"
        echo "  Priority:    $(getCommandInfo "$command" "priority")"
        echo "  Description: $(getCommandInfo "$command" "description")"
        ;;
        
    search)
        # Search for commands by name or description
        if [[ ${#ROLL_PARAMS[@]} -lt 2 ]]; then
            error "Usage: roll registry search <pattern>"
            exit 1
        fi
        
        pattern="${ROLL_PARAMS[1]}"
        
        initializeRegistry
        
        echo -e "\033[33mSearching for commands matching: '$pattern'\033[0m"
        echo ""
        
        found=0
        i=0
        while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
            command="${ROLL_REGISTRY_COMMANDS[$i]}"
            description="${ROLL_REGISTRY_DESCRIPTIONS[$i]}"
            category="${ROLL_REGISTRY_CATEGORIES[$i]}"
            
            if [[ "$command" =~ $pattern ]] || [[ "$description" =~ $pattern ]]; then
                printf "  %-20s %-10s %s\n" "$command" "[$category]" "$description"
                found=1
            fi
            i=$((i + 1))
        done
        
        if [[ $found -eq 0 ]]; then
            info "No commands found matching '$pattern'"
        fi
        ;;
        
    stats)
        # Display registry statistics
        showRegistryStats
        ;;
        
    refresh)
        # Refresh the command registry
        info "Refreshing command registry..."
        refreshRegistry
        success "Command registry refreshed"
        showRegistryStats
        ;;
        
    export)
        # Export command list in various formats
        format="${ROLL_PARAMS[1]:-simple}"
        
        case "$format" in
            json|csv|simple)
                exportCommands "$format"
                ;;
            *)
                error "Unsupported export format: $format"
                echo "Supported formats: simple, json, csv"
                exit 1
                ;;
        esac
        ;;
        
    validate)
        # Validate registry integrity
        initializeRegistry
        
        info "Validating command registry integrity..."
        
        errors=0
        i=0
        while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
            command="${ROLL_REGISTRY_COMMANDS[$i]}"
            cmd_path="${ROLL_REGISTRY_PATHS[$i]}"
            help_path="${ROLL_REGISTRY_HELP_PATHS[$i]}"
            
            # Check if command file exists
            if [[ ! -f "$cmd_path" ]]; then
                error "Command file missing: $cmd_path (for command: $command)"
                errors=$((errors + 1))
            fi
            
            # Check if help file exists (warning only)
            if [[ ! -f "$help_path" ]]; then
                warning "Help file missing: $help_path (for command: $command)"
            fi
            
            i=$((i + 1))
        done
        
        if [[ $errors -eq 0 ]]; then
            success "Registry validation passed"
        else
            error "Registry validation failed with $errors errors"
            exit 1
        fi
        ;;
        
    paths)
        # Show command search paths and their priorities
        showRegistryPaths
        ;;
        
    *)
        error "Unknown registry command: ${ROLL_PARAMS[0]}"
        echo "Available commands: list, categories, info, search, stats, refresh, export, validate, paths"
        exit 1
        ;;
esac 