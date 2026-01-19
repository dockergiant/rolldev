#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${ROLL_DIR}/utils/install.sh"
assertRollDevInstall
assertDockerRunning

if (( ${#ROLL_PARAMS[@]} == 0 )) || [[ "${ROLL_PARAMS[0]}" == "help" ]]; then
  roll svc --help || exit $? && exit $?
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
  eval "$(cat "${ROLL_HOME_DIR}/.env" | sed 's/\r$//g' | grep "^ROLL_")"
fi
export ROLL_IMAGE_REPOSITORY="${ROLL_IMAGE_REPOSITORY:-"ghcr.io/dockergiant"}"

## configure docker-compose files
DOCKER_COMPOSE_ARGS=()

DOCKER_COMPOSE_ARGS+=("-f")
DOCKER_COMPOSE_ARGS+=("${ROLL_DIR}/docker/docker-compose.yml")

# Load optional service flags
if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
    # Portainer service
    eval "$(grep "^ROLL_SERVICE_PORTAINER" "${ROLL_HOME_DIR}/.env")"

     # Startpage service
    eval "$(grep "^ROLL_SERVICE_STARTPAGE" "${ROLL_HOME_DIR}/.env")"
fi

ROLL_SERVICE_PORTAINER="${ROLL_SERVICE_PORTAINER:-0}"
if [[ "${ROLL_SERVICE_PORTAINER}" == 1 ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${ROLL_DIR}/docker/portainer-service.yml")
fi

ROLL_SERVICE_STARTPAGE="${ROLL_SERVICE_STARTPAGE:-1}"
if [[ "${ROLL_SERVICE_STARTPAGE}" == 1 ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${ROLL_DIR}/docker/startpage-service.yml")
fi

## special handling when 'svc up' is run
if [[ "${ROLL_PARAMS[0]}" == "up" ]]; then
		# update images if needed
		if [[ $(isOnline) == true ]]; then
		  roll svc pull
		fi

    ## sign certificate used by global services (by default roll.test)
    if [[ -f "${ROLL_HOME_DIR}/.env" ]]; then
        eval "$(grep "^ROLL_SERVICE_DOMAIN" "${ROLL_HOME_DIR}/.env")"
    fi

    ROLL_SERVICE_DOMAIN="${ROLL_SERVICE_DOMAIN:-roll.test}"
    if [[ ! -f "${ROLL_SSL_DIR}/certs/${ROLL_SERVICE_DOMAIN}.crt.pem" ]]; then
        "${ROLL_DIR}/bin/roll" sign-certificate "${ROLL_SERVICE_DOMAIN}"
    fi

    ## copy configuration files into location where they'll be mounted into containers from
    mkdir -p "${ROLL_HOME_DIR}/etc/traefik"
    cp "${ROLL_DIR}/config/traefik/traefik.yml" "${ROLL_HOME_DIR}/etc/traefik/traefik.yml"

    ## generate dynamic traefik ssl termination configuration
    cat > "${ROLL_HOME_DIR}/etc/traefik/dynamic.yml" <<-EOT
		tls:
		  stores:
		    default:
		      defaultCertificate:
		        certFile: /etc/ssl/certs/${ROLL_SERVICE_DOMAIN}.crt.pem
		        keyFile: /etc/ssl/certs/${ROLL_SERVICE_DOMAIN}.key.pem
		  certificates:
	EOT

    for cert in $(find "${ROLL_SSL_DIR}/certs" -type f -name "*.crt.pem" | sed -E 's#^.*/ssl/certs/(.*)\.crt\.pem$#\1#'); do
        cat >> "${ROLL_HOME_DIR}/etc/traefik/dynamic.yml" <<-EOF
		    - certFile: /etc/ssl/certs/${cert}.crt.pem
		      keyFile: /etc/ssl/certs/${cert}.key.pem
		EOF
    done

    ## always execute svc up using --detach mode
    if ! (containsElement "-d" "$@" || containsElement "--detach" "$@"); then
        ROLL_PARAMS=("${ROLL_PARAMS[@]:1}")
        ROLL_PARAMS=(up -d "${ROLL_PARAMS[@]}")
    fi
fi

ROLL_VERSION=$(cat ${ROLL_DIR}/version)

## pass orchestration through to docker-compose
ROLL_VERSION=${ROLL_VERSION:-"in-dev"} docker compose \
    --project-directory "${ROLL_HOME_DIR}" -p roll \
    "${DOCKER_COMPOSE_ARGS[@]}" "${ROLL_PARAMS[@]}" "$@"

## connect peered service containers to environment networks when 'svc up' is run
if [[ "${ROLL_PARAMS[0]}" == "up" ]]; then
    for network in $(docker network ls -f label=dev.roll.environment.name --format {{.Name}}); do
        connectPeeredServices "${network}"
    done
fi
