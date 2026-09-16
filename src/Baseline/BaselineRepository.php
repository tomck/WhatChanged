<?php

namespace FreePBX\modules\Pendingchanges\Baseline;

use FreePBX\modules\Pendingchanges\Security\Redactor;

class BaselineRepository
{
    private $module;
    private $database;
    private $redactor;
    private $configKey;
    private $legacyTable;

    public function __construct($module, $database, Redactor $redactor, $configKey, $legacyTable)
    {
        $this->module = $module;
        $this->database = $database;
        $this->redactor = $redactor;
        $this->configKey = $configKey;
        $this->legacyTable = $legacyTable;
    }

    public function get()
    {
        $encoded = $this->module->readModuleConfig($this->configKey);
        if (!$encoded) {
            $this->migrateLegacy();
            $encoded = $this->module->readModuleConfig($this->configKey);
        }

        $baseline = is_string($encoded) ? json_decode($encoded, true) : $encoded;
        if (
            !is_array($baseline)
            || !isset($baseline['database'], $baseline['files'], $baseline['captured_at'])
        ) {
            return null;
        }

        $database = is_array($baseline['database']) ? $baseline['database'] : array();
        $protected = array();
        foreach ($database as $table => $rows) {
            $protected[$table] = array();
            foreach ($rows as $snapshotRow) {
                $protected[$table][] = $this->redactor->protectRow($snapshotRow);
            }
        }

        if ($protected !== $database) {
            $baseline['database'] = $protected;
            $this->write($baseline);
        }

        return array(
            'database' => $protected,
            'files' => is_array($baseline['files']) ? $baseline['files'] : array(),
            'captured_at' => $baseline['captured_at'],
        );
    }

    public function save(array $database, array $files)
    {
        $this->write(array(
            'database' => $database,
            'files' => $files,
            'captured_at' => gmdate('c'),
        ));
    }

    public function delete()
    {
        $this->module->deleteModuleConfig($this->configKey);
        $this->database->exec('DROP TABLE IF EXISTS ' . $this->legacyTable);
    }

    public function migrateLegacy()
    {
        if ($this->module->readModuleConfig($this->configKey)) {
            return;
        }

        try {
            $statement = $this->database->prepare('SHOW TABLES LIKE ?');
            $statement->execute(array($this->legacyTable));
            if (!$statement->fetchColumn()) {
                return;
            }

            $row = $this->database->query(
                'SELECT database_snapshot, file_snapshot, captured_at FROM '
                . $this->legacyTable . ' WHERE id = 1'
            )->fetch(\PDO::FETCH_ASSOC);
            if ($row) {
                $this->write(array(
                    'database' => json_decode($row['database_snapshot'], true) ?: array(),
                    'files' => json_decode($row['file_snapshot'], true) ?: array(),
                    'captured_at' => $row['captured_at'],
                ));
            }
            $this->database->exec('DROP TABLE IF EXISTS ' . $this->legacyTable);
        } catch (\Exception $error) {
            // Installation must remain usable if a legacy migration cannot be
            // completed. The table is retained so a later attempt can retry.
        }
    }

    private function write(array $baseline)
    {
        $this->module->writeModuleConfig(
            $this->configKey,
            json_encode($baseline, JSON_UNESCAPED_SLASHES)
        );
    }
}
