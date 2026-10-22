# Change Log

See the full change log in GitHub: [https://github.com/dockergiant/rolldev/releases](https://github.com/dockergiant/rolldev/releases)

## 0.8.0

* Roll Inspector: `ROLL_INSPECTOR=1` adds a per-environment UI at `https://inspector.<domain>`. New keys `ROLL_INSPECTOR_TRACE`, `ROLL_INSPECTOR_TRACE_DEBUG`, `ROLL_INSPECTOR_PROFILE`, `ROLL_INSPECTOR_TRACE_DETAIL`, `ROLL_INSPECTOR_SAMPLE` and `ROLL_INSPECTOR_VERSION`, and a `roll inspector` command. The UI opens on an Overview with a request timeline and a cost strip. It has Health dashboards for Varnish, Valkey, OpenSearch and RabbitMQ, PHP traces with hotspots, a waterfall and a flame graph, and a Performance page that measures tracing overhead and switches tracing, profiling and sampling. A read-only `/api/v1`, a userscript badge and a DevTools extension expose the same data, and the rolldev MCP server gained Inspector tools. Inspector is off by default, and tracing needs the rebuilt php-fpm images. See [Roll Inspector](inspector.md).
* `magento2-init` sets up Magento 2.4.8 and 2.4.9 sessions with the `redis` handler against Valkey. It passed `--session-save=valkey`, a handler Magento does not register.
* `roll env describe` links RedisInsight at `https://redisinsight.<domain>`, the address Traefik routes.
* The Varnish container runs with `init: true`, so processes started with `docker exec` no longer stay behind as zombies.
* The nginx image re-resolves `php-fpm` every 10 seconds, so a recreated php-fpm container no longer gives 502 errors. Pull the rebuilt nginx image to get it.
