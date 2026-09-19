<?php
namespace FreePBX {
    interface BMO {}
}

namespace {
    class FreePBX_Helpers {}

    class PendingchangesLegacyFixture
    {
        public function status()
        {
            if (isset($GLOBALS['argv'][2]) && $GLOBALS['argv'][2] === 'degraded') {
                return [
                    'pending' => false,
                    'baseline' => true,
                    'watcher' => false,
                    'baseline_provenance' => [
                        'state' => 'degraded',
                        'detail' => 'The external watcher is unavailable.',
                    ],
                    'message' => 'Watcher health is degraded; current full-scope configuration state is unknown.',
                    'captured_at' => 1700000000,
                    'database' => [],
                    'astdb' => [],
                    'generated_files' => [],
                    'module_files' => [],
                    'coverage_limitations' => [],
                    'coverage' => [],
                    'attribution' => [],
                    'watcher_health' => [
                        'state' => 'not_installed',
                        'label' => 'Not Installed',
                        'severity' => 'warning',
                        'detail' => 'The external watcher is not installed; framework-only coverage is reduced.',
                        'sensor_loaded' => false,
                        'observation_age_seconds' => null,
                        'payload' => [
                            'state' => 'not_installed',
                            'label' => 'Not installed',
                            'severity' => 'warning',
                            'detail' => 'No installed watcher payload was found.',
                            'current' => false,
                            'embedded_version' => '0.1.9',
                            'installed_version' => null,
                            'update_command' => 'sudo '
                                . $GLOBALS['argv'][1] . '/bin/install-watcher',
                        ],
                    ],
                    'data_current' => false,
                    'coverage_mode' => 'framework',
                ];
            }
            return [
                'pending' => true,
                'baseline' => true,
                'watcher' => true,
                'baseline_provenance' => ['state' => 'trusted'],
                'message' => 'Configuration drift detected since the applied baseline.',
                'captured_at' => 1700000000,
                'watcher_observed_at' => 1700000030,
                'watcher_health' => [
                    'state' => 'healthy',
                    'label' => 'Healthy',
                    'severity' => 'success',
                    'detail' => 'A completed watcher observation is current.',
                    'sensor_loaded' => true,
                    'observation_age_seconds' => 5,
                    'payload' => [
                        'state' => 'current',
                        'label' => 'Current',
                        'severity' => 'success',
                        'detail' => 'The installed watcher matches the payload bundled with this module.',
                        'current' => true,
                        'embedded_version' => '0.1.9',
                        'installed_version' => '0.1.9',
                        'update_command' => 'sudo '
                            . $GLOBALS['argv'][1] . '/bin/install-watcher',
                    ],
                ],
                'data_current' => true,
                'coverage_mode' => 'watcher',
                'database' => [
                    'users' => [
                        'added' => [],
                        'removed' => [],
                        'updated' => [[
                            'key' => '7001',
                            'identity' => ['extension' => '7001', 'name' => 'Legacy test'],
                            'fields' => ['name' => ['before' => 'Before', 'after' => 'After']],
                        ]],
                    ],
                    'modules' => [
                        'added' => [],
                        'removed' => [],
                        'updated' => [[
                            'key' => '2',
                            'identity' => ['id' => '2', 'modulename' => 'core'],
                            'fields' => ['version' => ['before' => '17.0.32', 'after' => '17.0.33']],
                        ]],
                    ],
                    'freepbx_settings' => [
                        'added' => [],
                        'removed' => [],
                        'updated' => [[
                            'key' => 'hidden',
                            'identity' => ['name' => 'hidden'],
                            'fields' => [
                                'hidden' => ['before' => 1, 'after' => 0],
                                'emptyok' => ['before' => 1, 'after' => 0],
                            ],
                        ]],
                    ],
                ],
                'astdb' => [
                    'added' => [],
                    'removed' => [],
                    'updated' => [[
                        'key' => '/AMPUSER/7001/password',
                        'identity' => ['key' => '/AMPUSER/7001/password'],
                        'fields' => ['value' => ['before' => '[redacted]', 'after' => '[redacted]']],
                    ]],
                ],
                'generated_files' => [],
                'module_files' => [],
                'coverage_limitations' => [],
                'coverage' => ['database_tables' => ['users']],
                'attribution' => [
                    'enabled' => true,
                    'confidence' => 'likely',
                    'actors' => ['legacy_admin'],
                    'request_count' => 1,
                    'requests' => [[
                        'finished_at' => 1700000020,
                        'username' => 'legacy_admin',
                        'display' => 'extensions',
                        'method' => 'POST',
                    ]],
                ],
            ];
        }

        public function seedBaseline()
        {
            return ['tables' => 1, 'files' => 0];
        }
    }

    class FreePBX
    {
        public static function Pendingchanges()
        {
            return new PendingchangesLegacyFixture();
        }
    }

    if ($argc < 2 || $argc > 3) {
        fwrite(STDERR, "usage: legacy-page-smoke.php extracted-module-directory [degraded]\n");
        exit(2);
    }

    define('FREEPBX_IS_AUTH', true);
    $_SERVER['REQUEST_METHOD'] = 'GET';
    require $argv[1].'/Pendingchanges.class.php';
    if (!is_subclass_of('FreePBX\\modules\\Pendingchanges', 'FreePBX_Helpers')) {
        throw new \RuntimeException('Pendingchanges BMO class did not load');
    }

    ob_start();
    require $argv[1].'/page.pendingchanges.php';
    $html = ob_get_clean();
    $expectedText = isset($argv[2]) && $argv[2] === 'degraded'
        ? ['Pending Changes Tripwire', 'Watcher health', 'Not Installed', 'cannot be declared clear', 'install-watcher', 'No drift appears in the available evidence']
        : ['Pending Changes Tripwire', 'Watcher health', 'Healthy', 'Watcher payload', 'Current', 'Current full watcher snapshot', 'Expand all evidence', 'Collapse all evidence', '/AMPUSER/7001/password', '7001', 'Legacy test', 'legacy_admin', 'Module: core', 'Installed version', 'Hidden from menus', 'Empty value allowed', 'Whether FreePBX hides this setting', 'Whether FreePBX accepts an empty value'];
    foreach ($expectedText as $expected) {
        if (strpos($html, $expected) === false) {
            throw new \RuntimeException('Rendered page omitted: '.$expected);
        }
    }
    if (isset($argv[2]) && $argv[2] === 'degraded' && strpos($html, 'No attributable configuration or watched-file drift is currently present.') !== false) {
        throw new \RuntimeException('Degraded watcher page claimed a current clean state');
    }
    echo "legacy page rendering checks passed\n";
}
