# Welcome to RollDev's documentation!
==================================

```{include} ../README.md
---
start-line: 1
end-before: <!-- include_open_stop -->
---
```

Under the hood `docker-compose` is used to control everything which RollDev runs (shared services as well as per-project containers) via the Docker Engine.

## Features

* Traefik for SSL termination and routing/proxying requests into the correct containers.
* Dnsmasq to serve DNS responses for `.test` domains eliminating manual editing of `/etc/hosts`
* An SSH tunnel for connecting from Sequel Pro or TablePlus into any one of multiple running database containers.
* RollDev issued wildcard SSL certificates for running https on all local development domains.
* Full support for Magento 1, Magento 2, Laravel, Symfony 4, Shopware 6 on both macOS (Intel and Arm) and Linux.
* Ability to override, extend, or setup completely custom environment definitions on a per-project basis.
* (Optional) Portainer for quick visibility into what's running inside the local Docker host.

```{toctree}
---
maxdepth: 2
caption: Getting Started
---

installing
services
magento2-init
magento2-init-quick-reference
usage
duplicate
backup-restore
backup-restore-quick-reference
registry
environments
configuration
```

```{toctree}
---
maxdepth: 1
caption: About RollDev
---

changelog
images
Github Project <https://github.com/dockergiant/rolldev>
```
