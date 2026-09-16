# RollDev 0.7.1 Release Notes

## Read Before Upgrading

- **Linux and WSL projects started with 0.7.0 can have a `.roll` directory owned by root.** Run this once in each such project so `roll backup` can write there again:

  ```bash
  sudo chown -R "$(id -u):$(id -g)" .roll
  ```

## Fixes

- On Linux and WSL, the first `roll env up` of a project created `.roll` and `.roll/backups` owned by root, so `roll backup` failed with `Permission denied` and you could not add project commands in `.roll/commands`. On every platform, `magento2-init` and `mageos-init` printed `chmod: changing permissions of '/var/www/html/.roll': Operation not permitted`. The nginx, php-fpm and magepack containers no longer mount a volume over `.roll/backups`; on macOS, Mutagen still leaves backups out of the sync.
- `roll sign-certificate` and the commands that run it (`magento2-init`, `mageos-init`, `duplicate` and `multistore`) printed `The "ROLL_IMAGE_REPOSITORY" variable is not set. Defaulting to a blank string.` while checking whether Traefik runs.
- RollDev warned about a conflicting `~/.ssh/config`, once for every `roll svc` call, when the file had a `Host tunnel.roll.test` entry whose `## ROLL START ##` marker an SSH config editor had rewritten, for example to `# # ROLL START ##`. The check now looks for the host line itself.
- `magento2-init` and `mageos-init` number their steps 1 to 13. The count jumped from 10 to 12 halfway and used step 11 twice.
