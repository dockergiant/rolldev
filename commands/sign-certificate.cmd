#!/usr/bin/env bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

mkdir -p "${ROLL_SSL_DIR}/certs"

if [[ ! -f "${ROLL_SSL_DIR}/rootca/certs/ca.cert.pem" ]]; then
  fatal "Missing the root CA file. Please run 'roll install' and try again."
fi

if (( ${#ROLL_PARAMS[@]} == 0 )); then
  echo -e "\033[33mCommand '${ROLL_CMD_VERB}' requires a hostname as an argument, please use --help for details."
  exit -1
fi

CERTIFICATE_SAN_LIST=
for (( i = 0; i < ${#ROLL_PARAMS[@]} * 2; i+=2 )); do
  [[ ${CERTIFICATE_SAN_LIST} ]] && CERTIFICATE_SAN_LIST+=","
  CERTIFICATE_SAN_LIST+="DNS.$(expr $i + 1):${ROLL_PARAMS[i/2]}"
  CERTIFICATE_SAN_LIST+=",DNS.$(expr $i + 2):*.${ROLL_PARAMS[i/2]}"
done

CERTIFICATE_NAME="${ROLL_PARAMS[0]}"

if [[ -f "${ROLL_SSL_DIR}/certs/${CERTIFICATE_NAME}.key.pem" ]]; then
    >&2 echo -e "\033[33mWarning: Certificate for ${CERTIFICATE_NAME} already exists! Overwriting...\033[0m\n"
fi

echo "==> Generating private key ${CERTIFICATE_NAME}.key.pem"
openssl genrsa -out "${ROLL_SSL_DIR}/certs/${CERTIFICATE_NAME}.key.pem" 2048

echo "==> Generating signing req ${CERTIFICATE_NAME}.crt.pem"
openssl req -new -sha256 -config <(cat                            \
    "${ROLL_DIR}/config/openssl/certificate.conf"               \
    <(printf "extendedKeyUsage = serverAuth,clientAuth \n         \
      subjectAltName = %s" "${CERTIFICATE_SAN_LIST}")             \
  )                                                               \
  -key "${ROLL_SSL_DIR}/certs/${CERTIFICATE_NAME}.key.pem"      \
  -out "${ROLL_SSL_DIR}/certs/${CERTIFICATE_NAME}.csr.pem"      \
  -subj "/C=US/O=getroll.dev/CN=${CERTIFICATE_NAME}"

echo "==> Generating certificate ${CERTIFICATE_NAME}.crt.pem"
openssl x509 -req -days 365 -sha256 -extensions v3_req            \
  -extfile <(cat                                                  \
    "${ROLL_DIR}/config/openssl/certificate.conf"               \
    <(printf "extendedKeyUsage = serverAuth,clientAuth \n         \
      subjectAltName = %s" "${CERTIFICATE_SAN_LIST}")             \
  )                                                               \
  -CA "${ROLL_SSL_DIR}/rootca/certs/ca.cert.pem"                \
  -CAkey "${ROLL_SSL_DIR}/rootca/private/ca.key.pem"            \
  -CAserial "${ROLL_SSL_DIR}/rootca/serial"                     \
  -in "${ROLL_SSL_DIR}/certs/${CERTIFICATE_NAME}.csr.pem"       \
  -out "${ROLL_SSL_DIR}/certs/${CERTIFICATE_NAME}.crt.pem"

if [[ "$(cd "${ROLL_HOME_DIR}" && docker-compose -p roll -f "${ROLL_DIR}/docker/docker-compose.yml" ps -q traefik)" ]]
then
  echo "==> Updating traefik"
  "${ROLL_DIR}/bin/roll" svc up traefik
  "${ROLL_DIR}/bin/roll" svc restart traefik
fi
