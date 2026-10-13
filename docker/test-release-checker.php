<?php

use FreePBX\modules\Pendingchanges\Update\ReleaseChecker;

class ReleaseCheckerModuleFixture
{
    public $config = array();

    public function readModuleConfig($key)
    {
        return array_key_exists($key, $this->config) ? $this->config[$key] : null;
    }

    public function writeModuleConfig($key, $value)
    {
        $this->config[$key] = $value;
    }
}

if ($argc !== 2) {
    fwrite(STDERR, "usage: test-release-checker.php extracted-module-directory\n");
    exit(2);
}

require $argv[1] . '/autoload.php';

$moduleXml = file_get_contents($argv[1] . '/module.xml');
if (
    !is_string($moduleXml)
    || preg_match('/<version>\s*([0-9]+\.[0-9]+\.[0-9]+\.([0-9]+))\s*<\/version>/', $moduleXml, $matches) !== 1
) {
    throw new RuntimeException('Fixture module version could not be read');
}
$installedVersion = $matches[1];
$versionParts = explode('.', $installedVersion);
$versionParts[3] = (string) ((int) $versionParts[3] + 1);
$newerVersion = implode('.', $versionParts);

$installer = <<<'INSTALLER'
#!/usr/bin/env bash
module_version=${WHAT_CHANGED_VERSION:-17.0.2.8}
INSTALLER;

if (ReleaseChecker::parseInstallerVersion($installer) !== '17.0.2.8') {
    throw new RuntimeException('Installer fallback version was not parsed without the shell operator');
}
if (ReleaseChecker::parseInstallerVersion('module_version=-17.0.2.8') !== null) {
    throw new RuntimeException('Malformed installer version was accepted');
}

$module = new ReleaseCheckerModuleFixture();
$fetchCount = 0;
$now = 1800000000;
$remoteVersion = $newerVersion;
$fetcher = function ($url) use (&$fetchCount, &$remoteVersion) {
    ++$fetchCount;
    if ($url !== ReleaseChecker::INSTALLER_URL) {
        throw new RuntimeException('Release checker used an unexpected URL');
    }

    return "module_version=\${WHAT_CHANGED_VERSION:-" . $remoteVersion . "}\n";
};
$clock = function () use (&$now) {
    return $now;
};
$checker = new ReleaseChecker($module, $argv[1], $fetcher, $clock);

$available = $checker->status();
if (
    $available['state'] !== 'update_available'
    || $available['installed_version'] !== $installedVersion
    || $available['available_version'] !== $newerVersion
    || !$available['automatic']
    || $fetchCount !== 1
) {
    throw new RuntimeException('Update-available state was not classified correctly');
}

$cached = $checker->status();
if ($cached['state'] !== 'update_available' || $fetchCount !== 1) {
    throw new RuntimeException('Fresh release result was not served from the cache');
}

$checker->setAutomaticEnabled(false);
$now += ReleaseChecker::SUCCESS_TTL + 1;
$disabled = $checker->status();
if (
    $disabled['state'] !== 'disabled'
    || $disabled['automatic']
    || !$disabled['stale']
    || $fetchCount !== 1
) {
    throw new RuntimeException('Disabled automatic checking performed an outbound request');
}

$remoteVersion = $installedVersion;
$manual = $checker->status(true);
if ($manual['state'] !== 'current' || $manual['automatic'] || $fetchCount !== 2) {
    throw new RuntimeException('Manual update check did not refresh while automatic checks were disabled');
}

$unavailableModule = new ReleaseCheckerModuleFixture();
$badChecker = new ReleaseChecker(
    $unavailableModule,
    $argv[1],
    function () {
        return 'module_version=${WHAT_CHANGED_VERSION:-not-a-version}';
    },
    $clock
);
$unavailable = $badChecker->status();
if ($unavailable['state'] !== 'unavailable' || $unavailable['available_version'] !== null) {
    throw new RuntimeException('Malformed remote installer did not fail closed');
}

echo "release checker tests passed\n";
