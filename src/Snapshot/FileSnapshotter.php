<?php

namespace FreePBX\modules\Pendingchanges\Snapshot;

use FreePBX\modules\Pendingchanges\Support\PathResolver;

class FileSnapshotter
{
    private $paths;

    public function __construct(PathResolver $paths)
    {
        $this->paths = $paths;
    }

    public function capture()
    {
        $snapshot = array();
        $configRoot = $this->paths->asteriskConfigRoot();
        foreach (glob($configRoot . '/*.conf') ?: array() as $path) {
            if (is_file($path) && is_readable($path)) {
                $snapshot['generated/' . substr($path, strlen($configRoot) + 1)] = hash_file('sha256', $path);
            }
        }

        $moduleRoot = $this->paths->moduleRoot();
        foreach (glob($moduleRoot . '/*', GLOB_ONLYDIR) ?: array() as $module) {
            if (basename($module) === 'pendingchanges') {
                continue;
            }

            $digest = hash_init('sha256');
            $present = false;
            foreach (array('module.xml', 'module.sig') as $marker) {
                $path = $module . '/' . $marker;
                if (is_file($path) && is_readable($path)) {
                    hash_update($digest, $marker);
                    hash_update($digest, hash_file('sha256', $path, true));
                    $present = true;
                }
            }
            if ($present) {
                $snapshot['module/' . basename($module)] = hash_final($digest);
            }
        }

        ksort($snapshot);

        return $snapshot;
    }
}
