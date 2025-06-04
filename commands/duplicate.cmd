#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Load core utilities and configuration
ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

# Default configuration values
DUPLICATE_NAME=""
DUPLICATE_INCLUDE_SOURCE=1
DUPLICATE_ENCRYPT=""
DUPLICATE_START_ENV=1
DUPLICATE_UPDATE_URLS=1
DUPLICATE_DRY_RUN=0
DUPLICATE_QUIET=0
DUPLICATE_FORCE=0
PROGRESS=1

# Parse command line arguments
POSITIONAL_ARGS=()
# Start with any arguments passed from the main roll script
if [[ -n "${ROLL_PARAMS[*]}" ]]; then
    POSITIONAL_ARGS+=("${ROLL_PARAMS[@]}")
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            roll duplicate --help
            exit 0
            ;;
        --encrypt=*)
            DUPLICATE_ENCRYPT="${1#*=}"
            shift
            ;;
        --encrypt)
            # Flag without value - will prompt for password later
            DUPLICATE_ENCRYPT="PROMPT"
            shift
            ;;
        --no-source)
            DUPLICATE_INCLUDE_SOURCE=0
            shift
            ;;
        --no-start)
            DUPLICATE_START_ENV=0
            shift
            ;;
        --no-urls)
            DUPLICATE_UPDATE_URLS=0
            shift
            ;;
        --dry-run)
            DUPLICATE_DRY_RUN=1
            shift
            ;;
        --quiet|-q)
            DUPLICATE_QUIET=1
            PROGRESS=0
            shift
            ;;
        --force|-f)
            DUPLICATE_FORCE=1
            shift
            ;;
        --no-progress)
            PROGRESS=0
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            error "Unknown option: $1"
            exit 1
            ;;
        *)
            # Collect positional arguments
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Add any remaining arguments after -- to positional args
POSITIONAL_ARGS+=("$@")

# Extract environment name from positional arguments
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    DUPLICATE_NAME="${POSITIONAL_ARGS[0]}"
fi

# Utility functions for duplicate operations
function promptPassword() {
    local prompt="$1"
    local password=""
    local confirm=""
    
    # Don't prompt in quiet mode or non-interactive shells
    if [[ $DUPLICATE_QUIET -eq 1 ]] || [[ ! -t 0 ]]; then
        error "Password required but running in non-interactive mode. Use --encrypt=password instead."
        exit 1
    fi
    
    echo -n "$prompt: " >&2
    read -s password
    echo >&2
    
    if [[ -z "$password" ]]; then
        error "Password cannot be empty"
        exit 1
    fi
    
    # Confirm password for security
    echo -n "Confirm password: " >&2
    read -s confirm
    echo >&2
    
    if [[ "$password" != "$confirm" ]]; then
        error "Passwords do not match"
        exit 1
    fi
    
    echo "$password"
}

function showProgress() {
    [[ $PROGRESS -eq 0 ]] && return
    local current=$1
    local total=$2
    local description="$3"
    local percent=$((current * 100 / total))
    local bar_length=30
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r["
    printf "%*s" $filled_length | tr ' ' '='
    printf "%*s" $((bar_length - filled_length)) | tr ' ' '-'
    printf "] %d%% %s" $percent "$description"
    
    # Always end with a newline for clean output
    echo ""
}

function logMessage() {
    [[ $DUPLICATE_QUIET -eq 1 ]] && return
    local level="$1"
    shift
    case "$level" in
        INFO) info "$@" ;;
        SUCCESS) success "$@" ;;
        WARNING) warning "$@" ;;
        ERROR) error "$@" ;;
    esac
}

function validateDuplicateName() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        error "Duplicate environment name is required"
        return 1
    fi
    
    # Check if name is valid (alphanumeric, hyphens, underscores)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Environment name must contain only letters, numbers, hyphens, and underscores"
        return 1
    fi
    
    # Check if directory already exists
    local target_dir="$(dirname "$(pwd)")/${name}"
    if [[ -d "$target_dir" ]] && [[ $DUPLICATE_FORCE -eq 0 ]]; then
        error "Directory $target_dir already exists. Use --force to overwrite."
        return 1
    fi
    
    return 0
}

function createBackupForDuplicate() {
    local step="$1"
    local total="$2"
    
    showProgress $step $total "Creating backup of current environment"
    
    local backup_args=("all")
    
    # Note: We don't include source code in backup since we copy it directly
    # This makes backup/restore faster and more reliable for large codebases
    if [[ $DUPLICATE_INCLUDE_SOURCE -eq 1 ]]; then
        logMessage INFO "Source code will be copied directly (not via backup)"
    fi
    
    if [[ -n "$DUPLICATE_ENCRYPT" ]]; then
        if [[ "$DUPLICATE_ENCRYPT" == "PROMPT" ]]; then
            backup_args+=("--encrypt")
        else
            backup_args+=("--encrypt=${DUPLICATE_ENCRYPT}")
        fi
    fi
    
    # Add duplication parameters to modify environment names in backup
    backup_args+=("--duplicate-name=${DUPLICATE_NAME}")
    backup_args+=("--duplicate-domain=${DUPLICATE_NAME}.test")
    
    backup_args+=("--output-id")
    backup_args+=("--name=duplicate-data")
    backup_args+=("--description=Data backup created for duplicating to ${DUPLICATE_NAME}")
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would create backup with: roll backup ${backup_args[*]}"
        echo "latest-backup-id"
        return 0
    fi
    
    # Create backup and get the backup ID directly
    local backup_id
    if backup_id=$("${ROLL_DIR}/bin/roll" backup "${backup_args[@]}" 2>/dev/null); then
        # Remove any whitespace
        backup_id=$(echo "$backup_id" | tr -d ' \n')
        
        if [[ -n "$backup_id" ]]; then
            logMessage SUCCESS "Data backup created with ID: $backup_id"
            echo "$backup_id"
            return 0
        else
            logMessage ERROR "Failed to get backup ID from backup command"
            return 1
        fi
    else
        logMessage ERROR "Failed to create backup"
        return 1
    fi
}

function setupNewEnvironment() {
    local new_name="$1"
    local step="$2" 
    local total="$3"
    
    showProgress $step $total "Setting up new environment directory"
    
    local current_dir="$(pwd)"
    local target_dir="$(dirname "$current_dir")/${new_name}"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would create directory: $target_dir"
        logMessage INFO "[DRY RUN] Would copy environment files and source code"
        return 0
    fi
    
    # Remove target directory if it exists and force is enabled
    if [[ -d "$target_dir" ]] && [[ $DUPLICATE_FORCE -eq 1 ]]; then
        logMessage INFO "Removing existing directory: $target_dir"
        rm -rf "$target_dir"
    fi
    
    # Create new directory
    mkdir -p "$target_dir"
    
    # Copy all source code files and directories, excluding certain paths
    logMessage INFO "Copying source code files..."
    local exclude_patterns=(
        "--exclude=.roll/backups"
        "--exclude=var/cache"
        "--exclude=var/log"
        "--exclude=var/session"
        "--exclude=var/tmp"
        "--exclude=storage/logs"
        "--exclude=storage/framework/cache"
        "--exclude=storage/framework/sessions"
        "--exclude=storage/framework/views"
        "--exclude=node_modules"
        "--exclude=vendor/bin"
        "--exclude=*.log"
    )
    
    # Use rsync for efficient copying with exclusions
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "${exclude_patterns[@]}" "$current_dir/" "$target_dir/"
        logMessage SUCCESS "Source code copied using rsync"
    else
        # Fallback to cp if rsync is not available
        cp -r "$current_dir"/* "$target_dir/" 2>/dev/null || true
        cp -r "$current_dir"/.* "$target_dir/" 2>/dev/null || true
        
        # Remove excluded directories if they were copied
        rm -rf "$target_dir/.roll/backups" 2>/dev/null || true
        rm -rf "$target_dir/var/cache" 2>/dev/null || true
        rm -rf "$target_dir/var/log" 2>/dev/null || true
        rm -rf "$target_dir/node_modules" 2>/dev/null || true
        
        logMessage SUCCESS "Source code copied using cp"
    fi
    
    # Ensure .roll/backups directory exists but is empty
    mkdir -p "$target_dir/.roll/backups"
    
    # Update environment name in .env.roll
    if [[ -f "$target_dir/.env.roll" ]]; then
        sed_inplace "s/^ROLL_ENV_NAME=.*/ROLL_ENV_NAME=${new_name}/" "$target_dir/.env.roll"
        sed_inplace "s/^TRAEFIK_DOMAIN=.*/TRAEFIK_DOMAIN=${new_name}.test/" "$target_dir/.env.roll"
        logMessage INFO "Updated ROLL_ENV_NAME to: $new_name"
        logMessage INFO "Updated TRAEFIK_DOMAIN to: ${new_name}.test"
    fi
    
    logMessage SUCCESS "New environment directory created: $target_dir"
    echo "$target_dir"
}

function restoreBackupToNewEnvironment() {
    local backup_id="$1"
    local target_dir="$2"
    local step="$3"
    local total="$4"
    
    showProgress $step $total "Restoring backup to new environment"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would restore backup $backup_id to $target_dir"
        return 0
    fi
    
    # Verify target directory exists before changing to it
    if [[ ! -d "$target_dir" ]]; then
        logMessage ERROR "Target directory does not exist: $target_dir"
        return 1
    fi
    
    # Copy backup archive from original environment to new environment
    local source_backup_dir="$(pwd)/.roll/backups"
    local target_backup_dir="$target_dir/.roll/backups"
    
    # Find the backup archive in the source directory
    local backup_archive=""
    for ext in ".tar.gz" ".tar.xz" ".tar.lz4" ".tar"; do
        local potential_file="$source_backup_dir/backup_${ROLL_ENV_NAME}_${backup_id}${ext}"
        if [[ -f "$potential_file" ]]; then
            backup_archive="$potential_file"
            break
        fi
    done
    
    if [[ -z "$backup_archive" ]]; then
        logMessage ERROR "Backup archive not found for ID: $backup_id in $source_backup_dir"
        return 1
    fi
    
    # Ensure target backup directory exists
    mkdir -p "$target_backup_dir"
    
    # Copy backup archive to new environment
    local archive_name="$(basename "$backup_archive")"
    logMessage INFO "Copying backup archive: $archive_name"
    if ! cp "$backup_archive" "$target_backup_dir/"; then
        logMessage ERROR "Failed to copy backup archive to new environment"
        return 1
    fi
    
    # Change to target directory for restore
    if ! cd "$target_dir"; then
        logMessage ERROR "Failed to change to directory: $target_dir"
        return 1
    fi
    
    local restore_args=("--backup-id=${backup_id}")
    
    if [[ -n "$DUPLICATE_ENCRYPT" ]]; then
        if [[ "$DUPLICATE_ENCRYPT" == "PROMPT" ]]; then
            restore_args+=("--decrypt")
        else
            restore_args+=("--decrypt=${DUPLICATE_ENCRYPT}")
        fi
    fi
    
    restore_args+=("--force")
    restore_args+=("--quiet")
    
    if "${ROLL_DIR}/bin/roll" restore "${restore_args[@]}"; then
        logMessage SUCCESS "Backup restored to new environment"
        return 0
    else
        logMessage ERROR "Failed to restore backup to new environment"
        return 1
    fi
}

function generateNewCertificates() {
    local new_name="$1"
    local target_dir="$2"
    local step="$3"
    local total="$4"
    
    showProgress $step $total "Generating new SSL certificates"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would generate new certificates for *.${new_name}.test"
        return 0
    fi
    
    # Change to target directory
    cd "$target_dir"
    
    # Generate wildcard certificates for the new domain
    if "${ROLL_DIR}/bin/roll" sign-certificate "*.${new_name}.test" >/dev/null 2>&1; then
        logMessage SUCCESS "New SSL certificates generated for *.${new_name}.test"
        return 0
    else
        logMessage WARNING "Failed to generate SSL certificates (you may need to do this manually)"
        return 0  # Don't fail the whole process for certificate issues
    fi
}

function updateDatabaseUrls() {
    local new_name="$1"
    local target_dir="$2"
    local step="$3"
    local total="$4"
    
    if [[ $DUPLICATE_UPDATE_URLS -eq 0 ]]; then
        return 0
    fi
    
    showProgress $step $total "Updating database URLs"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would update URLs in database to use ${new_name}.test"
        return 0
    fi
    
    # Change to target directory
    cd "$target_dir"
    
    # Start the environment to update URLs
    "${ROLL_DIR}/bin/roll" env up -d >/dev/null 2>&1
    
    # Wait for services to be ready
    sleep 5
    
    # Update URLs based on environment type
    local env_type=""
    if [[ -f ".env.roll" ]]; then
        env_type=$(grep "^ROLL_ENV_TYPE=" .env.roll | cut -d= -f2)
    fi
    
    case "$env_type" in
        magento2)
            updateMagento2Urls "$new_name"
            ;;
        magento1)
            updateMagento1Urls "$new_name"
            ;;
        wordpress)
            updateWordPressUrls "$new_name"
            ;;
        *)
            logMessage INFO "Unknown environment type, skipping URL updates"
            ;;
    esac
    
    logMessage SUCCESS "Database URLs updated"
}

function updateMagento2Urls() {
    local new_name="$1"
    local new_url="https://app.${new_name}.test/"
    
    # Update core_config_data
    echo "UPDATE core_config_data SET value = '${new_url}' WHERE path IN ('web/unsecure/base_url', 'web/secure/base_url');" | \
        "${ROLL_DIR}/bin/roll" db import >/dev/null 2>&1
    
    logMessage INFO "Updated Magento 2 URLs to: $new_url"
}

function updateMagento1Urls() {
    local new_name="$1"
    local new_url="https://app.${new_name}.test/"
    
    # Update core_config_data
    echo "UPDATE core_config_data SET value = '${new_url}' WHERE path IN ('web/unsecure/base_url', 'web/secure/base_url');" | \
        "${ROLL_DIR}/bin/roll" db import >/dev/null 2>&1
    
    logMessage INFO "Updated Magento 1 URLs to: $new_url"
}

function updateWordPressUrls() {
    local new_name="$1"
    local new_url="https://${new_name}.test"
    
    # Update WordPress options
    echo "UPDATE wp_options SET option_value = '${new_url}' WHERE option_name IN ('home', 'siteurl');" | \
        "${ROLL_DIR}/bin/roll" db import >/dev/null 2>&1
    
    logMessage INFO "Updated WordPress URLs to: $new_url"
}

function startNewEnvironment() {
    local target_dir="$1"
    local step="$2"
    local total="$3"
    
    if [[ $DUPLICATE_START_ENV -eq 0 ]]; then
        return 0
    fi
    
    showProgress $step $total "Starting new environment"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would start new environment"
        return 0
    fi
    
    # Change to target directory
    cd "$target_dir"
    
    # Start the environment
    if "${ROLL_DIR}/bin/roll" env up -d >/dev/null 2>&1; then
        logMessage SUCCESS "New environment started successfully"
        return 0
    else
        logMessage ERROR "Failed to start new environment"
        return 1
    fi
}

function performDuplicate() {
    local new_name="$1"
    
    # Validate inputs
    validateDuplicateName "$new_name" || exit 1
    
    # Handle interactive password prompt if needed
    if [[ "$DUPLICATE_ENCRYPT" == "PROMPT" ]]; then
        DUPLICATE_ENCRYPT=$(promptPassword "Enter encryption password for backup")
    fi
    
    local current_env_name="$ROLL_ENV_NAME"
    local total_steps=6
    local current_step=0
    
    logMessage INFO "Duplicating environment '$current_env_name' to '$new_name'"
    
    # Step 1: Create backup
    ((current_step++))
    local backup_id
    if ! backup_id=$(createBackupForDuplicate $current_step $total_steps); then
        logMessage ERROR "Failed to create backup"
        exit 1
    fi
    
    # Step 2: Setup new environment directory
    ((current_step++))
    local target_dir
    if ! target_dir=$(setupNewEnvironment "$new_name" $current_step $total_steps); then
        logMessage ERROR "Failed to setup new environment directory"
        exit 1
    fi
    
    # Step 3: Restore backup to new environment
    ((current_step++))
    if ! restoreBackupToNewEnvironment "$backup_id" "$target_dir" $current_step $total_steps; then
        logMessage ERROR "Failed to restore backup to new environment"
        exit 1
    fi
    
    # Step 4: Generate new certificates
    ((current_step++))
    generateNewCertificates "$new_name" "$target_dir" $current_step $total_steps
    
    # Step 5: Update database URLs
    ((current_step++))
    updateDatabaseUrls "$new_name" "$target_dir" $current_step $total_steps
    
    # Step 6: Start new environment
    ((current_step++))
    startNewEnvironment "$target_dir" $current_step $total_steps
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage SUCCESS "Dry run completed successfully!"
        logMessage INFO "Target directory would be: $target_dir"
    else
        logMessage SUCCESS "Environment duplication completed successfully!"
        logMessage SUCCESS "New environment '$new_name' is ready at: $target_dir"
        logMessage INFO "You can access it at: https://app.${new_name}.test"
        logMessage INFO "To switch to the new environment: cd $target_dir"
    fi
}

# Main execution
if [[ -z "$DUPLICATE_NAME" ]]; then
    error "Environment name is required. Usage: roll duplicate <new-environment-name>"
    echo "Example: roll duplicate moduleshop-upgrade"
    exit 1
fi

performDuplicate "$DUPLICATE_NAME" 