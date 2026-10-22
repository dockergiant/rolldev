# Accepted risks and troubleshooting

## Accepted risks

Inspector holds the Docker socket and runs on a development machine. These risks are accepted:

* **No login.** Anything that reaches `https://inspector.<TRAEFIK_DOMAIN>` through Traefik can use Inspector, including the write actions. That covers processes on your host and code in any container, because php-fpm reaches Traefik through `extra_hosts`.
* **Gate against direct calls.** Traefik adds a secret header and Inspector accepts it only from Traefik's address on the env network. A container cannot call `inspector:8080` directly. This does not stop callers that go through Traefik.
* **`/api/v1` is open to every origin.** Any website open in the same browser can read your traces and cache. The routes are read-only.
* **Cross-site links open UI pages.** The links in the userscript and the DevTools panel open the UI as a top-level navigation. Inspector lets these through for GET and HEAD navigations outside `/api`. It refuses cross-site POSTs, script loads of UI files and navigations to `/api` paths. A foreign page can therefore send you to an Inspector screen, though it cannot read it.
* **Writes on `/api`** need the exact Inspector origin, a JSON content type and a CSRF header, and they refuse foreign origins.
* **LAN.** When Traefik listens beyond loopback (`TRAEFIK_LISTEN=0.0.0.0`), Inspector refuses every write and serves reads only.
* **Production data.** The raw `varnishlog` view, `MONITOR` arguments and trace SQL show cookies and data from production dumps. They stay on your machine.

## Troubleshooting

### 403 from the gate

Inspector answers 403 when a request skips Traefik, such as a container calling `http://inspector:8080`, or when it carries the wrong gate header. Use `https://inspector.<TRAEFIK_DOMAIN>`. A 503 reading "Traefik is not connected to <env>_default" means Traefik has not joined the env network. Run `roll svc up`.

### The image predates tracing

`roll inspector trace on` fails with "This php-fpm image predates tracing". `roll inspector status` shows the same under "Image supports tracing". Run:

```
roll env pull && roll env up
```

### New Relic conflict

Tracing and `ROLL_NEWRELIC=1` cannot run together. Roll errors out when both are set, and `roll inspector trace on` refuses. Set `ROLL_NEWRELIC=0` first.

### No traces appear

* Check `roll inspector status`: `ROLL_INSPECTOR_TRACE` must be `1`, or run `roll inspector trace on`.
* Varnish HITs never reach PHP and have no trace. Run `roll magento cache:clean full_page` and reload.
* The 256 MB store drops the oldest traces first. At one page per second it holds about 4 minutes. On the Performance page, the Traced requests card counts the benchmark requests the store left out on purpose, and the Dropped card names why the last payload was refused. `/api/v1/performance` also counts the dropped traces for Inspector's own host, which Traefik routes to nginx while Inspector restarts.

### The UI looks stale after an update

After `roll env pull && roll env up` your browser may still run the old UI. Reload the page. Hard-reload if that does not help.

### Mutagen sync for generated files

Slow syncing of generated files such as `generated/` or `var/` through Mutagen is a separate matter. Inspector neither causes nor fixes it, and tracing does not touch it.
