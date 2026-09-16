<?php
// Describe FreePBX's database and configured filesystem layout without
// exposing credentials. With no argument, retain the local-database safety
// contract used by the automatic SELECT-only account configurator.

if ($argc > 2 || ($argc === 2 && $argv[1] !== '--describe')) {
    fwrite(STDERR, "usage: configure-database.php [--describe]\n");
    exit(2);
}
$describeOnly = $argc === 2;
require '/etc/freepbx.conf';

$host = (string) (isset($amp_conf['AMPDBHOST']) ? $amp_conf['AMPDBHOST'] : 'localhost');
$port = (string) (isset($amp_conf['AMPDBPORT']) ? $amp_conf['AMPDBPORT'] : '3306');
$socket = (string) (isset($amp_conf['AMPDBSOCK']) ? $amp_conf['AMPDBSOCK'] : '');
$name = (string) (isset($amp_conf['AMPDBNAME']) ? $amp_conf['AMPDBNAME'] : 'asterisk');
$webroot = rtrim((string) (isset($amp_conf['AMPWEBROOT']) ? $amp_conf['AMPWEBROOT'] : '/var/www/html'), '/');
$astetc = rtrim((string) (isset($amp_conf['ASTETCDIR']) ? $amp_conf['ASTETCDIR'] : '/etc/asterisk'), '/');
$astvarlib = rtrim((string) (
    isset($amp_conf['ASTVARLIBDIR']) ? $amp_conf['ASTVARLIBDIR'] : (
        isset($amp_conf['ASTVARLIB']) ? $amp_conf['ASTVARLIB'] : '/var/lib/asterisk'
    )
), '/');
$webroot = $webroot === '' ? '/' : $webroot;
$astetc = $astetc === '' ? '/' : $astetc;
$astvarlib = $astvarlib === '' ? '/' : $astvarlib;
if (!$describeOnly && $socket === '' && !in_array($host, array('localhost', '127.0.0.1'), true)) {
    fwrite(STDERR, "Automatic setup supports only a local MariaDB server. Configure a reviewed SELECT-only account manually for remote MariaDB.\n");
    exit(1);
}
if (!preg_match('/^[A-Za-z0-9_]+$/', $name)) {
    fwrite(STDERR, "FreePBX database name is not safe for automated setup.\n");
    exit(1);
}
if (!preg_match('/^[0-9]+$/', $port) || (int) $port < 1 || (int) $port > 65535) {
    fwrite(STDERR, "FreePBX AMPDBPORT is not a valid TCP port.\n");
    exit(1);
}
$socket = trim($socket);
if ($socket !== '' && ($socket[0] !== '/' || preg_match('/[\x00-\x20\x7f]/', $socket)
    || preg_match('#(?:^|/)\.\.(?:/|$)#', $socket))) {
    fwrite(STDERR, "FreePBX AMPDBSOCK is not a safe absolute path.\n");
    exit(1);
}
foreach (array('AMPWEBROOT' => $webroot, 'ASTETCDIR' => $astetc, 'ASTVARLIBDIR' => $astvarlib) as $setting => $path) {
    if ($path[0] !== '/' || preg_match('/[\x00-\x20\x7f]/', $path)
        || preg_match('#(?:^|/)\.\.(?:/|$)#', $path)) {
        fwrite(STDERR, "FreePBX ".$setting." is not safe for automated setup.\n");
        exit(1);
    }
}
echo $host."\t".$port."\t".$name;
if ($describeOnly) {
    echo "\t".$webroot."\t".$astetc."\t".$astvarlib."\t".($socket === '' ? '-' : $socket);
}
