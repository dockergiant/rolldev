ARG ENV_SOURCE_IMAGE
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}-magento2
USER root

RUN install-php-extensions xdebug-^2

COPY debug/etc/*.ini /etc/
COPY debug/etc/conf.d/* /usr/local/etc/php/conf.d/

RUN docker-php-ext-enable xdebug

USER www-data
