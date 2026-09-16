<?php

namespace FreePBX\modules\Pendingchanges\Presentation;

class ChangePresenter
{
    public function pageModel(array $status)
    {
        $extensionChanges = $this->extensionChanges($status['database']);
        $otherDatabaseChanges = $status['database'];
        unset($otherDatabaseChanges['users'], $otherDatabaseChanges['devices']);

        $watcherHealth = isset($status['watcher_health']) && is_array($status['watcher_health'])
            ? $status['watcher_health']
            : array(
                'state' => 'invalid',
                'label' => 'Unknown',
                'severity' => 'danger',
                'detail' => 'Watcher health information is unavailable.',
                'sensor_loaded' => false,
                'observation_age_seconds' => null,
            );
        $watcherPayload = isset($watcherHealth['payload']) && is_array($watcherHealth['payload'])
            ? $watcherHealth['payload']
            : array(
                'state' => 'unknown',
                'label' => 'Unknown',
                'severity' => 'danger',
                'detail' => 'Watcher payload version information is unavailable.',
                'current' => false,
                'embedded_version' => null,
                'installed_version' => null,
                'update_command' => null,
            );
        $dataCurrent = !empty($status['data_current']);
        $baselineProvenance = isset($status['baseline_provenance'])
            && is_array($status['baseline_provenance'])
            ? $status['baseline_provenance']
            : array('state' => 'uncertain');
        $baselineTrusted = (isset($baselineProvenance['state'])
            ? $baselineProvenance['state']
            : '') === 'trusted';
        $severity = isset($watcherHealth['severity']) ? $watcherHealth['severity'] : '';

        if ($severity === 'danger') {
            $messageClass = 'alert-danger';
        } elseif ($severity === 'warning' || !$baselineTrusted || $status['pending']) {
            $messageClass = 'alert-warning';
        } else {
            $messageClass = 'alert-success';
        }

        return array(
            'status' => $status,
            'extensionChanges' => $extensionChanges,
            'otherDatabaseChanges' => $otherDatabaseChanges,
            'astdbChanges' => isset($status['astdb']) ? $status['astdb'] : array(),
            'attribution' => isset($status['attribution']) ? $status['attribution'] : array(),
            'watcherHealth' => $watcherHealth,
            'watcherPayload' => $watcherPayload,
            'dataCurrent' => $dataCurrent,
            'baselineProvenance' => $baselineProvenance,
            'baselineTrusted' => $baselineTrusted,
            'messageClass' => $messageClass,
        );
    }

    public function escape($value)
    {
        return htmlentities((string) $value, ENT_QUOTES, 'UTF-8');
    }

    public function json($value)
    {
        return $this->escape(json_encode($value, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    }

    public function tableLabel($table)
    {
        $labels = array(
            'fax_details' => 'Fax Configuration',
            'userman_users' => 'User Management users',
            'userman_users_settings' => 'User Management / UCP settings',
        );

        return isset($labels[$table])
            ? $labels[$table]
            : ucwords(str_replace('_', ' ', $table));
    }

    public function requestTarget(array $event)
    {
        if ((isset($event['operation']) ? $event['operation'] : '') === 'apply') {
            return 'Apply Config';
        }

        foreach (array('display', 'type', 'module', 'action', 'command', 'handler', 'script') as $field) {
            if (!empty($event[$field])) {
                return (string) $event[$field];
            }
        }

        return 'FreePBX admin request';
    }

    public function record($kind, $table, array $item)
    {
        $symbols = array('added' => '+', 'removed' => '−', 'updated' => '~');
        $row = $kind === 'updated'
            ? array('id' => isset($item['key']) ? $item['key'] : 'record')
            : $item;
        $details = $kind === 'updated'
            ? (isset($item['fields']) ? $item['fields'] : array())
            : $item;

        if ($kind === 'updated' && !empty($item['identity'])) {
            $title = $this->identity(
                $table,
                isset($item['identity']) ? $item['identity'] : array()
            );
        } elseif ($table === 'fax_details') {
            $title = $this->faxSettingLabel(
                (string) (isset($item['key']) ? $item['key'] : 'record')
            );
        } else {
            $title = $kind === 'updated'
                ? (string) (isset($item['key']) ? $item['key'] : 'record')
                : $this->identity($table, $row);
        }

        return array(
            'kind' => $kind,
            'symbol' => $symbols[$kind],
            'title' => $title,
            'summary' => 'Evidence',
            'details' => $details,
        );
    }

    public function extension($kind, array $item)
    {
        $symbols = array('added' => '+', 'removed' => '−', 'updated' => '~');

        return array(
            'kind' => $kind,
            'symbol' => $symbols[$kind],
            'title' => $item['id'] . ($item['name'] !== '' ? ' — ' . $item['name'] : ''),
            'summary' => 'Extension and endpoint evidence',
            'details' => $item['evidence'],
        );
    }

    private function identity($table, array $row)
    {
        if ($table === 'userman_users') {
            $username = (string) (isset($row['username']) ? $row['username'] : '');
            $id = (string) (isset($row['id']) ? $row['id'] : '');
            if ($username !== '') {
                return $username . ($id !== '' ? ' — User ' . $id : '');
            }
        }

        if ($table === 'userman_users_settings') {
            $user = (string) (isset($row['username'])
                ? $row['username']
                : 'User ' . (isset($row['uid']) ? $row['uid'] : 'record'));

            return $user . ' — ' . (string) (isset($row['module']) ? $row['module'] : 'setting')
                . ' / ' . (string) (isset($row['key']) ? $row['key'] : 'value');
        }

        foreach (array('extension', 'id', 'account', 'grpnum', 'device', 'user', 'key') as $field) {
            if (array_key_exists($field, $row) && $row[$field] !== '') {
                $label = (string) $row[$field];
                if (!empty($row['name'])) {
                    $label .= ' — ' . (string) $row['name'];
                } elseif (!empty($row['description'])) {
                    $label .= ' — ' . (string) $row['description'];
                }

                return $label;
            }
        }

        return $table . ' record';
    }

    private function faxSettingLabel($key)
    {
        $labels = array(
            'concurrentfax' => 'Concurrent fax channels',
            'ecm' => 'Error correction mode',
            'fax_rx_email' => 'Fax receive email',
            'force_detection' => 'Always generate detection code',
            'headerinfo' => 'Default fax header',
            'legacy_mode' => 'Legacy mode',
            'localstationid' => 'Local station identifier',
            'maxpages' => 'Maximum pages',
            'maxrate' => 'Maximum transfer rate',
            'minrate' => 'Minimum transfer rate',
            'papersize' => 'Default paper size',
            'sender_address' => 'Outgoing email address',
        );

        return isset($labels[$key]) ? $labels[$key] : ucwords(str_replace('_', ' ', $key));
    }

    private function recordId($kind, array $item)
    {
        if ($kind === 'updated') {
            return (string) (isset($item['key']) ? $item['key'] : 'record');
        }

        foreach (array('extension', 'id') as $field) {
            if (isset($item[$field]) && $item[$field] !== '') {
                return (string) $item[$field];
            }
        }

        return 'record';
    }

    private function extensionChanges(array $database)
    {
        $merged = array();
        $sources = array('users' => 'Extension', 'devices' => 'Endpoint device');

        foreach ($sources as $table => $label) {
            foreach (array('added', 'removed', 'updated') as $kind) {
                $items = isset($database[$table][$kind])
                    ? $database[$table][$kind]
                    : array();
                foreach ($items as $item) {
                    $id = $this->recordId($kind, $item);
                    if (!isset($merged[$kind][$id])) {
                        $merged[$kind][$id] = array(
                            'id' => $id,
                            'name' => '',
                            'evidence' => array(),
                        );
                    }

                    $row = $kind === 'updated'
                        ? (isset($item['identity']) ? $item['identity'] : array())
                        : $item;
                    $name = isset($row['name'])
                        ? $row['name']
                        : (isset($row['description']) ? $row['description'] : '');
                    if ($name !== '' && $merged[$kind][$id]['name'] === '') {
                        $merged[$kind][$id]['name'] = (string) $name;
                    }
                    $merged[$kind][$id]['evidence'][$label] = $kind === 'updated'
                        ? (isset($item['fields']) ? $item['fields'] : array())
                        : $item;
                }
            }
        }

        foreach ($merged as $kind => $items) {
            ksort($items, SORT_NATURAL);
            $merged[$kind] = array_values($items);
        }

        return $merged;
    }
}
