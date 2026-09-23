<?php

namespace FreePBX\modules;

require_once __DIR__ . '/autoload.php';

use FreePBX\modules\Pendingchanges\Service\PendingChangesService;
use FreePBX\modules\Pendingchanges\Watcher\HealthClassifier;

class Pendingchanges extends \FreePBX_Helpers implements \FreePBX\BMO
{
    const BASELINE_TABLE = 'pendingchanges_baseline';
    const BASELINE_CONFIG_KEY = 'framework_fallback_baseline';
    const MAX_TABLE_ROWS = 5000;

    const WATCH_TABLES = array(
        'announcement',
        'callbacks',
        'conferences',
        'customappsreg',
        'devices',
        'did',
        'extension_routes',
        'extensions',
        'fax_details',
        'featurecodes',
        'globals',
        'iax',
        'injected',
        'ivr_details',
        'ivr_entries',
        'miscapps',
        'miscdests',
        'modules',
        'outbound_route_sequences',
        'outbound_routes',
        'parkinglot',
        'pjsip',
        'queues_config',
        'queues_details',
        'queues_members',
        'ringgroups',
        'sip',
        'timeconditions',
        'timegroups',
        'timegroups_details',
        'trunk_dialpatterns',
        'trunks',
        'userman_users',
        'userman_users_settings',
        'users',
        'zap',
    );

    private $service;

    public function doConfigPageInit($page)
    {
    }

    public function install()
    {
        $this->service()->install();
    }

    public function uninstall()
    {
        $this->service()->uninstall();
    }

    public function getActionBar($request)
    {
        return array();
    }

    public function needReload()
    {
        return $this->service()->needReload();
    }

    public function baseline()
    {
        return $this->service()->baseline();
    }

    public function seedBaseline()
    {
        return $this->service()->seedBaseline();
    }

    public function status()
    {
        return $this->service()->status();
    }

    public function feedback()
    {
        return $this->service()->feedback();
    }

    public function redactionKeyStatus()
    {
        return $this->service()->redactionKeyStatus();
    }

    public static function classifyWatcherHealth(
        array $status,
        $now = null,
        $installed = true,
        $sensorLoaded = false
    ) {
        return HealthClassifier::classify($status, $now, $installed, $sensorLoaded);
    }

    public function readModuleConfig($key)
    {
        return $this->getConfig($key);
    }

    public function writeModuleConfig($key, $value)
    {
        $this->setConfig($key, $value);
    }

    public function deleteModuleConfig($key)
    {
        $this->delConfig($key);
    }

    private function service()
    {
        if ($this->service === null) {
            $this->service = new PendingChangesService(
                $this,
                \FreePBX::Database(),
                self::WATCH_TABLES,
                self::MAX_TABLE_ROWS,
                self::BASELINE_CONFIG_KEY,
                self::BASELINE_TABLE
            );
        }

        return $this->service;
    }
}
