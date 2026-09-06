<?php
// Describe FreePBX's database without exposing credentials. With no argument,
// retain the standalone configurator's local-database safety contract. The
// embedded installer uses --describe to recognize remote databases and leave
// their watcher service disabled for reviewed manual configuration.

if ($argc > 2 || ($argc === 2 && $argv[1] !== '--describe')) {
    fwrite(STDERR, "usage: configure-database.php [--describe]\n");
    exit(2);
}
$describeOnly = $argc === 2;
require '/etc/freepbx.conf';

$host = (string) (isset($amp_conf['AMPDBHOST']) ? $amp_conf['AMPDBHOST'] : 'localhost');
$name = (string) (isset($amp_conf['AMPDBNAME']) ? $amp_conf['AMPDBNAME'] : 'asterisk');
$webroot = rtrim((string) (isset($amp_conf['AMPWEBROOT']) ? $amp_conf['AMPWEBROOT'] : '/var/www/html'), '/');
if ($webroot === '') {
    $webroot = '/';
}
if (!$describeOnly && !in_array($host, ['localhost', '127.0.0.1'], true)) {
    fwrite(STDERR, "Automatic setup supports only a local MariaDB server. Configure a reviewed SELECT-only account manually for remote MariaDB.\n");
    exit(1);
}
if (!preg_match('/^[A-Za-z0-9_]+$/', $name)) {
    fwrite(STDERR, "FreePBX database name is not safe for automated setup.\n");
    exit(1);
}
if ($webroot[0] !== '/' || preg_match('/[\x00-\x20\x7f]/', $webroot)
    || preg_match('#(?:^|/)\.\.(?:/|$)#', $webroot)) {
    fwrite(STDERR, "FreePBX AMPWEBROOT is not safe for automated setup.\n");
    exit(1);
}
echo $host."\t".$name;
if ($describeOnly) {
    echo "\t".$webroot;
}
