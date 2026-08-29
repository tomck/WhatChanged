<?php
namespace FreePBX\modules;

class Pendingchanges extends \FreePBX_Helpers implements \FreePBX\BMO {
    private const BASELINE_TABLE = 'pendingchanges_baseline';
    // Keep the framework-only fallback bounded too. The external watcher is
    // preferred in production, but an unreadable watcher status must never
    // turn this page into an unbounded scan of CDR/CEL/add-on tables.
    private const WATCH_TABLES = [
        'announcement', 'callbacks', 'conferences', 'customappsreg', 'devices',
        'did', 'extension_routes', 'extensions', 'featurecodes', 'globals',
        'iax', 'injected', 'ivr_details', 'ivr_entries', 'miscapps', 'miscdests',
        'outbound_route_sequences', 'outbound_routes', 'parkinglot', 'pjsip',
        'queues_config', 'queues_details', 'queues_members', 'ringgroups', 'sip',
        'timeconditions', 'timegroups', 'timegroups_details',
        'trunk_dialpatterns', 'trunks', 'users', 'zap',
    ];
    private const MAX_TABLE_ROWS = 5000;

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

    public function needReload(): bool {
        $statement = \FreePBX::Database()->prepare("SELECT value FROM admin WHERE variable = 'need_reload'");
        $statement->execute();
        return $statement->fetchColumn() === 'true';
    }

    public function baseline(): ?array {
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

    public function seedBaseline(): array {
        if ($this->needReload()) {
            throw new \RuntimeException('Cannot seed a baseline while Apply Changes is pending. Apply or clear the pending reload first.');
        }
        $database = $this->databaseSnapshot();
        $files = $this->fileSnapshot();
        $stmt = \FreePBX::Database()->prepare('REPLACE INTO '.self::BASELINE_TABLE.' (id, database_snapshot, file_snapshot, captured_at) VALUES (1, ?, ?, NOW())');
        $stmt->execute([json_encode($database, JSON_UNESCAPED_SLASHES), json_encode($files, JSON_UNESCAPED_SLASHES)]);
        return ['tables' => count($database), 'files' => count($files)];
    }

    public function status(): array {
        $watcher = $this->watcherStatus();
        if ($watcher !== null) {
            $files = $watcher['file_drift'];
            return [
                'pending' => $watcher['need_reload'],
                'database' => $watcher['database_drift'],
                'files' => $files,
                'generated_files' => $this->fileScope($files, 'generated/'),
                'module_files' => $this->fileScope($files, 'module/'),
                'coverage_limitations' => $watcher['coverage_limitations'] ?? [],
                'message' => $watcher['message'],
                'baseline' => $watcher['baseline_available'],
                'captured_at' => $watcher['baseline_captured_at'] ?? null,
                'watcher_observed_at' => $watcher['observed_at'],
                'watcher' => true,
            ];
        }
        $baseline = $this->baseline();
        $pending = $this->needReload();
        if (!$baseline) {
            return ['pending' => $pending, 'baseline' => false, 'message' => 'No applied baseline has been seeded.', 'watcher' => false];
        }
        $database = $this->databaseDiff($baseline['database'], $this->databaseSnapshot());
        $files = $this->fileDiff($baseline['files'], $this->fileSnapshot());
        $hasDrift = !empty($database) || !empty($files);
        $message = $pending && !$hasDrift
            ? 'Reload requested; origin unavailable.'
            : ($pending ? 'Configuration drift detected since the applied baseline.' : 'No pending reload.');
        return compact('pending', 'database', 'files', 'message') + [
            'generated_files' => $this->fileScope($files, 'generated/'),
            'module_files' => $this->fileScope($files, 'module/'),
            'coverage_limitations' => [],
            'baseline' => true, 'captured_at' => $baseline['captured_at'], 'watcher' => false,
        ];
    }

    private function watcherStatus(): ?array {
        $path = '/var/lib/asterisk/pendingchanges-watcher/status.json';
        if (!is_readable($path)) {
            return null;
        }
        $status = json_decode((string) file_get_contents($path), true);
        if (!is_array($status) || !isset($status['need_reload'], $status['database_drift'], $status['file_drift'], $status['message'])) {
            return null;
        }
        return $status;
    }

    private function databaseSnapshot(): array {
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
            $rows = \FreePBX::Database()->query('SELECT * FROM '.$quoted)->fetchAll(\PDO::FETCH_ASSOC);
            $normalized = [];
            foreach ($rows as $row) {
                ksort($row);
                $normalized[] = $row;
            }
            usort($normalized, static fn($a, $b) => strcmp(json_encode($a), json_encode($b)));
            $snapshot[$table] = $normalized;
        }
        ksort($snapshot);
        return $snapshot;
    }

    private function fileSnapshot(): array {
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

    private function fileScope(array $files, string $prefix): array {
        return array_filter($files, static fn($name) => str_starts_with((string) $name, $prefix), ARRAY_FILTER_USE_KEY);
    }

    private function databaseDiff(array $before, array $after): array {
        $diff = [];
        foreach (array_unique(array_merge(array_keys($before), array_keys($after))) as $table) {
            $old = $before[$table] ?? [];
            $new = $after[$table] ?? [];
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

    private function fileDiff(array $before, array $after): array {
        $diff = [];
        foreach (array_unique(array_merge(array_keys($before), array_keys($after))) as $file) {
            if (($before[$file] ?? null) !== ($after[$file] ?? null)) {
                $diff[$file] = ['before' => $before[$file] ?? null, 'after' => $after[$file] ?? null];
            }
        }
        return $diff;
    }
}
