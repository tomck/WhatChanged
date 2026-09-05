<?php
namespace FreePBX {
    interface BMO {}
}

namespace {
    class FreePBX_Helpers {}

    if ($argc !== 2) {
        fwrite(STDERR, "usage: watcher-health-smoke.php extracted-module-directory\n");
        exit(2);
    }

    require $argv[1].'/Pendingchanges.class.php';
    $class = 'FreePBX\\modules\\Pendingchanges';
    $base = ['observed_at' => 1000, 'watcher_health' => ['expected_refresh_seconds' => 30]];
    $healthy = $class::classifyWatcherHealth($base, 1090, true, true);
    $delayed = $class::classifyWatcherHealth($base, 1091, true, false);
    $stale = $class::classifyWatcherHealth($base, 1301, true, false);
    $legacy = $class::classifyWatcherHealth(['observed_at' => 1000], 1090, true, false);
    $invalid = $class::classifyWatcherHealth(['observed_at' => 0], 1000, true, false);

    if ($healthy['state'] !== 'healthy' || !$healthy['sensor_loaded'] || $healthy['observation_age_seconds'] !== 90) {
        throw new \RuntimeException('Healthy watcher classification failed');
    }
    if ($delayed['state'] !== 'delayed' || $delayed['severity'] !== 'warning') {
        throw new \RuntimeException('Delayed watcher classification failed');
    }
    if ($stale['state'] !== 'stale' || $stale['severity'] !== 'danger') {
        throw new \RuntimeException('Stale watcher classification failed');
    }
    if ($legacy['state'] !== 'healthy' || $legacy['expected_refresh_seconds'] !== 30) {
        throw new \RuntimeException('Legacy watcher compatibility failed');
    }
    if ($invalid['state'] !== 'invalid') {
        throw new \RuntimeException('Invalid watcher classification failed');
    }
    echo "watcher health classification checks passed\n";
}
