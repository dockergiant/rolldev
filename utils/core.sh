#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## global service containers to be connected with the project docker network
DOCKER_PEERED_SERVICES=("traefik" "tunnel" "mailhog")

## messaging functions
function success {
  >&2 printf "\033[32mSUCCESS\033[0m: %s\n" "$*"
}

function info {
  >&2 printf "\033[33mINFO\033[0m: %s\n" "$*"
}

function warning {
  >&2 printf "\033[33mWARNING\033[0m: %s\n" "$*"
}

function error {
  >&2 printf "\033[31mERROR\033[0m: %s\n" "$*"
}

function fatal {
  error "$@"
  exit 1
}

## usage: box <tput color> <line>...
function box() {
	local color="$1"; shift
	## bash 4.4+ applies set -u inside arithmetic, so w must start at 0 rather than unset
	local s=("$@") b="" w=0 use_tput=0

	## tput fails without a terminal (cron, CI, pipes), so only colour the box on a real TTY
	if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]] && command -v tput >/dev/null 2>&1; then
		use_tput=1
	fi

	for l in "${s[@]}"; do
		((w < ${#l})) && {
			b="$l"
			w="${#l}"
		}
	done
	((use_tput)) && tput setaf 3
	echo " -${b//?/-}-
| ${b//?/ } |"
	for l in "${s[@]}"; do
		if ((use_tput)); then
			printf '| %s%*s%s |\n' "$(tput setaf "$color")" "-$w" "$l" "$(tput setaf 3)"
		else
			printf '| %*s |\n' "-$w" "$l"
		fi
	done
	echo "| ${b//?/ } |
 -${b//?/-}-"
	((use_tput)) && tput sgr 0

	return 0
}

function boxinfo() {
	box 7 "$@"
}

function boxsuccess() {
	box 2 "$@"
}

function boxerror() {
	box 1 "$@"
}

function version {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

## bash 3.2 has no ${var^}
function capitalize() {
  local s="$1"
  printf '%s%s' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"
}

## determines if value is present in an array; returns 0 if element is present
## in array, otherwise returns 1
##
## usage: containsElement <needle> <haystack>
##
function containsElement {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

## verify docker is running
function assertDockerRunning {
  if ! docker system info >/dev/null 2>&1; then
    fatal "Docker does not appear to be running. Please start Docker."
  fi
}

## methods to peer global services requiring network connectivity with project networks
function connectPeeredServices {
  for svc in "${DOCKER_PEERED_SERVICES[@]}"; do
    echo "Connecting ${svc} to $1 network"
    (docker network connect "$1" ${svc} 2>&1| grep -v 'already exists in network') || true
  done
}

function disconnectPeeredServices {
  for svc in "${DOCKER_PEERED_SERVICES[@]}"; do
    echo "Disconnecting ${svc} from $1 network"
    (docker network disconnect "$1" ${svc} 2>&1| grep -v 'is not connected') || true
  done
}

## ping -t is a timeout on BSD but a TTL on GNU, and ICMP is often blocked, so probe the registry
## that svc pull needs. No -f: the endpoint answers 401, and any HTTP response proves reachability.
function isOnline() {
  if curl -s -m 3 -o /dev/null "https://ghcr.io/v2/" 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

## usage: printf '"%s"' "$(jsonEscape "$raw")"
function jsonEscape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  raw="${raw//$'\r'/\\r}"
  raw="${raw//$'\t'/\\t}"
  printf '%s' "$raw"
}

## cross-platform sed in-place editing function
## works on both macOS (BSD sed) and Linux (GNU sed)
function sed_inplace() {
    local pattern="$1"
    local file="$2"
    local backup_ext="${3:-.bak}"

    # Only the attached suffix form works in both BSD and GNU sed; $OSTYPE does not tell which sed is on
    # PATH (macOS users often have GNU sed from Homebrew), and GNU sed reads a separate suffix as the script
    sed -i"$backup_ext" "$pattern" "$file"

    # Remove backup file if it exists and we used .bak extension
    if [[ "$backup_ext" == ".bak" && -f "${file}${backup_ext}" ]]; then
        rm -f "${file}${backup_ext}"
    fi
}

## The URI carries the database password, and `open "$uri"` would put it in argv where ps shows it.
## osascript reads its script from stdin, so only "osascript -" is visible.
function openInTablePlus() {
  local uri="$1"
  local app="${TABLEPLUS_APP:-TablePlus}"
  local escaped escaped_app

  escaped="${uri//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped_app="${app//\\/\\\\}"
  escaped_app="${escaped_app//\"/\\\"}"

  ## told to the app explicitly: a bare `open location` goes to whichever app claims mariadb+ssh://
  if printf 'tell application "%s" to open location "%s"\n' "${escaped_app}" "${escaped}" | osascript - >/dev/null 2>&1; then
    return 0
  fi

  warning "Could not hand the connection to TablePlus via osascript; falling back to \`open\`,"
  warning "which briefly exposes the database password in the process list."
  open "${uri}" -a "${TABLEPLUS_APP:-TablePlus}"
}
