#!/bin/bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-process to bubble up normally
trap '' ERR

if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
		boxerror "This command is only working for Magento 2 projects" && exit 1
fi

echo "Confirming n98-magerun2 is installed..."
"${ROLL_DIR}/bin/roll" magerun > /dev/null 2>&1


LOCALADMIN_EXISTS=$("${ROLL_DIR}/bin/roll" magerun admin:user:list | grep "localadmin" || echo '')
if [[ -z "$LOCALADMIN_EXISTS" ]]; then
  echo "Setup user account localadmin..."
  "${ROLL_DIR}/bin/roll" magerun admin:user:create --admin-user "localadmin" --admin-password "admin123" --admin-email "localadmin@roll.test" --admin-firstname "Local" --admin-lastname "Admin"
fi

FORCE_TFA_PROVIDER_EXISTS=$("${ROLL_DIR}/bin/roll" magento config:show twofactorauth/general/force_providers | grep "google" || echo '')
if [[ -z "$FORCE_TFA_PROVIDER_EXISTS" ]]; then
  echo "Force google as default TFA Provider"
  "${ROLL_DIR}/bin/roll" magento config:set twofactorauth/general/force_providers google
fi

echo "Setting autologin 2fa code"
"${ROLL_DIR}/bin/roll" magento security:tfa:google:set-secret localadmin "LAJWZZTAI4KAHY7NBS6NOM3BDZK62IPDT3U5ARGXCJ4WVG7PJSG37FC4XODYWV2UNYMQG3LVMEUTIHO52FQGZU4Z462VNWYKPOM23M2YZNWAJW732RTNAVTQ2APUV64BPBJZKT7I4CAT62KLFEP5DZLWINPZ3JVOWJ6CPOAA77RSFK2PAG6YPS4VP55WYX5BPTX4Z7P6EZ4CY"

echo -e "\n-------------------------------"
printf "\n\nDone!\n\nNow you need to set\n\n  ROLL_ADMIN_AUTOLOGIN=1\n\nin your .env.roll configuration\n\n!!!!!\nIf you executed this command due to the admin popup modal\nthen just refresh the login page!\n!!!!!\n\n\n"