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
            return [
                'pending' => true,
                'baseline' => true,
                'watcher' => true,
                'message' => 'Configuration drift detected since the applied baseline.',
                'captured_at' => 1700000000,
                'watcher_observed_at' => 1700000030,
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
                ],
                'astdb' => ['added' => [], 'removed' => [], 'updated' => []],
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

    if ($argc !== 2) {
        fwrite(STDERR, "usage: legacy-page-smoke.php extracted-module-directory\n");
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
    foreach (['Pending Changes Tripwire', '7001', 'Legacy test', 'legacy_admin'] as $expected) {
        if (strpos($html, $expected) === false) {
            throw new \RuntimeException('Rendered page omitted: '.$expected);
        }
    }
    echo "legacy page rendering checks passed\n";
}
