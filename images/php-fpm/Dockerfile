ARG PHP_SOURCE_IMAGE="docker.io/rollupdev/php"
ARG PHP_VERSION
ARG PHP_VARIANT="fpm-loaders"
FROM ${PHP_SOURCE_IMAGE}:${PHP_VERSION}-${PHP_VARIANT}

# Clear undesired settings from base fpm images
ENV COMPOSER_ALLOW_SUPERUSER=
ENV COMPOSER_HOME=

ENV MAILHOG_HOST    mailhog
ENV MAILHOG_PORT    1025

RUN set -eux; \
	apt-get update; \
    apt-get install -y --no-install-recommends pv sudo python3-pip bash-completion rsync socat oathtool \
        wget ack automake autoconf nano vim build-essential; \
    rm -rf /var/lib/apt/lists/*;


RUN set -eux; \
	apt-get update; \
    apt-get install -y --no-install-recommends python2; \
    ln -sf /bin/python2 /bin/python; \
    rm -rf /var/lib/apt/lists/;

ENV NODE_VERSION    10
RUN npm install -g n; \
    n install ${NODE_VERSION}; \
    rm -rf /usr/local/n/versions/node;

COPY docker-entrypoint /usr/local/bin/
COPY etc/profile.d/*.sh /etc/profile.d/
COPY etc/*.ini /etc/
COPY etc/php.d/*.ini /etc/php.d/
COPY etc/php.d/05-additions.ini.template /etc/php.d/

# Install mhsendmail to support routing email through mailhog
RUN mkdir -p /tmp/mhsendmail; \
    cd /tmp/mhsendmail; \
    curl -vLOs https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64; \
    chmod +x mhsendmail_linux_amd64; \
    mv mhsendmail_linux_amd64 /usr/local/bin/mhsendmail;

# Install awscli to support data backfill workflows using S3 storage; segno for QR code generation
RUN pip3 install awscli segno --no-cache-dir

# Configure www-data user as primary php-fpm user for better local dev experience
RUN chmod 0755 ~www-data; \
    mkdir -p /var/www/html; \
    chown -R www-data:www-data /var/www/html; \
    echo "www-data ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/nopasswd; \
    PHP_FPM_USER=$(grep -i '^user = ' /usr/local/etc/php-fpm.d/www.conf | awk '{print $3}'); \
    PHP_FPM_GROUP=$(grep -i '^group = ' /usr/local/etc/php-fpm.d/www.conf | awk '{print $3}'); \
    find /var/log /usr/local/lib/php | xargs chown -R www-data:www-data; \
    perl -pi -e 's/^(user|group) = php-fpm$/$1 = www-data/g' /usr/local/etc/php-fpm.d/www.conf;

WORKDIR /var/www/html
USER www-data
