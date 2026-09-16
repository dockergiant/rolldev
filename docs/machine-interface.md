# Driving RollDev from a Script

Everything RollDev does also works without a terminal: from a CI job, a deploy script, a build server that rebuilds environments overnight, or an AI assistant. This page lists the parts of the interface meant for that.

Don't parse the human output. It carries ANSI colour and its layout can change between releases. The JSON output below is the stable interface.

## Machine-Readable Output

Four commands accept `--format json`:

```bash
roll status --format json          # every project on the host
roll env describe --format json    # one project, its services and their state
roll registry list --format json   # every available command, with descriptions
roll env doctor --format json      # per-check diagnostics
```

The JSON contains no ANSI escapes and no credentials, and values are escaped, so a path with a quote or a non-ASCII character still parses.

`status` and `describe` share the fields `name`, `type`, `dir`, `url`, `network` and `containers`:

- `status` returns `{"running": true, "projects": [ … ], "services": [ … ]}`. `running` says whether the global RollDev services are up, `projects` holds one object per environment on the host, and `services` lists the global services such as traefik and dnsmasq.
- `describe` returns one project object with a `services` array for that project's containers.

Every service entry has at least `name` and `status`.

```bash
# services of this project that are not running
roll env describe --format json | jq -r '.services[] | select(.status != "running") | .name'

# every environment on the host
roll status --format json | jq -r '.projects[].name'
```

`doctor` returns an overall `ok` and a `checks` array with one entry per check. A check skipped with `--ignore-services` reports `"ok": null`. See [Doctor](configuration/doctor.md).

`registry list` returns `command`, `category`, `description`, `priority` and `source` per command. `priority` is the search tier: project `.roll/commands` (1), `~/.roll/commands` (2), `~/.roll/reclu` (3), built-in (4). The lowest number wins, so a project command replaces a built-in with the same name.

## Feature Detection

Which commands exist depends on the RollDev version, on installed command packs, and on the project's own commands. Check before you call one:

```bash
if roll has-command dpull; then
    roll dpull
fi
```

`has-command` prints nothing and exits `0` or `1`. It resolves through the registry, so it also finds project and add-on commands.

## Waiting for Services

`roll env up` returns once Compose has started the containers, before the services inside are ready. Add `--wait`:

```bash
roll env up --wait
roll db connect -e 'SELECT 1'
```

`--wait` uses the healthchecks for `db`, `redis`, `elasticsearch`, `opensearch` and `rabbitmq`. nginx and varnish have none, because Traefik stops routing to a container whose healthcheck is still starting or failing. The search engines are checked through `/_cluster/health`, because their containers can keep the port open while the cluster inside has died.

Containers created before the healthchecks existed have no health status, so `--wait` cannot wait for them. Recreate the environment once after upgrading: `roll env down && roll env up`.

## Prompts Without a Terminal

A prompt takes its value from a flag, positional argument or environment variable first. Only with a terminal on stdin does it ask. Without one, it fails at once and names the flag to use:

```
ERROR: Cannot prompt for a password: no terminal attached.
ERROR: Supply it non-interactively with --encrypt=<password>.
```

| Prompt | Non-interactive form |
|---|---|
| `roll env-init` name and type | `roll env-init <name> <type>` |
| `roll env-init` overwrite confirmation | `ROLL_ENV_INIT_FORCE=1` |
| `roll backup` encryption password | `--encrypt=<password>` |
| `roll restore` decryption password | `--decrypt=<password>` |
| `roll duplicate` encryption password | `--encrypt=<password>` |
| `roll copyfromcontainer` file picker | `--cachegrind <file>` or `--traces <file>` |

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success. For `doctor`, every check passed. For `has-command`, the command exists. |
| `1` | Failure. For `doctor`, at least one check failed. For `has-command`, no such command. |

`--help` exits `1` as well. That is long-standing behaviour, not a failure.

## Running Many Environments on One Host

- `ROLL_PUBLISH_PORTS=0` stops BrowserSync from publishing host ports that collide between environments.
- `ELASTICSEARCH_JAVA_OPTS` and `OPENSEARCH_JAVA_OPTS` set the search engine heap per project.

See [Unattended Operation](configuration/unattended-operation.md).

## Example

```bash
#!/usr/bin/env bash
set -euo pipefail

roll env up --wait

if ! roll env doctor --format json > doctor.json; then
    jq -r '.checks[] | select(.ok == false) | "\(.check): \(.detail)"' doctor.json >&2
    exit 1
fi

roll env sh php-fpm 'bin/magento setup:upgrade > var/log/upgrade.log'
```

`roll env exec php-fpm bin/magento ... > out.log` writes `out.log` on the host. `roll env sh` runs the command through `sh -c` in the container, so redirects and pipes apply there.
