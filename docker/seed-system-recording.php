<?php
// Exercise the System Recordings BMO inside the disposable Docker lab only.
if (!is_file('/.dockerenv')) {
    fwrite(STDERR, "Refusing to run outside Docker.\n");
    exit(2);
}

require '/etc/freepbx.conf';

$action = getenv('FREEPBX_RECORDING_ACTION') ?: 'add';
$name = 'WhatChanged disposable recording';
$database = FreePBX::Database();
$find = $database->prepare('SELECT id FROM recordings WHERE displayname = ? ORDER BY id');
$find->execute(array($name));
$ids = $find->fetchAll(PDO::FETCH_COLUMN);
$recordings = FreePBX::Recordings();

if ($action === 'cleanup' || $action === 'delete') {
    foreach ($ids as $id) {
        $recordings->delRecording((int) $id);
    }
    echo "Removed disposable System Recording fixture.\n";
    exit(0);
}

if ($action === 'add') {
    foreach ($ids as $id) {
        $recordings->delRecording((int) $id);
    }
    $recordings->addRecording(
        $name,
        'Initial WhatChanged coverage fixture',
        'whatchanged-alpha-fixture',
        0,
        '',
        'en'
    );
    echo "Created disposable System Recording fixture.\n";
    exit(0);
}

if ($action === 'update' && count($ids) === 1) {
    $recordings->updateRecording(
        (int) $ids[0],
        $name,
        'Updated WhatChanged coverage fixture',
        'whatchanged-alpha-fixture',
        0,
        '',
        'en'
    );
    echo "Updated disposable System Recording fixture.\n";
    exit(0);
}

throw new RuntimeException('Disposable System Recording fixture is not in the expected state.');
