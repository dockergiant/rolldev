ARG ENV_SOURCE_IMAGE
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}
ARG TARGETARCH
USER root

RUN install-php-extensions blackfire

# Install the Blackfire Client to provide access to the CLI tool
RUN mkdir -p /tmp/blackfire \
    && CLIENT_URL='https://packages.blackfire.io/binaries/blackfire/2.10.0/blackfire-linux_amd64.tar.gz'\
    && if [[ '${TARGETARCH}' == 'arm64' ]]; then CLIENT_URL='https://packages.blackfire.io/binaries/blackfire/2.10.0/blackfire-linux_arm64.tar.gz'; fi \
    && curl -L ${CLIENT_URL} | tar zxp -C /tmp/blackfire \
    && mv /tmp/blackfire/blackfire /usr/bin/blackfire \
    && rm -rf /tmp/blackfire

COPY blackfire/etc/php.d/*.ini /etc/php.d/

USER www-data
