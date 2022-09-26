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

## configure docker-compose files
DOCKER_COMPOSE_ARGS=()

DOCKER_COMPOSE_ARGS+=("-f")
DOCKER_COMPOSE_ARGS+=("${ROLL_DIR}/docker/docker-compose.yml")

## special handling when 'svc up' is run
if [[ "${ROLL_PARAMS[0]}" == "up" ]]; then
		# update images if needed
		roll svc pull

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

## pass ochestration through to docker-compose
docker-compose \
    --project-directory "${ROLL_HOME_DIR}" -p roll \
    "${DOCKER_COMPOSE_ARGS[@]}" "${ROLL_PARAMS[@]}" "$@"

## connect peered service containers to environment networks when 'svc up' is run
if [[ "${ROLL_PARAMS[0]}" == "up" ]]; then
    for network in $(docker network ls -f label=dev.roll.environment.name --format {{.Name}}); do
        connectPeeredServices "${network}"
    done
fi
