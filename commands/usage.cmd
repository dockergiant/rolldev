#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## local project directory if running within one; don't fail if it can't be found
ROLL_ENV_PATH="$(locateEnvPath 2>/dev/null)" || true

if [[ -n "$ROLL_ENV_PATH" ]];then
	loadEnvConfig "${ROLL_ENV_PATH}" || true
	
	# Pre-load environment-specific usage fragments to set variables for global usage.help
	if [[ -n "$ROLL_ENV_TYPE" ]]; then
	  # Load system environment-specific usage fragments
	  if [[ -f "${ROLL_DIR}/commands/${ROLL_ENV_TYPE}/usage.help" ]]; then
	    source "${ROLL_DIR}/commands/${ROLL_ENV_TYPE}/usage.help"
	  fi
	  
	  # Load global environment-specific usage fragments (new structure)
	  if [[ -f "${ROLL_HOME_DIR:-$HOME/.roll}/commands/${ROLL_ENV_TYPE}/usage.help" ]]; then
	    source "${ROLL_HOME_DIR:-$HOME/.roll}/commands/${ROLL_ENV_TYPE}/usage.help"
	  fi
	  
	  # Load global environment-specific usage fragments (legacy structure)
	  if [[ -f "${ROLL_HOME_DIR:-$HOME/.roll}/reclu/${ROLL_ENV_TYPE}/usage.help" ]]; then
	    source "${ROLL_HOME_DIR:-$HOME/.roll}/reclu/${ROLL_ENV_TYPE}/usage.help"
	  fi
	fi
fi

## Load usage info for the given command falling back on default usage text
if [[ -f "${ROLL_CMD_HELP}" ]]; then
  # Load command-specific help file
  source "${ROLL_CMD_HELP}"
elif [[ -f "${ROLL_HOME_DIR:-$HOME/.roll}/commands/usage.help" ]]; then
  # Load global usage (variables are already set above)
  source "${ROLL_HOME_DIR:-$HOME/.roll}/commands/usage.help"
elif [[ -f "${ROLL_HOME_DIR:-$HOME/.roll}/reclu/usage.help" ]]; then
  # Load legacy global usage
  source "${ROLL_HOME_DIR:-$HOME/.roll}/reclu/usage.help"
else
  # Load system default usage (fragments already loaded above if needed)
  source "${ROLL_DIR}/commands/usage.help"
fi

echo -e "${ROLL_USAGE}"
exit 1
