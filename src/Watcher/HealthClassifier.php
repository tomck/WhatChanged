<?php

namespace FreePBX\modules\Pendingchanges\Watcher;

class HealthClassifier
{
    public static function classify(array $status, $now = null, $installed = true, $sensorLoaded = false)
    {
        $now = $now === null ? time() : (int) $now;
        $observed = isset($status['observed_at']) && is_numeric($status['observed_at'])
            ? (int) $status['observed_at']
            : 0;
        if ($observed <= 0) {
            return self::failure(
                'invalid',
                'Watcher status has no valid observation time.',
                $installed,
                $sensorLoaded
            );
        }

        $metadata = isset($status['watcher_health']) && is_array($status['watcher_health'])
            ? $status['watcher_health']
            : array();
        $expected = isset($metadata['expected_refresh_seconds']) && is_numeric($metadata['expected_refresh_seconds'])
            ? (int) ceil((float) $metadata['expected_refresh_seconds'])
            : 30;
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

        return array(
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
        );
    }

    public static function missingStatus($installed, $sensorLoaded)
    {
        if ($installed) {
            return self::failure(
                'installed_unconfigured',
                'The watcher appears installed but has not published a readable observation.',
                true,
                $sensorLoaded
            );
        }

        return self::failure(
            'not_installed',
            'The external watcher is not installed; framework-only coverage is reduced.',
            false,
            $sensorLoaded,
            'warning'
        );
    }

    public static function failure($state, $detail, $installed, $sensorLoaded, $severity = 'danger')
    {
        return array(
            'state' => $state,
            'label' => ucwords(str_replace('_', ' ', $state)),
            'severity' => $severity,
            'detail' => $detail,
            'installed' => (bool) $installed,
            'sensor_loaded' => (bool) $sensorLoaded,
            'observation_age_seconds' => null,
            'expected_refresh_seconds' => null,
        );
    }
}
