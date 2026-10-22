# RollDev 0.8.0 Release Notes

This release adds Roll Inspector, a page per environment that shows what a request did across Varnish, nginx, PHP, Valkey or Redis, RabbitMQ, the database and the search engine. It also fixes Magento 2.4.8 and 2.4.9 sessions in `magento2-init`, the RedisInsight link in `roll env describe`, and zombie processes in the Varnish container.

## Read Before Upgrading

- **Inspector is off by default.** Existing projects keep running as before, and `env-init` writes `ROLL_INSPECTOR=0`. Set `ROLL_INSPECTOR=1` and run `roll env up` to start it.
- **Tracing needs the new php-fpm images.** The images repository adds dd-trace-php, Excimer and `roll-inspector-ini` to php-fpm. Once its CI has rebuilt and published them, pull them in each project where you want tracing:

  ```bash
  roll env pull
  roll env up
  ```

  An older php-fpm image ignores `ROLL_INSPECTOR_TRACE=1` without a message. `roll inspector status` shows whether your image supports tracing and profiling, and `roll inspector trace on` names the pull when it does not.
- **Inspector has no login and mounts the Docker socket.** Run it on your development machine only. With `TRAEFIK_LISTEN=0.0.0.0` it refuses every write action and serves reads. `/api/v1` answers any origin, so a website open in the same browser can read your traces and cache keys. See [Accepted risks and troubleshooting](https://dockergiant.github.io/rolldev/inspector/risks-and-troubleshooting.html).
- **`ROLL_INSPECTOR_TRACE=1` and `ROLL_NEWRELIC=1` cannot run together.** `roll env` stops with an error when you set both.

## New

- **Roll Inspector.** Set `ROLL_INSPECTOR=1` in `.env.roll`, run `roll env up` and open `https://inspector.<TRAEFIK_DOMAIN>`. Inspector installs nothing in your services. It reads them through the Docker socket and their own protocols, and joins Varnish, nginx, PHP and cache activity into one row per request.
- New `.env.roll` keys:

  | Key | Default | Notes |
  |-----|---------|-------|
  | `ROLL_INSPECTOR` | `0` | `1` adds the `inspector` service |
  | `ROLL_INSPECTOR_TRACE` | `0` | `1` loads the tracer in `php-fpm`. Needs `ROLL_INSPECTOR=1` |
  | `ROLL_INSPECTOR_TRACE_DEBUG` | `0` | `1` also traces `php-debug`. Needs `ROLL_INSPECTOR_TRACE=1` |
  | `ROLL_INSPECTOR_PROFILE` | `off` | `excimer` adds sampling profiles for the flame graph |
  | `ROLL_INSPECTOR_TRACE_DETAIL` | `full` | `lean` drops the Magento block, event and plugin spans |
  | `ROLL_INSPECTOR_SAMPLE` | `10` | Seconds between metrics samples: `10`, `30`, `60` or `off` |
  | `ROLL_INSPECTOR_VERSION` | `latest` | Image tag of `inspector` |

  `roll env` and `roll config` reject combinations that cannot work. `ROLL_INSPECTOR_PROFILE=excimer` without tracing gives a warning and leaves profiling off.
- `roll inspector` opens Inspector in your browser, the same as `roll inspector open`. `roll inspector status` shows the toggles, the container state and what your php-fpm image supports. `roll inspector trace on|off` switches tracing in the running php containers until they restart.
- Tracing runs on dd-trace-php 1.26.0, Datadog's open-source PHP tracer. Inspector takes the Datadog agent's place on port 8126, so you need no Datadog account and your traces stay on your machine. The tracer covers Magento controllers, blocks, templates, events, plugins and observers, plus PDO, phpredis and curl. From those spans Inspector ranks hot spans, finds repeated (N+1) calls and splits each request into SQL, cache, search, HTTP and PHP time. Tracing and profiling pass their checks on PHP 7.4 to 8.5.
- Profiling runs on Excimer, Wikimedia's sampling profiler. It samples traced requests every 5 ms and feeds the flame graph next to the waterfall.
- The Overview has a card per service, the live request list and a cost strip for the request you select. Dashboards for Varnish, Valkey or Redis, OpenSearch and RabbitMQ show health charts over 5, 15 or 60 minutes, let you browse bans, cache keys, indices and queues, stream live events, and run actions such as a Varnish purge behind a confirm dialog.
- The Performance page shows what Inspector costs you: payload per request, intake per minute, `exec` calls into your containers and the live streams with a Stop button. It switches tracing, trace detail, profiling and the sample interval. Its benchmark times one URL with tracing off, lean, full and full with profiling, then puts your settings back.
- `https://inspector.<domain>/api/v1` serves the same data as read-only JSON, described at `/api/v1/openapi.json`. `/api/v1/page?url=` tells you whether Varnish served a URL as HIT, MISS or PASS, why, and which spans cost the most.
- A userscript for Tampermonkey or Violentmonkey puts a badge on each shop page, such as "MISS · 1.36 s · 160 SQL · N+1 ×3". Install it from `/userscript/roll-inspector.user.js`.
- A DevTools extension for Chrome and Edge adds a Roll Inspector tab that joins the page's requests to their traces. Download it from `/extension/roll-inspector.zip`.
- rolldev-mcp-server 1.1.0 adds six read-only tools: `rolldev_inspector_overview`, `rolldev_inspector_traces`, `rolldev_inspector_trace`, `rolldev_inspector_hotspots`, `rolldev_inspector_request` and `rolldev_inspector_service`. Ask Claude "Why is /category-1.html slow?" and it reads the trace for you.
- `roll env describe` and `roll config` list Inspector, and the docs have a Roll Inspector section.

## Fixes

- For Magento 2.4.8 and 2.4.9, `magento2-init` passed `--session-save=valkey` and `--session-save-valkey-*` to `setup:install`, but Magento registers only the `db` and `redis` session handlers. Sessions now use the `redis` handler against the Valkey container, which speaks the Redis protocol. The cache and page cache keep the `valkey` backend.
- `roll env describe` linked RedisInsight at `https://insight.<domain>`, while Traefik routes it at `https://redisinsight.<domain>`. The link now matches the route.
- varnishd ran as PID 1 in the Varnish container and never reaped the tools that `docker exec` starts there, such as `varnishlog` and `timeout`. Finished processes piled up as zombies. The container now runs with `init: true`; `roll env up` recreates it.
- nginx kept the IP of `php-fpm` it resolved first, so a recreated php-fpm container with a new IP gave 502 errors until nginx restarted. The nginx image now resolves again every 10 seconds (`resolver 127.0.0.11 valid=10s`). That fix ships in the nginx image: after the images repository rebuilds it, run `roll env pull nginx` and `roll env up`.

---

**Full Changelog**: https://github.com/dockergiant/rolldev/compare/0.7.1...0.8.0
