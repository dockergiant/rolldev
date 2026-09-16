# Unattended Operation

These settings matter on a build server that runs many environments side by side. A single project on a developer machine rarely needs them.

## Suppressing Published Host Ports

With [BrowserSync](livereload.md) enabled (`ROLL_BROWSERSYNC=1`), RollDev publishes its web and UI ports on the host. Two environments with BrowserSync on the same host then claim the same port, Compose reports `Bind for 0.0.0.0:<port> failed: port is already allocated`, and `php-fpm` does not start.

Set `ROLL_PUBLISH_PORTS=0` in `.env.roll` to skip the host port mapping:

```
ROLL_PUBLISH_PORTS=0
```

The default is `1`. With `0`, `BROWSERSYNC_PORT_WEB` and `BROWSERSYNC_PORT_UI` still reach the `php-fpm` container, so BrowserSync keeps working for anything on the container network, such as Traefik.

## Search Engine Heap Size

Elasticsearch starts with a JVM heap of `-Xms64m -Xmx512m`, OpenSearch with the default of its image (1g). A large catalog can need more: the container is killed halfway through indexing, and the application only shows a connection error.

Override it per project in `.env.roll`:

```
ELASTICSEARCH_JAVA_OPTS=-Xms256m -Xmx2g
OPENSEARCH_JAVA_OPTS=-Xms256m -Xmx2g
```

Each setting applies to its own engine, so set the one for the engine the project has enabled.

## Waiting for Services

`roll env up --wait` blocks until every service with a healthcheck reports healthy. Use it before a step that needs a ready service, such as a database import right after starting the environment. `roll env doctor --format json` reports the state of the environment in a form a script can check; see [Doctor](doctor.md).
