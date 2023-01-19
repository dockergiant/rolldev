<?php

require_once(__DIR__ . DIRECTORY_SEPARATOR . 'constants.php');

$matrix = [];

foreach (PHP_VERSIONS as $phpVersion) {
    $experimental = in_array($phpVersion, EXPERIMENTAL_PHP_VERSIONS);
    $phpOsRelease = array_key_exists($phpVersion, PHP_VERSIONS_OS_RELEASE) ? PHP_VERSIONS_OS_RELEASE[$phpVersion] : 'bullseye';
    $matrix[] = [
        'php_version' => $phpVersion,
        'php_os_release' => $phpOsRelease,
        'experimental' => $experimental,
        'latest' => $phpVersion === PHP_LATEST,
    ];
}

echo 'matrix=' . json_encode(['include' => $matrix]);