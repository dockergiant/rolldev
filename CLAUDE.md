# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RollDev** (`roll-docker-stack`) is a Docker-based local development environment framework, written almost entirely in **Bash**. It provides a single `roll` CLI that orchestrates `docker compose` to spin up consistent, per-project containerized stacks for PHP frameworks and CMS platforms (Magento 1/2, Laravel, Symfony, TYPO3, Shopware, WordPress, Akeneo, generic PHP).

- **Current version:** `0.6.2` (see `version` file)
- **Language:** Bash (must stay **Bash 3.2+ compatible** — macOS default shell)
- **Distribution:** Homebrew tap `dockergiant/roll/roll`
- **Container images:** pulled from `ghcr.io/dockergiant/*` (built by the sibling `images/` repo)
- **License:** MIT
- **Docs site:** https://dockergiant.github.io/rolldev

This repo contains the **CLI + orchestration logic + compose definitions**. The actual Docker *images* live in the separate `images/` repository (`/Volumes/Development/RollDev/images`).

## Architecture

```
bin/roll                 # CLI entry point — resolves ROLL_DIR, sources utils, parses args, sources the command
utils/                   # Core shell modules (sourced by bin/roll in order)
  core.sh                #   messaging (success/info/warning/error/fatal), boxinfo, version(), helpers, peered services
  config.sh              #   configuration schema + validation + .env.roll loading + postProcessConfig
  registry.sh            #   command discovery/registry across multiple search paths with priorities
  env.sh                 #   locateEnvPath, env type resolution, docker-compose partial assembly
  install.sh             #   install/bootstrap helpers
commands/                # ~60 modular commands: <name>.cmd (logic) + <name>.help (usage text)
  magento1/  magento2/  wordpress/   # env-type-specific sub-command directories
docker/                  # Global shared services (run once per machine, not per project)
  docker-compose.yml     #   traefik, dnsmasq, mailhog (mailpit), tunnel (sshd)
  portainer-service.yml  #   optional Portainer
  startpage-service.yml  #   optional dashboard
environments/            # Per-env-type docker-compose fragments
  includes/              #   shared service definitions (php-fpm, nginx, db, redis, elasticsearch, ...)
  magento2/ laravel/ ... #   env-type compose + init.env defaults
config/                  # traefik.yml, openssl certificate configs, varnish
docs/                    # Sphinx + myst-parser (Markdown) documentation source
```

### How a command runs

1. `bin/roll` resolves `ROLL_DIR` (following symlinks — important for the Homebrew install), verifies Docker + `docker compose >= 2.2.3`.
2. Sources `utils/core.sh`, `config.sh`, `registry.sh`, `env.sh`.
3. Calls `findCommand "$1"` (in `registry.sh`) which lazily builds the command registry and returns `found:<cmd_path>:<help_path>`.
4. Parses remaining args. Commands in the `ROLL_CMD_ANYARGS` array (`svc env db redis sync shell debug composer magento magerun ...`) pass **all** trailing args/flags straight through to the container; other commands reject unknown flags.
5. `source "${ROLL_CMD_EXEC}"` — the `.cmd` file runs in the CLI's own shell context (it does **not** `exec`), so it has access to all sourced functions and exported config.

### Command registry & discovery (`utils/registry.sh`)

Commands are discovered from multiple directories with **priority (lower = wins)**:

| Priority | Path | Purpose |
|----------|------|---------|
| 1 | `${ROLL_ENV_PATH}/.roll/commands` | project-local custom commands |
| 1 | `${ROLL_HOME_DIR}/commands/${ROLL_ENV_TYPE}` | user env-type overrides (new) |
| 1 | `${ROLL_HOME_DIR}/reclu/${ROLL_ENV_TYPE}` | user env-type overrides (legacy) |
| 2 | `${ROLL_DIR}/commands/${ROLL_ENV_TYPE}` | built-in env-type commands (e.g. `commands/magento2/`) |
| 2 | `${ROLL_HOME_DIR}/commands` | user global commands |
| 3 | `${ROLL_HOME_DIR}/reclu` | legacy user global commands |
| 4 | `${ROLL_DIR}/commands` | built-in global commands |

A command is any `<name>.cmd` file; its sibling `<name>.help` provides usage. Higher-priority directories override lower ones, so users/projects can shadow built-ins.

### Compose assembly (`utils/env.sh` + `commands/env.cmd`)

`roll env <args>` is the core orchestrator. It builds a list of `-f <file>` args by calling `appendEnvPartialIfExists <name>` for each enabled service, then runs one `docker compose` invocation. `appendEnvPartialIfExists` looks for fragments in this order (each found file is layered on top):

```
environments/includes/<name>.base.yml
environments/includes/<name>.<SUBT>.yml          # SUBT = darwin | linux | wsl
environments/<ENV_TYPE>/<name>.base.yml
environments/<ENV_TYPE>/<name>.<SUBT>.yml
${ROLL_HOME_DIR}/environments/...                # user overrides, same shape
```

Which partials get appended is driven by the `ROLL_*` service toggles (see config schema). The final compose call is:

```bash
docker compose --env-file <proj>/.env.roll --project-directory <proj> -p <ROLL_ENV_NAME> \
    -f <partial> -f <partial> ... <up|down|...>
```

**Global "peered" services** (`traefik`, `tunnel`, `mailhog` — see `DOCKER_PEERED_SERVICES` in `core.sh`) are connected to / disconnected from each project's `<name>_default` network on `env up` / `env down`. All projects share the `roll` Docker network for the global services.

## Configuration System (`utils/config.sh`)

Config is loaded from (later overrides earlier):
1. `${ROLL_HOME_DIR}/.env.roll` (global, new style)
2. `${ROLL_HOME_DIR}/.env` (global, legacy)
3. `<project>/.env.roll` (per-project — **required**; located by walking up from `pwd` looking for a file containing `ROLL_ENV_NAME` + `ROLL_ENV_TYPE`)

`initConfigSchema()` defines a typed schema (`boolean:<default>`, `string:<default|required|optional>`). Values are validated on load (`validateConfigValue`), defaults applied, then `postProcessConfig()` derives computed values (PHP image variant, Node variant, nginx template selection, xdebug version, WSL/Linux SSH handling, env-type service defaults).

`ROLL_HOME_DIR` defaults to `$HOME/.roll`. SSL lives at `${ROLL_HOME_DIR}/ssl`, composer cache at `${ROLL_COMPOSER_DIR:-$HOME/.composer}`.

### Key config schema (selected — full list in `config.sh:initConfigSchema`)

| Key | Type / default | Notes |
|-----|----------------|-------|
| `ROLL_ENV_NAME` | string, **required** | project name → docker compose project + network prefix |
| `ROLL_ENV_TYPE` | string, **required** | one of the `environments/` dirs (magento2, laravel, ...) |
| `ROLL_ENV_SUBT` | string | auto-set: `darwin` / `linux` / `wsl` |
| `PHP_VERSION` | `8.1` | |
| `PHP_XDEBUG_3` | `1` | selects `xdebug3` vs legacy `debug` image |
| `PHP_MEMORY_LIMIT` | `2G` | |
| `COMPOSER_VERSION` | optional | `1` / `2` / `2lts` |
| `NODE_VERSION` | `18` | `0` disables the node variant |
| `DB_DISTRIBUTION` | `mariadb` | `mariadb` or `mysql` |
| `DB_DISTRIBUTION_VERSION` | `10.4` | |
| `ROLL_NGINX` / `ROLL_DB` / `ROLL_REDIS` | `1` | core service toggles |
| `ROLL_VARNISH` / `ROLL_ELASTICSEARCH` / `ROLL_RABBITMQ` | `0` | default on **only** for magento2 (via `postProcessConfig`) |
| `ROLL_OPENSEARCH` / `ROLL_DRAGONFLY` / `ROLL_MONGODB` | `0` | |
| `ROLL_ELASTICVUE` / `ROLL_REDISINSIGHT` | `0` | GUI helper services |
| `ROLL_SELENIUM` / `ROLL_ALLURE` / `ROLL_TEST_DB` | `0` | testing stack |
| `ROLL_MAGEPACK` / `ROLL_BROWSERSYNC` | `0` | |
| `ROLL_MAGENTO_STATIC_CACHING` | `0` | picks prod vs `-dev` nginx template |
| `ROLL_ADMIN_AUTOLOGIN` | `0` | magento2 auto-login nginx template |
| `ROLL_NEWRELIC` / `NEWRELIC_LICENSE_KEY` | `0` / optional | |
| `ROLL_IMAGE_REPOSITORY` | `ghcr.io/dockergiant` | image registry base |
| `ROLL_RESTART_POLICY` | `always` | |
| `TRAEFIK_DOMAIN` / `TRAEFIK_SUBDOMAIN` / `TRAEFIK_LISTEN` | / / `127.0.0.1` | routing |

**Conflict rules:** `ROLL_REDIS` and `ROLL_DRAGONFLY` cannot both be `1` (fatal in `env.cmd` / `checkConfigConflicts`).

## Common Commands

```bash
# Global services (run once per machine)
roll svc up | down | restart | status

# Project lifecycle (run inside a project dir with .env.roll)
roll env-init <name> <type>        # scaffold .env.roll for an env type
roll env up | down | start | stop | restart | ps | logs   # passes through to docker compose
roll restart                       # restart project
roll status                        # project status
roll sign-certificate <domain>     # issue trusted SSL cert via local CA

# Shells into the php-fpm container
roll shell                         # interactive bash (www-data)
roll debug                         # shell with Xdebug enabled (php-debug)
roll root / rootshell / rootnotty  # root variants
roll cli / clinotty / cliq         # run single commands in container

# PHP / Magento / Node tooling (proxied into the container)
roll composer <args>
roll magento <args>                # bin/magento (magento2)
roll magerun <args>                # n98-magerun2
roll node <args> / roll npm <args>
roll add-php-ext <ext>             # install extra PHP extension at runtime

# Magento 2 project creation
roll magento2-init <name> [version]

# Database & backups
roll db [connect|import|...]
roll redis
roll backup [db|media]
roll restore [db|media] / roll restore-full
roll tableplus / roll tablePlus    # open DB GUI
roll duplicate                     # clone an environment
roll multistore                    # magento multistore helpers

# Introspection
roll config                        # show resolved config
roll registry                      # show command registry / search paths
roll describe                      # describe the assembled compose stack
roll version
```

`roll env-init` writes a `.env.roll` seeded from `environments/<type>/init.env`. Env-type-specific commands live under `commands/<type>/` (e.g. `commands/magento2/cache.cmd`, `setup-autologin.cmd`, `fixperms.cmd`, `fixowns.cmd`, `magepack.cmd`, `grunt.cmd`).

## Environments

Valid env types are auto-discovered from any `environments/*/<type>.base.yml`:

`akeneo`, `laravel`, `local`, `magento1`, `magento2`, `php`, `shopware`, `symfony`, `typo3`, `vuejs`, `wordpress`.

Shared service fragments in `environments/includes/`:
`php-fpm` (+ `.darwin`/`.linux`), `nginx` (+ `.darwin`), `db`, `redis`, `redisinsight`, `dragonfly`, `elasticsearch`, `elasticvue`, `opensearch`, `rabbitmq`, `mongodb`, `varnish`, `selenium`, `allure`, `browsersync`, `git`, `networks`.

Each env-type dir provides `<type>.base.yml`, an `init.env` (default toggles), optional `.darwin.yml`/`.linux.yml` platform overrides, and (magento2) `.mutagen.yml`, `.magepack.*.yml`, `.tests.base.yml`.

**macOS file sync:** on darwin, `env.cmd` uses **Mutagen** (`<type>.mutagen.yml` or `.roll/mutagen.yml`) and auto pauses/resumes/starts sync around `env up|down|start|stop`.

## Global Services (`docker/docker-compose.yml`)

| Service | Image | Role |
|---------|-------|------|
| `traefik` | `traefik` | reverse proxy / TLS termination, `*.test` routing, dashboard at `traefik.${ROLL_SERVICE_DOMAIN:-roll.test}` |
| `dnsmasq` | `${ROLL_IMAGE_REPOSITORY}/dnsmasq` | resolves `*.test → 127.0.0.1`, upstream Cloudflare DNS, managed via webproc UI |
| `mailhog` | `axllent/mailpit` | catch-all SMTP + web UI (MailPit, replaced MailHog) |
| `tunnel` | `panubo/sshd` | SSH TCP-forward tunnel (e.g. host `localhost:2222` → container DB ports) |

All on the shared `roll` network. Routing uses `${ROLL_SERVICE_DOMAIN:-roll.test}`.

## Development Guidelines

**Shell scripts:**
- Must pass **ShellCheck** (CI-enforced via `.github/workflows/shellcheck.yml`).
- Maintain **Bash 3.2+ compatibility** — no associative arrays; the codebase uses *parallel indexed arrays* (see `registry.sh`/`config.sh`). Follow this pattern.
- Use the messaging helpers from `core.sh`: `success`, `info`, `warning`, `error`, `fatal`, `boxinfo`/`boxsuccess`/`boxerror`. Never raw `echo` for status.
- Every `.cmd`/`.sh` (except `bin/roll`) must guard with `[[ ! ${ROLL_DIR} ]] && ... exit 1` at the top — they are meant to be sourced, not run directly.
- Use `sed_inplace` from `core.sh` for cross-platform in-place edits (BSD vs GNU sed).
- Use `version()` from `core.sh` for version comparisons.

**Adding a command:** drop `<name>.cmd` (+ `<name>.help`) in `commands/` (or `commands/<env-type>/` for env-specific). The registry auto-discovers it. Add it to `ROLL_CMD_ANYARGS` in `bin/roll` only if it should pass arbitrary args/flags through to a container.

**Adding a service:** add `environments/includes/<svc>.base.yml` (+ platform overrides), a `ROLL_<SVC>` toggle in `config.sh:initConfigSchema`, and an `appendEnvPartialIfExists "<svc>"` guard in `commands/env.cmd`.

**Cross-platform:** support macOS (`darwin`), Linux (`linux`), and WSL2 (`wsl`). `ROLL_ENV_SUBT` is auto-detected. Platform-specific compose via `<name>.<subt>.yml`.

**Docs:** Sphinx + myst-parser (Markdown). Source in `docs/`. Build with `make html` in `docs/`. CI builds + publishes to GitHub Pages.

## Container Images

Pulled from GitHub Container Registry: `${ROLL_IMAGE_REPOSITORY:-ghcr.io/dockergiant}/<service>`.

PHP image name is composed at runtime: base `php-fpm` + variant `-${ROLL_ENV_TYPE}` (e.g. `-magento2`) + `-node${NODE_VERSION}`, tagged by `PHP_VERSION`. Example: `ghcr.io/dockergiant/php-fpm-magento2:8.1`. Images are built/published by the sibling `images/` repo.

## CI/CD (`.github/workflows/`)

| Workflow | Purpose |
|----------|---------|
| `shellcheck.yml` | Lint all shell scripts (enforced) |
| `build-documentation.yml` | Build Sphinx docs |
| `pages.yml` | Publish docs to GitHub Pages |
| `tag-release.yml` | Semantic version tagging / release |
| `push-release-to-brew.yml` | Update the Homebrew tap on release |

## Related Repos

- **`../images`** — Dockerfiles + CI that build all `ghcr.io/dockergiant/*` images consumed here.
- Homebrew formula / CLI distribution: `dockergiant/homebrew-roll`.
