<?php

namespace FreePBX\modules\Pendingchanges\Snapshot;

use FreePBX\modules\Pendingchanges\Security\Redactor;

class DatabaseSnapshotter
{
    private $database;
    private $redactor;
    private $tables;
    private $maxRows;

    public function __construct($database, Redactor $redactor, array $tables, $maxRows)
    {
        $this->database = $database;
        $this->redactor = $redactor;
        $this->tables = $tables;
        $this->maxRows = (int) $maxRows;
    }

    public function capture()
    {
        $rows = $this->database
            ->query('SHOW FULL TABLES WHERE Table_type = "BASE TABLE"')
            ->fetchAll(\PDO::FETCH_NUM);
        $available = array_column($rows, 0);
        $snapshot = array();

        foreach ($this->tables as $table) {
            if (!in_array($table, $available, true)) {
                continue;
            }

            $quoted = '`' . str_replace('`', '``', $table) . '`';
            $count = (int) $this->database
                ->query('SELECT COUNT(*) FROM ' . $quoted)
                ->fetchColumn();
            if ($count > $this->maxRows) {
                continue;
            }

            $columns = $this->columnsFor($table);
            $where = $table === 'modules' ? " WHERE `modulename` <> 'pendingchanges'" : '';
            $rows = $this->database
                ->query('SELECT ' . $columns . ' FROM ' . $quoted . $where)
                ->fetchAll(\PDO::FETCH_ASSOC);
            $normalized = array();
            foreach ($rows as $row) {
                $row = $this->redactor->protectRow($row);
                ksort($row);
                $normalized[] = $row;
            }
            usort($normalized, static function ($left, $right) {
                return strcmp(json_encode($left), json_encode($right));
            });
            $snapshot[$table] = $normalized;
        }

        ksort($snapshot);

        return $snapshot;
    }

    private function columnsFor($table)
    {
        if ($table === 'modules') {
            return '`id`, `modulename`, `version`, `enabled`';
        }

        if ($table === 'userman_users') {
            return '`id`, `auth`, `authid`, `username`, `description`, `default_extension`, '
                . '`primary_group`, `fname`, `lname`, `displayname`, `title`, `company`, '
                . '`department`, `language`, `timezone`, `dateformat`, `timeformat`, '
                . '`datetimeformat`, `email`, `cell`, `work`, `home`, `fax`';
        }

        return '*';
    }
}
