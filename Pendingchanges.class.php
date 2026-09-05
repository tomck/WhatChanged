<?php
namespace FreePBX\modules;

class Pendingchanges extends \FreePBX_Helpers implements \FreePBX\BMO {
    const BASELINE_TABLE = 'pendingchanges_baseline';
    // Keep the framework-only fallback bounded too. The external watcher is
    // preferred in production, but an unreadable watcher status must never
    // turn this page into an unbounded scan of CDR/CEL/add-on tables.
    const WATCH_TABLES = [
        'announcement', 'callbacks', 'conferences', 'customappsreg', 'devices',
        'did', 'extension_routes', 'extensions', 'fax_details', 'featurecodes', 'globals',
        'iax', 'injected', 'ivr_details', 'ivr_entries', 'miscapps', 'miscdests', 'modules',
        'outbound_route_sequences', 'outbound_routes', 'parkinglot', 'pjsip',
        'queues_config', 'queues_details', 'queues_members', 'ringgroups', 'sip',
        'timeconditions', 'timegroups', 'timegroups_details',
        'trunk_dialpatterns', 'trunks', 'userman_users', 'userman_users_settings', 'users', 'zap',
    ];
    const MAX_TABLE_ROWS = 5000;

    public function doConfigPageInit($page) {}

    public function install() {
        \FreePBX::Database()->exec('CREATE TABLE IF NOT EXISTS '.self::BASELINE_TABLE.' (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            database_snapshot LONGTEXT NOT NULL,
            file_snapshot LONGTEXT NOT NULL,
            captured_at DATETIME NOT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
    }

    public function uninstall() {
        \FreePBX::Database()->exec('DROP TABLE IF EXISTS '.self::BASELINE_TABLE);
    }

    public function getActionBar($request) {
        return [];
    }

    public function needReload() {
        $statement = \FreePBX::Database()->prepare("SELECT value FROM admin WHERE variable = 'need_reload'");
        $statement->execute();
        return $statement->fetchColumn() === 'true';
    }

    public function baseline() {
        $statement = \FreePBX::Database()->query('SELECT database_snapshot, file_snapshot, captured_at FROM '.self::BASELINE_TABLE.' WHERE id = 1');
        $row = $statement->fetch(\PDO::FETCH_ASSOC);
        if (!$row) {
            return null;
        }
        return [
            'database' => json_decode($row['database_snapshot'], true) ?: [],
            'files' => json_decode($row['file_snapshot'], true) ?: [],
            'captured_at' => $row['captured_at'],
        ];
    }

    public function seedBaseline() {
        if ($this->needReload()) {
            throw new \RuntimeException('Cannot seed a baseline while Apply Changes is pending. Apply or clear the pending reload first.');
        }
        $database = $this->databaseSnapshot();
        $files = $this->fileSnapshot();
        $stmt = \FreePBX::Database()->prepare('REPLACE INTO '.self::BASELINE_TABLE.' (id, database_snapshot, file_snapshot, captured_at) VALUES (1, ?, ?, NOW())');
        $stmt->execute([json_encode($database, JSON_UNESCAPED_SLASHES), json_encode($files, JSON_UNESCAPED_SLASHES)]);
        return ['tables' => count($database), 'files' => count($files)];
    }

    public function status() {
        $probe = $this->watcherProbe();
        $watcher = $probe['status'];
        $health = $probe['health'];
        if ($watcher !== null) {
            $files = $watcher['file_drift'];
            $current = $health['state'] === 'healthy';
            $pending = $current ? $watcher['need_reload'] : $this->needReload();
            $message = $watcher['message'];
            if ($health['state'] === 'delayed') {
                $message = 'Watcher observation is delayed; current configuration state may be incomplete.';
            } elseif ($health['state'] === 'stale') {
                $message = 'Watcher results are stale. Current configuration state is unknown.';
            }
            return [
                'pending' => $pending,
                'database' => $watcher['database_drift'],
                'astdb' => isset($watcher['astdb_drift']) ? $watcher['astdb_drift'] : [],
                'files' => $files,
                'generated_files' => $this->fileScope($files, 'generated/'),
                'module_files' => $this->fileScope($files, 'module/'),
                'coverage_limitations' => isset($watcher['coverage_limitations']) ? $watcher['coverage_limitations'] : [],
                'coverage' => isset($watcher['coverage']) ? $watcher['coverage'] : [],
                'attribution' => isset($watcher['attribution']) ? $watcher['attribution'] : [],
                'message' => $message,
                'baseline' => $watcher['baseline_available'],
                'captured_at' => isset($watcher['baseline_captured_at']) ? $watcher['baseline_captured_at'] : null,
                'watcher_observed_at' => $watcher['observed_at'],
                'watcher' => true,
                'watcher_health' => $health,
                'data_current' => $current,
                'coverage_mode' => 'watcher',
            ];
        }
        $baseline = $this->baseline();
        $pending = $this->needReload();
        if (!$baseline) {
            return [
                'pending' => $pending,
                'database' => [],
                'astdb' => [],
                'files' => [],
                'generated_files' => [],
                'module_files' => [],
                'coverage_limitations' => [],
                'coverage' => [],
                'attribution' => $this->unavailableAttribution($pending),
                'baseline' => false,
                'captured_at' => null,
                'message' => 'No applied baseline has been seeded; full watcher coverage is unavailable.',
                'watcher' => false,
                'watcher_health' => $health,
                'data_current' => false,
                'coverage_mode' => 'framework',
            ];
        }
        $database = $this->databaseDiff($baseline['database'], $this->databaseSnapshot());
        $files = $this->fileDiff($baseline['files'], $this->fileSnapshot());
        $hasDrift = !empty($database) || !empty($files);
        if ($hasDrift) {
            $message = $pending
                ? 'Configuration drift detected by the framework-only fallback; watcher coverage is degraded.'
                : 'Framework-only drift detected; watcher coverage is degraded.';
        } else {
            $message = $pending
                ? 'Reload requested; full origin analysis is unavailable because watcher health is degraded.'
                : 'Watcher health is degraded; current full-scope configuration state is unknown.';
        }
        return compact('pending', 'database', 'files', 'message') + [
            'generated_files' => $this->fileScope($files, 'generated/'),
            'module_files' => $this->fileScope($files, 'module/'),
            'coverage_limitations' => [],
            'astdb' => [],
            'coverage' => [
                'database_tables' => self::WATCH_TABLES,
                'database_exclusions' => ['modules.modulename=pendingchanges'],
                'astdb_families' => [],
                'generated_files' => '/etc/asterisk/*.conf',
                'module_tree_digests' => 'all modules except pendingchanges',
            ],
            'attribution' => $this->unavailableAttribution($pending),
            'baseline' => true,
            'captured_at' => $baseline['captured_at'],
            'watcher' => false,
            'watcher_health' => $health,
            'data_current' => false,
            'coverage_mode' => 'framework',
        ];
    }

    public function feedback() {
        $path = '/var/lib/asterisk/pendingchanges-watcher/feedback.jsonl';
        if (!is_readable($path)) {
            return ['schema' => 1, 'events' => [], 'message' => 'No local watcher feedback ledger is available.'];
        }
        $events = [];
        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            $event = json_decode($line, true);
            if (is_array($event) && (isset($event['schema']) ? $event['schema'] : null) === 1) {
                $events[] = $event;
            }
        }
        return [
            'schema' => 1,
            'privacy' => 'Types, counts, field names, coverage-limit reasons, and timestamps only. No configuration values, identifiers, hostnames, credentials, or call data.',
            'events' => $events,
        ];
    }

    private function watcherProbe() {
        $path = '/var/lib/asterisk/pendingchanges-watcher/status.json';
        $installed = $this->watcherInstalled();
        $sensorLoaded = $this->attributionSensorLoaded();
        if (!is_readable($path)) {
            return [
                'status' => null,
                'health' => self::watcherHealthForMissingStatus($installed, $sensorLoaded),
            ];
        }
        $contents = file_get_contents($path);
        if ($contents === false) {
            return [
                'status' => null,
                'health' => self::watcherHealthFailure('unreadable', 'Watcher status exists but could not be read.', $installed, $sensorLoaded),
            ];
        }
        $status = json_decode((string) $contents, true);
        if (!is_array($status) || !isset($status['observed_at'], $status['need_reload'], $status['database_drift'], $status['file_drift'], $status['message'])) {
            return [
                'status' => null,
                'health' => self::watcherHealthFailure('invalid', 'Watcher status is malformed or incomplete.', $installed, $sensorLoaded),
            ];
        }
        return [
            'status' => $status,
            'health' => self::classifyWatcherHealth($status, time(), $installed, $sensorLoaded),
        ];
    }

    public static function classifyWatcherHealth(array $status, $now = null, $installed = true, $sensorLoaded = false) {
        $now = $now === null ? time() : (int) $now;
        $observed = isset($status['observed_at']) && is_numeric($status['observed_at']) ? (int) $status['observed_at'] : 0;
        if ($observed <= 0) {
            return self::watcherHealthFailure('invalid', 'Watcher status has no valid observation time.', $installed, $sensorLoaded);
        }
        $metadata = isset($status['watcher_health']) && is_array($status['watcher_health']) ? $status['watcher_health'] : [];
        $expected = isset($metadata['expected_refresh_seconds']) && is_numeric($metadata['expected_refresh_seconds'])
            ? (int) ceil((float) $metadata['expected_refresh_seconds']) : 30;
        if ($expected < 1 || $expected > 3600) {
            $expected = 30;
        }
        $age = max(0, $now - $observed);
        $healthyDeadline = max(15, $expected * 3);
        $delayedDeadline = max(60, $expected * 10);
        if ($age <= $healthyDeadline) {
            $state = 'healthy';
            $label = 'Healthy';
            $severity = 'success';
            $detail = 'A completed watcher observation is current.';
        } elseif ($age <= $delayedDeadline) {
            $state = 'delayed';
            $label = 'Delayed';
            $severity = 'warning';
            $detail = 'The latest completed watcher observation is later than expected.';
        } else {
            $state = 'stale';
            $label = 'Stale';
            $severity = 'danger';
            $detail = 'The latest watcher observation is too old to describe current configuration state.';
        }
        return [
            'state' => $state,
            'label' => $label,
            'severity' => $severity,
            'detail' => $detail,
            'installed' => (bool) $installed,
            'sensor_loaded' => (bool) $sensorLoaded,
            'observation_age_seconds' => $age,
            'expected_refresh_seconds' => $expected,
            'healthy_deadline_seconds' => $healthyDeadline,
            'stale_deadline_seconds' => $delayedDeadline,
        ];
    }

    private static function watcherHealthForMissingStatus($installed, $sensorLoaded) {
        if ($installed) {
            return self::watcherHealthFailure(
                'installed_unconfigured',
                'The watcher appears installed but has not published a readable observation.',
                true,
                $sensorLoaded
            );
        }
        return self::watcherHealthFailure(
            'not_installed',
            'The external watcher is not installed; framework-only coverage is reduced.',
            false,
            $sensorLoaded,
            'warning'
        );
    }

    private static function watcherHealthFailure($state, $detail, $installed, $sensorLoaded, $severity = 'danger') {
        return [
            'state' => $state,
            'label' => ucwords(str_replace('_', ' ', $state)),
            'severity' => $severity,
            'detail' => $detail,
            'installed' => (bool) $installed,
            'sensor_loaded' => (bool) $sensorLoaded,
            'observation_age_seconds' => null,
            'expected_refresh_seconds' => null,
        ];
    }

    private function watcherInstalled() {
        foreach ([
            '/usr/lib/what-changed-watcher/watcher.py',
            '/usr/local/lib/what-changed-watcher/watcher.py',
            '/etc/systemd/system/what-changed-watcher.service',
            '/lib/systemd/system/what-changed-watcher.service',
            '/usr/lib/systemd/system/what-changed-watcher.service',
            '/etc/what-changed-watcher.env',
        ] as $path) {
            if (file_exists($path)) {
                return true;
            }
        }
        return false;
    }

    private function attributionSensorLoaded() {
        return strpos((string) ini_get('auto_prepend_file'), 'what-changed-request-audit.php') !== false;
    }

    private function unavailableAttribution($pending) {
        return [
            'enabled' => false,
            'confidence' => $pending ? 'unavailable' : 'none',
            'actors' => [],
            'requests' => [],
            'note' => 'Authenticated request correlation requires the external watcher sensor.',
            'caveat' => 'Request correlation is evidence of who may have staged work, not proof that an account caused each reported state change.',
        ];
    }

    private function databaseSnapshot() {
        $available = array_column(\FreePBX::Database()->query('SHOW FULL TABLES WHERE Table_type = "BASE TABLE"')->fetchAll(\PDO::FETCH_NUM), 0);
        $snapshot = [];
        foreach (self::WATCH_TABLES as $table) {
            if (!in_array($table, $available, true)) {
                continue;
            }
            $quoted = '`'.str_replace('`', '``', $table).'`';
            $count = (int) \FreePBX::Database()->query('SELECT COUNT(*) FROM '.$quoted)->fetchColumn();
            if ($count > self::MAX_TABLE_ROWS) {
                continue;
            }
            // The signature column is a bulky verification cache, not module
            // activation state, and may contain non-UTF-8 blob data. Keep the
            // framework fallback aligned with the external watcher.
            if ($table === 'modules') {
                $columns = '`id`, `modulename`, `version`, `enabled`';
            } elseif ($table === 'userman_users') {
                $columns = '`id`, `auth`, `authid`, `username`, `description`, `default_extension`, `primary_group`, `fname`, `lname`, `displayname`, `title`, `company`, `department`, `language`, `timezone`, `dateformat`, `timeformat`, `datetimeformat`, `email`, `cell`, `work`, `home`, `fax`';
            } else {
                $columns = '*';
            }
            $where = $table === 'modules' ? " WHERE `modulename` <> 'pendingchanges'" : '';
            $rows = \FreePBX::Database()->query('SELECT '.$columns.' FROM '.$quoted.$where)->fetchAll(\PDO::FETCH_ASSOC);
            $normalized = [];
            foreach ($rows as $row) {
                if ($table === 'userman_users_settings' && preg_match('/password|secret|token|pin|(^|_)key($|_)/i', (string) (isset($row['module']) ? $row['module'] : '').' '.(string) (isset($row['key']) ? $row['key'] : ''))) {
                    $row['val'] = '[redacted sha256:'.hash('sha256', (string) (isset($row['val']) ? $row['val'] : '')).']';
                }
                ksort($row);
                $normalized[] = $row;
            }
            usort($normalized, static function ($a, $b) {
                return strcmp(json_encode($a), json_encode($b));
            });
            $snapshot[$table] = $normalized;
        }
        ksort($snapshot);
        return $snapshot;
    }

    private function fileSnapshot() {
        $root = '/etc/asterisk';
        $snapshot = [];
        foreach (glob($root.'/*.conf') ?: [] as $path) {
            if (is_file($path) && is_readable($path)) {
                $snapshot['generated/'.substr($path, strlen($root) + 1)] = hash_file('sha256', $path);
            }
        }
        $moduleRoot = '/var/www/html/admin/modules';
        foreach (glob($moduleRoot.'/*', GLOB_ONLYDIR) ?: [] as $module) {
            if (basename($module) === 'pendingchanges') {
                continue;
            }
            $digest = hash_init('sha256');
            $iterator = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($module, \FilesystemIterator::SKIP_DOTS));
            $paths = iterator_to_array($iterator);
            ksort($paths, SORT_STRING);
            foreach ($paths as $path) {
                if ($path->isFile()) {
                    hash_update($digest, $path->getRelativePathname());
                    hash_update_file($digest, $path->getPathname());
                }
            }
            $snapshot['module/'.basename($module)] = hash_final($digest);
        }
        ksort($snapshot);
        return $snapshot;
    }

    private function fileScope(array $files, $prefix) {
        return array_filter($files, static function ($name) use ($prefix) {
            return strncmp((string) $name, $prefix, strlen($prefix)) === 0;
        }, ARRAY_FILTER_USE_KEY);
    }

    private function databaseDiff(array $before, array $after) {
        $diff = [];
        foreach (array_unique(array_merge(array_keys($before), array_keys($after))) as $table) {
            $old = isset($before[$table]) ? $before[$table] : [];
            $new = isset($after[$table]) ? $after[$table] : [];
            if ($old === $new) {
                continue;
            }
            $oldMap = array_fill_keys(array_map('json_encode', $old), true);
            $newMap = array_fill_keys(array_map('json_encode', $new), true);
            $diff[$table] = [
                'added' => array_values(array_map('json_decode', array_keys(array_diff_key($newMap, $oldMap)))),
                'removed' => array_values(array_map('json_decode', array_keys(array_diff_key($oldMap, $newMap)))),
                'before_count' => count($old),
                'after_count' => count($new),
            ];
        }
        return $diff;
    }

    private function fileDiff(array $before, array $after) {
        $diff = [];
        foreach (array_unique(array_merge(array_keys($before), array_keys($after))) as $file) {
            $old = isset($before[$file]) ? $before[$file] : null;
            $new = isset($after[$file]) ? $after[$file] : null;
            if ($old !== $new) {
                $diff[$file] = ['before' => $old, 'after' => $new];
            }
        }
        return $diff;
    }
}
