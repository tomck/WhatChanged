<?php
// Create/update/remove a disposable User Management UCP assignment entirely
// inside the Docker lab. Never install or invoke this helper on a real PBX.
if (!is_file('/.dockerenv')) {
    fwrite(STDERR, "Refusing to run outside Docker.\n");
    exit(2);
}

require '/etc/freepbx.conf';

$action = getenv('FREEPBX_USERMAN_ACTION') ?: 'assign';
$username = 'whatchanged_alpha_fixture';
$userman = FreePBX::Userman();
$user = $userman->getUserByUsername($username);

if ($action === 'cleanup') {
    if (!empty($user['id'])) {
        $userman->deleteUserByID((int) $user['id']);
        needreload();
    }
    echo "Removed disposable User Management fixture.\n";
    exit(0);
}

if ($action === 'create') {
    if (empty($user['id'])) {
        $result = $userman->addUser(
            $username,
            bin2hex(random_bytes(24)),
            'none',
            'WhatChanged disposable User Management fixture'
        );
        if (empty($result['status']) || empty($result['id'])) {
            throw new RuntimeException('Could not create disposable User Management fixture.');
        }
        needreload();
    }
    echo "Created disposable User Management fixture.\n";
    exit(0);
}

if (empty($user['id'])) {
    throw new RuntimeException('Disposable User Management fixture does not exist.');
}

$assignments = $action === 'update' ? ['7999', '7998'] : ['7999'];
$userman->setModuleSettingByID((int) $user['id'], 'ucp|Settings', 'assigned', $assignments);
needreload();
echo 'Staged disposable UCP assignment action: '.$action.".\n";
