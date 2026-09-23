#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

# shellcheck disable=SC2034 # read by magento1-init.cmd, which is sourced below
MAGENTO1_DISTRIBUTION=ce
source "${ROLL_DIR}/commands/magento1-init.cmd"
