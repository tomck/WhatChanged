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
    foreach (['status', 'redactionKeyStatus'] as $method) {
        if (!$class->hasMethod($method)
            || $class->getMethod($method)->getDeclaringClass()->getName() !== $class->getName()) {
            throw new RuntimeException('FreePBX BMO adapter does not expose ' . $method);
        }
    }

    $redactor = 'FreePBX\\modules\\Pendingchanges\\Security\\Redactor';
    if (!$redactor::sensitiveField('data', ['variable' => 'TURN_PASSWORD', 'data' => 'private'])) {
        throw new RuntimeException('Generic semantic secret was not classified');
    }
    if ($redactor::sensitiveField('value', ['name' => 'secretary', 'value' => 'visible'])) {
        throw new RuntimeException('Innocent semantic value was classified as secret');
    }
    foreach (['AMPMGRPASS', 'ASTMGRPASS', 'AMPDBPASS', 'md5_cred', 'CERTKEY', 'SSLPASS'] as $field) {
        if (!$redactor::sensitiveField($field, [$field => 'private'])) {
            throw new RuntimeException('Known credential field was not classified: ' . $field);
        }
    }
    if (!$redactor::sensitiveField(
        'data',
        ['keyword' => 'register', 'data' => 'account:private-password@sip.example.invalid']
    )) {
        throw new RuntimeException('SIP registration material was not classified');
    }
    if (!$redactor::sensitiveField(
        'value',
        ['keyword' => 'AMPMGRPASS', 'name' => 'Asterisk Manager password', 'value' => 'private']
    )) {
        throw new RuntimeException('Exact semantic secret in a multi-column row was not classified');
    }
    if ($redactor::sensitiveField('match_pattern_pass', ['match_pattern_pass' => '18005551212'])) {
        throw new RuntimeException('Outbound-route match pattern was misclassified as a credential');
    }
    $endpointToken = ['ext' => '7999', 'dpma_token_seq' => 'private-endpoint-token'];
    if (!$redactor::sensitiveField('dpma_token_seq', $endpointToken)) {
        throw new RuntimeException('Endpoint Manager token sequence was not classified as sensitive');
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
    $publicEndpoint = $redactorInstance->publicRow($endpointToken);
    if ($publicEndpoint['dpma_token_seq'] !== '[redacted]') {
        throw new RuntimeException('Endpoint Manager token sequence was exposed');
    }
    $differClass = 'FreePBX\\modules\\Pendingchanges\\Diff\\SnapshotDiffer';
    $differ = new $differClass($redactorInstance);
    $diff = $differ->database($before, $after);
    $published = json_encode($diff);
    if (strpos($published, '[redacted]') === false || strpos($published, $prefix) !== false) {
        throw new RuntimeException('Framework diff exposed a protected fingerprint');
    }

    // Redaction key lifecycle is read-only: absent before the first snapshot,
    // ok with owner-only permissions, insecure when group/other-readable,
    // invalid when corrupt — each with an operator remedy. The unreadable
    // state cannot be simulated as root and is covered by inspection.
    $keyDir = sys_get_temp_dir() . '/pendingchanges-keystatus-' . getmypid();
    @mkdir($keyDir, 0700, true);
    $GLOBALS['amp_conf']['ASTVARLIBDIR'] = $keyDir;
    $watcherKeyDir = $keyDir . '/pendingchanges-watcher';
    mkdir($watcherKeyDir, 0700, true);
    $keyPath = $watcherKeyDir . '/redaction.key';
    $keyReport = $redactorInstance->keyStatus();
    if ($keyReport['state'] !== 'absent' || $keyReport['path'] !== $keyPath) {
        throw new RuntimeException('Missing redaction key was not reported as absent');
    }
    file_put_contents($keyPath, str_repeat('c', 64));
    chmod($keyPath, 0600);
    $keyReport = $redactorInstance->keyStatus();
    if ($keyReport['state'] !== 'ok') {
        throw new RuntimeException('Valid redaction key was not reported as ok');
    }
    chmod($keyPath, 0644);
    $keyReport = $redactorInstance->keyStatus();
    if ($keyReport['state'] !== 'insecure') {
        throw new RuntimeException('Group-readable redaction key was not reported as insecure');
    }
    file_put_contents($keyPath, 'not-a-key');
    chmod($keyPath, 0600);
    $keyReport = $redactorInstance->keyStatus();
    if ($keyReport['state'] !== 'invalid' || $keyReport['remedy'] === '') {
        throw new RuntimeException('Corrupt redaction key was not reported as invalid with a remedy');
    }
    unlink($keyPath);
    rmdir($watcherKeyDir);
    rmdir($keyDir);

    echo "framework fallback security checks passed\n";
}
