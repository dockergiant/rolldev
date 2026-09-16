#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## bin/roll stops parsing at the first flag, so positionals before it are in ROLL_PARAMS and the
## rest in "$@"; restore reads both, in order
set -- "${ROLL_PARAMS[@]}" "$@"

## --include-source restores into a new directory whose .env.roll comes out of the backup, so there
## is no environment to load; settle that before the preamble
RESTORE_INCLUDE_SOURCE=0
for restore_arg in "$@"; do
    if [[ "${restore_arg}" == "--include-source" ]]; then
        RESTORE_INCLUDE_SOURCE=1
        break
    fi
done

if [[ ${RESTORE_INCLUDE_SOURCE} -eq 0 ]]; then
    # Load core utilities and configuration
    ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
    loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
fi
assertDockerRunning

# Default configuration values
RESTORE_BACKUP_ID=""
RESTORE_BACKUP_FILE=""
RESTORE_OUTPUT_DIR=""
ROLL_ENV_LOADED=0
RESTORE_SERVICES=()
RESTORE_CONFIG=1
RESTORE_VERIFY=1
RESTORE_FORCE=0
RESTORE_DRY_RUN=0
RESTORE_QUIET=0
RESTORE_VERBOSE=0
RESTORE_DECRYPT=""
RESTORE_POSITIONALS=()
PROGRESS=1

# Legacy migration support
RESTORE_LEGACY_MIGRATION=1

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        --include-source)
            RESTORE_INCLUDE_SOURCE=1
            shift
            ;;
        --backup-id=*|--backup=*)
            RESTORE_BACKUP_ID="${1#*=}"
            shift
            ;;
        --services=*)
            IFS=',' read -ra RESTORE_SERVICES <<< "${1#*=}"
            shift
            ;;
        --no-config)
            RESTORE_CONFIG=0
            shift
            ;;
        --no-verify)
            RESTORE_VERIFY=0
            shift
            ;;
        --force|-f)
            RESTORE_FORCE=1
            shift
            ;;
        --dry-run)
            RESTORE_DRY_RUN=1
            shift
            ;;
        --quiet|-q)
            RESTORE_QUIET=1
            PROGRESS=0
            shift
            ;;
        --verbose|-v)
            RESTORE_VERBOSE=1
            shift
            ;;
        --decrypt=*)
            RESTORE_DECRYPT="${1#*=}"
            shift
            ;;
        --decrypt)
            # Flag without value - will prompt for password later
            RESTORE_DECRYPT="PROMPT"
            shift
            ;;
        --no-progress)
            PROGRESS=0
            shift
            ;;
        --no-legacy-migration)
            RESTORE_LEGACY_MIGRATION=0
            shift
            ;;
        --)
            shift
            RESTORE_POSITIONALS+=("$@")
            break
            ;;
        -*)
            error "Unknown option: $1"
            exit 1
            ;;
        *)
            RESTORE_POSITIONALS+=("$1")
            shift
            ;;
    esac
done

for restore_positional in "${RESTORE_POSITIONALS[@]}"; do
    if [[ ${RESTORE_INCLUDE_SOURCE} -eq 1 ]]; then
        ## archive first, target directory second
        if [[ -z "$RESTORE_BACKUP_FILE" ]]; then
            RESTORE_BACKUP_FILE="$restore_positional"
        elif [[ -z "$RESTORE_OUTPUT_DIR" ]]; then
            RESTORE_OUTPUT_DIR="$restore_positional"
        else
            error "Unexpected argument: $restore_positional"
            RESTORE_BACKUP_FILE=""
        fi
    elif [[ "$restore_positional" == "all" ]]; then
        # "roll restore all" from the old interface means the latest backup, which is the default
        continue
    elif [[ -z "$RESTORE_BACKUP_ID" && "$restore_positional" =~ ^[0-9]+$ ]]; then
        RESTORE_BACKUP_ID="$restore_positional"
    else
        ## older versions ignored words such as "db" here; matching them against archive names could
        ## pick an unrelated backup
        warning "Ignoring argument '$restore_positional': backup IDs are numeric. Use --backup-id=<id> or --services=<list>."
    fi
done

## A full restore works from inside the target directory, so every later $(pwd) is the restored project
if [[ ${RESTORE_INCLUDE_SOURCE} -eq 1 ]]; then
    if [[ -z "$RESTORE_BACKUP_FILE" || -z "$RESTORE_OUTPUT_DIR" ]]; then
        if [[ "${ROLL_CMD_VERB:-restore}" == "restore-full" ]]; then
            error "Usage: roll restore-full <archive> <output-dir>"
        else
            error "Usage: roll restore --include-source <archive> <output-dir>"
        fi
        exit 1
    fi

    ## resolve the archive before cd, so a relative path still means what the caller typed
    case "$RESTORE_BACKUP_FILE" in
        /*) ;;
        *) RESTORE_BACKUP_FILE="$(pwd)/${RESTORE_BACKUP_FILE}" ;;
    esac

    mkdir -p "$RESTORE_OUTPUT_DIR"
    cd "$RESTORE_OUTPUT_DIR" || fatal "Could not enter ${RESTORE_OUTPUT_DIR}"
    ROLL_ENV_PATH="$(pwd)"
fi

function performRestore() {
    local backup_id="$1"
    
    # Perform legacy migration if needed
    performLegacyMigration
    
    # Validate database environment
    if [[ ${ROLL_DB:-1} -eq 0 ]]; then
        logMessage ERROR "Database environment is not enabled (ROLL_DB=0)"
        exit 1
    fi
    
    # Find backup if not specified
    if [[ -z "$backup_id" ]]; then
        backup_id=$(findLatestBackup)
        if [[ -z "$backup_id" ]]; then
            logMessage ERROR "No backups found and no backup ID specified"
            exit 1
        fi
        logMessage INFO "Using latest backup: $backup_id"
    fi
    
    # Determine backup path
    local backup_path="$(pwd)/.roll/backups/$backup_id"
    
    # Check if backup exists as directory
    if [[ ! -d "$backup_path" ]]; then
        # Try to extract from archive
        backup_path=$(extractBackupArchive "$backup_id")
        if [[ $? -ne 0 ]]; then
            logMessage ERROR "Backup not found: $backup_id"
            exit 1
        fi
    fi
    
    # Detect if backup is encrypted and handle password prompting. Quiet mode is an explicit
    # request for no interaction, so it stays a hard error even when stdin is a terminal.
    if detectEncryptedBackup "$backup_path"; then
        assertGpgInstalled
        if [[ -z "$RESTORE_DECRYPT" ]] || [[ "$RESTORE_DECRYPT" == "PROMPT" ]]; then
            if [[ $RESTORE_QUIET -eq 1 ]]; then
                fatal "Password required but running in quiet mode. Use --decrypt=<password> instead."
            fi
            RESTORE_DECRYPT=""
            promptPassword RESTORE_DECRYPT "--decrypt=<password>" "Encrypted backup detected. Enter decryption password"
        fi

        if [[ -z "$RESTORE_DECRYPT" ]]; then
            logMessage ERROR "Encrypted backup requires a password. Use --decrypt=password or --decrypt to prompt."
            exit 1
        fi
        
        logMessage INFO "Encrypted backup detected, will decrypt during restoration"
    fi
    
    # Validate backup
    validateBackup "$backup_path" || exit 1
    
    # Get backup metadata
    local metadata=$(getBackupMetadata "$backup_path")
    logMessage INFO "Restoring backup: $backup_id"
    
    # Detect available services in backup
    local available_services=($(detectBackupServices "$backup_path"))
    if [[ ${#available_services[@]} -eq 0 ]]; then
        logMessage ERROR "No services found in backup"
        exit 1
    fi
    
    logMessage INFO "Available services in backup: ${available_services[*]}"
    
    # Determine which services to restore
    local services_to_restore=()
    if [[ ${#RESTORE_SERVICES[@]} -gt 0 ]]; then
        # Use specified services
        for service in "${RESTORE_SERVICES[@]}"; do
            if containsElement "$service" "${available_services[@]}"; then
                services_to_restore+=("$service")
            else
                logMessage WARNING "Service $service not found in backup, skipping"
            fi
        done
    else
        # Restore all available services
        services_to_restore=("${available_services[@]}")
    fi
    
    if [[ ${#services_to_restore[@]} -eq 0 ]]; then
        logMessage ERROR "No services to restore"
        exit 1
    fi
    
    logMessage INFO "Restoring services: ${services_to_restore[*]}"
    
    # Stop environment
    stopEnvironment
    
    # Calculate total steps
    local total_steps=${#services_to_restore[@]}
    if [[ $RESTORE_CONFIG -eq 1 ]]; then
        total_steps=$((total_steps + 1))
    fi

    local current_step=0

    # Restore volumes
    for service in "${services_to_restore[@]}"; do
        current_step=$((current_step + 1))
        logMessage INFO "Restoring ${service} volume..."
        restoreVolume "$service" "$backup_path" $current_step $total_steps
    done

    # Restore configurations
    if [[ $RESTORE_CONFIG -eq 1 ]]; then
        current_step=$((current_step + 1))
        logMessage INFO "Restoring configuration files..."
        restoreConfigurations "$backup_path" $current_step $total_steps
    fi
    
    # Clean up extracted backup if it was temporary
    if [[ "$backup_path" =~ _extracted$ ]]; then
        rm -rf "$backup_path"
    fi
    
    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        logMessage SUCCESS "Dry run completed successfully!"
    else
        logMessage SUCCESS "Restore completed successfully!"

        # Auto-sign SSL certificate for the environment domain
        signEnvironmentCertificate

        logMessage INFO "You can now start your environment with: roll env up"
    fi
}


function extractBackupArchiveFile() {
    local archive_file="$1"
    local backup_dir="$(pwd)/.roll/backups"
    local base_name="$(basename "$archive_file")"
    base_name="${base_name%%.tar*}"
    local extract_dir="$backup_dir/${base_name}_extracted"

    logVerbose "Extracting backup archive file"
    logVerbose "Archive file: $archive_file"
    logVerbose "Backup directory: $backup_dir"
    logVerbose "Extract directory: $extract_dir"

    if [[ -d "$extract_dir" ]]; then
        logVerbose "Found already extracted backup at: $extract_dir"
        echo "$extract_dir"
        return 0
    fi

    mkdir -p "$extract_dir"

    local decompress_cmd="cat"
    case "$archive_file" in
        *.tar.gz) decompress_cmd="gzip -d" ;;
        *.tar.xz) decompress_cmd="xz -d" ;;
        *.tar.lz4) decompress_cmd="lz4 -d" ;;
    esac

    logVerbose "Using decompression command: $decompress_cmd"

    if $decompress_cmd < "$archive_file" | tar -xf - -C "$extract_dir" --strip-components=1 2>/dev/null; then
        logVerbose "Successfully extracted to: $extract_dir"
        echo "$extract_dir"
        return 0
    else
        logMessage ERROR "Failed to extract backup archive"
        rm -rf "$extract_dir"
        return 1
    fi
}

function restoreSourceCode() {
    local backup_path="$1"
    local target_dir="$2"
    local step="$3"
    local total="$4"

    showProgress $step $total "Restoring source code"

    local src_file=""
    local is_encrypted=false

    for ext in ".tar.gz" ".tar.xz" ".tar.lz4" ".tar"; do
        if [[ -f "$backup_path/source${ext}.gpg" ]]; then
            src_file="$backup_path/source${ext}.gpg"
            is_encrypted=true
            break
        elif [[ -f "$backup_path/source${ext}" ]]; then
            src_file="$backup_path/source${ext}"
            break
        fi
    done

    if [[ -z "$src_file" ]]; then
        logMessage INFO "No source code archive found in backup"
        return 0
    fi

    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would extract source code to $target_dir"
        return 0
    fi

    mkdir -p "$target_dir"

    # Use direct file reading instead of piping for cross-platform compatibility
    # BSD tar (macOS) doesn't reliably handle piped stdin with -C flag
    # Both BSD and GNU tar auto-detect compression format with -xf
    if [[ $is_encrypted == true ]]; then
        if [[ -z "$RESTORE_DECRYPT" ]]; then
            logMessage ERROR "Encrypted source archive found but no decryption password provided"
            return 1
        fi
        # Decrypt to temp file first, then extract directly
        local temp_file="$backup_path/source_decrypted.tar"
        case "$src_file" in
            *.tar.gz.gpg) temp_file="$backup_path/source_decrypted.tar.gz" ;;
            *.tar.xz.gpg) temp_file="$backup_path/source_decrypted.tar.xz" ;;
            *.tar.lz4.gpg) temp_file="$backup_path/source_decrypted.tar.lz4" ;;
        esac

        if echo "$RESTORE_DECRYPT" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$src_file" > "$temp_file"; then
            if tar -xf "$temp_file" -C "$target_dir"; then
                rm -f "$temp_file"
                logMessage SUCCESS "Source code restored"
                return 0
            else
                rm -f "$temp_file"
                logMessage ERROR "Failed to extract source code"
                return 1
            fi
        else
            rm -f "$temp_file" 2>/dev/null
            logMessage ERROR "Failed to decrypt source archive"
            return 1
        fi
    else
        # Direct extraction - works on both BSD tar (macOS) and GNU tar (Linux)
        if tar -xf "$src_file" -C "$target_dir"; then
            logMessage SUCCESS "Source code restored"
            return 0
        else
            logMessage ERROR "Failed to restore source code"
            return 1
        fi
    fi
}

function performFullRestore() {
    logMessage INFO "Starting full restore from $(basename "$RESTORE_BACKUP_FILE")..."

    logVerbose "Backup file: $RESTORE_BACKUP_FILE"
    logVerbose "Output directory: $RESTORE_OUTPUT_DIR"
    logVerbose "Environment path: $ROLL_ENV_PATH"

    # Perform legacy migration if needed
    performLegacyMigration

    # Validate database environment
    if [[ ${ROLL_DB:-1} -eq 0 ]]; then
        logMessage ERROR "Database environment is not enabled (ROLL_DB=0)"
        exit 1
    fi

    # Determine backup path from archive argument
    local backup_path=""

    logVerbose "Checking backup file type..."
    if [[ -f "$RESTORE_BACKUP_FILE" ]]; then
        logMessage INFO "Extracting backup archive..."
        logVerbose "Backup is a file, extracting..."
        backup_path=$(extractBackupArchiveFile "$RESTORE_BACKUP_FILE")
        logMessage SUCCESS "Archive extracted"
    elif [[ -d "$RESTORE_BACKUP_FILE" ]]; then
        logVerbose "Backup is a directory"
        backup_path="$RESTORE_BACKUP_FILE"
    else
        logMessage ERROR "Backup file not found: $RESTORE_BACKUP_FILE"
        exit 1
    fi

    logVerbose "Backup path resolved to: $backup_path"
    
    # Detect if backup is encrypted and handle password prompting. Quiet mode is an explicit
    # request for no interaction, so it stays a hard error even when stdin is a terminal.
    if detectEncryptedBackup "$backup_path"; then
        assertGpgInstalled
        if [[ -z "$RESTORE_DECRYPT" ]] || [[ "$RESTORE_DECRYPT" == "PROMPT" ]]; then
            if [[ $RESTORE_QUIET -eq 1 ]]; then
                fatal "Password required but running in quiet mode. Use --decrypt=<password> instead."
            fi
            RESTORE_DECRYPT=""
            promptPassword RESTORE_DECRYPT "--decrypt=<password>" "Encrypted backup detected. Enter decryption password"
        fi

        if [[ -z "$RESTORE_DECRYPT" ]]; then
            logMessage ERROR "Encrypted backup requires a password. Use --decrypt=password or --decrypt to prompt."
            exit 1
        fi
        
        logMessage INFO "Encrypted backup detected, will decrypt during restoration"
    fi
    
    # Validate backup
    validateBackup "$backup_path" || exit 1
    
    # Get backup metadata
    local metadata=$(getBackupMetadata "$backup_path")
    logMessage INFO "Restoring backup from: $(basename "$RESTORE_BACKUP_FILE")"
    logVerbose "Backup metadata: $metadata"

    local source_exists=0
    for ext in ".tar.gz" ".tar.xz" ".tar.lz4" ".tar"; do
        if [[ -f "$backup_path/source${ext}" ]] || [[ -f "$backup_path/source${ext}.gpg" ]]; then
            logVerbose "Found source archive: source${ext}"
            source_exists=1
            break
        fi
    done
    logVerbose "Source code exists in backup: $source_exists"

    if [[ $ROLL_ENV_LOADED -eq 0 ]]; then
        ROLL_ENV_NAME=$(echo "$metadata" | sed -n 's/.*"environment"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        logVerbose "Extracted ROLL_ENV_NAME from metadata: ${ROLL_ENV_NAME:-<empty>}"
    fi
    
    # Detect available services in backup
    local available_services=($(detectBackupServices "$backup_path"))
    if [[ ${#available_services[@]} -eq 0 ]]; then
        logMessage ERROR "No services found in backup"
        exit 1
    fi
    
    logMessage INFO "Available services in backup: ${available_services[*]}"

    # Determine which services to restore
    local services_to_restore=()
    if [[ ${#RESTORE_SERVICES[@]} -gt 0 ]]; then
        logVerbose "User specified services to restore: ${RESTORE_SERVICES[*]}"
        # Use specified services
        for service in "${RESTORE_SERVICES[@]}"; do
            if containsElement "$service" "${available_services[@]}"; then
                services_to_restore+=("$service")
            else
                logMessage WARNING "Service $service not found in backup, skipping"
            fi
        done
    else
        logVerbose "No specific services requested, restoring all available"
        # Restore all available services
        services_to_restore=("${available_services[@]}")
    fi
    
    if [[ ${#services_to_restore[@]} -eq 0 ]]; then
        logMessage ERROR "No services to restore"
        exit 1
    fi
    
    logMessage INFO "Restoring services: ${services_to_restore[*]}"
    
    # Stop environment
    stopEnvironment
    
    # Calculate total steps
    local total_steps=${#services_to_restore[@]}
    if [[ $RESTORE_CONFIG -eq 1 ]]; then
        total_steps=$((total_steps + 1))
    fi
    if [[ $source_exists -eq 1 ]]; then
        total_steps=$((total_steps + 1))
    fi

    local current_step=0

    # Restore source code if available
    if [[ $source_exists -eq 1 ]]; then
        current_step=$((current_step + 1))
        logMessage INFO "Restoring source code..."
        restoreSourceCode "$backup_path" "$ROLL_ENV_PATH" $current_step $total_steps
    fi

    # Restore configurations
    if [[ $RESTORE_CONFIG -eq 1 ]]; then
        current_step=$((current_step + 1))
        logMessage INFO "Restoring configuration files..."
        restoreConfigurations "$backup_path" $current_step $total_steps
        ## a dry run writes no .env.roll to load
        if [[ $ROLL_ENV_LOADED -eq 0 && $RESTORE_DRY_RUN -eq 0 ]]; then
            loadEnvConfig "$ROLL_ENV_PATH" || exit 1
            ROLL_ENV_LOADED=1
        fi
    fi

    # Restore volumes
    for service in "${services_to_restore[@]}"; do
        current_step=$((current_step + 1))
        logMessage INFO "Restoring ${service} volume..."
        restoreVolume "$service" "$backup_path" $current_step $total_steps
    done
    
    # Clean up extracted backup if it was temporary
    if [[ "$backup_path" =~ _extracted$ ]]; then
        rm -rf "$backup_path"
    fi
    
    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        logMessage SUCCESS "Dry run completed successfully!"
    else
        logMessage SUCCESS "Restore completed successfully!"

        # Auto-sign SSL certificate for the environment domain
        signEnvironmentCertificate

        logMessage INFO "You can now start your environment with: roll env up"
    fi
}

# Main execution
if [[ ${RESTORE_INCLUDE_SOURCE} -eq 1 ]]; then
    performFullRestore
    exit $?
fi

if [[ -z "$RESTORE_BACKUP_ID" ]]; then
    # If no backup ID provided, use the latest; findLatestBackup returns 1 when there is none
    RESTORE_BACKUP_ID=$(findLatestBackup) || true
    if [[ -z "$RESTORE_BACKUP_ID" ]]; then
        error "No backups found. Please create a backup first with: roll backup"
        exit 1
    fi
    logMessage INFO "No backup ID specified, using latest: $RESTORE_BACKUP_ID"
fi

performRestore "$RESTORE_BACKUP_ID"
