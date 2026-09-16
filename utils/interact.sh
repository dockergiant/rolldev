#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

## Prompts share one rule: a value already supplied by flag or environment wins, a prompt only runs
## with a terminal on stdin, and otherwise the command fails naming the flag that supplies the value.
## That keeps roll usable from scripts and CI, where a prompt would hang.

function isInteractive() {
    [[ -t 0 ]]
}

## fatalNoTty <what> <how-to-supply>
function fatalNoTty() {
    local what="$1"
    local how="$2"

    error "Cannot prompt for ${what}: no terminal attached."
    fatal "Supply it non-interactively with ${how}."
}

## promptInput <varname> <how-to-supply> <prompt> [placeholder]
function promptInput() {
    local var="$1" how="$2" prompt="$3" placeholder="${4:-}"
    local current="" value="" status=0

    eval "current=\${${var}:-}"
    if [[ -n "${current}" ]]; then
        return 0
    fi

    if ! isInteractive; then
        fatalNoTty "${prompt}" "${how}"
    fi

    if [[ -n "${placeholder}" ]]; then
        prompt="${prompt} (${placeholder})"
    fi

    ## read fails on EOF, which set -e would otherwise turn into a silent exit
    read -r -p "${prompt} " value || status=$?
    if [[ ${status} -ne 0 || -z "${value}" ]]; then
        [[ ${status} -ne 0 ]] && >&2 echo ""
        fatal "No value entered."
    fi

    printf -v "${var}" '%s' "${value}"
    return 0
}

## promptChoose <varname> <how-to-supply> <header> <option>...
function promptChoose() {
    local var="$1" how="$2" header="$3"
    shift 3
    local current="" value="" option=""

    eval "current=\${${var}:-}"
    if [[ -n "${current}" ]]; then
        return 0
    fi

    if (( $# == 0 )); then
        fatal "promptChoose called with no options for ${var}."
    fi

    if ! isInteractive; then
        fatalNoTty "${header}" "${how}"
    fi

    >&2 echo "${header}"
    local PS3="Enter a number: "
    select option in "$@"; do
        if [[ -n "${option}" ]]; then
            value="${option}"
            break
        fi
        >&2 echo "Please choose one of the numbers above."
    done

    if [[ -z "${value}" ]]; then
        >&2 echo ""
        fatal "No option selected."
    fi

    printf -v "${var}" '%s' "${value}"
    return 0
}

## promptConfirm <how-to-supply> <question>
## Returns 0 for yes and 1 for anything else.
function promptConfirm() {
    local how="$1" question="$2"
    local answer="" status=0

    if ! isInteractive; then
        fatalNoTty "confirmation" "${how}"
    fi

    read -r -p "${question} [y/N] " answer || status=$?
    if [[ ${status} -ne 0 ]]; then
        >&2 echo ""
        return 1
    fi

    case "${answer}" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

## promptPassword <varname> <how-to-supply> <prompt> [confirm-prompt]
## Assigns through printf -v, so the password never passes through a command substitution or argv.
function promptPassword() {
    local var="$1" how="$2" prompt="$3" confirm_prompt="${4:-}"
    local current="" value="" confirm="" status=0

    eval "current=\${${var}:-}"
    if [[ -n "${current}" ]]; then
        return 0
    fi

    if ! isInteractive; then
        fatalNoTty "a password" "${how}"
    fi

    read -r -s -p "${prompt}: " value || status=$?
    >&2 echo ""
    if [[ ${status} -ne 0 || -z "${value}" ]]; then
        fatal "Password cannot be empty."
    fi

    if [[ -n "${confirm_prompt}" ]]; then
        read -r -s -p "${confirm_prompt}: " confirm || true
        >&2 echo ""
        if [[ "${value}" != "${confirm}" ]]; then
            fatal "Passwords do not match."
        fi
    fi

    printf -v "${var}" '%s' "${value}"
    return 0
}
