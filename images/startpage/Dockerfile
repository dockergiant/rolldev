FROM node:latest

USER root
RUN apt-get update; apt-get install -y gettext-base
RUN mkdir -p /home/node/app
COPY data/* /home/node/app
# Configure Docker entrypoint
COPY docker-entrypoint /usr/local/bin

ENTRYPOINT ["docker-entrypoint"]
