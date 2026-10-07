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
    $service = 'FreePBX\\modules\\Pendingchanges\\Service\\PendingChangesService';
    $coverage = $service::coverageRegression([
        [
            'reason' => 'table_visibility_regressed',
            'tables' => ['endpoint_extensions', 'incoming'],
        ],
        [
            'reason' => 'optional_table_visibility_unknown',
            'tables' => ['optional_module_table'],
        ],
        [
            'reason' => 'table_visibility_regressed',
            'tables' => ['incoming'],
        ],
    ]);
    if (!$coverage['regressed'] || $coverage['tables'] !== ['endpoint_extensions', 'incoming']) {
        throw new \RuntimeException('Coverage regression classification failed');
    }
    $coverage = $service::coverageRegression([
        ['reason' => 'optional_table_visibility_unknown', 'tables' => ['optional_module_table']],
    ]);
    if ($coverage['regressed'] || $coverage['tables'] !== []) {
        throw new \RuntimeException('Optional table visibility was misclassified as a regression');
    }
    $doctorStatus = [
        'data_current' => true,
        'baseline_provenance' => ['state' => 'trusted'],
        'coverage_regressed' => false,
    ];
    if ($service::doctorExitCode($doctorStatus, true, false) !== 0) {
        throw new \RuntimeException('Authoritative doctor status did not exit cleanly');
    }
    $doctorStatus['coverage_regressed'] = true;
    if ($service::doctorExitCode($doctorStatus, true, false) !== 2) {
        throw new \RuntimeException('Coverage regression did not fail doctor closed');
    }
    echo "watcher health classification checks passed\n";
}
