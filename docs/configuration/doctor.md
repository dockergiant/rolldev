# Diagnosing an Environment

`roll env doctor`, also available as `roll doctor`, checks whether the current project environment is fit to run. It prints one line per check, so a broken service shows up before a build or import runs into it.

```bash
roll env doctor
roll env doctor --format json
```

## Checks

- **`env-config`**: `.env.roll` for this project loads.
- **`docker`**: the Docker daemon is reachable. Use `roll doctor` for this check; `roll env doctor` stops earlier when Docker is down.
- **`container:<service>`**: every project container is running, and its healthcheck reports healthy. A container without a healthcheck, for example one created before the healthchecks existed, counts as running. Run `roll env up` once to recreate it with a healthcheck.
- **`port-80`, `port-443`, `port-53`**: the ports of the global Traefik and dnsmasq containers are bound by those containers, or free for them.
- **`port-browsersync`**: with `ROLL_BROWSERSYNC=1` and published ports, php-fpm is running.
- **`search-engine:<engine>`**: OpenSearch or Elasticsearch answers `/_cluster/health` through Traefik with a status other than red.
- **`search-engine-write:<engine>`**: the search engine accepts a throwaway index, which doctor deletes again. This catches a green cluster that refuses writes after hitting a disk watermark.
- **`disk`**: the Docker data root has at least 5GB free. Doctor checks this from inside a running project container, which works for Docker on Linux as well as Docker Desktop and OrbStack.

## Exit Status and JSON Output

Doctor exits `0` when every check passes and `1` when any check fails, so a build pipeline can gate on it.

`--format json` prints one JSON object without ANSI escapes or credentials:

```json
{
  "checks": [
    {"check": "docker", "ok": true, "detail": "Docker daemon is reachable."}
  ],
  "ok": true
}
```

## Skipping Services

A build host without Traefik cannot reach the search engine through its domain. Skip those checks by service name:

```bash
roll env doctor --ignore-services=opensearch
```

Skipped checks are still listed, as `SKIP` in the report and `"ok": null` in JSON, and never fail the run. A name that matches nothing in the environment is allowed, so one invocation works across projects.
