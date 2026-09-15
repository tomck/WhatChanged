<?php
// Disposable-lab regression for the 17.0.1.6 custom-table to BMO kvstore
// migration. No production PBX is ever targeted by this script.
require '/etc/freepbx.conf';

$service = FreePBX::Pendingchanges();
$database = FreePBX::Database();
$originalBaseline = $service->getConfig('framework_fallback_baseline');
$service->delConfig('framework_fallback_baseline');
$database->exec('DROP TABLE IF EXISTS pendingchanges_baseline');
$database->exec('CREATE TABLE pendingchanges_baseline (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    database_snapshot LONGTEXT NOT NULL,
    file_snapshot LONGTEXT NOT NULL,
    captured_at DATETIME NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
$statement = $database->prepare(
    'INSERT INTO pendingchanges_baseline (id, database_snapshot, file_snapshot, captured_at) VALUES (1, ?, ?, ?)'
);
$statement->execute(array(
    json_encode(array('users' => array(array('extension' => '7001', 'name' => 'Migration fixture')))),
    json_encode(array('generated/migration.conf' => 'fixture-digest')),
    '2026-01-02 03:04:05',
));

$service->install();
$baseline = $service->baseline();
if (!is_array($baseline)
    || $baseline['database']['users'][0]['extension'] !== '7001'
    || $baseline['files']['generated/migration.conf'] !== 'fixture-digest'
    || $baseline['captured_at'] !== '2026-01-02 03:04:05'
) {
    throw new RuntimeException('Legacy framework baseline was not preserved in BMO storage');
}
$table = $database->query("SHOW TABLES LIKE 'pendingchanges_baseline'")->fetchColumn();
if ($table !== false) {
    throw new RuntimeException('Legacy one-row baseline table was not removed after migration');
}

// Restore the exact pre-test module state. Module Admin may legitimately have
// left Apply Config pending, in which case creating a new baseline must remain
// forbidden.
if ($originalBaseline) {
    $service->setConfig('framework_fallback_baseline', $originalBaseline);
} else {
    $service->delConfig('framework_fallback_baseline');
}
echo "framework baseline BMO migration passed\n";
