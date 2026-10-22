# RollDev 0.8.0 Release Notes

### 🔍 Meet Roll Inspector 🔍

RollDev 0.8.0 brings **Roll Inspector**, one page per environment that shows what a request did in Varnish, nginx, PHP, Valkey or Redis, OpenSearch and RabbitMQ. It also adds **local APM tracing** for PHP, service dashboards and a read-only API for your own scripts. The release fixes Magento 2.4.8 and 2.4.9 sessions in `magento2-init`, the RedisInsight link in `roll env describe`, and zombie processes in the Varnish container.

> [!NOTE]
> Inspector is **off by default**. Nothing changes in your projects until you set `ROLL_INSPECTOR=1`. Read **⚠️ Read Before Upgrading** below for tracing and the accepted risks.

---

## 🧡 NEW: Roll Inspector!!!

Switch it on per project and open it:

```bash
roll config set ROLL_INSPECTOR 1
roll config set ROLL_INSPECTOR_TRACE 1        # PHP tracing, optional
roll env up
roll inspector                                # opens https://inspector.<your domain>
```

![Roll Inspector Overview](https://dockergiant.github.io/rolldev/_images/overview.png)

Inspector installs nothing in your services. It runs as one extra container in your environment, reads Varnish, Valkey or Redis, OpenSearch and RabbitMQ through the Docker socket and their own protocols, and joins everything into one row per request. Varnish puts its request id in the `X-Varnish` header and the PHP tracer stores it, so the Varnish log line and the PHP trace of a request match exactly.

| Key | Default | What it does |
|---|---|---|
| `ROLL_INSPECTOR` | `0` | `1` adds the `inspector` service |
| `ROLL_INSPECTOR_TRACE` | `0` | `1` loads the PHP tracer in `php-fpm` |
| `ROLL_INSPECTOR_TRACE_DEBUG` | `0` | `1` also traces `php-debug` |
| `ROLL_INSPECTOR_PROFILE` | `off` | `excimer` adds sampling profiles for the flame graph |
| `ROLL_INSPECTOR_TRACE_DETAIL` | `full` | `lean` drops the Magento block, event and plugin spans |
| `ROLL_INSPECTOR_SAMPLE` | `10` | Seconds between dashboard samples: `10`, `30`, `60` or `off` |
| `ROLL_INSPECTOR_VERSION` | `latest` | Image tag of `inspector` |

📖 [Roll Inspector docs](https://dockergiant.github.io/rolldev/inspector.html)

---

## ✨ Highlights

### 🐢 Find the slow part of a page in three clicks

PHP traces open on **Hotspots**: routes ranked by p95, the most expensive operations across all traces (SQL, cache calls, plugins, blocks) and repeated N+1 calls. Pick a route, open its slowest request, and the **Bottlenecks** tab ranks the hot spans by their own time with their share of the request. "Show in waterfall" jumps to the span, and the flame graph shows the PHP stack from the profile.

![Bottlenecks of a category page](https://dockergiant.github.io/rolldev/_images/trace-bottlenecks.png)

📖 [Finding a bottleneck](https://dockergiant.github.io/rolldev/inspector/bottlenecks.html)

### 🛰️ Local APM, no account needed

Tracing runs on dd-trace-php 1.26.0, Datadog's open-source PHP tracer. Inspector takes the Datadog agent's place on port 8126, so you need no Datadog account and your traces never leave your machine. The tracer covers Magento controllers, blocks, templates, events, plugins and observers, plus PDO, phpredis and curl. Profiles come from Excimer, Wikimedia's sampling profiler, every 5 ms.

Tracing and profiling pass their checks on **PHP 7.4, 8.0, 8.1, 8.2, 8.3, 8.4 and 8.5**, in `php-fpm` and in `php-debug` next to Xdebug.

📖 [How it works](https://dockergiant.github.io/rolldev/inspector/how-it-works.html)

### 📊 Dashboards per service

Varnish gets a "% served from cache" donut, hits, misses and passes over time, storage and the pages that miss most. Valkey or Redis, OpenSearch and RabbitMQ get their own charts over the last 5, 15 or 60 minutes. Each service also has Browse (bans, cache keys and their decoded values, indices, queues), Live streams and Actions such as a purge by tag, which always ask for confirmation first.

![Varnish dashboard](https://dockergiant.github.io/rolldev/_images/varnish-dashboard.png)

📖 [Service dashboards](https://dockergiant.github.io/rolldev/inspector/services.html)

### ⚡ See what Inspector costs, and switch it off

The Performance page shows the payload per request, the intake per minute, the `exec` calls into your containers and the live streams, each with a Stop button. Switch tracing, trace detail, profiling and the sample interval from there. Its benchmark times one URL with tracing off, lean, full and full with profiling, then puts your settings back.

📖 [Performance](https://dockergiant.github.io/rolldev/inspector/performance.html)

### 🔌 Use it from your browser, your scripts and Claude

- **`/api/v1`** serves the same data as JSON to any origin, described at `/api/v1/openapi.json`. `/api/v1/page?url=` tells you whether Varnish served a URL as HIT, MISS or PASS, why, and which spans cost the most.
- **A userscript** for Tampermonkey or Violentmonkey puts a badge on every shop page, such as `MISS · 1.36 s · 160 SQL · N+1 ×3`. Install it from `/userscript/roll-inspector.user.js`.
- **A DevTools extension** for Chrome and Edge adds a Roll Inspector tab that joins the page's requests to their traces through `X-Varnish`. Download it from `/extension/roll-inspector.zip` and load it unpacked.
- **rolldev-mcp-server 1.2.0** adds six read-only tools: `rolldev_inspector_overview`, `_traces`, `_trace`, `_hotspots`, `_request` and `_service`. Ask Claude "Why is /category-1.html slow?" and it reads the trace for you.

📖 [API and browser integrations](https://dockergiant.github.io/rolldev/inspector/api-and-extensions.html)

---

## ⚠️ Read Before Upgrading

- **Inspector is off by default.** Existing projects keep running as before, and `env-init` writes `ROLL_INSPECTOR=0`.
- **Tracing needs the new php-fpm images.** The images repository adds dd-trace-php, Excimer and `roll-inspector-ini` to every php-fpm image. Pull them in each project where you want tracing:

  ```bash
  roll env pull
  roll env up
  ```

  An older php-fpm image ignores `ROLL_INSPECTOR_TRACE=1` without a message. `roll inspector status` shows whether your image supports tracing and profiling.
- **Inspector has no login and mounts the Docker socket.** Run it on your development machine only. With `TRAEFIK_LISTEN=0.0.0.0` it refuses every write action and keeps serving reads. `/api/v1` answers any origin, so a website open in the same browser can read your traces and cache keys.
- **`ROLL_INSPECTOR_TRACE=1` and `ROLL_NEWRELIC=1` cannot run together.** `roll env` stops with an error when you set both.

📖 [Accepted risks and troubleshooting](https://dockergiant.github.io/rolldev/inspector/risks-and-troubleshooting.html)

---

## 🚀 More New Features

- `roll inspector` opens Inspector, `roll inspector status` shows the toggles, the container state and what your php-fpm image supports, and `roll inspector trace on|off` switches tracing in the running php containers until they restart.
- `roll env describe` and `roll config` list Inspector.
- `roll env` and `roll config` reject toggle combinations that cannot work. `ROLL_INSPECTOR_PROFILE=excimer` without tracing gives a warning and leaves profiling off.
- The docs have a Roll Inspector section with screenshots and architecture diagrams.

---

## 🐛 Fixes

### 🪄 Magento

- For Magento 2.4.8 and 2.4.9, `magento2-init` passed `--session-save=valkey` and `--session-save-valkey-*` to `setup:install`, but Magento registers only the `db` and `redis` session handlers. Sessions now use the `redis` handler against the Valkey container, which speaks the Redis protocol. The cache and page cache keep the `valkey` backend.

### 🐳 Environments and Docker

- `roll env describe` linked RedisInsight at `https://insight.<domain>`, while Traefik routes it at `https://redisinsight.<domain>`.
- varnishd ran as PID 1 in the Varnish container and never reaped the tools that `docker exec` starts there, such as `varnishlog` and `timeout`, so finished processes piled up as zombies. The container now runs with `init: true`; `roll env up` recreates it.
- nginx kept the first IP it resolved for `php-fpm`, so a recreated php-fpm container with a new IP gave 502 errors until nginx restarted. The nginx image now resolves again every 10 seconds. Run `roll env pull nginx` and `roll env up` to get it.

### 🧱 Images

- Every fresh php-fpm build failed at its first pecl install with `XML Error: Not well-formed` and `No releases available`. pecl.php.net's CDN answers HTTP/1.1 with chunked bodies that PEAR cannot decode, so the images now let PEAR fetch over HTTP/1.0. This also fixes `ADD_PHP_EXT` installs at container start.

<details>
<summary><b>🧰 Internal</b></summary>

- New `ghcr.io/dockergiant/inspector` image: a Go binary with an embedded Alpine.js UI, built for amd64 and arm64. CI builds the UI, runs the Go and UI tests, then builds the image.
- `images/inspector/scripts/php-matrix` checks tracing, profiling, lean mode and the off state per PHP version and per variant against a capture server.
- `roll-inspector-ini on|off` in the php-fpm images renders or removes the tracer ini. The entrypoint calls it from `ROLL_INSPECTOR_TRACE` and keeps FPM starting when an image has no tracer.

</details>

---

**Full Changelog**: https://github.com/dockergiant/rolldev/compare/0.7.1...0.8.0
