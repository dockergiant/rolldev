ARG ENV_SOURCE_IMAGE
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}
USER root

RUN set -eux \
    && mkdir -p /usr/local/bin \
    && curl -s curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar > /usr/local/bin/wp-cli \
    && chmod +x /usr/local/bin/wp-cli

# Create wp alias for wp-cli
RUN ln -s /usr/local/bin/wp-cli /usr/local/bin/wp

USER www-data
