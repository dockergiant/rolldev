#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Upstream keeps the migration logic in one script, documented at
## https://mage-os.org/get-started/migration-guide/ (the script URL printed there is stale).
MAGEOS_MIGRATE_SCRIPT_REPO="https://raw.githubusercontent.com/mage-os-lab/migrate-m2-to-mageos"
MAGEOS_MIGRATE_SCRIPT_NAME="migrate-to-mage-os.sh"
MAGEOS_MIGRATE_MAGENTO_VERSION="2.4.9"
MAGEOS_MIGRATE_PHP_VERSION="8.3.0"

MIGRATE_ASSUME_YES=0
MIGRATE_SKIP_BACKUP=0
MIGRATE_NO_SECURITY_BLOCKING=0
MIGRATE_SCRIPT_REF="main"
MIGRATE_SCRIPT_SOURCE=""
MIGRATE_DEVELOPER_MODE=0
MIGRATE_DRY_RUN=0

## mageos-migrate takes any args, so the flags arrive in "$@"
migrateArgs=("$@")
i=0
while [[ $i -lt ${#migrateArgs[@]} ]]; do
    case "${migrateArgs[$i]}" in
        -h|--help)
            source "${ROLL_DIR}/commands/usage.cmd"
            ;;
        -y|--yes)
            MIGRATE_ASSUME_YES=1
            ;;
        --skip-backup)
            MIGRATE_SKIP_BACKUP=1
            ;;
        --no-security-blocking)
            MIGRATE_NO_SECURITY_BLOCKING=1
            ;;
        --script-ref=*)
            MIGRATE_SCRIPT_REF="${migrateArgs[$i]#*=}"
            ;;
        --script-ref)
            i=$((i + 1))
            MIGRATE_SCRIPT_REF="${migrateArgs[$i]:-}"
            ;;
        --script=*)
            MIGRATE_SCRIPT_SOURCE="${migrateArgs[$i]#*=}"
            ;;
        --script)
            i=$((i + 1))
            MIGRATE_SCRIPT_SOURCE="${migrateArgs[$i]:-}"
            ;;
        --developer-mode)
            MIGRATE_DEVELOPER_MODE=1
            ;;
        --dry-run)
            MIGRATE_DRY_RUN=1
            ;;
        *)
            fatal "Unsupported argument ${migrateArgs[$i]}"
            ;;
    esac
    i=$((i + 1))
done

if (( ${#ROLL_PARAMS[@]} > 0 )); then
    fatal "roll mageos-migrate takes only flags, not ${ROLL_PARAMS[*]}"
fi

if [[ -z "${MIGRATE_SCRIPT_REF}" ]]; then
    fatal "--script-ref needs a branch, tag or commit"
fi

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
    fatal "roll mageos-migrate works on magento2 environments, this one is ${ROLL_ENV_TYPE}"
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

## migrateInContainer <command>
## Runs in php-fpm as www-data without a TTY, so the output can be captured and read here. The migration
## script runs as the same user, so every check sees what the migration will see.
function migrateInContainer() {
    "${ROLL_DIR}/bin/roll" env exec -T -u www-data php-fpm bash -c "$1" 2>&1
}

if [[ -z "$("${ROLL_DIR}/bin/roll" env ps -q php-fpm 2>/dev/null)" ]]; then
    info "Starting the environment, because the checks run inside the php-fpm container"
    "${ROLL_DIR}/bin/roll" env up --wait || fatal "Could not start the environment"
fi

info "Checking whether this project can migrate"

MIGRATE_VERSION_OUTPUT="$(migrateInContainer 'bin/magento --version')" || true
case "${MIGRATE_VERSION_OUTPUT}" in
    *Mage-OS*)
        fatal "This project already runs Mage-OS: ${MIGRATE_VERSION_OUTPUT}"
        ;;
esac

MIGRATE_MAGENTO_VERSION="$(printf '%s' "${MIGRATE_VERSION_OUTPUT}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-p[0-9]+)?' | head -1)" || true
case "${MIGRATE_MAGENTO_VERSION}" in
    "${MAGEOS_MIGRATE_MAGENTO_VERSION}"*)
        success "Magento ${MIGRATE_MAGENTO_VERSION}"
        ;;
    "")
        error "Could not read the Magento version from the container."
        fatal "bin/magento --version reported: ${MIGRATE_VERSION_OUTPUT}"
        ;;
    *)
        error "The migration script requires Magento ${MAGEOS_MIGRATE_MAGENTO_VERSION}, this project runs ${MIGRATE_MAGENTO_VERSION}."
        fatal "Upgrade this project to ${MAGEOS_MIGRATE_MAGENTO_VERSION} first, then migrate to Mage-OS."
        ;;
esac

MIGRATE_PHP_VERSION="$(migrateInContainer 'php -r "echo PHP_VERSION;"')" || true
if ! test "$(version "${MIGRATE_PHP_VERSION:-0}")" -ge "$(version "${MAGEOS_MIGRATE_PHP_VERSION}")"; then
    error "The migration script requires PHP ${MAGEOS_MIGRATE_PHP_VERSION} or newer, the container runs ${MIGRATE_PHP_VERSION:-an unknown version}."
    fatal "Raise PHP_VERSION in .env.roll and run roll env up, then migrate to Mage-OS."
fi
success "PHP ${MIGRATE_PHP_VERSION}"

if [[ "$(migrateInContainer 'test -f app/etc/env.php && test -f bin/magento && echo ok')" != "ok" ]]; then
    fatal "app/etc/env.php or bin/magento is missing, so this is not an installed Magento project"
fi
success "Installed Magento project"

MIGRATE_MODE_OUTPUT="$(migrateInContainer 'bin/magento deploy:mode:show')" || true
case "${MIGRATE_MODE_OUTPUT}" in
    *developer*)
        success "Developer mode"
        ;;
    *)
        warning "The migration script requires developer mode, this project reports: ${MIGRATE_MODE_OUTPUT}"
        if [[ ${MIGRATE_DEVELOPER_MODE} -eq 0 ]] \
            && ! promptConfirm "--developer-mode" "Switch this project to developer mode now?"
        then
            fatal "Switch it yourself with: roll magento deploy:mode:set developer"
        fi
        "${ROLL_DIR}/bin/roll" cli bash -c 'bin/magento deploy:mode:set developer' \
            || fatal "Could not switch to developer mode"
        success "Developer mode"
        ;;
esac

if git -C "${ROLL_ENV_PATH}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && [[ -n "$(git -C "${ROLL_ENV_PATH}" status --porcelain 2>/dev/null)" ]]
then
    warning "This project has uncommitted changes, and the migration rewrites composer.json and composer.lock"
fi

MIGRATE_SCRIPT_DIR="${ROLL_ENV_PATH}/.roll/tmp"
MIGRATE_SCRIPT_FILE="${MIGRATE_SCRIPT_DIR}/${MAGEOS_MIGRATE_SCRIPT_NAME}"
mkdir -p "${MIGRATE_SCRIPT_DIR}"

if [[ -n "${MIGRATE_SCRIPT_SOURCE}" ]]; then
    [[ -f "${MIGRATE_SCRIPT_SOURCE}" ]] || fatal "No such script: ${MIGRATE_SCRIPT_SOURCE}"
    cp "${MIGRATE_SCRIPT_SOURCE}" "${MIGRATE_SCRIPT_FILE}" || fatal "Could not copy ${MIGRATE_SCRIPT_SOURCE}"
    MIGRATE_SCRIPT_ORIGIN="${MIGRATE_SCRIPT_SOURCE}"
else
    MIGRATE_SCRIPT_ORIGIN="${MAGEOS_MIGRATE_SCRIPT_REPO}/${MIGRATE_SCRIPT_REF}/${MAGEOS_MIGRATE_SCRIPT_NAME}"
    curl -fsSL "${MIGRATE_SCRIPT_ORIGIN}" -o "${MIGRATE_SCRIPT_FILE}" \
        || fatal "Could not download ${MIGRATE_SCRIPT_ORIGIN}"
fi

info "Migration script: ${MIGRATE_SCRIPT_ORIGIN}"
info "  $(wc -l < "${MIGRATE_SCRIPT_FILE}" | tr -d ' ') lines, sha256 $(sha256sum "${MIGRATE_SCRIPT_FILE}" | cut -d' ' -f1)"
info "  kept at .roll/tmp/${MAGEOS_MIGRATE_SCRIPT_NAME}, so you can read what runs"

## on macOS the project reaches the container through Mutagen, which needs a moment for a new file
if [[ "${ROLL_ENV_SUBT}" == "darwin" ]]; then
    MIGRATE_WAITED=0
    until migrateInContainer "test -f .roll/tmp/${MAGEOS_MIGRATE_SCRIPT_NAME}" >/dev/null 2>&1; do
        if [[ ${MIGRATE_WAITED} -ge 60 ]]; then
            fatal "The container still does not see .roll/tmp/${MAGEOS_MIGRATE_SCRIPT_NAME}; check roll sync list"
        fi
        sleep 2
        MIGRATE_WAITED=$((MIGRATE_WAITED + 2))
    done
fi

if [[ ${MIGRATE_DRY_RUN} -eq 1 ]]; then
    success "Dry run: this project can migrate to Mage-OS"
    info "Run roll mageos-migrate to back up and migrate"
    exit 0
fi

if [[ ${MIGRATE_ASSUME_YES} -eq 0 ]]; then
    boxinfo "Migrating ${ROLL_ENV_NAME} from Magento ${MIGRATE_MAGENTO_VERSION} to Mage-OS" \
        "" \
        "This rewrites composer.json and composer.lock and replaces every magento package." \
        "Never run it against production." \
        "" \
        "A full backup runs first, unless you passed --skip-backup."
    promptConfirm "--yes" "Migrate ${ROLL_ENV_NAME} to Mage-OS?" || fatal "Migration cancelled."
fi

MIGRATE_BACKUP_ID=""
if [[ ${MIGRATE_SKIP_BACKUP} -eq 1 ]]; then
    warning "Skipping the backup because of --skip-backup"
else
    info "Creating a full backup, which stops the environment"
    "${ROLL_DIR}/bin/roll" backup all || fatal "The backup failed, so nothing was migrated"
    MIGRATE_BACKUP_ID="$(cd "${ROLL_ENV_PATH}" && findLatestBackup)" || true
    if [[ -n "${MIGRATE_BACKUP_ID}" ]]; then
        success "Backup ${MIGRATE_BACKUP_ID} created, restore it with: roll restore ${MIGRATE_BACKUP_ID}"
    else
        warning "Could not determine the backup id, look it up with: roll backup list"
    fi

    info "Starting the environment again"
    "${ROLL_DIR}/bin/roll" env up --wait || fatal "Could not start the environment after the backup"
fi

## migrateRestoreHint <message>
function migrateRestoreHint() {
    if [[ -n "${MIGRATE_BACKUP_ID}" ]]; then
        error "Restore this project with: roll restore ${MIGRATE_BACKUP_ID}"
    fi
    fatal "$1"
}

MIGRATE_SCRIPT_FLAGS=""
if [[ ${MIGRATE_NO_SECURITY_BLOCKING} -eq 1 ]]; then
    MIGRATE_SCRIPT_FLAGS=" --no-security-blocking"
fi

info "Running the Mage-OS migration script in the php-fpm container"
MIGRATE_STATUS=0
## CI=1 drops the confirmation the script asks itself, which roll already asked above
"${ROLL_DIR}/bin/roll" cli bash -c \
    "cd /var/www/html && CI=1 bash .roll/tmp/${MAGEOS_MIGRATE_SCRIPT_NAME}${MIGRATE_SCRIPT_FLAGS}" \
    || MIGRATE_STATUS=$?

if [[ ${MIGRATE_STATUS} -ne 0 ]]; then
    error "The migration script stopped with exit code ${MIGRATE_STATUS}"
    migrateRestoreHint "Fix what it reported, then run: roll mageos-migrate --skip-backup"
fi

## the script ends after setup:upgrade; these four are step 3 of the migration guide
for step in "setup:di:compile" "setup:static-content:deploy -f" "indexer:reindex" "cache:flush"; do
    info "Running bin/magento ${step}"
    MIGRATE_STATUS=0
    "${ROLL_DIR}/bin/roll" cli bash -c "bin/magento ${step}" || MIGRATE_STATUS=$?
    if [[ ${MIGRATE_STATUS} -ne 0 ]]; then
        error "bin/magento ${step} stopped with exit code ${MIGRATE_STATUS}"
        migrateRestoreHint "Run the remaining commands from the migration guide yourself."
    fi
done

MIGRATE_VERSION_AFTER="$(migrateInContainer 'bin/magento --version')" || true
boxsuccess "Migration complete" \
    "" \
    "${MIGRATE_VERSION_AFTER}" \
    "Frontend: https://${TRAEFIK_SUBDOMAIN:-app}.${TRAEFIK_DOMAIN}/"
if [[ -n "${MIGRATE_BACKUP_ID}" ]]; then
    info "The pre-migration backup stays available: roll restore ${MIGRATE_BACKUP_ID}"
fi
