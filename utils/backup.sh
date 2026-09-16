#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Shared by backup, restore (including restore-full) and duplicate.
##
## Backups live in $(pwd)/.roll/backups rather than under ROLL_ENV_PATH, in all four commands, so a
## backup made from a project subdirectory is found by a restore run from the same place.

## macOS 13 and older have shasum but no sha256sum; both write and check the same "<hash>  <file>" lines
if ! command -v sha256sum >/dev/null 2>&1; then
    function sha256sum() {
        shasum -a 256 "$@"
    }
fi

function assertGpgInstalled() {
    command -v gpg >/dev/null 2>&1 && return 0
    fatal "gpg is required for encrypted backups (macOS: brew install gnupg; Debian/Ubuntu: apt install gnupg)"
}

function logMessage() {
    ## Only one of the quiet/verbose flags is set per invocation, whichever command is running
    if [[ ${BACKUP_QUIET:-0} -eq 1 || ${RESTORE_QUIET:-0} -eq 1 || ${DUPLICATE_QUIET:-0} -eq 1 ]]; then
        return 0
    fi

    local level="$1"
    shift
    case "$level" in
        INFO) info "$@" ;;
        SUCCESS) success "$@" ;;
        WARNING) warning "$@" ;;
        ERROR) error "$@" ;;
        VERBOSE) [[ ${BACKUP_VERBOSE:-0} -eq 1 || ${RESTORE_VERBOSE:-0} -eq 1 || ${DUPLICATE_VERBOSE:-0} -eq 1 ]] && info "[VERBOSE] $*" ;;
    esac

    ## a false VERBOSE test would otherwise become the return value and trip set -e
    return 0
}

function logVerbose() {
    logMessage VERBOSE "$@"
    return 0
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

    logVerbose "Looking for backup archive with ID: $backup_id"
    logVerbose "Backup directory: $backup_dir"

    # Check if already extracted
    if [[ -d "$extract_dir" ]]; then
        logVerbose "Found already extracted backup at: $extract_dir"
        echo "$extract_dir"
        return 0
    fi

    # Find the archive file
    local archive_file=""
    for ext in ".tar.gz" ".tar.xz" ".tar.lz4" ".tar"; do
        local potential_file="$backup_dir/backup_${ROLL_ENV_NAME}_${backup_id}${ext}"
        logVerbose "Checking for archive: $potential_file"
        if [[ -f "$potential_file" ]]; then
            archive_file="$potential_file"
            break
        fi
    done

    # Also check for generic archive names
    if [[ -z "$archive_file" ]]; then
        logVerbose "Trying generic archive name pattern: *${backup_id}*.tar*"
        archive_file=$(ls "$backup_dir"/*"$backup_id"*.tar* 2>/dev/null | head -1)
    fi

    if [[ -z "$archive_file" ]]; then
        logMessage ERROR "Backup archive not found for ID: $backup_id"
        return 1
    fi

    logMessage INFO "Extracting backup archive: $(basename "$archive_file")"
    logVerbose "Full archive path: $archive_file"
    logVerbose "Extract destination: $extract_dir"

    mkdir -p "$extract_dir"

    # Use direct file reading for cross-platform compatibility
    # BSD tar (macOS) doesn't reliably handle piped stdin with -C flag
    # Both BSD and GNU tar auto-detect compression format with -xf
    logVerbose "Extracting archive using direct file reading"

    if tar -xf "$archive_file" -C "$extract_dir" --strip-components=1; then
        logVerbose "Successfully extracted archive to: $extract_dir"
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
        if [[ -f "$backup_path/os.tar.gz" ]]; then
            services+=("opensearch")
        fi
    fi

    echo "${services[@]}"
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
    elif [[ "$service_name" == "elasticsearch" && -f "$backup_path/es.tar.gz" ]]; then
        # Legacy format uses short names for the search engines
        backup_file="$backup_path/es.tar.gz"
    elif [[ "$service_name" == "opensearch" && -f "$backup_path/os.tar.gz" ]]; then
        backup_file="$backup_path/os.tar.gz"
    else
        logMessage WARNING "Backup file not found for service: $service_name"
        logVerbose "Searched in: $backup_path/volumes/ and $backup_path/"
        return 0
    fi

    # Nothing mounts a search volume whose engine is switched off, so say so instead of restoring
    # into it silently. A full restore has no .env.roll yet at this point, so every toggle reads unset.
    if [[ ! -f "${ROLL_ENV_PATH}/.env.roll" ]]; then
        :
    elif [[ "$service_name" == "elasticsearch" && "${ROLL_ELASTICSEARCH:-0}" != "1" ]]; then
        logMessage WARNING "Backup contains an Elasticsearch index but ROLL_ELASTICSEARCH is not enabled - the restored volume will not be mounted by 'roll env up'"
    elif [[ "$service_name" == "opensearch" && "${ROLL_OPENSEARCH:-0}" != "1" ]]; then
        logMessage WARNING "Backup contains an OpenSearch index but ROLL_OPENSEARCH is not enabled - the restored volume will not be mounted by 'roll env up'"
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

    # --strip-components=1 drops the archive entry that carried the data directory's owner, so the
    # volume root stays root:root. Elasticsearch and OpenSearch run as uid 1000 and then fail with
    # AccessDeniedException. Take the owner from the restored content; the braces keep a failed
    # extraction from reporting success.
    local fix_volume_root='{ root_ref=$(find /data -mindepth 1 -maxdepth 1 -print -quit); [ -z "$root_ref" ] || chown "$(stat -c %u:%g "$root_ref")" /data; }'
    
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
        
        if echo "$RESTORE_DECRYPT" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$backup_file" | docker run --rm --name "$temp_container" --mount source="$volume_name",target=/data -i ubuntu bash -c "cd /data && $tar_cmd --strip-components=1 && $fix_volume_root" 2>/dev/null; then
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
                    -c "cd /data && tar -xzf /backup/$(basename "$backup_file") --strip-components=1 && $fix_volume_root" 2>/dev/null; then
                    
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
                    -c "cd /data && tar -xJf /backup/$(basename "$backup_file") --strip-components=1 && $fix_volume_root" 2>/dev/null; then
                    
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
                    -c "cd /data && lz4 -d /backup/$(basename "$backup_file") - | tar -xf - --strip-components=1 && $fix_volume_root" 2>/dev/null; then
                    
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
                    -c "cd /data && tar -xf /backup/$(basename "$backup_file") --strip-components=1 && $fix_volume_root" 2>/dev/null; then
                    
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
            
            # ROLL_NO_STATIC_CACHING is not in the schema; ROLL_MAGENTO_STATIC_CACHING is its inverse
            if grep -q '^[[:space:]]*ROLL_NO_STATIC_CACHING=' "$current_dir/.env"; then
                local legacy_no_static_caching=""
                legacy_no_static_caching="$(sed -n 's/^[[:space:]]*ROLL_NO_STATIC_CACHING=//p' "$current_dir/.env" | tail -n 1)"
                legacy_no_static_caching="${legacy_no_static_caching//[[:space:]]/}"
                local magento_static_caching=1
                if [[ "$legacy_no_static_caching" == "1" ]]; then
                    magento_static_caching=0
                fi
                sed -i.legacy '/^[[:space:]]*ROLL_NO_STATIC_CACHING=/d' "$current_dir/.env"
                echo "ROLL_MAGENTO_STATIC_CACHING=${magento_static_caching}" >> "$current_dir/.env"
            fi
            
            # Move to .env.roll if it contains ROLL_ variables
            if [[ -n "$(grep -r 'ROLL_' "$current_dir/.env")" ]]; then
                mv "$current_dir/.env" "$current_dir/.env.roll"
            fi
            
            logMessage SUCCESS "Legacy migration completed"
        fi
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

function signEnvironmentCertificate() {
    # Determine the domain to sign certificate for
    local domain="${TRAEFIK_DOMAIN:-}"

    # If TRAEFIK_DOMAIN not set, try to construct from env name
    if [[ -z "$domain" ]]; then
        domain="${ROLL_ENV_NAME}.test"
    fi

    if [[ -z "$domain" ]]; then
        logVerbose "No domain found for certificate signing, skipping"
        return 0
    fi

    # Check if root CA exists
    if [[ ! -f "${ROLL_SSL_DIR}/rootca/certs/ca.cert.pem" ]]; then
        logMessage WARNING "Root CA not found. Run 'roll install' first to enable SSL certificates."
        return 0
    fi

    logMessage INFO "Signing SSL certificates for ${domain}..."

    # Sign certificate for the main domain (includes domain and *.domain)
    logVerbose "Signing certificate for: ${domain}"
    if [[ $RESTORE_VERBOSE -eq 1 ]]; then
        "${ROLL_DIR}/bin/roll" sign-certificate "$domain" || {
            logMessage WARNING "Failed to sign certificate for ${domain}"
        }
    else
        "${ROLL_DIR}/bin/roll" sign-certificate "$domain" >/dev/null 2>&1 || {
            logMessage WARNING "Failed to sign certificate for ${domain}"
        }
    fi

    # Sign separate certificate for wildcard domain
    local wildcard_domain="*.${domain}"
    logVerbose "Signing certificate for: ${wildcard_domain}"
    if [[ $RESTORE_VERBOSE -eq 1 ]]; then
        "${ROLL_DIR}/bin/roll" sign-certificate "$wildcard_domain" || {
            logMessage WARNING "Failed to sign certificate for ${wildcard_domain}"
        }
    else
        "${ROLL_DIR}/bin/roll" sign-certificate "$wildcard_domain" >/dev/null 2>&1 || {
            logMessage WARNING "Failed to sign certificate for ${wildcard_domain}"
        }
    fi

    # Regenerate traefik dynamic config and restart to pick up new certificates
    logVerbose "Regenerating traefik configuration..."
    if [[ $RESTORE_VERBOSE -eq 1 ]]; then
        "${ROLL_DIR}/bin/roll" svc up traefik || {
            logMessage WARNING "Failed to restart traefik"
        }
    else
        "${ROLL_DIR}/bin/roll" svc up traefik >/dev/null 2>&1 || {
            logMessage WARNING "Failed to restart traefik"
        }
    fi

    logMessage SUCCESS "SSL certificates signed for ${domain}"
}

function stopEnvironment() {
    if [[ $RESTORE_DRY_RUN -eq 1 ]]; then
        logMessage INFO "[DRY RUN] Would stop environment"
        return 0
    fi

    logVerbose "Environment path: ${ROLL_ENV_PATH}"

    ## a full restore has no .env.roll until the configuration comes out of the backup
    if [[ ! -f "${ROLL_ENV_PATH}/.env.roll" ]]; then
        logMessage INFO "No environment configuration found yet, skipping stop"
        return 0
    fi

    logVerbose "Checking for running containers with project: ${ROLL_ENV_NAME}"
    local running_containers
    running_containers="$(docker ps --filter "label=com.docker.compose.project=${ROLL_ENV_NAME}" -q)" || true

    if [[ -n "${running_containers}" ]]; then
        logMessage INFO "Stopping environment for consistent restore..."
        "${ROLL_DIR}/bin/roll" env down >/dev/null 2>&1 || true
    else
        logVerbose "No running containers for this environment"
    fi

    return 0
}
