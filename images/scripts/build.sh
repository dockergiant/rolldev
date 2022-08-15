#!/usr/bin/env bash
set -e
trap 'error "$(printf "Command \`%s\` at $BASH_SOURCE:$LINENO failed with exit code $?" "$BASH_COMMAND")"' ERR

## find directory where this script is located following symlinks if neccessary
readonly BASE_DIR="$(
  cd "$(
    dirname "$(
      (readlink "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}") \
        | sed -e "s#^../#$(dirname "$(dirname "${BASH_SOURCE[0]}")")/#"
    )"
  )" >/dev/null \
  && pwd
)/.."
pushd ${BASE_DIR} >/dev/null

## import roll util functions
readonly ROLL_DIR="${BASE_DIR}/.."
source "${ROLL_DIR}/utils/core.sh"

SEARCH_PATH="${1:-}"
PUSH=""

## since fpm images no longer can be traversed, this script should require a search path vs defaulting to build all
if [[ -z ${SEARCH_PATH} ]]; then
  fatal "Missing search path. Please try again passing an image type as an argument."
fi

if [[ -z ${ACT} ]]; then
	PUSH="--push"
  ## login to docker hub as needed
  if [[ ${DOCKER_USERNAME:-} ]]; then
  	echo "Attempting non-interactive docker login (via provided credentials)"
  	echo "${DOCKER_PASSWORD:-}" | docker login -u "${DOCKER_USERNAME:-}" --password-stdin ${DOCKER_REGISTRY:-docker.io}
  elif [[ -t 1 ]]; then
  	echo "Attempting interactive docker login (tty)"
  	docker login ${DOCKER_REGISTRY:-docker.io}
  fi
fi


## define image repository to push
ROLL_IMAGE_REPOSITORY="${ROLL_IMAGE_REPOSITORY:-"docker.io/rollupdev"}"

## iterate over and build each Dockerfile
for file in $(find ${SEARCH_PATH} -type f -name Dockerfile | sort -V); do
    BUILD_DIR="$(dirname "${file}")"
    IMAGE_TAG="${ROLL_IMAGE_REPOSITORY}/$(echo "${BUILD_DIR}" | cut -d/ -f1)"
    IMAGE_SUFFIX="$(echo "${BUILD_DIR}" | cut -d/ -f2- -s | tr / - | sed 's/^-//')"

    ## due to build matrix requirements, magento1 and magento2 specific variants are built in separate invocation
    if [[ ${SEARCH_PATH} == "php-fpm" ]] && [[ ${file} =~ php-fpm/magento[1-2] ]]; then
      continue;
    fi

    ## fpm images will not have each version in a directory tree; require version be passed
    ## in as env variable for use as a build argument
    BUILD_ARGS=()
    if [[ ${SEARCH_PATH} = *fpm* ]]; then
      if [[ -z ${PHP_VERSION} ]]; then
        fatal "Building ${SEARCH_PATH} images requires PHP_VERSION env variable be set."
      fi

      ## define default sources for main php and environment images
      export PHP_SOURCE_IMAGE="${PHP_SOURCE_IMAGE:-"docker.io/rollupdev/php"}"
      BUILD_ARGS+=("--build-arg")
      BUILD_ARGS+=("PHP_SOURCE_IMAGE")

      export ENV_SOURCE_IMAGE="${ENV_SOURCE_IMAGE:-"${ROLL_IMAGE_REPOSITORY}/php-fpm"}"
      BUILD_ARGS+=("--build-arg")
      BUILD_ARGS+=("ENV_SOURCE_IMAGE")

      export PHP_VERSION

      IMAGE_TAG+=":${PHP_VERSION}"
      if [[ ${IMAGE_SUFFIX} ]]; then
        IMAGE_TAG+="-${IMAGE_SUFFIX}"
      fi
      BUILD_ARGS+=("--build-arg")
      BUILD_ARGS+=("PHP_VERSION")

      # Support for PHP 8 images which require (temporarily at least) use of non-loader variant of base image
      if [[ ${PHP_VARIANT:-} ]]; then
        export PHP_VARIANT
        BUILD_ARGS+=("--build-arg")
        BUILD_ARGS+=("PHP_VARIANT")
      fi
    else
      IMAGE_TAG+=":${IMAGE_SUFFIX}"
    fi

    # Skip build of xdebug3 fpm images on older versions of PHP (it requires PHP 7.2 or greater)
    if [[ ${IMAGE_SUFFIX} =~ 'xdebug3' ]] && (test $(version ${PHP_VERSION}) -lt $(version "7.2") \
    	|| test $(version ${PHP_VERSION}) -gt $(version "8.1")); then

      warning "Skipping build for ${IMAGE_TAG} (xdebug3 is unavailable for PHP ${PHP_VERSION})"
      continue
    fi

    # Skip build of xdebug2 fpm images on newer versions of PHP (it requires PHP 7.4 or lower)
	if [[ ! ${IMAGE_SUFFIX} =~ 'debug3' ]] && [[ ${IMAGE_SUFFIX} =~ 'debug' ]] && test $(version ${PHP_VERSION}) -gt $(version "7.4"); then
	  warning "Skipping build for ${IMAGE_TAG} (xdebug is unavailable for PHP ${PHP_VERSION})"
	  continue
	fi

	# Skip build of blackfire images on newer versions of PHP (it requires PHP 7.4 or lower)
	if [[ ${IMAGE_SUFFIX} =~ 'blackfire' ]] && test $(version ${PHP_VERSION}) -gt $(version "8.0"); then
	  warning "Skipping build for ${IMAGE_TAG} (blackfire is unavailable for PHP ${PHP_VERSION})"
	  continue
	fi

    if [[ -d "$(echo ${BUILD_DIR} | cut -d/ -f1)/context" ]]; then
      BUILD_CONTEXT="$(echo ${BUILD_DIR} | cut -d/ -f1)/context"
    else
      BUILD_CONTEXT="${BUILD_DIR}"
    fi

    printf "\e[01;31m==> building ${IMAGE_TAG} from ${BUILD_DIR}/Dockerfile with context ${BUILD_CONTEXT}\033[0m\n"
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    docker buildx create --use

    docker buildx build ${PUSH} --platform linux/amd64,linux/arm64 -t "${IMAGE_TAG}" -f ${BUILD_DIR}/Dockerfile ${BUILD_ARGS[@]} ${BUILD_CONTEXT}

done
