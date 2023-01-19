ARG MYSQL_VERSION
FROM mysql:${MYSQL_VERSION}

# MySQL 8.0 require skip-bin-log to avoid workarounds:
COPY etc/mysql/conf.d/skip-bin-log.cnf /etc/mysql/conf.d/
