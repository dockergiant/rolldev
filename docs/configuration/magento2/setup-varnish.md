# Setup Varnish Cache in Magento 2

To set up Varnish with the RollDev dev stack, follow these steps:

1. Enable Varnish in your project's .env.roll file located in the project root by adding the following line:
```
ROLL_VARNISH=1
```

2. Specify the Varnish version by adding the following line to the .env.roll file:
```
VARNISH_VERSION=6.0
```

3. Edit the app/etc/env.php file and add the following configuration to enable Varnish caching:
```php
'http_cache_hosts' => [
    [
        'host' => 'varnish',
        'port' => '80'
    ]
]
```
Make sure the host is set to "varnish" and the port is set to "80".

4. Run the following commands either from the command line or set them in the Magento admin configuration at the specified path:
```shell
bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto
bin/magento config:set --lock-env system/full_page_cache/caching_application 2
bin/magento config:set --lock-env system/full_page_cache/ttl 604800
```

5. Finally, flush the cache by running the command:
```shell
bin/magento cache:flush
```

These steps will set up Varnish with the RollDev dev stack for your project.