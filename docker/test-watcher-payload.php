<?php

use FreePBX\modules\Pendingchanges\Support\PathResolver;
use FreePBX\modules\Pendingchanges\Watcher\PayloadInspector;

if ($argc !== 2) {
    fwrite(STDERR, "usage: test-watcher-payload.php extracted-module-directory\n");
    exit(2);
}

$moduleRoot = rtrim($argv[1], '/');
require $moduleRoot . '/autoload.php';

function assertPayloadState($expected, array $payload)
{
    if ($payload['state'] !== $expected) {
        throw new RuntimeException(
            'Expected payload state ' . $expected . ', received ' . $payload['state']
        );
    }
}

$temporary = sys_get_temp_dir() . '/what-changed-payload-' . uniqid('', true);
$installed = $temporary . '/installed';
if (!mkdir($installed, 0700, true)) {
    throw new RuntimeException('Could not create watcher payload fixture directory');
}

$paths = new PathResolver();
$inspector = new PayloadInspector($paths, $moduleRoot, array(), array($installed));
assertPayloadState('not_installed', $inspector->inspect());
$embedded = trim(file_get_contents($moduleRoot . '/watcher/VERSION'));
assertPayloadState('current', $inspector->inspect($embedded));

file_put_contents($installed . '/watcher.py', "# fixture\n");
$legacy = $inspector->inspect();
assertPayloadState('outdated', $legacy);
if ($legacy['installed_version'] !== null) {
    throw new RuntimeException('Legacy payload unexpectedly reported a version');
}

file_put_contents($installed . '/VERSION', $embedded . "\n");
$current = $inspector->inspect();
assertPayloadState('current', $current);
if (!$current['current'] || $current['embedded_version'] !== $embedded) {
    throw new RuntimeException('Current watcher payload was not accepted');
}
if ($current['update_command'] !== 'sudo ' . $moduleRoot . '/bin/install-watcher') {
    throw new RuntimeException('Watcher payload update command is not exact');
}

file_put_contents($installed . '/VERSION', "0.0.1\n");
assertPayloadState('outdated', $inspector->inspect());
file_put_contents($installed . '/VERSION', "99.0.0\n");
assertPayloadState('newer', $inspector->inspect());

unlink($installed . '/VERSION');
unlink($installed . '/watcher.py');
rmdir($installed);
rmdir($temporary);

echo "watcher payload version checks passed\n";
