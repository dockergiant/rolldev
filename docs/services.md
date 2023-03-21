# Global Services

After running `roll svc up` for the first time following installation, the following URLs can be used to interact with the UIs for services RollDev runs globally:

* [https://traefik.roll.test/](https://traefik.roll.test/)
* [https://portainer.roll.test/](https://portainer.roll.test/) (Only when Portainer is enabled)
* [https://dnsmasq.roll.test/](https://dnsmasq.roll.test/)
* [https://mailhog.roll.test/](https://mailhog.roll.test/)

## Customizable Settings

When spinning up global services via `docker-compose` RollDev uses `~/.roll` as the project directory allowing a `.env` placed at `~/.roll/.env` to function for overriding variables in the `docker-compose` configuration used to deploy these services.

The following options are available (with default values indicated):

* `TRAEFIK_LISTEN=127.0.0.1` may be set to `0.0.0.0` for example to have Traefik accept connections from other devices on the local network.
* `ROLL_RESTART_POLICY=always` may be set to `no` to prevent Docker from restarting these service containers or any other valid [restart policy](https://docs.docker.com/config/containers/start-containers-automatically/#use-a-restart-policy) value.
* `ROLL_SERVICE_DOMAIN=den.test` may be set to a domain of your choosing if so desired. Please note that this will not currently change network settings or alter `dnsmasq` configuration. Any TLD other than `test` will require DNS resolution be manually configured.
* `ROLL_SERVICE_PORTAINER=0` may be set to `1` to also run Portainer when running `roll svc up`

:::{warning}
Setting ``TRAEFIK_LISTEN=0.0.0.0`` can be quite useful in some cases, but be aware that causing Traefik to listen for requests publicly poses a security risk when on public WiFi or networks otherwise outside of your control.
:::

After changing settings in `~/.roll/.env`, please run `roll svc up` to apply.
