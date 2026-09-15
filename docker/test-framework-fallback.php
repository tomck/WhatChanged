<?php
namespace FreePBX {
    interface BMO {}
}

namespace {
    class FreePBX_Helpers {}
    require __DIR__.'/../Pendingchanges.class.php';

    $class = new ReflectionClass('FreePBX\\modules\\Pendingchanges');
    $instance = $class->newInstance();

    $sensitive = $class->getMethod('sensitiveField');
    $sensitive->setAccessible(true);
    if (!$sensitive->invoke(null, 'data', ['variable' => 'TURN_PASSWORD', 'data' => 'private'])) {
        throw new RuntimeException('Generic semantic secret was not classified');
    }
    if ($sensitive->invoke(null, 'value', ['name' => 'secretary', 'value' => 'visible'])) {
        throw new RuntimeException('Innocent semantic value was classified as secret');
    }

    $moduleRoot = $class->getMethod('configuredModuleRoot');
    $moduleRoot->setAccessible(true);
    $GLOBALS['amp_conf'] = ['AMPWEBROOT' => '/srv/freepbx-web'];
    if ($moduleRoot->invoke($instance) !== '/srv/freepbx-web/admin/modules') {
        throw new RuntimeException('Framework fallback ignored AMPWEBROOT');
    }
    $configRoot = $class->getMethod('configuredAsteriskConfigRoot');
    $configRoot->setAccessible(true);
    $variableRoot = $class->getMethod('configuredAsteriskVariableRoot');
    $variableRoot->setAccessible(true);
    $GLOBALS['amp_conf']['ASTETCDIR'] = '/srv/asterisk-config';
    $GLOBALS['amp_conf']['ASTVARLIBDIR'] = '/srv/asterisk-data';
    if ($configRoot->invoke($instance) !== '/srv/asterisk-config'
        || $variableRoot->invoke($instance) !== '/srv/asterisk-data') {
        throw new RuntimeException('Framework fallback ignored configured Asterisk paths');
    }

    $prefix = '[protected hmac-sha256:';
    $before = ['settings' => [[
        'variable' => 'API_TOKEN', 'value' => $prefix.str_repeat('a', 64).']',
    ]]];
    $after = ['settings' => [[
        'variable' => 'API_TOKEN', 'value' => $prefix.str_repeat('b', 64).']',
    ]]];
    $diffMethod = $class->getMethod('databaseDiff');
    $diffMethod->setAccessible(true);
    $diff = $diffMethod->invoke($instance, $before, $after);
    $published = json_encode($diff);
    if (strpos($published, '[redacted]') === false || strpos($published, $prefix) !== false) {
        throw new RuntimeException('Framework diff exposed a protected fingerprint');
    }

    echo "framework fallback security checks passed\n";
}
