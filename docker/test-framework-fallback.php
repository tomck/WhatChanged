<?php
namespace FreePBX {
    interface BMO {}
}

namespace {
    class FreePBX_Helpers {}

    if ($argc !== 2) {
        fwrite(STDERR, "usage: test-framework-fallback.php extracted-module-directory\n");
        exit(2);
    }

    require $argv[1].'/Pendingchanges.class.php';

    $class = new ReflectionClass('FreePBX\\modules\\Pendingchanges');
    if ($class->getMethod('status')->getDeclaringClass()->getName() !== $class->getName()) {
        throw new RuntimeException('FreePBX BMO adapter does not expose its public contract');
    }

    $redactor = 'FreePBX\\modules\\Pendingchanges\\Security\\Redactor';
    if (!$redactor::sensitiveField('data', ['variable' => 'TURN_PASSWORD', 'data' => 'private'])) {
        throw new RuntimeException('Generic semantic secret was not classified');
    }
    if ($redactor::sensitiveField('value', ['name' => 'secretary', 'value' => 'visible'])) {
        throw new RuntimeException('Innocent semantic value was classified as secret');
    }

    $pathClass = 'FreePBX\\modules\\Pendingchanges\\Support\\PathResolver';
    $paths = new $pathClass();
    $GLOBALS['amp_conf'] = ['AMPWEBROOT' => '/srv/freepbx-web'];
    if ($paths->moduleRoot() !== '/srv/freepbx-web/admin/modules') {
        throw new RuntimeException('Framework fallback ignored AMPWEBROOT');
    }
    $GLOBALS['amp_conf']['ASTETCDIR'] = '/srv/asterisk-config';
    $GLOBALS['amp_conf']['ASTVARLIBDIR'] = '/srv/asterisk-data';
    if ($paths->asteriskConfigRoot() !== '/srv/asterisk-config'
        || $paths->asteriskVariableRoot() !== '/srv/asterisk-data') {
        throw new RuntimeException('Framework fallback ignored configured Asterisk paths');
    }

    $prefix = '[protected hmac-sha256:';
    $before = ['settings' => [[
        'variable' => 'API_TOKEN', 'value' => $prefix.str_repeat('a', 64).']',
    ]]];
    $after = ['settings' => [[
        'variable' => 'API_TOKEN', 'value' => $prefix.str_repeat('b', 64).']',
    ]]];
    $redactorInstance = new $redactor($paths);
    $differClass = 'FreePBX\\modules\\Pendingchanges\\Diff\\SnapshotDiffer';
    $differ = new $differClass($redactorInstance);
    $diff = $differ->database($before, $after);
    $published = json_encode($diff);
    if (strpos($published, '[redacted]') === false || strpos($published, $prefix) !== false) {
        throw new RuntimeException('Framework diff exposed a protected fingerprint');
    }

    echo "framework fallback security checks passed\n";
}
