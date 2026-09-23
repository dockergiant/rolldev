# Magento 1 projects

RollDev scaffolds a Magento 1 store in one command. `roll magento1-init` installs OpenMage LTS, the maintained continuation of Magento 1. `roll magento1ce-init` installs the original Magento CE 1.9.4.x, for when you need to reproduce an existing shop.

Both commands create the project directory, the `.env.roll`, an SSL certificate and the containers, then install an empty store with one store view, an admin account and a Redis cache.

## Usage

```bash
roll magento1-init   <project_name> [openmage_version] [target_directory]
roll magento1ce-init <project_name> [ce_version]       [target_directory]
```

```bash
roll magento1-init mystore                 # OpenMage 20.x
roll magento1-init mystore 20.18.0         # a fixed OpenMage release
roll magento1ce-init legacystore           # Magento CE 1.9.4.5
roll magento1ce-init legacystore 1.9.4.3 ~/Sites/
```

RollDev services must be running (`roll svc up`).

## Versions

| | `magento1-init` | `magento1ce-init` |
|---|---|---|
| Installs | OpenMage LTS via Composer (`openmage/magento-lts`) | Magento CE from the `OpenMage/magento-mirror` tag on GitHub |
| Versions | `20.x` (default), `20.18`, `20.18.0` | `1.9.4.0` to `1.9.4.5` (default `1.9.4.5`) |
| PHP | 8.4 | 7.2 |
| MariaDB | 10.11 | 10.3 |
| Redis | 7.2 | 5.0 |
| Composer | 2 | 1 |
| Node.js | off | off |

OpenMage releases before 20.13.0 do not allow PHP 8.4, and Composer stops on them. The PHP 7.2 images for Magento CE still work but no longer receive rebuilds.

## After installation

- Frontend: `https://app.<project_name>.test/`
- Admin: `https://app.<project_name>.test/shopmanager/`
- Admin username and password: `admin-credentials.txt` in the project root
- The cache runs on Redis database 0 (`app/etc/local.xml`). OpenMage keeps sessions in Redis database 2 through its `Cm_RedisSession` module; Magento CE keeps them in the database
- `roll magerun` runs n98-magerun 2.3.0 in the php-fpm container. Upstream archived n98-magerun and its 3.0.1 phar does not start; the image hides the PHP 8 deprecation notices of 2.3.0, which Magento would otherwise turn into exceptions in developer mode. For 3.0.1 in an OpenMage project, run `roll composer require --dev n98/magerun:3.0.1` and use `roll cli vendor/bin/n98-magerun`

Remove the environment with `roll env down -v`.

## Admin auto-login

Like Magento 2 projects, a Magento 1 project can sign you in on the admin login page automatically:

```bash
roll setup-autologin        # creates the admin user localadmin / admin123
```

Then set `ROLL_ADMIN_AUTOLOGIN=1` in `.env.roll` and run `roll env up`. nginx adds a script to each page; on the admin login page it signs in as `localadmin`. If that fails, the script stops after one attempt and shows why on the login page. Set `ROLL_ADMIN_AUTOLOGIN=0` and run `roll env up` to turn it off.

`roll setup-autologin` expects the tables without a prefix (`admin_user`).

## Mage One

Magento CE 1.9.4.x stops at PHP 7.2. [Mage One](https://mage-one.com/) sells patches that make it run on PHP 7.4 and PHP 8. RollDev cannot fetch them: you download them from the Mage One dashboard with your subscription. Apply them to a project created with `roll magento1ce-init`, then raise `PHP_VERSION` in `.env.roll` and run `roll env up`.
