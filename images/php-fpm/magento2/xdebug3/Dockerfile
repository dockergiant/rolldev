ARG ENV_SOURCE_IMAGE
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}-magento2
USER root

RUN PHP_V=$(echo ${PHP_VERSION} | head -n1 | cut -d' ' -f2 | awk -F '.' '{print $1$2}') \
    && if (( ${PHP_V} >= 80 )); then install-php-extensions xdebug-^3; else install-php-extensions xdebug-3.1.5; fi

COPY xdebug3/etc/*.ini /etc/
COPY xdebug3/etc/php.d/*.ini /etc/php.d/

USER www-data
