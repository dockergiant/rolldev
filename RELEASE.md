# RollDev 0.7.1 Release Notes

## Fixes

- `roll sign-certificate` and the commands that run it (`magento2-init`, `mageos-init`, `duplicate` and `multistore`) printed `The "ROLL_IMAGE_REPOSITORY" variable is not set. Defaulting to a blank string.` while checking whether Traefik runs.
- RollDev warned about a conflicting `~/.ssh/config`, once for every `roll svc` call, when the file had a `Host tunnel.roll.test` entry whose `## ROLL START ##` marker an SSH config editor had rewritten, for example to `# # ROLL START ##`. The check now looks for the host line itself.
