#!/usr/bin/env bash
# Parse every command, help and util file with the running bash, and check that no command on
# ROLL_CMD_ANYARGS re-invokes its own --help. Neither ShellCheck nor Ubuntu CI catches these:
# bash 3.2 mis-parses a lone apostrophe in a heredoc inside $( ), and an ANYARGS command that runs
# `roll <itself> --help` receives --help again and forks until killed.
#
# Run it under /bin/bash on macOS for the first check to mean anything.
set -eu

ROLL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROLL_DIR}"

failed=0

echo "bash ${BASH_VERSION} syntax check"
for file in bin/roll commands/*.cmd commands/*/*.cmd commands/*.help commands/*/*.help utils/*.sh; do
    [[ -e "${file}" ]] || continue
    if ! "${BASH}" -n "${file}" 2>/dev/null; then
        echo "  FAIL  ${file}"
        "${BASH}" -n "${file}" 2>&1 | sed 's/^/        /'
        failed=$((failed + 1))
    fi
done

echo "self-referential --help check"
anyargs=" $(sed -n 's/.*ROLL_CMD_ANYARGS=(\(.*\)).*/\1/p' bin/roll) "
for file in commands/*.cmd commands/*/*.cmd; do
    [[ -e "${file}" ]] || continue
    name="${file##*/}"
    name="${name%.cmd}"
    case "${anyargs}" in
        *" ${name} "*) ;;
        *) continue ;;
    esac
    if grep -qE "^[[:space:]]*(\"\\$\\{ROLL_DIR\\}/bin/)?roll\"?[[:space:]]+${name}[[:space:]]+(--help|-h)" "${file}"; then
        echo "  FAIL  ${file} re-invokes 'roll ${name} --help', which recurses forever"
        echo "        source \"\${ROLL_DIR}/commands/usage.cmd\" instead"
        failed=$((failed + 1))
    fi
done

if [[ ${failed} -ne 0 ]]; then
    echo "${failed} file(s) failed."
    exit 1
fi

echo "All files parse and no command re-invokes its own help."
