#!/usr/bin/env bash
#
# Docker-free smoke test for the roll CLI: commands that need no Docker daemon and no project, so
# bash 3.2 and BSD/GNU tool regressions show up in CI.
#
# Usage: smoke.sh [native|bash32]
#   native  run roll through its own #!/usr/bin/env bash shebang (default)
#   bash32  run roll under /bin/bash, which is bash 3.2.57 on macOS

set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROLL_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)"

MODE="${1:-native}"

## TEST_BASH also runs the helper tests: CI runners put Homebrew bash 5 first on PATH, which would
## otherwise hide bash 3.2 failures behind their #!/usr/bin/env bash
case "${MODE}" in
  bash32)
    ROLL_BIN=(/bin/bash "${ROLL_DIR}/bin/roll")
    TEST_BASH=/bin/bash
    ;;
  native)
    ROLL_BIN=("${ROLL_DIR}/bin/roll")
    TEST_BASH=bash
    ;;
  *)
    >&2 echo "Usage: $0 [native|bash32]"
    exit 1
    ;;
esac

run() {
  echo "+ ${ROLL_BIN[*]} $*"
  "${ROLL_BIN[@]}" "$@"
}

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/roll-smoke.XXXXXX")"
cleanup() {
  rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

run version
run config schema >/dev/null

echo "+ roll (bare) prints the usage once"
mkdir -p "${TMP_DIR}/empty-home"
usage_count="$(ROLL_HOME_DIR="${TMP_DIR}/empty-home" "${ROLL_BIN[@]}" 2>&1 | grep -c 'Commands:' || true)"
if [[ "${usage_count}" != "1" ]]; then
  >&2 echo "FAIL: bare roll printed the usage ${usage_count} times"
  exit 1
fi
run registry validate
run registry categories >/dev/null
run registry paths >/dev/null

(
  cd -- "${TMP_DIR}"
  "${ROLL_BIN[@]}" env-init smoketest magento2 </dev/null
  "${ROLL_BIN[@]}" config validate

  echo "+ env-init takes a piped answer to the overwrite prompt"
  if ! echo y | "${ROLL_BIN[@]}" env-init smoketest magento2 >/dev/null 2>&1; then
    >&2 echo "FAIL: env-init rejected a piped overwrite answer"
    exit 1
  fi

  echo "+ env-init with an invalid name (no tty)"
  mkdir invalid-name && cd invalid-name
  if "${ROLL_BIN[@]}" env-init Invalid_Name magento2 </dev/null >/dev/null 2>&1; then
    >&2 echo "FAIL: env-init accepted an invalid environment name"
    exit 1
  fi
)

"${TEST_BASH}" "${SCRIPT_DIR}/test-syntax.sh"
"${TEST_BASH}" "${SCRIPT_DIR}/test-interact.sh" </dev/null
"${TEST_BASH}" "${SCRIPT_DIR}/test-table.sh"

echo "Smoke test passed (${MODE} mode)."
