<?php
namespace FreePBX\modules;

class Pendingchanges extends \FreePBX_Helpers implements \FreePBX\BMO {
    private const BASELINE_TABLE = 'pendingchanges_baseline';
    private const EXCLUDED_TABLES = [
        'admin', 'asteriskcdrdb', 'cdr', 'cel', 'cronmanager', 'kvstore',
        'notifications', 'pendingchanges_baseline', 'queue_log',
    ];

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
            return [
                'pending' => $watcher['need_reload'],
                'database' => $watcher['database_drift'],
                'files' => $watcher['file_drift'],
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
        return compact('pending', 'database', 'files', 'message') + ['baseline' => true, 'captured_at' => $baseline['captured_at'], 'watcher' => false];
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
        $tables = \FreePBX::Database()->query('SHOW FULL TABLES WHERE Table_type = "BASE TABLE"')->fetchAll(\PDO::FETCH_NUM);
        $snapshot = [];
        foreach ($tables as $entry) {
            $table = $entry[0];
            if (in_array($table, self::EXCLUDED_TABLES, true) || strpos($table, 'pendingchanges_') === 0) {
                continue;
            }
            $rows = \FreePBX::Database()->query('SELECT * FROM `'.str_replace('`', '``', $table).'`')->fetchAll(\PDO::FETCH_ASSOC);
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
                $snapshot[substr($path, strlen($root) + 1)] = hash_file('sha256', $path);
            }
        }
        ksort($snapshot);
        return $snapshot;
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
