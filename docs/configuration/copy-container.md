# Copying Files Between Host and Container

`roll copyfromcontainer` and `roll copytocontainer` copy files between the project directory on the host and `/var/www/html` in the `php-fpm` container, without going through the sync or bind mount.

## copyfromcontainer

```bash
roll copyfromcontainer vendor/autoload.php
```

Copies the file or folder from the container to the same relative path on the host.

```bash
roll copyfromcontainer --all
```

Copies the entire project source from the container to the host.

```bash
roll copyfromcontainer --cachegrind [file]
roll copyfromcontainer --traces [file]
```

Copies a cachegrind profile or Xdebug trace from `/tmp` in the `php-debug` container into `tmp/profiles` or `tmp/traces` in the project. Without a file name you pick one from a numbered list, which needs a terminal. In a script, pass the file name.

```bash
roll copyfromcontainer --realpath <file>
```

Copies an absolute path from the container into the project `tmp` folder.

## copytocontainer

```bash
roll copytocontainer vendor
```

Copies the file or folder from the host into the container. On Magento 2 projects `roll fixowns` and `roll fixperms` run on that path afterwards.

```bash
roll copytocontainer --all
```

Copies the entire project source from the host into the container. Use it after recreating a container to bring back files that only existed in the old one.
