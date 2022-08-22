#!/bin/bash

docker build --no-cache --build-arg PHP_VERSION=7.4 -t rollupdev/php-fpm:7.4 -f Dockerfile context


docker build --no-cache --build-arg PHP_VERSION=7.4 --build-arg ENV_SOURCE_IMAGE=docker.io/rollupdev/php-fpm -t rollupdev/php-fpm:7.4-debug -f debug/Dockerfile context
docker build --no-cache --build-arg PHP_VERSION=7.4 --build-arg ENV_SOURCE_IMAGE=docker.io/rollupdev/php-fpm -t rollupdev/php-fpm:7.4-xdebug3 -f xdebug3/Dockerfile context


docker build --no-cache --build-arg PHP_VERSION=7.4 --build-arg ENV_SOURCE_IMAGE=docker.io/rollupdev/php-fpm -t rollupdev/php-fpm:7.4-magento2 -f magento2/Dockerfile context

docker build --no-cache --build-arg PHP_VERSION=7.4 --build-arg ENV_SOURCE_IMAGE=docker.io/rollupdev/php-fpm -t rollupdev/php-fpm:7.4-magento2-debug -f magento2/debug/Dockerfile context
docker build --no-cache --build-arg PHP_VERSION=7.4 --build-arg ENV_SOURCE_IMAGE=docker.io/rollupdev/php-fpm -t rollupdev/php-fpm:7.4-magento2-xdebug3 -f magento2/xdebug3/Dockerfile context
