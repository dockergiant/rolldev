#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Load core utilities and configuration
ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

# Default configuration values
BACKUP_COMPRESSION="gzip"  # Options: gzip, xz, lz4, none
BACKUP_ENCRYPT=""
BACKUP_EXCLUDE_LOGS=1
BACKUP_INCLUDE_SOURCE=0
BACKUP_PARALLEL=1
BACKUP_RETENTION_DAYS=30
BACKUP_VERIFY=1
BACKUP_QUIET=0
BACKUP_OUTPUT_ID=0
BACKUP_NAME=""
BACKUP_DESCRIPTION=""
BACKUP_DUPLICATE_NAME=""  # New environment name for duplication
BACKUP_DUPLICATE_DOMAIN=""  # New domain for duplication
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
            roll backup --help
            exit 0
            ;;
        --compression=*)
            BACKUP_COMPRESSION="${1#*=}"
            shift
            ;;
        --encrypt=*)
            BACKUP_ENCRYPT="${1#*=}"
            shift
            ;;
        --encrypt)
            # Flag without value - will prompt for password later
            BACKUP_ENCRYPT="PROMPT"
            shift
            ;;
        --no-compression)
            BACKUP_COMPRESSION="none"
            shift
            ;;
        --include-logs)
            BACKUP_EXCLUDE_LOGS=0
            shift
            ;;
        --include-source)
            BACKUP_INCLUDE_SOURCE=1
            shift
            ;;
        --no-parallel)
            BACKUP_PARALLEL=0
            shift
            ;;
        --retention=*)
            BACKUP_RETENTION_DAYS="${1#*=}"
            shift
            ;;
        --no-verify)
            BACKUP_VERIFY=0
            shift
            ;;
        --quiet|-q)
            BACKUP_QUIET=1
            PROGRESS=0
            shift
            ;;
        --output-id)
            BACKUP_OUTPUT_ID=1
            BACKUP_QUIET=1
            PROGRESS=0
            shift
            ;;
        --name=*)
            BACKUP_NAME="${1#*=}"
            shift
            ;;
        --description=*)
            BACKUP_DESCRIPTION="${1#*=}"
            shift
            ;;
        --duplicate-name=*)
            BACKUP_DUPLICATE_NAME="${1#*=}"
            shift
            ;;
        --duplicate-domain=*)
            BACKUP_DUPLICATE_DOMAIN="${1#*=}"
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
            # Collect positional arguments (commands)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Add any remaining arguments after -- to positional args
POSITIONAL_ARGS+=("$@")

# Set remaining parameters from positional arguments - use backup-specific variable name
BACKUP_COMMAND_PARAMS=("${POSITIONAL_ARGS[@]}")

if (( ${#BACKUP_COMMAND_PARAMS[@]} == 0 )); then
    BACKUP_COMMAND_PARAMS=("all")
fi

# Utility functions for backup operations
function promptPassword() {
    local prompt="$1"
    local password=""
    local confirm=""
    
    # Don't prompt in quiet mode or non-interactive shells
    if [[ $BACKUP_QUIET -eq 1 ]] || [[ ! -t 0 ]]; then
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
    [[ $BACKUP_QUIET -eq 1 ]] && return
    local level="$1"
    shift
    case "$level" in
        INFO) info "$@" ;;
        SUCCESS) success "$@" ;;
        WARNING) warning "$@" ;;
        ERROR) error "$@" ;;
    esac
}

function validateCompression() {
    case "$BACKUP_COMPRESSION" in
        gzip|xz|lz4|none) return 0 ;;
        *) 
            error "Invalid compression format: $BACKUP_COMPRESSION. Supported: gzip, xz, lz4, none"
            return 1
            ;;
    esac
}

function getCompressionExtension() {
    case "$BACKUP_COMPRESSION" in
        gzip) echo ".tar.gz" ;;
        xz) echo ".tar.xz" ;;
        lz4) echo ".tar.lz4" ;;
        none) echo ".tar" ;;
    esac
}

function getCompressionCommand() {
    case "$BACKUP_COMPRESSION" in
        gzip) echo "gzip" ;;
        xz) echo "xz -9" ;;
        lz4) echo "lz4 -9" ;;
        none) echo "cat" ;;
    esac
}

function detectEnabledServices() {
    local services=()
    
    # Check database services
    if [[ ${ROLL_DB:-1} -eq 1 ]]; then
        case "${DB_DISTRIBUTION:-mariadb}" in
            mysql|mariadb) services+=("db:mysql:dbdata") ;;
            postgres) services+=("db:postgres:dbdata") ;;
        esac
    fi
    
    # Check Redis/Dragonfly
    if [[ ${ROLL_REDIS:-0} -eq 1 ]]; then
        services+=("redis:redis:redis")
    elif [[ ${ROLL_DRAGONFLY:-0} -eq 1 ]]; then
        services+=("dragonfly:dragonfly:dragonfly")
    fi
    
    # Check Elasticsearch/OpenSearch
    if [[ ${ROLL_ELASTICSEARCH:-0} -eq 1 ]]; then
        services+=("elasticsearch:elasticsearch:esdata")
    elif [[ ${ROLL_OPENSEARCH:-0} -eq 1 ]]; then
        services+=("opensearch:opensearch:osdata")
    fi
    
    # Check MongoDB
    if [[ ${ROLL_MONGODB:-0} -eq 1 ]]; then
        services+=("mongodb:mongodb:mongodb")
    fi
    
    # Check RabbitMQ
    if [[ ${ROLL_RABBITMQ:-0} -eq 1 ]]; then
        services+=("rabbitmq:rabbitmq:rabbitmq")
    fi
    
    # Check Varnish (cache data)
    if [[ ${ROLL_VARNISH:-0} -eq 1 ]]; then
        services+=("varnish:varnish:varnish")
    fi
    
    echo "${services[@]}"
}

function createBackupDirectory() {
    local timestamp=${1:-$(date +%s)}
    local backup_dir="$(pwd)/.roll/backups/$timestamp"
    
    # Create backup directories
    mkdir -p "$backup_dir"/{volumes,config,metadata,logs}
    
    echo "$backup_dir"
}

function generateBackupMetadata() {
    local backup_dir="$1"
    local services=("${@:2}")
    
    cat > "$backup_dir/metadata/backup.json" <<EOF
{
    "timestamp": $(date +%s),
    "date": "$(date -Iseconds)",
    "environment": "${ROLL_ENV_NAME}",
    "version": "$(cat ${ROLL_DIR}/version 2>/dev/null || echo 'unknown')",
    "services": [$(printf '"%s",' "${services[@]}" | sed 's/,$//')],
    "compression": "${BACKUP_COMPRESSION}",
    "encrypted": $([ -n "$BACKUP_ENCRYPT" ] && echo "true" || echo "false"),
    "name": "${BACKUP_NAME}",
    "description": "${BACKUP_DESCRIPTION}",
    "include_source": ${BACKUP_INCLUDE_SOURCE},
    "exclude_logs": ${BACKUP_EXCLUDE_LOGS},
    "docker_compose_version": "$(docker compose version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)",
    "platform": "$(uname -s)",
    "architecture": "$(uname -m)"
}
EOF
    
    # Create checksums file
    touch "$backup_dir/metadata/checksums.sha256"
}

function backupVolume() {
    local service_name="$1"
    local volume_name="$2"
    local backup_dir="$3"
    local step="$4"
    local total="$5"
    
    local full_volume_name="${ROLL_ENV_NAME}_${volume_name}"
    local output_file="$backup_dir/volumes/${service_name}$(getCompressionExtension)"
    local temp_container="${ROLL_ENV_NAME}_backup_${service_name}_$$"
    
    showProgress $step $total "Backing up $service_name volume"
    
    # Check if volume exists
    if ! docker volume inspect "$full_volume_name" >/dev/null 2>&1; then
        logMessage WARNING "Volume $full_volume_name does not exist, skipping"
        return 1  # Return failure so this service won't be included in successful_services
    fi
    
    # Use the same approach as the original working backup script
    # Switch back to ubuntu and use the original tar command structure
    local tar_compression_flag=""
    case "$BACKUP_COMPRESSION" in
        gzip) tar_compression_flag="z" ;;
        xz) tar_compression_flag="J" ;;
        lz4) tar_compression_flag="" ;; # lz4 doesn't have direct tar support, fallback to pipe
        none) tar_compression_flag="" ;;
    esac
    
    # Create backup directory for volume if it doesn't exist
    mkdir -p "$backup_dir/volumes"
    
    # Execute backup with the original working approach - use ubuntu and direct tar compression
    if [[ "$BACKUP_COMPRESSION" == "lz4" ]]; then
        # Handle lz4 separately since tar doesn't support it directly
        if [[ $BACKUP_OUTPUT_ID -eq 1 ]]; then
            docker run --rm --name "$temp_container" \
                --mount source="$full_volume_name",target=/data \
                -v "$backup_dir/volumes":/backup \
                ubuntu bash \
                -c "tar -cf - /data | lz4 -9 > /backup/${service_name}.tar.lz4" >/dev/null 2>&1
        else
            docker run --rm --name "$temp_container" \
                --mount source="$full_volume_name",target=/data \
                -v "$backup_dir/volumes":/backup \
                ubuntu bash \
                -c "tar -cf - /data | lz4 -9 > /backup/${service_name}.tar.lz4"
        fi
    else
        # Use original working approach for gzip, xz, and none
        local tar_cmd="tar -c${tar_compression_flag}vf /backup/${service_name}$(getCompressionExtension) /data"
        if [[ $BACKUP_EXCLUDE_LOGS -eq 1 ]]; then
            tar_cmd="tar -c${tar_compression_flag}vf /backup/${service_name}$(getCompressionExtension) --exclude='*.log' --exclude='*_log' --exclude='log_*' --exclude='*.tmp' /data"
        fi
        
        if [[ $BACKUP_OUTPUT_ID -eq 1 ]]; then
            # Suppress all output when using --output-id
            docker run --rm --name "$temp_container" \
                --mount source="$full_volume_name",target=/data \
                -v "$backup_dir/volumes":/backup \
                ubuntu bash \
                -c "$tar_cmd" >/dev/null 2>&1
        else
            docker run --rm --name "$temp_container" \
                --mount source="$full_volume_name",target=/data \
                -v "$backup_dir/volumes":/backup \
                ubuntu bash \
                -c "$tar_cmd"
        fi
    fi
    
    # Check if backup was successful
    if [[ $? -eq 0 && -f "$backup_dir/volumes/${service_name}$(getCompressionExtension)" ]]; then
        # Generate checksum
        local checksum=$(sha256sum "$backup_dir/volumes/${service_name}$(getCompressionExtension)" | cut -d' ' -f1)
        echo "$checksum  volumes/${service_name}$(getCompressionExtension)" >> "$backup_dir/metadata/checksums.sha256"
        
        if [[ $BACKUP_OUTPUT_ID -eq 0 ]]; then
            logMessage SUCCESS "Successfully backed up $service_name volume ($(du -h "$backup_dir/volumes/${service_name}$(getCompressionExtension)" | cut -f1))"
        fi
        return 0
    else
        if [[ $BACKUP_OUTPUT_ID -eq 0 ]]; then
            logMessage ERROR "Failed to backup $service_name volume"
        fi
        return 1
    fi
}

function backupConfigurations() {
    local backup_dir="$1"
    local step="$2"
    local total="$3"
    
    showProgress $step $total "Backing up configuration files"
    
    local config_files=()
    
    # Environment-specific configuration files
    if [[ -f "$(pwd)/.env.roll" ]]; then
        config_files+=(".env.roll")
    fi
    
    if [[ -f "$(pwd)/app/etc/env.php" ]]; then
        config_files+=("app/etc/env.php")
    fi
    
    if [[ -f "$(pwd)/auth.json" ]]; then
        config_files+=("auth.json")
    fi
    
    if [[ -f "$(pwd)/composer.json" ]]; then
        config_files+=("composer.json")
    fi
    
    if [[ -f "$(pwd)/composer.lock" ]]; then
        config_files+=("composer.lock")
    fi
    
    # Additional framework-specific configs
    if [[ -f "$(pwd)/.env" ]]; then
        config_files+=(".env")
    fi
    
    if [[ -f "$(pwd)/config/database.yml" ]]; then
        config_files+=("config/database.yml")
    fi
    
    # Copy configuration files
    for config_file in "${config_files[@]}"; do
        if [[ -f "$(pwd)/$config_file" ]]; then
            local target_dir="$backup_dir/config/$(dirname "$config_file")"
            mkdir -p "$target_dir"
            
            # Check if this is a duplication backup and needs environment name replacement
            if [[ -n "$BACKUP_DUPLICATE_NAME" && "$config_file" == ".env.roll" ]]; then
                # Create a modified version of .env.roll with new environment names
                local temp_env_file="$target_dir/$(basename "$config_file")"
                cp "$(pwd)/$config_file" "$temp_env_file"
                
                # Replace ROLL_ENV_NAME and TRAEFIK_DOMAIN for duplication
                sed_inplace "s/^ROLL_ENV_NAME=.*/ROLL_ENV_NAME=${BACKUP_DUPLICATE_NAME}/" "$temp_env_file"
                if [[ -n "$BACKUP_DUPLICATE_DOMAIN" ]]; then
                    sed_inplace "s/^TRAEFIK_DOMAIN=.*/TRAEFIK_DOMAIN=${BACKUP_DUPLICATE_DOMAIN}/" "$temp_env_file"
                else
                    sed_inplace "s/^TRAEFIK_DOMAIN=.*/TRAEFIK_DOMAIN=${BACKUP_DUPLICATE_NAME}.test/" "$temp_env_file"
                fi
                
                logMessage INFO "Backed up $config_file (modified for duplication: ${BACKUP_DUPLICATE_NAME})"
            else
                # Copy file as-is for non-duplication backups or other files
                cp "$(pwd)/$config_file" "$target_dir/"
                logMessage INFO "Backed up $config_file"
            fi
        fi
    done
    
    # Backup docker-compose overrides if they exist
    if [[ -f "$(pwd)/.roll/roll-env.yml" ]]; then
        cp "$(pwd)/.roll/roll-env.yml" "$backup_dir/config/"
        logMessage INFO "Backed up roll-env.yml"
    fi
    
    logMessage SUCCESS "Configuration backup completed"
}

function backupSourceCode() {
    local backup_dir="$1"
    local step="$2"
    local total="$3"
    
    showProgress $step $total "Backing up source code"
    
    local exclude_patterns=(
        "--exclude=node_modules"
        "--exclude=var/cache"
        "--exclude=var/log"
        "--exclude=var/session"
        "--exclude=var/tmp"
        "--exclude=storage/logs"
        "--exclude=storage/framework/cache"
        "--exclude=storage/framework/sessions"
        "--exclude=storage/framework/views"
        "--exclude=.roll/backups"
        "--exclude=*.log"
    )
    
    tar "${exclude_patterns[@]}" -cf - . | $(getCompressionCommand) > "$backup_dir/source$(getCompressionExtension)" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        local checksum=$(sha256sum "$backup_dir/source$(getCompressionExtension)" | cut -d' ' -f1)
        echo "$checksum  source$(getCompressionExtension)" >> "$backup_dir/metadata/checksums.sha256"
        logMessage SUCCESS "Source code backup completed ($(du -h "$backup_dir/source$(getCompressionExtension)" | cut -f1))"
    else
        logMessage ERROR "Failed to backup source code"
        return 1
    fi
}

function encryptBackup() {
    local backup_dir="$1"
    local passphrase="$2"
    
    if [[ -z "$passphrase" ]]; then
        return 0
    fi
    
    logMessage INFO "Encrypting backup files..."
    
    # Create temporary file for new checksums
    local temp_checksums="$backup_dir/metadata/checksums.sha256.new"
    [[ -f "$backup_dir/metadata/checksums.sha256" ]] && cp "$backup_dir/metadata/checksums.sha256" "$temp_checksums"
    
    # Process tar files for encryption
    while IFS= read -r -d '' file; do
        if command -v gpg >/dev/null 2>&1; then
            local encrypted_file="${file}.gpg"
            if gpg --batch --yes --cipher-algo AES256 --compress-algo 1 \
                --symmetric --passphrase "$passphrase" \
                --output "$encrypted_file" "$file"; then
                
                # Generate new checksum for encrypted file
                local relative_path="${file#$backup_dir/}"
                local encrypted_relative_path="${relative_path}.gpg"
                local checksum=$(sha256sum "$encrypted_file" | cut -d' ' -f1)
                
                # Update checksums file to replace original with encrypted version
                if [[ -f "$temp_checksums" ]]; then
                    sed_inplace "s|^[a-f0-9]*  ${relative_path}$|${checksum}  ${encrypted_relative_path}|" "$temp_checksums"
                fi
                
                # Remove original file
                rm "$file"
                
                logMessage INFO "Encrypted $(basename "$file")"
            else
                logMessage ERROR "Failed to encrypt $file"
                rm -f "$temp_checksums"
                return 1
            fi
        else
            logMessage WARNING "GPG not available, skipping encryption"
            rm -f "$temp_checksums"
            return 1
        fi
    done < <(find "$backup_dir" -name "*.tar*" -type f -print0)
    
    # Process configuration files for encryption
    if [[ -d "$backup_dir/config" ]]; then
        while IFS= read -r -d '' file; do
            if command -v gpg >/dev/null 2>&1; then
                local encrypted_file="${file}.gpg"
                if gpg --batch --yes --cipher-algo AES256 --compress-algo 1 \
                    --symmetric --passphrase "$passphrase" \
                    --output "$encrypted_file" "$file"; then
                    
                    # Generate checksum for encrypted config file
                    local relative_path="${file#$backup_dir/}"
                    local encrypted_relative_path="${relative_path}.gpg"
                    local checksum=$(sha256sum "$encrypted_file" | cut -d' ' -f1)
                    
                    # Add checksum entry for the encrypted config file
                    if [[ -f "$temp_checksums" ]]; then
                        echo "$checksum  $encrypted_relative_path" >> "$temp_checksums"
                    fi
                    
                    # Remove original file
                    rm "$file"
                    
                    logMessage INFO "Encrypted config file $(basename "$file")"
                else
                    logMessage ERROR "Failed to encrypt config file $file"
                    rm -f "$temp_checksums"
                    return 1
                fi
            else
                logMessage WARNING "GPG not available, skipping encryption"
                rm -f "$temp_checksums"
                return 1
            fi
        done < <(find "$backup_dir/config" -type f -print0)
    fi
    
    # Replace original checksums file with updated one
    if [[ -f "$temp_checksums" ]]; then
        mv "$temp_checksums" "$backup_dir/metadata/checksums.sha256"
    fi
    
    logMessage SUCCESS "Backup encryption completed"
}

function verifyBackup() {
    local backup_dir="$1"
    
    if [[ $BACKUP_VERIFY -eq 0 ]]; then
        return 0
    fi
    
    logMessage INFO "Verifying backup integrity..."
    
    if [[ -f "$backup_dir/metadata/checksums.sha256" ]]; then
        # Verify checksums with detailed output
        local verify_output
        if verify_output=$(cd "$backup_dir" && sha256sum -c metadata/checksums.sha256 2>&1); then
            logMessage SUCCESS "Backup verification passed"
            return 0
        else
            logMessage ERROR "Backup verification failed"
            
            # Show which files failed verification
            local failed_files=$(echo "$verify_output" | grep -E "(No such file|FAILED)" | head -5)
            if [[ -n "$failed_files" ]]; then
                logMessage ERROR "Failed files:"
                echo "$failed_files" | while read -r line; do
                    logMessage ERROR "  $line"
                done
                
                # Check if this might be an encryption issue
                if echo "$verify_output" | grep -q "No such file or directory"; then
                    logMessage INFO "Files may be encrypted. Use --no-verify to skip verification for encrypted backups."
                fi
            fi
            
            return 1
        fi
    else
        logMessage WARNING "No checksums found, skipping verification"
        return 0
    fi
}

function cleanupOldBackups() {
    local backup_base_dir="$(pwd)/.roll/backups"
    
    if [[ $BACKUP_RETENTION_DAYS -le 0 ]]; then
        return 0
    fi
    
    logMessage INFO "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    find "$backup_base_dir" -maxdepth 1 -type d -name '[0-9]*' -mtime +$BACKUP_RETENTION_DAYS | while read -r old_backup; do
        logMessage INFO "Removing old backup: $(basename "$old_backup")"
        rm -rf "$old_backup"
    done
    
    # Also clean up old compressed backups
    find "$backup_base_dir" -maxdepth 1 -name "*.tar*" -mtime +$BACKUP_RETENTION_DAYS -delete
    
    logMessage INFO "Cleanup completed"
}

function performBackup() {
    local backup_type="$1"
    
    # Validate inputs
    validateCompression || exit 1
    
    # Handle interactive password prompt if needed
    if [[ "$BACKUP_ENCRYPT" == "PROMPT" ]]; then
        BACKUP_ENCRYPT=$(promptPassword "Enter encryption password")
    fi
    
    # Detect enabled services
    local enabled_services=($(detectEnabledServices))
    if [[ ${#enabled_services[@]} -eq 0 ]]; then
        logMessage ERROR "No services enabled for backup"
        exit 1
    fi
    
    # Stop environment to ensure consistent backup
    logMessage INFO "Stopping environment for consistent backup..."
    "${ROLL_DIR}/bin/roll" env down >/dev/null 2>&1
    
    # Create backup directory
    local timestamp=$(date +%s)
    local backup_dir=$(createBackupDirectory "$timestamp")
    
    logMessage INFO "Starting backup to: $backup_dir"
    logMessage INFO "Backup type: $backup_type, Compression: $BACKUP_COMPRESSION"
    
    # Track successfully backed up services
    local successful_services=()
    
    # Calculate total steps
    local total_steps=2  # metadata + config
    case "$backup_type" in
        all)
            total_steps=$((${#enabled_services[@]} + 3))  # services + config + source + metadata
            if [[ $BACKUP_INCLUDE_SOURCE -eq 1 ]]; then
                ((total_steps++))
            fi
            ;;
        db|database)
            total_steps=3
            ;;
        *)
            total_steps=3
            ;;
    esac
    
    local current_step=0
    
    # Backup based on type
    case "$backup_type" in
        all)
            # Backup all enabled services
            for service_info in "${enabled_services[@]}"; do
                IFS=':' read -r service_name service_type volume_name <<< "$service_info"
                ((current_step++))
                if backupVolume "$service_name" "$volume_name" "$backup_dir" $current_step $total_steps; then
                    successful_services+=("$service_info")
                fi
            done
            
            # Backup configurations
            ((current_step++))
            backupConfigurations "$backup_dir" $current_step $total_steps
            
            # Backup source code if requested
            if [[ $BACKUP_INCLUDE_SOURCE -eq 1 ]]; then
                ((current_step++))
                backupSourceCode "$backup_dir" $current_step $total_steps
            fi
            ;;
        db|database)
            # Find database service
            for service_info in "${enabled_services[@]}"; do
                IFS=':' read -r service_name service_type volume_name <<< "$service_info"
                if [[ "$service_type" =~ ^(mysql|mariadb|postgres)$ ]]; then
                    ((current_step++))
                    if backupVolume "$service_name" "$volume_name" "$backup_dir" $current_step $total_steps; then
                        successful_services+=("$service_info")
                    fi
                    break
                fi
            done
            ;;
        redis|dragonfly)
            # Find Redis/Dragonfly service
            for service_info in "${enabled_services[@]}"; do
                IFS=':' read -r service_name service_type volume_name <<< "$service_info"
                if [[ "$service_type" =~ ^(redis|dragonfly)$ ]]; then
                    ((current_step++))
                    if backupVolume "$service_name" "$volume_name" "$backup_dir" $current_step $total_steps; then
                        successful_services+=("$service_info")
                    fi
                    break
                fi
            done
            ;;
        elasticsearch|opensearch)
            # Find search service
            for service_info in "${enabled_services[@]}"; do
                IFS=':' read -r service_name service_type volume_name <<< "$service_info"
                if [[ "$service_type" =~ ^(elasticsearch|opensearch)$ ]]; then
                    ((current_step++))
                    if backupVolume "$service_name" "$volume_name" "$backup_dir" $current_step $total_steps; then
                        successful_services+=("$service_info")
                    fi
                    break
                fi
            done
            ;;
        mongodb)
            # Find MongoDB service
            for service_info in "${enabled_services[@]}"; do
                IFS=':' read -r service_name service_type volume_name <<< "$service_info"
                if [[ "$service_type" == "mongodb" ]]; then
                    ((current_step++))
                    if backupVolume "$service_name" "$volume_name" "$backup_dir" $current_step $total_steps; then
                        successful_services+=("$service_info")
                    fi
                    break
                fi
            done
            ;;
        config|configuration)
            # Only backup configuration files
            ((current_step++))
            backupConfigurations "$backup_dir" $current_step $total_steps
            ;;
        *)
            logMessage ERROR "Unknown backup type: $backup_type"
            exit 1
            ;;
    esac
    
    # Generate metadata with successfully backed up services
    ((current_step++))
    generateBackupMetadata "$backup_dir" "${successful_services[@]}"
    showProgress $current_step $total_steps "Generating metadata"
    
    # Encrypt if requested
    if [[ -n "$BACKUP_ENCRYPT" ]]; then
        encryptBackup "$backup_dir" "$BACKUP_ENCRYPT"
    fi
    
    # Verify backup
    verifyBackup "$backup_dir"
    
    # Create compressed archive for the entire backup
    local archive_name="backup_${ROLL_ENV_NAME}_${timestamp}$(getCompressionExtension)"
    logMessage INFO "Creating final backup archive: $archive_name"
    
    # Suppress tar warnings when using --output-id
    if [[ $BACKUP_OUTPUT_ID -eq 1 ]]; then
        (cd "$(pwd)/.roll/backups" && tar -cf - "$timestamp" 2>/dev/null | $(getCompressionCommand) > "$archive_name")
    else
        (cd "$(pwd)/.roll/backups" && tar -cf - "$timestamp" | $(getCompressionCommand) > "$archive_name")
    fi
    
    if [[ $? -eq 0 ]]; then
        # Update latest symlink
        (cd "$(pwd)/.roll/backups" && ln -sf "$archive_name" "latest$(getCompressionExtension)")
        
        if [[ $BACKUP_OUTPUT_ID -eq 1 ]]; then
            # Only output the backup ID for programmatic use
            echo "$timestamp"
        else
            logMessage SUCCESS "Backup completed successfully!"
            logMessage INFO "Backup ID: $timestamp"
            logMessage INFO "Archive: $archive_name ($(du -h "$(pwd)/.roll/backups/$archive_name" | cut -f1))"
            logMessage INFO "Location: $(pwd)/.roll/backups/"
        fi
        
        # Clean up directory version (keep archive)
        rm -rf "$backup_dir"
    else
        logMessage ERROR "Failed to create final backup archive"
        exit 1
    fi
    
    # Cleanup old backups
    if [[ $BACKUP_OUTPUT_ID -eq 0 ]]; then
        cleanupOldBackups
        logMessage SUCCESS "Backup process completed!"
    else
        # Silent cleanup for output-id mode
        cleanupOldBackups >/dev/null 2>&1
    fi
}

# Main execution
case "${BACKUP_COMMAND_PARAMS[0]}" in
    all|db|database|redis|dragonfly|elasticsearch|opensearch|mongodb|config|configuration)
        performBackup "${BACKUP_COMMAND_PARAMS[0]}"
        ;;
    list|ls)
        echo "Available backups:"
        if [[ -d "$(pwd)/.roll/backups" ]]; then
            ls -la "$(pwd)/.roll/backups/" | grep -E '^d.*[0-9]{10}$|^-.*backup_.*\.tar'
        else
            echo "No backups found."
        fi
        ;;
    info)
        if [[ -n "${BACKUP_COMMAND_PARAMS[1]}" ]]; then
            backup_id="${BACKUP_COMMAND_PARAMS[1]}"
            
            # First check if directory exists (uncompressed backup)
            metadata_file="$(pwd)/.roll/backups/$backup_id/metadata/backup.json"
            if [[ -f "$metadata_file" ]]; then
                cat "$metadata_file" | jq '.' 2>/dev/null || cat "$metadata_file"
            else
                # Look for compressed archive
                archive_file=""
                for ext in ".tar.gz" ".tar.xz" ".tar.lz4" ".tar"; do
                    potential_file="$(pwd)/.roll/backups/backup_${ROLL_ENV_NAME}_${backup_id}${ext}"
                    if [[ -f "$potential_file" ]]; then
                        archive_file="$potential_file"
                        break
                    fi
                done
                
                if [[ -z "$archive_file" ]]; then
                    # Also check for generic archive names
                    archive_file=$(ls "$(pwd)/.roll/backups"/*"$backup_id"*.tar* 2>/dev/null | head -1)
                fi
                
                if [[ -n "$archive_file" ]]; then
                    # Extract metadata from archive
                    logMessage INFO "Extracting metadata from $(basename "$archive_file")..."
                    
                    # Determine decompression command
                    case "$archive_file" in
                        *.tar.gz) decompress_cmd="gzip -dc" ;;
                        *.tar.xz) decompress_cmd="xz -dc" ;;
                        *.tar.lz4) decompress_cmd="lz4 -dc" ;;
                        *.tar) decompress_cmd="cat" ;;
                        *) decompress_cmd="cat" ;;
                    esac
                    
                    # Extract and display metadata
                    if metadata_content=$($decompress_cmd "$archive_file" | tar -xOf - "$backup_id/metadata/backup.json" 2>/dev/null); then
                        echo "$metadata_content" | jq '.' 2>/dev/null || echo "$metadata_content"
                    else
                        error "Could not extract metadata from backup archive"
                        exit 1
                    fi
                else
                    error "Backup not found for ID: $backup_id"
                    exit 1
                fi
            fi
        else
            error "Please specify a backup ID"
            exit 1
        fi
        ;;
    clean)
        days=${BACKUP_COMMAND_PARAMS[1]:-30}
        BACKUP_RETENTION_DAYS=$days
        cleanupOldBackups
        ;;
    *)
        error "Unknown command: ${BACKUP_COMMAND_PARAMS[0]}"
        echo "Available commands: all, db, redis, elasticsearch, mongodb, config, list, info, clean"
        exit 1
        ;;
esac
