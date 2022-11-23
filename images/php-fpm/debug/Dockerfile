ARG ENV_SOURCE_IMAGE
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}
USER root

RUN install-php-extensions xdebug-^2

COPY debug/etc/*.ini ${PHP_INI_DIR}/
COPY debug/etc/conf.d/* ${PHP_INI_DIR}/conf.d/

RUN docker-php-ext-enable xdebug
