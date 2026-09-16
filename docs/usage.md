# RollDev Usage

## Common Commands

### Project Initialization

Create a new Magento 2 project (automated setup):

    roll magento2-init myproject 2.4.7

Launch a shell session within the project environment's `php-fpm` container:

    roll shell

For use with alternative shells, see the
[Alternative Shells](configuration/alternative-shells.md) page

Stopping a running environment:

    roll env stop

Starting a stopped environment:

    roll env start

Import a database (if you don't have `pv` installed, use `cat` instead):

    pv /path/to/dump.sql.gz | gunzip -c | roll db import

Monitor database processlist:

    watch -n 3 "roll db connect -A -e 'show processlist'"

Tail environment nginx and php logs:

    roll env logs --tail 0 -f nginx php-fpm php-debug

Tail the varnish activity log:

    roll env exec -T varnish varnishlog

Flush varnish:

     roll env exec -T varnish varnishadm 'ban req.url ~ .' 

Connect to redis:

    roll redis

Flush redis completely:

    roll redis flushall

Run redis continuous stat mode

    roll redis --stat

Remove volumes completely:

    roll env down -v

Start the environment and wait until every service reports healthy:

    roll env up --wait

Run a shell command in a container, with redirects and pipes applied inside the container:

    roll env sh php-fpm 'bin/magento cache:flush > var/log/flush.log'

Check whether the environment is fit to run (see [Diagnosing an Environment](configuration/doctor.md)):

    roll env doctor

## Copying Files

Copy a file or folder from the `php-fpm` container to the host, or back:

    roll copyfromcontainer app/etc/env.php
    roll copytocontainer app/code/Vendor/Module

See [Copying Files Between Host and Container](configuration/copy-container.md) for `--all`, `--cachegrind`, `--traces` and `--realpath`.

## Environment Duplication

Duplicate the current environment to create a new environment with a different name:

    roll duplicate new-environment-name

Create an encrypted duplicate:

    roll duplicate staging-env --encrypt

Preview what would be duplicated without executing:

    roll duplicate test-env --dry-run

For detailed duplication documentation, see the [Environment Duplication](duplicate.md) page.

## Backup and Restore Commands

Create a backup of all enabled services:

    roll backup

Create a backup of specific services:

    roll backup db
    roll backup redis

List available backups:

    roll backup list

Show backup information:

    roll backup info 1672531200

Restore the latest backup:

    roll restore

Restore a specific backup:

    roll restore 1672531200

Preview what would be restored:

    roll restore --dry-run

Restore a full backup, source code included, into a new directory:

    roll restore --include-source backup_envname_1672531200.tar.gz ~/Sites/newenv

For detailed backup and restore documentation, see the [Backup and Restore](backup-restore.md) page.

## Further Information

Run `roll help` and `roll env -h` for more details and useful command information.
