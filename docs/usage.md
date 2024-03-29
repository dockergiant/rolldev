# RollDev Usage

## Common Commands

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

Run redis continous stat mode

    roll redis --stat

Remove volumes completely:

    roll env down -v

## Further Information

Run `roll help` and `roll env -h` for more details and useful command information.
