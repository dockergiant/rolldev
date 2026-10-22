#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

if [[ "${ROLL_PARAMS[0]:-}" == "help" ]]; then
  source "${ROLL_DIR}/commands/usage.cmd"
fi

if [[ "${ROLL_INSPECTOR:-0}" != "1" ]]; then
  fatal "Roll Inspector is off. Set ROLL_INSPECTOR=1 in .env.roll and run roll env up."
fi

INSPECTOR_URL="https://inspector.${TRAEFIK_DOMAIN}"
INSPECTOR_TEMPLATE="/usr/local/etc/php/conf.d/98-ddtrace.ini.template"

inspectorContainer() {
  "${ROLL_DIR}/bin/roll" env ps -q inspector 2>/dev/null | head -n 1 || true
  return 0
}

inspectorHealth() {
  docker inspect --format '{{.State.Health.Status}}' "$1" 2>/dev/null || true
  return 0
}

inspectorServiceHasTemplate() {
  "${ROLL_DIR}/bin/roll" env exec -T "$1" test -f "${INSPECTOR_TEMPLATE}" >/dev/null 2>&1
}

inspectorServiceHasExcimer() {
  "${ROLL_DIR}/bin/roll" env exec -T "$1" sh -c 'php -m | grep -qx excimer' >/dev/null 2>&1
}

inspectorTraceServices() {
  echo "php-fpm"
  [[ "${ROLL_INSPECTOR_TRACE_DEBUG:-0}" == "1" ]] && echo "php-debug"
  return 0
}

INSPECTOR_ACTION="${ROLL_PARAMS[0]:-open}"

case "${INSPECTOR_ACTION}" in
  open)
    INSPECTOR_CONTAINER="$(inspectorContainer)"
    if [[ -z "${INSPECTOR_CONTAINER}" ]] || [[ "$(docker inspect --format '{{.State.Running}}' "${INSPECTOR_CONTAINER}" 2>/dev/null || true)" != "true" ]]; then
      fatal "Roll Inspector is not running. Run roll env up first."
    fi
    if [[ "$(inspectorHealth "${INSPECTOR_CONTAINER}")" != "healthy" ]]; then
      warning "Roll Inspector is not healthy yet; the route serves the store until it is."
    fi
    if [[ "${ROLL_ENV_SUBT}" == "darwin" ]]; then
      open "${INSPECTOR_URL}" || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "${INSPECTOR_URL}" >/dev/null 2>&1 || true
    fi
    success "Roll Inspector: ${INSPECTOR_URL}"
    ;;
  status)
    INSPECTOR_CONTAINER="$(inspectorContainer)"
    INSPECTOR_STATE="not running"
    INSPECTOR_HEALTH_TEXT="-"
    if [[ -n "${INSPECTOR_CONTAINER}" ]]; then
      INSPECTOR_STATE="$(docker inspect --format '{{.State.Status}}' "${INSPECTOR_CONTAINER}" 2>/dev/null || true)"
      INSPECTOR_HEALTH_TEXT="$(inspectorHealth "${INSPECTOR_CONTAINER}")"
      [[ -z "${INSPECTOR_HEALTH_TEXT}" ]] && INSPECTOR_HEALTH_TEXT="-"
    fi
    INSPECTOR_TRACING_SUPPORT="no"
    inspectorServiceHasTemplate php-fpm && INSPECTOR_TRACING_SUPPORT="yes"
    INSPECTOR_PROFILING_SUPPORT="no"
    inspectorServiceHasExcimer php-fpm && INSPECTOR_PROFILING_SUPPORT="yes"

    tableNew
    tableTitle "$(tableColor bold "Roll Inspector:")  ${ROLL_ENV_NAME}"
    tableHeader "SETTING" "VALUE"
    tableRow "ROLL_INSPECTOR" "${ROLL_INSPECTOR:-0}"
    tableRow "ROLL_INSPECTOR_TRACE" "${ROLL_INSPECTOR_TRACE:-0}"
    tableRow "ROLL_INSPECTOR_TRACE_DEBUG" "${ROLL_INSPECTOR_TRACE_DEBUG:-0}"
    tableRow "ROLL_INSPECTOR_PROFILE" "${ROLL_INSPECTOR_PROFILE:-off}"
    tableRow "ROLL_INSPECTOR_TRACE_DETAIL" "${ROLL_INSPECTOR_TRACE_DETAIL:-full}"
    tableRow "ROLL_INSPECTOR_SAMPLE" "${ROLL_INSPECTOR_SAMPLE:-10}"
    tableRow "Container" "${INSPECTOR_STATE}"
    tableRow "Health" "${INSPECTOR_HEALTH_TEXT}"
    tableRow "URL" "${INSPECTOR_URL}"
    tableRow "Image supports tracing" "${INSPECTOR_TRACING_SUPPORT}"
    tableRow "Image supports profiling" "${INSPECTOR_PROFILING_SUPPORT}"
    tableRender
    ;;
  trace)
    INSPECTOR_TRACE_MODE="${ROLL_PARAMS[1]:-}"
    if [[ "${INSPECTOR_TRACE_MODE}" != "on" && "${INSPECTOR_TRACE_MODE}" != "off" ]]; then
      fatal "Usage: roll inspector trace on|off"
    fi
    if [[ "${ROLL_NEWRELIC:-0}" == "1" ]]; then
      fatal "Tracing and ROLL_NEWRELIC cannot both be enabled. Set ROLL_NEWRELIC=0 first."
    fi
    INSPECTOR_CONTAINER="$(inspectorContainer)"
    if [[ -z "${INSPECTOR_CONTAINER}" ]]; then
      fatal "Roll Inspector is not running. Run roll env up first."
    fi
    if ! inspectorServiceHasTemplate php-fpm; then
      fatal "This php-fpm image predates tracing: run roll env pull && roll env up"
    fi
    for INSPECTOR_SERVICE in $(inspectorTraceServices); do
      "${ROLL_DIR}/bin/roll" env exec -T -u root \
        -e ROLL_ENV_NAME="${ROLL_ENV_NAME}" -e ROLL_INSPECTOR_PROFILE="${ROLL_INSPECTOR_PROFILE:-off}" \
        -e ROLL_INSPECTOR_TRACE_DETAIL="${ROLL_INSPECTOR_TRACE_DETAIL:-full}" \
        "${INSPECTOR_SERVICE}" roll-inspector-ini "${INSPECTOR_TRACE_MODE}"
      "${ROLL_DIR}/bin/roll" env exec -T -u root "${INSPECTOR_SERVICE}" kill -USR2 1
    done
    success "Tracing is ${INSPECTOR_TRACE_MODE} in $(inspectorTraceServices | tr '\n' ' ')"
    info "This lasts until the php containers restart: roll env restart php-fpm returns to the .env.roll values."
    ;;
  *)
    fatal "Unknown inspector action '${INSPECTOR_ACTION}'. Use open, status or trace on|off."
    ;;
esac
