#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Load core utilities (environment config loaded later if needed)
assertDockerRunning

# Default configuration values
RESTORE_SERVICES=()
RESTORE_CONFIG=1
RESTORE_VERIFY=1
RESTORE_FORCE=0
RESTORE_DRY_RUN=0
RESTORE_QUIET=0
RESTORE_VERBOSE=0
RESTORE_DECRYPT=""
RESTORE_BACKUP_FILE=""
RESTORE_OUTPUT_DIR=""
PROGRESS=1
ROLL_ENV_LOADED=0

# Legacy migration support
RESTORE_LEGACY_MIGRATION=1

# Parse command line arguments
POSITIONAL_ARGS=()
# Start with any arguments passed from the main roll script
if [[ -n "${ROLL_PARAMS[*]}" ]]; then
    POSITIONAL_ARGS+=("${ROLL_PARAMS[@]}")
fi
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            roll restore-full --help
            exit 0
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
            break
            ;;
        -*)
            error "Unknown option: $1"
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Add any remaining arguments after -- to positional args
POSITIONAL_ARGS+=("$@")

# Expect exactly two positional arguments: archive and output directory
if [[ ${#POSITIONAL_ARGS[@]} -ne 2 ]]; then
    error "Usage: roll restore-full [options] archive output-dir"
    exit 1
fi

RESTORE_BACKUP_FILE="${POSITIONAL_ARGS[0]}"
RESTORE_OUTPUT_DIR="${POSITIONAL_ARGS[1]}"

# Set environment path
mkdir -p "$RESTORE_OUTPUT_DIR"
cd "$RESTORE_OUTPUT_DIR"
ROLL_ENV_PATH="$(pwd)"

# Utility functions for restore operations
function promptPassword() {
    local prompt="$1"
    local password=""
    
    # Don't prompt in quiet mode or non-interactive shells
    if [[ $RESTORE_QUIET -eq 1 ]] || [[ ! -t 0 ]]; then
        error "Password required but running in non-interactive mode. Use --decrypt=password instead."
        exit 1
    fi
    
    echo -n "$prompt: " >&2
    read -s password
    echo >&2
    
    if [[ -z "$password" ]]; then
        error "Password cannot be empty"
        exit 1
    fi
    
    echo "$password"
}

function detectEncryptedBackup() {
    local backup_path="$1"
    
    # Check if backup contains .gpg files
    if [[ -d "$backup_path" ]]; then
        # Directory format - check for .gpg files
        if find "$backup_path" -name "*.gpg" -type f | head -1 | grep -q .; then
            return 0  # Encrypted
        fi
    else
        # Archive format - check if archive contains .gpg files
        local archive_file="$backup_path"
        if [[ -f "$archive_file" ]]; then
            # Determine decompression command
            local decompress_cmd="cat"
            case "$archive_file" in
                *.tar.gz) decompress_cmd="gzip -dc" ;;
                *.tar.xz) decompress_cmd="xz -dc" ;;
                *.tar.lz4) decompress_cmd="lz4 -dc" ;;
            esac
            
            # Check if archive contains .gpg files
            if $decompress_cmd "$archive_file" | tar -tf - 2>/dev/null | grep -q "\.gpg$"; then
                return 0  # Encrypted
            fi
        fi
    fi
    
    return 1  # Not encrypted
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
    [[ $RESTORE_QUIET -eq 1 ]] && return
    local level="$1"
    shift
    case "$level" in
        INFO) info "$@" ;;
        SUCCESS) success "$@" ;;
        WARNING) warning "$@" ;;
        ERROR) error "$@" ;;
        VERBOSE) [[ $RESTORE_VERBOSE -eq 1 ]] && info "[VERBOSE] $@" ;;
    esac
}

function logVerbose() {
    [[ $RESTORE_VERBOSE -eq 1 ]] && logMessage INFO "$@"
}

function performLegacyMigration() {
    if [[ $RESTORE_LEGACY_MIGRATION -eq 0 ]]; then
        return 0
    fi
    
    local current_dir="$(pwd)"
    
    # Handle Warden to Roll migration
    if [[ ! -f "$current_dir/.env.roll" ]]; then
        if [[ -f "$current_dir/.env" ]]; then
            logMessage INFO "Performing legacy Warden to Roll migration..."
            
            # Create backup of original .env
            cp "$current_dir/.env" "$current_dir/.env.backup.$(date +%s)"
            
            # Convert WARDEN to ROLL
            sed -i.warden 's/WARDEN/ROLL/g' "$current_dir/.env"
            
            # Migrate .warden directory to .roll
            if [[ -d "$current_dir/.warden" ]]; then
                mv "$current_dir/.warden" "$current_dir/.roll"
                
                if [[ -f "$current_dir/.roll/warden-env.yml" ]]; then
                    mv "$current_dir/.roll/warden-env.yml" "$current_dir/.roll/roll-env.yml"
                    sed -i.warden 's/WARDEN/ROLL/g;s/warden/roll/g' "$current_dir/.roll/roll-env.yml"
                fi
            fi
            
            # Ensure ROLL_NO_STATIC_CACHING is set
            if [[ -n "$(grep -r 'ROLL_NO_STATIC_CACHING' "$current_dir/.env")" ]]; then
                perl -i -pe's/.*ROLL_NO_STATIC_CACHING.*$/ROLL_NO_STATIC_CACHING\=1/g' "$current_dir/.env"
            else
                echo "ROLL_NO_STATIC_CACHING=1" >> "$current_dir/.env"
            fi
            
            # Move to .env.roll if it contains ROLL_ variables
            if [[ -n "$(grep -r 'ROLL_' "$current_dir/.env")" ]]; then
                mv "$current_dir/.env" "$current_dir/.env.roll"
            fi
            
            logMessage SUCCESS "Legacy migration completed"
        fi
    fi
}

function findLatestBackup() {
    local backup_dir="$(pwd)/.roll/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        return 1
    fi
    
    # Look for timestamped directories first (new format)
    local latest_dir=$(ls "$backup_dir" 2>/dev/null | grep '^[0-9]\{10\}$' | sort -n | tail -1)
    if [[ -n "$latest_dir" ]]; then
        echo "$latest_dir"
        return 0
    fi
    
    # Look for compressed archives
    local latest_archive=$(ls "$backup_dir"/backup_*_*.tar* 2>/dev/null | sort | tail -1)
    if [[ -n "$latest_archive" ]]; then
        # Extract timestamp from filename
        local timestamp=$(basename "$latest_archive" | grep -o '[0-9]\{10\}')
        echo "$timestamp"
        return 0
    fi
    
    return 1
}

function extractBackupArchive() {
    local backup_id="$1"
    local backup_dir="$(pwd)/.roll/backups"
    local extract_dir="$backup_dir/${backup_id}_extracted"
    
    # Check if already extracted
    if [[ -d "$extract_dir" ]]; then
        echo "$extract_dir"
        return 0
    fi
    
    # Find the archive file
    local archive_file=""
    for ext in ".tar.gz" ".tar.xz" ".tar.lz4" ".tar"; do
        local potential_file="$backup_dir/backup_${ROLL_ENV_NAME}_${backup_id}${ext}"
        if [[ -f "$potential_file" ]]; then
            archive_file="$potential_file"
            break
        fi
    done
    
    # Also check for generic archive names
    if [[ -z "$archive_file" ]]; then
        archive_file=$(ls "$backup_dir"/*"$backup_id"*.tar* 2>/dev/null | head -1)
    fi
    
    if [[ -z "$archive_file" ]]; then
        logMessage ERROR "Backup archive not found for ID: $backup_id"
        return 1
    fi
    
    logMessage INFO "Extracting backup archive: $(basename "$archive_file")"
    
    mkdir -p "$extract_dir"
    
    # Determine decompression command based on file extension
    local decompress_cmd="cat"
    case "$archive_file" in
        *.tar.gz) decompress_cmd="gzip -d" ;;
        *.tar.xz) decompress_cmd="xz -d" ;;
        *.tar.lz4) decompress_cmd="lz4 -d" ;;
    esac
    
    if $decompress_cmd < "$archive_file" | tar -xf - -C "$extract_dir" --strip-components=1 2>/dev/null; then
        echo "$extract_dir"
        return 0
    else
        logMessage ERROR "Failed to extract backup archive"
        rm -rf "$extract_dir"
        return 1
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

function validateBackup() {
    local backup_path="$1"
    
    if [[ $RESTORE_VERIFY -eq 0 ]]; then
        return 0
    fi
    
    logMessage INFO "Validating backup integrity..."
    
    # Check if backup metadata exists
    if [[ ! -f "$backup_path/metadata/backup.json" ]]; then
        logMessage WARNING "Backup metadata not found, proceeding with legacy format"
        return 0
    fi
    
    # Verify checksums if available
    if [[ -f "$backup_path/metadata/checksums.sha256" ]]; then
        if (cd "$backup_path" && sha256sum -c metadata/checksums.sha256 >/dev/null 2>&1); then
            logMessage SUCCESS "Backup integrity verified"
            return 0
        else
            logMessage ERROR "Backup integrity check failed"
            return 1
        fi
    fi
    
    logMessage SUCCESS "Backup validation completed"
    return 0
}

function getBackupMetadata() {
    local backup_path="$1"
    local metadata_file="$backup_path/metadata/backup.json"
    
    if [[ -f "$metadata_file" ]]; then
        cat "$metadata_file"
    else
        # Return empty JSON for legacy backups
        echo "{}"
    fi
}

function detectBackupServices() {
    local backup_path="$1"
    local services=()
    
    # Check for volume backups
    if [[ -d "$backup_path/volumes" ]]; then
        for volume_file in "$backup_path/volumes"/*; do
            if [[ -f "$volume_file" ]]; then
                local service_name=$(basename "$volume_file" | sed 's/\.tar.*//')
                services+=("$service_name")
            fi
        done
    else
        # Legacy format detection
        if [[ -f "$backup_path/db.tar.gz" ]]; then
            services+=("db")
        fi
        if [[ -f "$backup_path/redis.tar.gz" ]]; then
            services+=("redis")
        fi
        if [[ -f "$backup_path/es.tar.gz" ]]; then
            services+=("elasticsearch")
        fi
    fi
    
    echo "${services[@]}"
}

function stopEnvironment() {
    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would stop environment"
        return 0
    fi

    logMessage INFO "Stopping environment for consistent restore..."
    logVerbose "Environment path: ${ROLL_ENV_PATH}"

    # Check if environment is configured before trying to stop it
    # The env commands require .env.roll to exist, which may not be the case
    # during a full restore (config comes from backup)
    if [[ ! -f "${ROLL_ENV_PATH}/.env.roll" ]]; then
        logMessage INFO "No environment configuration found yet, skipping stop"
        logVerbose "Missing file: ${ROLL_ENV_PATH}/.env.roll"
        return 0
    fi

    # Use docker compose directly instead of roll env to avoid exit on error
    # when environment is not fully configured
    local project_name="${ROLL_ENV_NAME:-}"
    if [[ -z "$project_name" ]]; then
        # Try to extract from .env.roll if available
        logVerbose "ROLL_ENV_NAME not set, extracting from .env.roll"
        project_name=$(grep -E "^ROLL_ENV_NAME=" "${ROLL_ENV_PATH}/.env.roll" 2>/dev/null | cut -d'=' -f2 | tr -d '"'"'" || true)
    fi

    logVerbose "Project name: ${project_name:-<not set>}"

    if [[ -n "$project_name" ]]; then
        # Check if any containers are running for this project
        logVerbose "Checking for running containers with label: com.docker.compose.project=${project_name}"
        local running_containers=$(docker ps --filter "label=com.docker.compose.project=${project_name}" --format '{{.Names}}' 2>/dev/null || true)
        if [[ -n "$running_containers" ]]; then
            logVerbose "Found running containers: $running_containers"
            logMessage INFO "Stopping running containers..."
            logVerbose "Executing: docker compose -p ${project_name} down"
            docker compose -p "${project_name}" down >/dev/null 2>&1 || true
            logVerbose "Containers stopped"
        else
            logVerbose "No running containers found"
        fi
    else
        logVerbose "No project name available, skipping container stop"
    fi
}

function getVolumeMapping() {
    local service_name="$1"
    
    case "$service_name" in
        db) 
            case "${DB_DISTRIBUTION:-mariadb}" in
                mysql|mariadb) echo "${ROLL_ENV_NAME}_dbdata:mysql" ;;
                postgres) echo "${ROLL_ENV_NAME}_dbdata:postgres" ;;
                *) echo "${ROLL_ENV_NAME}_dbdata:mysql" ;;
            esac
            ;;
        redis) echo "${ROLL_ENV_NAME}_redis:redis" ;;
        dragonfly) echo "${ROLL_ENV_NAME}_dragonfly:dragonfly" ;;
        elasticsearch) echo "${ROLL_ENV_NAME}_esdata:elasticsearch" ;;
        opensearch) echo "${ROLL_ENV_NAME}_osdata:opensearch" ;;
        mongodb) echo "${ROLL_ENV_NAME}_mongodb:mongodb" ;;
        rabbitmq) echo "${ROLL_ENV_NAME}_rabbitmq:rabbitmq" ;;
        varnish) echo "${ROLL_ENV_NAME}_varnish:varnish" ;;
        *) echo "${ROLL_ENV_NAME}_${service_name}:generic" ;;
    esac
}

function restoreVolume() {
    local service_name="$1"
    local backup_path="$2"
    local step="$3"
    local total="$4"

    showProgress $step $total "Restoring $service_name volume"

    local volume_mapping=$(getVolumeMapping "$service_name")
    IFS=':' read -r volume_name service_type <<< "$volume_mapping"

    logVerbose "Restoring service: $service_name"
    logVerbose "Volume mapping: $volume_mapping"
    logVerbose "Volume name: $volume_name, Service type: $service_type"

    # Determine backup file location (check for both encrypted and unencrypted)
    local backup_file=""
    local is_encrypted=false

    # Check for encrypted files first (.gpg extension)
    if [[ -f "$backup_path/volumes/${service_name}.tar.gz.gpg" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.gz.gpg"
        is_encrypted=true
    elif [[ -f "$backup_path/volumes/${service_name}.tar.xz.gpg" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.xz.gpg"
        is_encrypted=true
    elif [[ -f "$backup_path/volumes/${service_name}.tar.lz4.gpg" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.lz4.gpg"
        is_encrypted=true
    elif [[ -f "$backup_path/volumes/${service_name}.tar.gpg" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.gpg"
        is_encrypted=true
    # Check for unencrypted files
    elif [[ -f "$backup_path/volumes/${service_name}.tar.gz" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.gz"
    elif [[ -f "$backup_path/volumes/${service_name}.tar.xz" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.xz"
    elif [[ -f "$backup_path/volumes/${service_name}.tar.lz4" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar.lz4"
    elif [[ -f "$backup_path/volumes/${service_name}.tar" ]]; then
        backup_file="$backup_path/volumes/${service_name}.tar"
    elif [[ -f "$backup_path/${service_name}.tar.gz" ]]; then
        # Legacy format
        backup_file="$backup_path/${service_name}.tar.gz"
    else
        logMessage WARNING "Backup file not found for service: $service_name"
        logVerbose "Searched in: $backup_path/volumes/ and $backup_path/"
        return 0
    fi

    logVerbose "Found backup file: $backup_file"
    logVerbose "Encrypted: $is_encrypted"
    
    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        if [[ $is_encrypted == true ]]; then
            logMessage INFO "[DRY RUN] Would decrypt and restore $service_name from $backup_file to volume $volume_name"
        else
            logMessage INFO "[DRY RUN] Would restore $service_name from $backup_file to volume $volume_name"
        fi
        return 0
    fi
    
    # Validate decryption password if file is encrypted
    if [[ $is_encrypted == true ]]; then
        if [[ -z "$RESTORE_DECRYPT" ]]; then
            logMessage ERROR "Encrypted backup file found but no decryption password provided"
            return 1
        fi
    fi
    
    # Get Docker Compose version for proper labeling
    local docker_compose_version=$(docker compose version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    local volume_base_name=$(echo "$volume_name" | sed "s/${ROLL_ENV_NAME}_//")

    logVerbose "Docker Compose version: $docker_compose_version"
    logVerbose "Volume base name: $volume_base_name"

    # Remove existing volume if it exists
    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
        if [[ $RESTORE_FORCE -eq 1 ]]; then
            logMessage INFO "Removing existing volume: $volume_name"
            logVerbose "Executing: docker volume rm $volume_name"
            docker volume rm "$volume_name" >/dev/null 2>&1
        else
            logMessage ERROR "Volume $volume_name already exists. Use --force to overwrite."
            return 1
        fi
    else
        logVerbose "Volume $volume_name does not exist yet"
    fi

    # Create new volume with proper labels
    logVerbose "Creating volume: $volume_name with labels"
    logVerbose "  - com.docker.compose.project=$ROLL_ENV_NAME"
    logVerbose "  - com.docker.compose.version=$docker_compose_version"
    logVerbose "  - com.docker.compose.volume=$volume_base_name"
    docker volume create "$volume_name" \
        --label com.docker.compose.project="$ROLL_ENV_NAME" \
        --label com.docker.compose.version="$docker_compose_version" \
        --label com.docker.compose.volume="$volume_base_name" >/dev/null 2>&1

    # Restore the volume data with decryption if needed
    local temp_container="${ROLL_ENV_NAME}_restore_${service_name}_$$"
    logVerbose "Temp container name: $temp_container"
    
    if [[ $is_encrypted == true ]]; then
        # Decrypt and decompress pipeline - use ubuntu and original tar approach with strip components
        # Use passphrase-fd to avoid shell escaping issues with passwords
        # Determine the correct tar command based on the backup file format
        local tar_cmd="tar -xf -"
        case "$backup_file" in
            *.tar.gz.gpg) tar_cmd="tar -xzf -" ;;
            *.tar.xz.gpg) tar_cmd="tar -xJf -" ;;
            *.tar.lz4.gpg) tar_cmd="lz4 -d - | tar -xf -" ;;
        esac
        
        if echo "$RESTORE_DECRYPT" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$backup_file" | docker run --rm --name "$temp_container" --mount source="$volume_name",target=/data -i ubuntu bash -c "cd /data && $tar_cmd --strip-components=1" 2>/dev/null; then
            logMessage SUCCESS "Successfully restored and decrypted $service_name volume"
            return 0
        else
            logMessage ERROR "Failed to decrypt and restore $service_name volume"
            return 1
        fi
    else
        # Regular restore without decryption - use ubuntu and original tar approach with strip components
        # For compressed files, we need to handle decompression properly
        case "$backup_file" in
            *.tar.gz)
                if docker run --rm --name "$temp_container" \
                    --mount source="$volume_name",target=/data \
                    -v "$(dirname "$backup_file")":/backup \
                    ubuntu bash \
                    -c "cd /data && tar -xzf /backup/$(basename "$backup_file") --strip-components=1" 2>/dev/null; then
                    
                    logMessage SUCCESS "Successfully restored $service_name volume"
                    return 0
                else
                    logMessage ERROR "Failed to restore $service_name volume"
                    return 1
                fi
                ;;
            *.tar.xz)
                if docker run --rm --name "$temp_container" \
                    --mount source="$volume_name",target=/data \
                    -v "$(dirname "$backup_file")":/backup \
                    ubuntu bash \
                    -c "cd /data && tar -xJf /backup/$(basename "$backup_file") --strip-components=1" 2>/dev/null; then
                    
                    logMessage SUCCESS "Successfully restored $service_name volume"
                    return 0
                else
                    logMessage ERROR "Failed to restore $service_name volume"
                    return 1
                fi
                ;;
            *.tar.lz4)
                if docker run --rm --name "$temp_container" \
                    --mount source="$volume_name",target=/data \
                    -v "$(dirname "$backup_file")":/backup \
                    ubuntu bash \
                    -c "cd /data && lz4 -d /backup/$(basename "$backup_file") - | tar -xf - --strip-components=1" 2>/dev/null; then
                    
                    logMessage SUCCESS "Successfully restored $service_name volume"
                    return 0
                else
                    logMessage ERROR "Failed to restore $service_name volume"
                    return 1
                fi
                ;;
            *.tar)
                if docker run --rm --name "$temp_container" \
                    --mount source="$volume_name",target=/data \
                    -v "$(dirname "$backup_file")":/backup \
                    ubuntu bash \
                    -c "cd /data && tar -xf /backup/$(basename "$backup_file") --strip-components=1" 2>/dev/null; then
                    
                    logMessage SUCCESS "Successfully restored $service_name volume"
                    return 0
                else
                    logMessage ERROR "Failed to restore $service_name volume"
                    return 1
                fi
                ;;
            *)
                logMessage ERROR "Unsupported backup file format: $backup_file"
                return 1
                ;;
        esac
    fi
}

function restoreConfigurations() {
    local backup_path="$1"
    local step="$2"
    local total="$3"
    
    if [[ $RESTORE_CONFIG -eq 0 ]]; then
        return 0
    fi
    
    showProgress $step $total "Restoring configuration files"
    
    local config_source_dir="$backup_path/config"
    local current_dir="$(pwd)"
    
    # Legacy format support
    if [[ ! -d "$config_source_dir" ]]; then
        # Check for legacy files in backup root (both encrypted and unencrypted)
        local legacy_files=("env.php" "auth.json")
        for file in "${legacy_files[@]}"; do
            local source_file=""
            local is_encrypted=false
            
            # Check for encrypted version first
            if [[ -f "$backup_path/${file}.gpg" ]]; then
                source_file="$backup_path/${file}.gpg"
                is_encrypted=true
            elif [[ -f "$backup_path/$file" ]]; then
                source_file="$backup_path/$file"
            fi
            
            if [[ -n "$source_file" ]]; then
                local target_path=""
                case "$file" in
                    env.php) target_path="$current_dir/app/etc/env.php" ;;
                    auth.json) target_path="$current_dir/auth.json" ;;
                esac
                
                if [[ -n "$target_path" ]]; then
                    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
                        if [[ $is_encrypted == true ]]; then
                            logMessage INFO "[DRY RUN] Would decrypt and restore $file to $target_path"
                        else
                            logMessage INFO "[DRY RUN] Would restore $file to $target_path"
                        fi
                    else
                        mkdir -p "$(dirname "$target_path")"
                        
                        if [[ $is_encrypted == true ]]; then
                            # Decrypt the file directly to target location
                            if [[ -n "$RESTORE_DECRYPT" ]]; then
                                if echo "$RESTORE_DECRYPT" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$source_file" > "$target_path"; then
                                    logMessage INFO "Decrypted and restored $file"
                                else
                                    logMessage ERROR "Failed to decrypt $file"
                                    return 1
                                fi
                            else
                                logMessage ERROR "Encrypted config file found but no decryption password provided"
                                return 1
                            fi
                        else
                            cp "$source_file" "$target_path"
                            logMessage INFO "Restored $file"
                        fi
                    fi
                fi
            fi
        done
        return 0
    fi
    
    # New format with structured config directory
    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would restore configuration files from $config_source_dir"
        return 0
    fi
    
    # Restore configuration files (both encrypted and unencrypted)
    if [[ -d "$config_source_dir" ]]; then
        # Process all files including .gpg files
        find "$config_source_dir" -type f | while read -r config_file; do
            local relative_path="${config_file#$config_source_dir/}"
            local is_encrypted=false
            
            # Check if file is encrypted
            if [[ "$config_file" == *.gpg ]]; then
                is_encrypted=true
                # Remove .gpg extension for target path
                relative_path="${relative_path%.gpg}"
            fi
            
            local target_path="$current_dir/$relative_path"
            
            # Create target directory if needed
            mkdir -p "$(dirname "$target_path")"
            
            # Backup existing file if it exists
            if [[ -f "$target_path" ]]; then
                if [[ $is_encrypted == true ]]; then
                    # For encrypted files, we can't easily compare so always backup
                    cp "$target_path" "$target_path.backup.$(date +%s)"
                    logMessage INFO "Backed up existing $relative_path"
                elif ! cmp -s "$config_file" "$target_path"; then
                    cp "$target_path" "$target_path.backup.$(date +%s)"
                    logMessage INFO "Backed up existing $relative_path"
                fi
            fi
            
            if [[ $is_encrypted == true ]]; then
                # Decrypt the file
                if [[ -n "$RESTORE_DECRYPT" ]]; then
                    if echo "$RESTORE_DECRYPT" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$config_file" > "$target_path"; then
                        logMessage INFO "Decrypted and restored $relative_path"
                    else
                        logMessage ERROR "Failed to decrypt $relative_path"
                        return 1
                    fi
                else
                    logMessage ERROR "Encrypted config file found but no decryption password provided"
                    return 1
                fi
            else
                # Copy unencrypted file
                cp "$config_file" "$target_path"
                logMessage INFO "Restored $relative_path"
            fi
        done
    fi
    
    logMessage SUCCESS "Configuration restore completed"
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

    local decompress_cmd="cat"
    case "$src_file" in
        *.tar.gz*) decompress_cmd="gzip -dc" ;;
        *.tar.xz*) decompress_cmd="xz -dc" ;;
        *.tar.lz4*) decompress_cmd="lz4 -dc" ;;
    esac

    if [[ $is_encrypted == true ]]; then
        if [[ -z "$RESTORE_DECRYPT" ]]; then
            logMessage ERROR "Encrypted source archive found but no decryption password provided"
            return 1
        fi
        if echo "$RESTORE_DECRYPT" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$src_file" | $decompress_cmd | tar -xf - -C "$target_dir" 2>/dev/null; then
            logMessage SUCCESS "Source code restored"
            return 0
        else
            logMessage ERROR "Failed to restore source code"
            return 1
        fi
    else
        if $decompress_cmd "$src_file" | tar -xf - -C "$target_dir" 2>/dev/null; then
            logMessage SUCCESS "Source code restored"
            return 0
        else
            logMessage ERROR "Failed to restore source code"
            return 1
        fi
    fi
}

function performRestore() {

    logVerbose "Starting full restore process"
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
        logVerbose "Backup is a file, extracting..."
        backup_path=$(extractBackupArchiveFile "$RESTORE_BACKUP_FILE")
    elif [[ -d "$RESTORE_BACKUP_FILE" ]]; then
        logVerbose "Backup is a directory"
        backup_path="$RESTORE_BACKUP_FILE"
    else
        logMessage ERROR "Backup file not found: $RESTORE_BACKUP_FILE"
        exit 1
    fi

    logVerbose "Backup path resolved to: $backup_path"
    
    # Detect if backup is encrypted and handle password prompting
    if detectEncryptedBackup "$backup_path"; then
        if [[ -z "$RESTORE_DECRYPT" ]]; then
            # No password provided, prompt for it
            RESTORE_DECRYPT=$(promptPassword "Encrypted backup detected. Enter decryption password")
        elif [[ "$RESTORE_DECRYPT" == "PROMPT" ]]; then
            # Explicit prompt requested
            RESTORE_DECRYPT=$(promptPassword "Enter decryption password")
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
    logMessage INFO "Restoring backup from: $(basename \"$RESTORE_BACKUP_FILE\")"
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
        ROLL_ENV_NAME=$(echo "$metadata" | grep -o '"environment"[^"]*"' | head -1 | sed 's/.*"environment"[ ]*:[ ]*"\([^"]*\)".*/\1/')
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
        restoreSourceCode "$backup_path" "$ROLL_ENV_PATH" $current_step $total_steps
    fi

    # Restore configurations
    if [[ $RESTORE_CONFIG -eq 1 ]]; then
        current_step=$((current_step + 1))
        restoreConfigurations "$backup_path" $current_step $total_steps
        if [[ $ROLL_ENV_LOADED -eq 0 ]]; then
            loadEnvConfig "$ROLL_ENV_PATH" || exit 1
            ROLL_ENV_LOADED=1
        fi
    fi

    # Restore volumes
    for service in "${services_to_restore[@]}"; do
        current_step=$((current_step + 1))
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
        logMessage INFO "You can now start your environment with: roll env up"
    fi
}

# Main execution
performRestore
