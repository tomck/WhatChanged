<?php

namespace FreePBX\modules\Pendingchanges\Watcher;

use FreePBX\modules\Pendingchanges\Support\PathResolver;

class Probe
{
    private $paths;

    public function __construct(PathResolver $paths)
    {
        $this->paths = $paths;
    }

    public function inspect()
    {
        $path = $this->paths->asteriskVariableRoot() . '/pendingchanges-watcher/status.json';
        $installed = $this->installed();
        $sensorLoaded = $this->attributionSensorLoaded();

        if (!is_readable($path)) {
            return array(
                'status' => null,
                'health' => HealthClassifier::missingStatus($installed, $sensorLoaded),
            );
        }

        $contents = file_get_contents($path);
        if ($contents === false) {
            return array(
                'status' => null,
                'health' => HealthClassifier::failure(
                    'unreadable',
                    'Watcher status exists but could not be read.',
                    $installed,
                    $sensorLoaded
                ),
            );
        }

        $status = json_decode((string) $contents, true);
        if (
            !is_array($status)
            || !isset(
                $status['observed_at'],
                $status['need_reload'],
                $status['database_drift'],
                $status['file_drift'],
                $status['message']
            )
        ) {
            return array(
                'status' => null,
                'health' => HealthClassifier::failure(
                    'invalid',
                    'Watcher status is malformed or incomplete.',
                    $installed,
                    $sensorLoaded
                ),
            );
        }

        return array(
            'status' => $status,
            'health' => HealthClassifier::classify($status, time(), $installed, $sensorLoaded),
        );
    }

    private function installed()
    {
        $markers = array(
            '/usr/lib/what-changed-watcher/watcher.py',
            '/usr/local/lib/what-changed-watcher/watcher.py',
            '/etc/systemd/system/what-changed-watcher.service',
            '/lib/systemd/system/what-changed-watcher.service',
            '/usr/lib/systemd/system/what-changed-watcher.service',
            '/etc/what-changed-watcher.env',
        );

        foreach ($markers as $path) {
            if (file_exists($path)) {
                return true;
            }
        }

        return false;
    }

    private function attributionSensorLoaded()
    {
        return defined('WHAT_CHANGED_ATTRIBUTION_SENSOR_ACTIVE')
            && WHAT_CHANGED_ATTRIBUTION_SENSOR_ACTIVE === true;
    }
}
