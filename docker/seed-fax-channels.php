<?php
// Stage a Fax Configuration channel-limit fixture only in the Docker lab.
if (!is_file('/.dockerenv')) {
    fwrite(STDERR, "Refusing to run outside Docker.\n");
    exit(2);
}

require '/etc/freepbx.conf';

$action = getenv('FREEPBX_FAX_ACTION') ?: 'set';
$database = FreePBX::Database();

if ($action === 'cleanup') {
    $statement = $database->prepare("DELETE FROM fax_details WHERE `key` = 'concurrentfax'");
    $statement->execute();
    if ($statement->rowCount() > 0) {
        needreload();
    }
    echo "Removed disposable concurrent-fax fixture.\n";
    exit(0);
}

$value = getenv('FREEPBX_FAX_CHANNELS') ?: '1';
if (!preg_match('/^[1-9][0-9]*$/', $value)) {
    throw new RuntimeException('Fax channel fixture must be a positive integer.');
}

FreePBX::Fax()->setSettings(['concurrentfax' => $value]);
echo 'Staged disposable concurrent fax channels='.$value.".\n";
