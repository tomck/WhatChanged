<?php
// Find the local FreePBX database name without exposing credentials. Root's
// local MariaDB socket creates the dedicated SELECT-only watcher account.

if ($argc !== 1) {
    fwrite(STDERR, "usage: configure-database.php\n");
    exit(2);
}
require '/etc/freepbx.conf';

$host = (string) ($amp_conf['AMPDBHOST'] ?? 'localhost');
$name = (string) ($amp_conf['AMPDBNAME'] ?? 'asterisk');
if (!in_array($host, ['localhost', '127.0.0.1'], true)) {
    fwrite(STDERR, "The packaged setup supports only a local MariaDB server. Configure a reviewed SELECT-only account manually for remote MariaDB.\n");
    exit(1);
}
if (!preg_match('/^[A-Za-z0-9_]+$/', $name)) {
    fwrite(STDERR, "FreePBX database name is not safe for automated setup.\n");
    exit(1);
}
echo $host."\t".$name;
