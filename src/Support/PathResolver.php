<?php

namespace FreePBX\modules\Pendingchanges\Support;

class PathResolver
{
    public function moduleRoot()
    {
        $webroot = $this->configuredPath('AMPWEBROOT', '/var/www/html');

        return ($webroot === '/' ? '' : $webroot) . '/admin/modules';
    }

    public function asteriskConfigRoot()
    {
        return $this->configuredPath('ASTETCDIR', '/etc/asterisk');
    }

    public function asteriskVariableRoot()
    {
        if (isset($GLOBALS['amp_conf']['ASTVARLIBDIR'])) {
            return $this->configuredPath('ASTVARLIBDIR', '/var/lib/asterisk');
        }

        return $this->configuredPath('ASTVARLIB', '/var/lib/asterisk');
    }

    public function configuredPath($setting, $default)
    {
        $path = isset($GLOBALS['amp_conf'][$setting])
            ? (string) $GLOBALS['amp_conf'][$setting]
            : $default;
        $path = $path === '/' ? '/' : rtrim($path, '/');

        if (
            $path === ''
            || $path[0] !== '/'
            || preg_match('/[\x00-\x20\x7f]/', $path)
            || preg_match('#(?:^|/)\.\.(?:/|$)#', $path)
        ) {
            throw new \RuntimeException('FreePBX ' . $setting . ' is not a safe absolute path.');
        }

        return $path;
    }
}
