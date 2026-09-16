<?php

namespace FreePBX\modules\Pendingchanges\Watcher;

use FreePBX\modules\Pendingchanges\Support\PathResolver;

class PayloadInspector
{
    private $paths;
    private $moduleRoot;
    private $servicePaths;
    private $libraryRoots;

    public function __construct(
        PathResolver $paths,
        $moduleRoot = null,
        $servicePaths = null,
        $libraryRoots = null
    ) {
        $this->paths = $paths;
        $this->moduleRoot = $moduleRoot;
        $this->servicePaths = $servicePaths;
        $this->libraryRoots = $libraryRoots;
    }

    public function inspect($observedVersion = null)
    {
        $module = $this->moduleRoot === null
            ? $this->paths->pendingChangesModuleRoot()
            : rtrim($this->moduleRoot, '/');
        $embeddedVersion = $this->readVersion($module . '/watcher/VERSION');
        $installedRoot = $this->installedRoot();
        $installedVersion = $this->validVersion($observedVersion)
            ? $observedVersion
            : ($installedRoot === null ? null : $this->readVersion($installedRoot . '/VERSION'));
        $command = 'sudo ' . $module . '/bin/install-watcher';

        if ($installedRoot === null && !$this->validVersion($observedVersion)) {
            return $this->result(
                'not_installed',
                'Not installed',
                'warning',
                'No installed watcher payload was found.',
                false,
                $embeddedVersion,
                null,
                $command
            );
        }

        if ($embeddedVersion === null) {
            return $this->result(
                'unknown',
                'Unknown',
                'danger',
                'The module does not contain readable watcher version metadata.',
                false,
                null,
                $installedVersion,
                $command
            );
        }

        if ($installedVersion === null) {
            return $this->result(
                'outdated',
                'Update required',
                'warning',
                'The installed watcher predates payload version tracking.',
                false,
                $embeddedVersion,
                null,
                $command
            );
        }

        if ($installedVersion === $embeddedVersion) {
            return $this->result(
                'current',
                'Current',
                'success',
                'The installed watcher matches the payload bundled with this module.',
                true,
                $embeddedVersion,
                $installedVersion,
                $command
            );
        }

        $newer = version_compare($installedVersion, $embeddedVersion, '>');

        return $this->result(
            $newer ? 'newer' : 'outdated',
            $newer ? 'Module update required' : 'Update required',
            'warning',
            $newer
                ? 'The installed watcher is newer than the payload bundled with this module. '
                    . 'Update the Pending Changes module before changing the watcher.'
                : 'The installed watcher does not match the payload bundled with this module.',
            false,
            $embeddedVersion,
            $installedVersion,
            $newer ? null : $command
        );
    }

    private function installedRoot()
    {
        $servicePaths = $this->servicePaths === null
            ? array(
                '/etc/systemd/system/what-changed-watcher.service',
                '/run/systemd/system/what-changed-watcher.service',
                '/usr/local/lib/systemd/system/what-changed-watcher.service',
                '/usr/lib/systemd/system/what-changed-watcher.service',
                '/lib/systemd/system/what-changed-watcher.service',
            )
            : $this->servicePaths;

        foreach ($servicePaths as $servicePath) {
            if (!is_readable($servicePath)) {
                continue;
            }
            $service = file_get_contents($servicePath);
            if (!is_string($service)) {
                continue;
            }
            if (preg_match('#/usr/local/lib/what-changed-watcher/watcher\.py#', $service)) {
                return '/usr/local/lib/what-changed-watcher';
            }
            if (preg_match('#/usr/lib/what-changed-watcher/watcher\.py#', $service)) {
                return '/usr/lib/what-changed-watcher';
            }
        }

        $libraryRoots = $this->libraryRoots === null
            ? array('/usr/lib/what-changed-watcher', '/usr/local/lib/what-changed-watcher')
            : $this->libraryRoots;
        foreach ($libraryRoots as $root) {
            if (is_file($root . '/watcher.py') || is_file($root . '/VERSION')) {
                return $root;
            }
        }

        return null;
    }

    private function readVersion($path)
    {
        if (!is_readable($path)) {
            return null;
        }
        $version = trim((string) file_get_contents($path));

        return $this->validVersion($version) ? $version : null;
    }

    private function validVersion($version)
    {
        return is_string($version)
            && preg_match('/^[0-9]+\.[0-9]+\.[0-9]+$/', $version);
    }

    private function result(
        $state,
        $label,
        $severity,
        $detail,
        $current,
        $embeddedVersion,
        $installedVersion,
        $command
    ) {
        return array(
            'state' => $state,
            'label' => $label,
            'severity' => $severity,
            'detail' => $detail,
            'current' => (bool) $current,
            'embedded_version' => $embeddedVersion,
            'installed_version' => $installedVersion,
            'update_command' => $command,
        );
    }
}
