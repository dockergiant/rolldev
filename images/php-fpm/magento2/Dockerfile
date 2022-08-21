ARG ENV_SOURCE_IMAGE
ARG PHP_VERSION
FROM ${ENV_SOURCE_IMAGE}:${PHP_VERSION}
USER root

RUN npm install -g grunt-cli gulp yarn

RUN set -eux \
    && mkdir -p /usr/local/bin \
    && curl -s https://files.magerun.net/n98-magerun2.phar > /usr/local/bin/n98-magerun \
    && chmod +x /usr/local/bin/n98-magerun

RUN set -eux \
    && curl -o /etc/bash_completion.d/n98-magerun2.phar.bash \
        https://raw.githubusercontent.com/netz98/n98-magerun2/master/res/autocompletion/bash/n98-magerun2.phar.bash \
    && perl -pi -e 's/^(complete -o default .*)$/$1 n98-magerun/' /etc/bash_completion.d/n98-magerun2.phar.bash

# Create mr alias for n98-magerun
RUN ln -s /usr/local/bin/n98-magerun /usr/local/bin/mr

USER www-data
