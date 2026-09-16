<?php

namespace FreePBX\modules\Pendingchanges\Diff;

use FreePBX\modules\Pendingchanges\Security\Redactor;

class SnapshotDiffer
{
    private $redactor;

    public function __construct(Redactor $redactor)
    {
        $this->redactor = $redactor;
    }

    public function database(array $before, array $after)
    {
        $diff = array();
        $tables = array_unique(array_merge(array_keys($before), array_keys($after)));

        foreach ($tables as $table) {
            $old = isset($before[$table]) ? $before[$table] : array();
            $new = isset($after[$table]) ? $after[$table] : array();
            if ($old === $new) {
                continue;
            }

            $oldMap = array_fill_keys(array_map('json_encode', $old), true);
            $newMap = array_fill_keys(array_map('json_encode', $new), true);
            $added = array();
            foreach (array_keys(array_diff_key($newMap, $oldMap)) as $encoded) {
                $added[] = $this->redactor->publicRow(json_decode($encoded, true));
            }

            $removed = array();
            foreach (array_keys(array_diff_key($oldMap, $newMap)) as $encoded) {
                $removed[] = $this->redactor->publicRow(json_decode($encoded, true));
            }

            $diff[$table] = array(
                'added' => $added,
                'removed' => $removed,
                'before_count' => count($old),
                'after_count' => count($new),
            );
        }

        return $diff;
    }

    public function files(array $before, array $after)
    {
        $diff = array();
        $files = array_unique(array_merge(array_keys($before), array_keys($after)));

        foreach ($files as $file) {
            $old = isset($before[$file]) ? $before[$file] : null;
            $new = isset($after[$file]) ? $after[$file] : null;
            if ($old !== $new) {
                $diff[$file] = array('before' => $old, 'after' => $new);
            }
        }

        return $diff;
    }

    public function fileScope(array $files, $prefix)
    {
        return array_filter(
            $files,
            static function ($name) use ($prefix) {
                return strncmp((string) $name, $prefix, strlen($prefix)) === 0;
            },
            ARRAY_FILTER_USE_KEY
        );
    }
}
