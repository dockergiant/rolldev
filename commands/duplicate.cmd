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
DUPLICATE_RUN_MAGENTO_COMMANDS=1
DUPLICATE_DRY_RUN=0
DUPLICATE_QUIET=0
DUPLICATE_FORCE=0
DUPLICATE_VERBOSE=0

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
            shift
            ;;
        --force|-f)
            DUPLICATE_FORCE=1
            shift
            ;;
        --no-magento-commands)
            DUPLICATE_RUN_MAGENTO_COMMANDS=0
            shift
            ;;
        --verbose)
            DUPLICATE_VERBOSE=1
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

function executeCommand() {
    local description="$1"
    shift
    local cmd=("$@")
    
    if [[ $DUPLICATE_VERBOSE -eq 1 ]]; then
        # In verbose mode, show what we're doing and don't trap output
        logMessage INFO "$description"
        "${cmd[@]}"
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            logMessage ERROR "$description failed with exit code: $exit_code"
        fi
        return $exit_code
    else
        # In non-verbose mode, run silently unless there's an error
        local output
        if output=$("${cmd[@]}" 2>&1); then
            return 0
        else
            local exit_code=$?
            logMessage ERROR "$description failed with exit code: $exit_code"
            logMessage ERROR "Output: $output"
            return $exit_code
        fi
    fi
}

function createBackup() {
    local step="$1"
    local total="$2"
    
    local backup_args=("all")
    
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
    local backup_exit_code
    
    logMessage INFO "Creating backup..."
    
    # The --output-id flag outputs ONLY the backup ID (no warnings)
    if backup_id=$("${ROLL_DIR}/bin/roll" backup "${backup_args[@]}" 2>&1); then
        backup_exit_code=0
        # Remove any whitespace (should just be a number)
        backup_id=$(echo "$backup_id" | tr -d ' \n\r\t')
    else
        backup_exit_code=$?
        backup_id=""
    fi
    
    if [[ $backup_exit_code -eq 0 ]] && [[ -n "$backup_id" ]] && [[ "$backup_id" =~ ^[0-9]+$ ]]; then
        logMessage SUCCESS "Data backup created with ID: $backup_id"
        echo "$backup_id"
        return 0
    else
        logMessage ERROR "Failed to create backup or get valid backup ID"
        logMessage ERROR "Backup command output: '$backup_id'"
        logMessage ERROR "Exit code: $backup_exit_code"
        return 1
    fi
}

function restoreBackup() {
    local backup_id="$1"
    local target_dir="$2"
    local original_dir="$3"
    local step="$4"
    local total="$5"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would restore backup $backup_id to $target_dir"
        return 0
    fi
    
    # Verify target directory exists
    if [[ ! -d "$target_dir" ]]; then
        logMessage ERROR "Target directory does not exist: $target_dir"
        return 1
    fi
    
    # Verify backup file exists (should have been copied by previous step)
    local target_backup_dir="$target_dir/.roll/backups"
    local backup_file=""
    
    # Just check the most common .tar.gz format directly
    backup_file="${target_backup_dir}/backup_${ROLL_ENV_NAME}_${backup_id}.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        # Try other extensions if .tar.gz doesn't exist
        for ext in ".tar.xz" ".tar.lz4" ".tar"; do
            local test_file="${target_backup_dir}/backup_${ROLL_ENV_NAME}_${backup_id}${ext}"
            if [[ -f "$test_file" ]]; then
                backup_file="$test_file"
                break
            fi
        done
    fi
    
    if [[ -z "$backup_file" ]]; then
        logMessage ERROR "Backup file not found in target directory for ID: $backup_id"
        logMessage ERROR "Expected location: $target_backup_dir"
        logMessage ERROR "Target backup directory contents:"
        ls -la "$target_backup_dir/" || logMessage ERROR "Failed to list target backup directory"
        return 1
    fi
    
    logMessage SUCCESS "Backup file found in target directory: $(basename "$backup_file")"
    
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
    
    # Execute restore command
    if executeCommand "Restoring backup" "${ROLL_DIR}/bin/roll" restore "${restore_args[@]}"; then
        logMessage SUCCESS "Backup restored to new environment"
        return 0
    else
        local restore_exit_code=$?
        logMessage ERROR "Failed to restore backup to new environment"
        logMessage ERROR "Restore command exit code: $restore_exit_code"
        return 1
    fi
}

function generateCertificates() {
    local new_name="$1"
    local target_dir="$2"
    local step="$3"
    local total="$4"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would generate new certificates for *.${new_name}.test"
        return 0
    fi
    
    # Change to target directory
    cd "$target_dir"
    
    # Generate wildcard certificates for the new domain
    if executeCommand "Generating SSL certificates" "${ROLL_DIR}/bin/roll" sign-certificate "*.${new_name}.test"; then
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
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would update URLs in database to use ${new_name}.test"
        return 0
    fi
    
    # Change to target directory
    cd "$target_dir"
    
    # Start the environment to update URLs
    if ! executeCommand "Starting environment for URL updates" "${ROLL_DIR}/bin/roll" env up -d; then
        logMessage ERROR "Failed to start environment for URL updates"
        return 1
    fi
    
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
    
    # Update core_config_data for base URLs
    logMessage INFO "Updating Magento 2 URLs to: $new_url"
    
    executeCommand "Updating base URLs in database" \
        bash -c "echo \"UPDATE core_config_data SET value = '${new_url}' WHERE path IN ('web/unsecure/base_url', 'web/secure/base_url');\" | ${ROLL_DIR}/bin/roll db import"
    
    executeCommand "Updating base link URLs in database" \
        bash -c "echo \"UPDATE core_config_data SET value = '${new_url}' WHERE path IN ('web/unsecure/base_link_url', 'web/secure/base_link_url');\" | ${ROLL_DIR}/bin/roll db import"
    
    # Update app/etc/env.php configuration
    updateMagentoEnvPhp "$new_url"
    
    logMessage INFO "Updated both database and env.php configurations"
    
    # Wait for services to be fully ready
    logMessage INFO "Waiting for Magento services to be ready..."
    sleep 10
    
    # Check if PHP container is responding
    local retry_count=0
    local max_retries=30
    while [ $retry_count -lt $max_retries ]; do
        if executeCommand "Testing PHP container readiness" "${ROLL_DIR}/bin/roll" clinotty php -v; then
            logMessage INFO "PHP container is ready"
            break
        fi
        sleep 2
        ((retry_count++))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        logMessage WARNING "PHP container not ready after ${max_retries} attempts, skipping Magento commands"
        return 0
    fi
    
    # Run post-duplication Magento commands
    if [[ $DUPLICATE_RUN_MAGENTO_COMMANDS -eq 1 ]]; then
        runMagentoCommands
    else
        logMessage INFO "Skipping Magento post-duplication commands (--no-magento-commands)"
    fi
}

function updateMagentoEnvPhp() {
    local new_url="$1"
    local env_php_file="app/etc/env.php"
    
    if [[ ! -f "$env_php_file" ]]; then
        logMessage WARNING "app/etc/env.php not found, skipping env.php URL update"
        return 0
    fi
    
    logMessage INFO "Updating URLs in app/etc/env.php"
    
    # Create backup
    cp "$env_php_file" "${env_php_file}.backup.$(date +%s)"
    
    # Update base URLs in env.php using sed
    sed_inplace "s|'base_url' => 'https://[^']*'|'base_url' => '${new_url}'|g" "$env_php_file"
    
    logMessage SUCCESS "Updated URLs in app/etc/env.php"
}

function runMagentoCommands() {
    logMessage INFO "Running Magento post-duplication commands..."
    
    # Import app configuration
    executeCommand "Executing app:config:import" "${ROLL_DIR}/bin/roll" magento app:config:import
    
    # Setup upgrade
    executeCommand "Executing setup:upgrade" "${ROLL_DIR}/bin/roll" magento setup:upgrade
    
    # DI compilation
    executeCommand "Executing setup:di:compile" "${ROLL_DIR}/bin/roll" magento setup:di:compile
    
    # Clean cache
    executeCommand "Executing cache:clean" "${ROLL_DIR}/bin/roll" magento cache:clean
    
    # Flush cache
    executeCommand "Executing cache:flush" "${ROLL_DIR}/bin/roll" magento cache:flush
    
    logMessage SUCCESS "Magento post-duplication commands completed"
}

function updateMagento1Urls() {
    local new_name="$1"
    local new_url="https://app.${new_name}.test/"
    
    executeCommand "Updating Magento 1 URLs" \
        bash -c "echo \"UPDATE core_config_data SET value = '${new_url}' WHERE path IN ('web/unsecure/base_url', 'web/secure/base_url');\" | ${ROLL_DIR}/bin/roll db import"
    
    logMessage INFO "Updated Magento 1 URLs to: $new_url"
}

function updateWordPressUrls() {
    local new_name="$1"
    local new_url="https://${new_name}.test"
    
    executeCommand "Updating WordPress URLs" \
        bash -c "echo \"UPDATE wp_options SET option_value = '${new_url}' WHERE option_name IN ('home', 'siteurl');\" | ${ROLL_DIR}/bin/roll db import"
    
    logMessage INFO "Updated WordPress URLs to: $new_url"
}

function startNewEnvironment() {
    local target_dir="$1"
    local step="$2"
    local total="$3"
    
    if [[ $DUPLICATE_START_ENV -eq 0 ]]; then
        return 0
    fi
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would start new environment"
        return 0
    fi
    
    # Change to target directory
    cd "$target_dir"
    
    # Start the environment
    if executeCommand "Starting new environment" "${ROLL_DIR}/bin/roll" env up -d; then
        logMessage SUCCESS "New environment started successfully"
        return 0
    else
        logMessage ERROR "Failed to start new environment"
        return 1
    fi
}

function setupNewEnvironment() {
    local new_name="$1"
    local step="$2" 
    local total="$3"
    
    local current_dir="$(pwd)"
    local target_dir="$(dirname "$current_dir")/${new_name}"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would create directory: $target_dir"
        logMessage INFO "[DRY RUN] Would copy environment files and source code"
        echo "$target_dir"
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
        if [[ $DUPLICATE_VERBOSE -eq 1 ]]; then
            rsync -av "${exclude_patterns[@]}" "$current_dir/" "$target_dir/" >&2
        else
            rsync -a "${exclude_patterns[@]}" "$current_dir/" "$target_dir/" >/dev/null 2>&1
        fi
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

function copyBackupToNewEnvironment() {
    local backup_id="$1"
    local new_name="$2" 
    local current_dir="$3"
    local step="$4"
    local total="$5"
    
    local target_dir="$(dirname "$current_dir")/${new_name}"
    local source_backup_dir="$current_dir/.roll/backups"
    local target_backup_dir="$target_dir/.roll/backups"
    
    if [[ $DUPLICATE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would copy backup $backup_id to $target_backup_dir"
        return 0
    fi
    
    # Create parent target directory first, then backup subdirectory
    logMessage INFO "Creating target directory structure: $target_dir"
    mkdir -p "$target_dir"
    mkdir -p "$target_backup_dir"
    
    # Find the backup archive directly (should exist immediately)
    local backup_archive=""
    
    # Just check the most common .tar.gz format directly
    backup_archive="${source_backup_dir}/backup_${ROLL_ENV_NAME}_${backup_id}.tar.gz"
    
    if [[ ! -f "$backup_archive" ]]; then
        # Try other extensions if .tar.gz doesn't exist
        for ext in ".tar.xz" ".tar.lz4" ".tar"; do
            local test_file="${source_backup_dir}/backup_${ROLL_ENV_NAME}_${backup_id}${ext}"
            if [[ -f "$test_file" ]]; then
                backup_archive="$test_file"
                break
            fi
        done
    fi
    
    if [[ -z "$backup_archive" ]]; then
        logMessage ERROR "Backup archive not found for ID: $backup_id in $source_backup_dir"
        logMessage ERROR "Expected pattern: backup_${ROLL_ENV_NAME}_${backup_id}.*"
        logMessage ERROR "Source backup directory contents:"
        ls -la "$source_backup_dir/" || logMessage ERROR "Failed to list source backup directory"
        return 1
    fi
    
    # Copy backup archive to new environment
    local archive_name="$(basename "$backup_archive")"
    logMessage INFO "Copying backup archive: $archive_name"
    logMessage INFO "From: $backup_archive"
    logMessage INFO "To: $target_backup_dir/"
    
    if ! cp "$backup_archive" "$target_backup_dir/"; then
        logMessage ERROR "Failed to copy backup archive to new environment"
        logMessage ERROR "Source exists: $(test -f "$backup_archive" && echo "YES" || echo "NO")"
        logMessage ERROR "Target dir exists: $(test -d "$target_backup_dir" && echo "YES" || echo "NO")"
        logMessage ERROR "Target dir writable: $(test -w "$target_backup_dir" && echo "YES" || echo "NO")"
        return 1
    fi
    
    # Verify the backup file was copied successfully
    local copied_backup_file="$target_backup_dir/$archive_name"
    if [[ ! -f "$copied_backup_file" ]]; then
        logMessage ERROR "Backup file was not successfully copied to: $copied_backup_file"
        logMessage ERROR "Target directory contents:"
        ls -la "$target_backup_dir/" || logMessage ERROR "Failed to list target backup directory"
        return 1
    fi
    
    logMessage SUCCESS "Backup archive copied successfully"
    logMessage INFO "Copied file: $copied_backup_file ($(du -h "$copied_backup_file" | cut -f1))"
    
    return 0
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
    local current_dir="$(pwd)"
    local total_steps=7
    local current_step=0
    
    logMessage INFO "Duplicating environment '$current_env_name' to '$new_name'"
    
    # Step 1: Create backup
    ((current_step++))
    local backup_id
    if ! backup_id=$(createBackup $current_step $total_steps); then
        logMessage ERROR "Failed to create backup"
        exit 1
    fi
    
    # Step 2: Setup new environment directory (rsync source code)
    ((current_step++))
    local target_dir
    if ! target_dir=$(setupNewEnvironment "$new_name" $current_step $total_steps 2>/dev/null); then
        logMessage ERROR "Failed to setup new environment directory"
        exit 1
    fi
    
    # Step 3: Copy backup file to target location AFTER rsync
    ((current_step++))
    if ! copyBackupToNewEnvironment "$backup_id" "$new_name" "$current_dir" $current_step $total_steps; then
        logMessage ERROR "Failed to copy backup file to new environment"
        exit 1
    fi
    
    # Step 4: Restore backup from already-copied file
    ((current_step++))
    if ! restoreBackup "$backup_id" "$target_dir" "$current_dir" $current_step $total_steps; then
        logMessage ERROR "Backup restoration step failed - stopping duplication process"
        exit 1
    fi
    
    # Step 5: Generate new certificates
    ((current_step++))
    generateCertificates "$new_name" "$target_dir" $current_step $total_steps
    
    # Step 6: Update database URLs
    ((current_step++))
    updateDatabaseUrls "$new_name" "$target_dir" $current_step $total_steps
    
    # Step 7: Start new environment
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