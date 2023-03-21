#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function installSshConfig () {
  if ! grep '## ROLL START ##' /etc/ssh/ssh_config >/dev/null; then
    echo "==> Configuring sshd tunnel in host ssh_config (requires sudo privileges)"
    echo "    Note: This addition to the ssh_config file can sometimes be erased by a system"
    echo "    upgrade requiring reconfiguring the SSH config for tunnel.roll.test."
    cat <<-EOT | sudo tee -a /etc/ssh/ssh_config >/dev/null

			## ROLL START ##
			Host tunnel.roll.test
			HostName 127.0.0.1
			User user
			Port 2222
			IdentityFile ~/.roll/tunnel/ssh_key
			## ROLL END ##
			EOT
  fi

  if [[ -f "${HOME}/.ssh/config" ]]; then
    if grep 'Host \*' "$HOME/.ssh/config" >/dev/null; then
      echo ""
      echo "==> Conflicting configuration found in your $HOME/.ssh/config file"
      echo "    You need to add the following configuration to your $HOME/.ssh/config file"
      echo "
## ROLL START ##
Host tunnel.roll.test
HostName 127.0.0.1
User user
Port 2222
IdentityFile ~/.roll/tunnel/ssh_key
## ROLL END ##"
    fi
  fi
}

function assertRollDevInstall {
  if [[ ! -f "${ROLL_HOME_DIR}/.installed" ]] \
    || [[ "${ROLL_HOME_DIR}/.installed" -ot "${ROLL_DIR}/bin/roll" ]]
  then
    [[ -f "${ROLL_HOME_DIR}/.installed" ]] && echo "==> Updating roll" || echo "==> Starting initialization"

    "${ROLL_DIR}/bin/roll" install

    [[ -f "${ROLL_HOME_DIR}/.installed" ]] && echo "==> Update complete" || echo "==> Initialization complete"
    date > "${ROLL_HOME_DIR}/.installed"
  fi

  ## append settings for tunnel.roll.test in /etc/ssh/ssh_config
  #
  # NOTE: This function is called on every invocation of this assertion in an attempt to ensure
  # the ssh configuration for the tunnel is present following it's removal following a system
  # upgrade (macOS Catalina has been found to reset the global SSH configuration file)
  #

  installSshConfig
}
