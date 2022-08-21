ARG PHP_SOURCE_IMAGE="docker.io/rollupdev/php"
ARG PHP_VERSION
ARG PHP_VARIANT="fpm"
FROM ${PHP_SOURCE_IMAGE}:${PHP_VERSION}-${PHP_VARIANT}

# Clear undesired settings from base fpm images
ENV COMPOSER_ALLOW_SUPERUSER=
ENV COMPOSER_HOME=

ENV MAILHOG_HOST    mailhog
ENV MAILHOG_PORT    1025

RUN set -eux; \
    apt-get update -y; \
    PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | awk -F '.' '{print $1$2}'); \
    if [ ${PHP_VERSION} -gt 72 ]; \
            then apt-get install -y --no-install-recommends bind9-utils; \
            else apt-get install -y --no-install-recommends bind9utils; \
    fi; \
    apt-get install -y --no-install-recommends pv sudo python3-pip bash-completion rsync socat oathtool \
        wget ack automake autoconf nano vim cron mariadb-client python2; \
    ln -nsf /usr/bin/python2 /usr/bin/python; \
    rm -rf /var/lib/apt/lists/*

ENV NODE_VERSION    10
RUN npm install -g n; \
    n install ${NODE_VERSION}; \
    rm -rf /usr/local/n/versions/node;

COPY docker-entrypoint /usr/local/bin/
COPY etc/profile.d/*.sh /etc/profile.d/
COPY etc/opcache-config /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini
COPY etc/php.d/*.ini /usr/local/etc/php/conf.d
COPY etc/php.d/05-additions.ini.template /usr/local/etc/php/conf.d

ARG TARGETARCH
# Install mhsendmail to support routing email through mailhog
RUN mkdir -p /tmp/mhsendmail; \
    cd /tmp/mhsendmail; \
    curl -vLOs https://github.com/dockergiant/mhsendmail/releases/download/v0.3.0/mhsendmail_linux_$TARGETARCH; \
    chmod +x mhsendmail_linux_$TARGETARCH; \
    mv mhsendmail_linux_$TARGETARCH /usr/local/bin/mhsendmail;

# Configure www-data user as primary php-fpm user for better local dev experience
RUN mkdir -p /home/www-data \
    && chown www-data:www-data /home/www-data \
    && usermod -d /home/www-data www-data \
    && chmod 0755 ~www-data \
    && mkdir -p /var/www/html \
    && chown www-data:www-data /var/www/html \
    && echo "www-data ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd \
    && PHP_FPM_USER=$(grep -i '^user = ' /usr/local/etc/php-fpm.d/www.conf | awk '{print $3}') \
    && PHP_FPM_GROUP=$(grep -i '^group = ' /usr/local/etc/php-fpm.d/www.conf | awk '{print $3}') \
    && perl -pi -e 's/^(user|group) = php-fpm$/$1 = www-data/g' /usr/local/etc/php-fpm.d/www.conf

WORKDIR /var/www/html
USER www-data
