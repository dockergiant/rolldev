# RollDev 0.7.0 Release Notes

This release adds `roll env doctor`, JSON output for scripts, container healthchecks and a shared backup library, fixes backup and restore across macOS, Linux and WSL, and includes the work merged since 0.6.2.

## Read Before Upgrading

- **Magento 2 service defaults now apply.** A magento2 `.env.roll` that leaves out `ROLL_VARNISH`, `ROLL_ELASTICSEARCH` or `ROLL_RABBITMQ` now gets those services, as the defaults always intended. Schema defaults used to be filled in first, which switched the three off. Projects that set the toggles explicitly, which `env-init` always does, see no change. A project with `ROLL_OPENSEARCH=1` does not get Elasticsearch added.
- **`MARIADB_VERSION` and `MYSQL_VERSION` now set the database image.** Without `DB_DISTRIBUTION_VERSION`, these older keys were ignored and the database ran 10.4. A project with `MARIADB_VERSION=10.3` would now start MariaDB 10.3 on data that 10.4 already upgraded, which MariaDB does not support. Check such projects and set the version they actually run; `DB_DISTRIBUTION_VERSION` still wins when both are set.
- **`MONGODB_VERSION` became `MONGO_VERSION`.** The mongodb service read a key the schema never defined. An existing `MONGODB_VERSION` still works, and the default stays 7. A project that set `MONGO_VERSION` itself ran 7 regardless; it now gets the version it sets, so check that value against the data.
- **For `roll env` commands, `.env.roll` now wins over `~/.roll/.env`.** `env` used to re-read the `ROLL_*` lines of the global file after the project file, so a key set in both files took the global value. Every other command already let the project win.
- **`restore-full` is now `restore --include-source`.** The `restore-full` name keeps working, with the same arguments.
- **`roll restore <word>`:** a numeric argument is the backup ID, as before. Any other word (for example `roll restore db`) is ignored with a warning and the latest backup is restored, which is what older versions did silently; use `--services=db` to restore one service.
- **`status`, `describe`, `registry` and `doctor` take any arguments**, so `--format json` reaches them.
- **Registry categories come from help-file headers** (`## @category:`). `roll registry list "" environment` used to list project and env-type commands; that search path is now the `source` field, and `export csv` has it as a new last column.
- **Containers get healthchecks.** Run `roll env up` once so Compose recreates them with a healthcheck.
- **Homebrew no longer installs `gum`, `dialog`, `pv`, `perl` and `pgrep`.** RollDev does not use them. `brew autoremove` can remove them after the upgrade, so a command of your own in `~/.roll/commands` that calls one of them needs it installed separately, for example `brew install gum dialog pv`.

## New

- `roll env doctor` (also `roll doctor`): checks configuration, Docker, container health, the ports of the global services, search engine health and writes, and disk space. It supports `--format json` and `--ignore-services=<a,b>`, and exits 1 when a check fails.
- `--format json` on `roll status`, `roll env describe` and `roll registry list`.
- `roll has-command <name>`: exits 0 or 1 without output, for scripts.
- `roll env describe`, `roll env doctor` and `roll status` draw their tables through one renderer (`utils/table.sh`) that fits the terminal width and wraps long cells.
- `roll env up --wait`, backed by healthchecks for db, redis/valkey, elasticsearch, opensearch and rabbitmq. nginx and varnish get none on purpose: Traefik stops routing to a container while its healthcheck is starting or failing, which would hide the site right after `env up` and replace a PHP error page with a Traefik 404.
- `roll env sh <service> '<command>'`: runs through `sh -c` in the container, so redirects and pipes apply there.
- `roll backup --output-dir=PATH --archive-name=NAME --keep-dir`: write the archive somewhere else, under a fixed name, and keep the uncompressed directory.
- `ROLL_PUBLISH_PORTS=0`: BrowserSync no longer publishes host ports, so many environments can run on one host.
- `ELASTICSEARCH_JAVA_OPTS` and `OPENSEARCH_JAVA_OPTS`: set the search engine heap per project.
- `roll copyfromcontainer` and `roll copytocontainer` are now built in.
- `ROLL_ENV_INIT_FORCE=1` lets `env-init` overwrite an existing `.env.roll` without asking.
- Help files carry a description and category, shown by `roll registry categories` and `roll registry list --format json`.
- `roll mageos-init` scaffolds Mage-OS 1.1.0 and newer.
- `REDIS_DISTRIBUTION=valkey` runs Valkey as the redis service, and the container is named after the distribution.

## Fixes

- A restored Elasticsearch or OpenSearch volume came back owned by root, so the engine would not start. The volume root now gets the owner of the restored data.
- `roll restore <id>` ignored an ID given before any flag and restored the latest backup.
- `roll restore --dry-run` now leaves the environment running.
- `roll restore` reads legacy `es.tar.gz` and `os.tar.gz` backups and accepts `roll restore all`.
- A backup whose final archive step ran out of disk was reported as successful, and the uncompressed copy was deleted.
- `roll backup` and `roll duplicate` could stop without a message on bash 5 (Linux) at the first progress step.
- OpenSearch ignored its heap setting: it reads `OPENSEARCH_JAVA_OPTS`, not `ES_JAVA_OPTS`. Unset, it keeps the image heap (1g) it has always run with; set `OPENSEARCH_JAVA_OPTS` to change it. It also skips the demo security config, which newer OpenSearch versions refuse to start without an admin password.
- `roll env up` ran an extra `docker compose up --no-start` every time because of a quoting error.
- WSL now loads the `.linux.yml` compose fragments.
- `roll svc up` refreshes images on Linux: the online check used `ping -t`, which means TTL there.
- `roll db` works with MariaDB images that only ship `mariadb` and `mariadb-dump`.
- `roll redis --help` ran `redis-cli --help` in the container.
- `roll status --help` failed to parse on the macOS system bash.
- `roll registry categories` and `stats` failed on bash 3.2.
- `roll --help` printed the usage twice.
- `roll env describe` takes about 1s instead of 9s.
- `roll vnc` finds the selenium container on Compose v2.
- `roll fixowns` and `roll fixperms` accept more than one path.
- `roll env-init` rejects an environment name Compose cannot use, and fails instead of looping when there is no terminal.
- `roll env-init` for `local` and `vuejs` produces a working project.
- Box output no longer fails under cron or without a terminal.
- `roll install` warns on a Linux distribution without a supported CA trust store.
- `magento2-init` renders the 2FA QR code on images that ship the segno Python module, and stops when `composer create-project` fails.
- `roll backup` and `roll restore` work on macOS 13 and older, which ship `shasum` but no `sha256sum`.
- `roll backup --encrypt` and restoring an encrypted backup stop at once when `gpg` is missing and name the package to install. The backup used to run through every volume and fail at the encryption step, and the restore failed halfway.
- `brew install` failed on Linux with the Docker Compose package from Ubuntu, whose version string (`2.40.3+ds1-0ubuntu1~24.04.1`) the formula could not parse, and on macOS with Colima or Rancher Desktop. The formula now finds `docker` on your PATH.

## Security

- `roll tableplus` no longer passes the database password as a process argument.
- Traefik mounts the Docker socket read-only.
- `shell`, `rootshell` and `env` no longer `eval` the contents of `~/.roll/.env`; the config loader already reads and validates it. `roll svc` keeps its own reading of that file, because Docker Compose parses the same file for the global services (inline comments, `${VAR}` expansion).

## Internal

- New shared libraries: `utils/backup.sh` for backup, restore and duplicate, `utils/interact.sh` for prompts (plain bash, no gum), and `utils/table.sh` for tables.
- ShellCheck runs on Ubuntu and macOS with a `.shellcheckrc`, plus a Docker-free smoke suite under bash 3.2 (`.github/scripts/`).
- New `init.env` pins `NGINX_VERSION=1.30` for every environment type.

---

**Full Changelog**: https://github.com/dockergiant/rolldev/compare/0.6.2...0.7.0
