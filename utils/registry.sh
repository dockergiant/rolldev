#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Command Registry System
## Discovers and manages commands across all Roll directories
## Compatible with Bash 3.2+ (macOS default)

# Command registry cache using indexed arrays for Bash 3.2 compatibility
ROLL_REGISTRY_COMMANDS=()
ROLL_REGISTRY_PATHS=()
ROLL_REGISTRY_HELP_PATHS=()
ROLL_REGISTRY_CATEGORIES=()
ROLL_REGISTRY_DESCRIPTIONS=()
ROLL_REGISTRY_PRIORITIES=()
ROLL_REGISTRY_INITIALIZED=0

# Command search paths with priorities (lower number = higher priority)
# Note: ROLL_HOME_DIR may not be available when this script is sourced, so we define this dynamically
ROLL_COMMAND_SEARCH_PATHS=()

# Function to get command search paths (called when registry is initialized)
function getCommandSearchPaths() {
    local search_paths=(
        "2:${ROLL_HOME_DIR:-$HOME/.roll}/commands" 
        "3:${ROLL_HOME_DIR:-$HOME/.roll}/reclu"
        "4:${ROLL_DIR}/commands"
    )
    printf '%s\n' "${search_paths[@]}"
}

# Environment-specific command paths (added dynamically if env is available)
function getEnvCommandPaths() {
    local env_paths=()
    
    # Add project-local commands if ROLL_ENV_PATH is available
    if [[ -n "${ROLL_ENV_PATH}" && -d "${ROLL_ENV_PATH}/.roll/commands" ]]; then
        env_paths+=("1:${ROLL_ENV_PATH}/.roll/commands")
    fi
    
    # Add environment-specific commands if ROLL_ENV_TYPE is available
    if [[ -n "${ROLL_ENV_TYPE}" ]]; then
        # Check for commands in ${ROLL_HOME_DIR}/commands/${ROLL_ENV_TYPE} (new structure)
        [[ -d "${ROLL_HOME_DIR:-$HOME/.roll}/commands/${ROLL_ENV_TYPE}" ]] && env_paths+=("1:${ROLL_HOME_DIR:-$HOME/.roll}/commands/${ROLL_ENV_TYPE}")
        # Check for commands in ${ROLL_HOME_DIR}/reclu/${ROLL_ENV_TYPE} (legacy structure)
        [[ -d "${ROLL_HOME_DIR:-$HOME/.roll}/reclu/${ROLL_ENV_TYPE}" ]] && env_paths+=("1:${ROLL_HOME_DIR:-$HOME/.roll}/reclu/${ROLL_ENV_TYPE}")
        # System environment-specific commands
        [[ -d "${ROLL_DIR}/commands/${ROLL_ENV_TYPE}" ]] && env_paths+=("2:${ROLL_DIR}/commands/${ROLL_ENV_TYPE}")
    fi
    
    printf '%s\n' "${env_paths[@]}"
}

## Helper function to find command index in registry
function findCommandIndex() {
    local command="$1"
    local i=0
    for registered_command in "${ROLL_REGISTRY_COMMANDS[@]}"; do
        if [[ "$registered_command" == "$command" ]]; then
            echo $i
            return 0
        fi
        i=$((i + 1))
    done
    echo -1
}

## Extract command metadata from help file
function extractCommandMetadata() {
    local help_file="$1"
    local metadata_type="$2"
    
    if [[ ! -f "$help_file" ]]; then
        echo ""
        return 0
    fi
    
    case "$metadata_type" in
        description)
            # Simple approach - just return empty for now
            echo ""
            ;;
        category)
            # Simple approach - just return general for now
            echo "general"
            ;;
        *)
            echo ""
            ;;
    esac
    
    return 0
}

## Register a single command in the registry
function registerCommand() {
    local command="$1"
    local cmd_path="$2"
    local help_path="$3"
    local priority="$4"
    local category="${5:-general}"
    
    local existing_index=$(findCommandIndex "$command")
    
    if [[ $existing_index -ge 0 ]]; then
        # Command already exists, check priority
        local existing_priority="${ROLL_REGISTRY_PRIORITIES[$existing_index]}"
        if [[ $priority -lt $existing_priority ]]; then
            # New command has higher priority, replace it
            ROLL_REGISTRY_PATHS[$existing_index]="$cmd_path"
            ROLL_REGISTRY_HELP_PATHS[$existing_index]="$help_path"
            ROLL_REGISTRY_PRIORITIES[$existing_index]="$priority"
            ROLL_REGISTRY_CATEGORIES[$existing_index]="$category"
            ROLL_REGISTRY_DESCRIPTIONS[$existing_index]="$(extractCommandMetadata "$help_path" "description")"
        fi
    else
        # New command, add to registry
        ROLL_REGISTRY_COMMANDS+=("$command")
        ROLL_REGISTRY_PATHS+=("$cmd_path")
        ROLL_REGISTRY_HELP_PATHS+=("$help_path")
        ROLL_REGISTRY_PRIORITIES+=("$priority")
        ROLL_REGISTRY_CATEGORIES+=("$category")
        ROLL_REGISTRY_DESCRIPTIONS+=("$(extractCommandMetadata "$help_path" "description")")
    fi
}

## Scan a directory for commands
function scanCommandDirectory() {
    local search_entry="$1"
    local priority="${search_entry%%:*}"
    local directory="${search_entry##*:}"
    local category="${2:-general}"
    
    # Skip if directory doesn't exist
    if [[ ! -d "$directory" ]]; then
        return 0
    fi
    
    local cmd_file help_file command_name
    
    # Find all .cmd files in directory
    for cmd_file in "$directory"/*.cmd; do
        # Skip if no .cmd files found (glob didn't match)
        [[ ! -f "$cmd_file" ]] && continue
        
        command_name="$(basename "$cmd_file" .cmd)"
        help_file="$directory/$command_name.help"
        
        # Extract category from help file if available
        if [[ -f "$help_file" ]]; then
            local extracted_category="$(extractCommandMetadata "$help_file" "category")"
            [[ -n "$extracted_category" && "$extracted_category" != "general" ]] && category="$extracted_category"
        fi
        
        registerCommand "$command_name" "$cmd_file" "$help_file" "$priority" "$category"
    done
}

## Initialize command registry by scanning all directories
function initializeRegistry() {
    # Skip if already initialized
    if [[ $ROLL_REGISTRY_INITIALIZED -eq 1 ]]; then
        return 0
    fi
    
    # Clear existing registry
    ROLL_REGISTRY_COMMANDS=()
    ROLL_REGISTRY_PATHS=()
    ROLL_REGISTRY_HELP_PATHS=()
    ROLL_REGISTRY_CATEGORIES=()
    ROLL_REGISTRY_DESCRIPTIONS=()
    ROLL_REGISTRY_PRIORITIES=()
    
    # Scan environment-specific directories first (highest priority)
    while IFS= read -r env_path; do
        [[ -n "$env_path" ]] && scanCommandDirectory "$env_path" "environment"
    done < <(getEnvCommandPaths)
    
    # Scan global command directories using dynamic search paths
    while IFS= read -r search_path; do
        [[ -n "$search_path" ]] && scanCommandDirectory "$search_path" "global"
    done < <(getCommandSearchPaths)
    
    ROLL_REGISTRY_INITIALIZED=1
}

## Get command information from registry
function getCommandInfo() {
    local command="$1"
    local info_type="$2"
    
    local index=$(findCommandIndex "$command")
    [[ $index -eq -1 ]] && return 1
    
    case "$info_type" in
        path)
            echo "${ROLL_REGISTRY_PATHS[$index]}"
            ;;
        help)
            echo "${ROLL_REGISTRY_HELP_PATHS[$index]}"
            ;;
        category)
            echo "${ROLL_REGISTRY_CATEGORIES[$index]}"
            ;;
        description)
            echo "${ROLL_REGISTRY_DESCRIPTIONS[$index]}"
            ;;
        priority)
            echo "${ROLL_REGISTRY_PRIORITIES[$index]}"
            ;;
        *)
            return 1
            ;;
    esac
}

## Check if command exists in registry
function isCommandRegistered() {
    local command="$1"
    local index=$(findCommandIndex "$command")
    [[ $index -ge 0 ]]
}

## List all registered commands
function listRegisteredCommands() {
    local filter="${1:-}"
    local category_filter="${2:-}"
    
    local i=0
    while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
        local command="${ROLL_REGISTRY_COMMANDS[$i]}"
        local category="${ROLL_REGISTRY_CATEGORIES[$i]}"
        
        # Apply filters
        if [[ -n "$filter" && ! "$command" =~ $filter ]]; then
            i=$((i + 1))
            continue
        fi
        
        if [[ -n "$category_filter" && "$category" != "$category_filter" ]]; then
            i=$((i + 1))
            continue
        fi
        
        echo "$command"
        i=$((i + 1))
    done
}

## List commands by category
function listCommandsByCategory() {
    local target_category="${1:-}"
    
    # Get unique categories if no specific category requested
    if [[ -z "$target_category" ]]; then
        local categories=()
        local i=0
        while [[ $i -lt ${#ROLL_REGISTRY_CATEGORIES[@]} ]]; do
            local category="${ROLL_REGISTRY_CATEGORIES[$i]}"
            local found=0
            local existing_category
            for existing_category in "${categories[@]}"; do
                if [[ "$existing_category" == "$category" ]]; then
                    found=1
                    break
                fi
            done
            [[ $found -eq 0 ]] && categories+=("$category")
            i=$((i + 1))
        done
        
        # Display all categories
        for category in "${categories[@]}"; do
            echo -e "\033[33m${category^} Commands:\033[0m"
            listCommandsByCategory "$category"
            echo ""
        done
        return 0
    fi
    
    # List commands in specific category
    local i=0
    while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
        local command="${ROLL_REGISTRY_COMMANDS[$i]}"
        local category="${ROLL_REGISTRY_CATEGORIES[$i]}"
        local description="${ROLL_REGISTRY_DESCRIPTIONS[$i]}"
        
        if [[ "$category" == "$target_category" ]]; then
            printf "  %-20s %s\n" "$command" "$description"
        fi
        i=$((i + 1))
    done
}

## Find command and return its execution details
function findCommand() {
    local command="$1"
    
    # Initialize registry if needed
    initializeRegistry
    
    # Check registry first
    if isCommandRegistered "$command"; then
        local cmd_path="$(getCommandInfo "$command" "path")"
        local help_path="$(getCommandInfo "$command" "help")"
        
        # Return in format: "found:cmd_path:help_path"
        echo "found:$cmd_path:$help_path"
        return 0
    fi
    
    # Command not found
    echo "notfound"
    return 0
}

## Refresh registry (useful after adding new commands)
function refreshRegistry() {
    ROLL_REGISTRY_INITIALIZED=0
    initializeRegistry
}

## Display registry statistics
function showRegistryStats() {
    initializeRegistry
    
    echo -e "\033[33mCommand Registry Statistics:\033[0m"
    echo "  Total commands: ${#ROLL_REGISTRY_COMMANDS[@]}"
    
    # Count by category
    local categories=()
    local category_counts=()
    local i=0
    
    while [[ $i -lt ${#ROLL_REGISTRY_CATEGORIES[@]} ]]; do
        local category="${ROLL_REGISTRY_CATEGORIES[$i]}"
        local found_index=-1
        local j=0
        
        # Find existing category
        for existing_category in "${categories[@]}"; do
            if [[ "$existing_category" == "$category" ]]; then
                found_index=$j
                break
            fi
            j=$((j + 1))
        done
        
        if [[ $found_index -ge 0 ]]; then
            # Increment existing category count
            category_counts[$found_index]=$((${category_counts[$found_index]} + 1))
        else
            # Add new category
            categories+=("$category")
            category_counts+=(1)
        fi
        
        i=$((i + 1))
    done
    
    # Display category counts
    i=0
    while [[ $i -lt ${#categories[@]} ]]; do
        printf "  %-15s: %d commands\n" "${categories[$i]^}" "${category_counts[$i]}"
        i=$((i + 1))
    done
}

## Display command search paths
function showRegistryPaths() {
    echo "Command Search Paths (by priority):"
    echo ""
    
    # Show environment-specific paths first
    local env_paths
    env_paths=($(getEnvCommandPaths))
    if [[ ${#env_paths[@]} -gt 0 ]]; then
        echo "Environment-Specific Paths (${ROLL_ENV_TYPE:-unknown}):"
        local env_path
        for env_path in "${env_paths[@]}"; do
            local priority="${env_path%%:*}"
            local directory="${env_path##*:}"
            if [[ -d "$directory" ]]; then
                echo "  ✅ Priority $priority: $directory"
            else
                echo "  ❌ Priority $priority: $directory"
            fi
        done
        echo ""
    fi
    
    # Show global command paths
    echo "Global Command Paths:"
    while IFS= read -r search_path; do
        local priority="${search_path%%:*}"
        local directory="${search_path##*:}"
        if [[ -d "$directory" ]]; then
            echo "  ✅ Priority $priority: $directory"
        else
            echo "  ❌ Priority $priority: $directory"
        fi
    done < <(getCommandSearchPaths)
}

## Export command list for external tools
function exportCommands() {
    local format="${1:-simple}"
    
    initializeRegistry
    
    case "$format" in
        json)
            echo "["
            local i=0
            while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
                local command="${ROLL_REGISTRY_COMMANDS[$i]}"
                local path="${ROLL_REGISTRY_PATHS[$i]}"
                local help_path="${ROLL_REGISTRY_HELP_PATHS[$i]}"
                local category="${ROLL_REGISTRY_CATEGORIES[$i]}"
                local description="${ROLL_REGISTRY_DESCRIPTIONS[$i]}"
                local priority="${ROLL_REGISTRY_PRIORITIES[$i]}"
                
                echo "  {"
                echo "    \"command\": \"$command\","
                echo "    \"path\": \"$path\","
                echo "    \"help_path\": \"$help_path\","
                echo "    \"category\": \"$category\","
                echo "    \"description\": \"$description\","
                echo "    \"priority\": $priority"
                if [[ $i -eq $((${#ROLL_REGISTRY_COMMANDS[@]} - 1)) ]]; then
                    echo "  }"
                else
                    echo "  },"
                fi
                i=$((i + 1))
            done
            echo "]"
            ;;
        csv)
            echo "command,path,help_path,category,description,priority"
            local i=0
            while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
                local command="${ROLL_REGISTRY_COMMANDS[$i]}"
                local path="${ROLL_REGISTRY_PATHS[$i]}"
                local help_path="${ROLL_REGISTRY_HELP_PATHS[$i]}"
                local category="${ROLL_REGISTRY_CATEGORIES[$i]}"
                local description="${ROLL_REGISTRY_DESCRIPTIONS[$i]}"
                local priority="${ROLL_REGISTRY_PRIORITIES[$i]}"
                
                echo "$command,$path,$help_path,$category,\"$description\",$priority"
                i=$((i + 1))
            done
            ;;
        simple|*)
            local i=0
            while [[ $i -lt ${#ROLL_REGISTRY_COMMANDS[@]} ]]; do
                echo "${ROLL_REGISTRY_COMMANDS[$i]}"
                i=$((i + 1))
            done
            ;;
    esac
} 