#!/bin/bash
# Check if ROLL_DIR is set
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# Locate and load environment configuration
ROLL_ENV_PATH="$(locateEnvPath)" || { echo "Failed to locate environment path" >&2; exit 1; }
loadEnvConfig "${ROLL_ENV_PATH}" || { echo "Failed to load environment configuration" >&2; exit 1; }
assertDockerRunning

## Error handling
trap 'echo "An error occurred." >&2; exit 1' ERR

# Check if the environment type is Magento 2
if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
    boxerror "This command is only working for Magento 2 projects" && exit 1
    exit 1
fi

printf "\n\nConfirming n98-magerun2 is installed...\n\n"
if ! "${ROLL_DIR}/bin/roll" magerun > /dev/null 2>&1; then
    echo "n98-magerun2 is not installed." >&2
    exit 1
fi

# Check and create localadmin if it doesn't exist
LOCALADMIN_EXISTS=$("${ROLL_DIR}/bin/roll" magerun admin:user:list | grep "localadmin" || echo '')
if [[ -z "$LOCALADMIN_EXISTS" ]]; then
  printf "Setup user account localadmin...\n\n"
  if ! "${ROLL_DIR}/bin/roll" magerun admin:user:create --admin-user "localadmin" --admin-password "admin123" --admin-email "localadmin@roll.test" --admin-firstname "Local" --admin-lastname "Admin"; then
    echo "Failed to create admin user." >&2
    exit 1
  fi
fi

# TFA Module check and configuration
TFA_MODULE_ENABLED=$("${ROLL_DIR}/bin/roll" magento module:status --enabled | grep Magento_TwoFactorAuth || echo '')
if [[ -n "$TFA_MODULE_ENABLED" ]]; then
  FORCE_TFA_PROVIDER_EXISTS=$("${ROLL_DIR}/bin/roll" magento config:show twofactorauth/general/force_providers | grep "google" || echo '')
  if [[ -z "$FORCE_TFA_PROVIDER_EXISTS" ]]; then
    printf "Force google as default TFA Provider\n\n"
    if ! "${ROLL_DIR}/bin/roll" magento config:set twofactorauth/general/force_providers google; then
      echo "Error: Probably 2fa module is not installed or enabled." >&2
    fi
  fi
  printf "Setting autologin 2fa code\n\n"
  if ! "${ROLL_DIR}/bin/roll" magento security:tfa:google:set-secret localadmin "LAJWZZTAI4KAHY7NBS6NOM3BDZK62IPDT3U5ARGXCJ4WVG7PJSG37FC4XODYWV2UNYMQG3LVMEUTIHO52FQGZU4Z462VNWYKPOM23M2YZNWAJW732RTNAVTQ2APUV64BPBJZKT7I4CAT62KLFEP5DZLWINPZ3JVOWJ6CPOAA77RSFK2PAG6YPS4VP55WYX5BPTX4Z7P6EZ4CY"; then
      echo "Failed to set 2fa code." >&2
      exit 1
    fi
fi

# Final instructions
boxsuccess "Operation Completed Successfully!" \
"" \
"Next Steps:" \
"" \
"1. Enable Automatic Admin Login:" \
"   Edit your .env.roll configuration file." \
"   Add the following line:" \
"" \
"     ROLL_ADMIN_AUTOLOGIN=1" \
"" \
"2. Refresh Admin Login:" \
"" \
"   If you ran this due to an admin login issue," \
"   simply refresh the login page to apply the changes."
