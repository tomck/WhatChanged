<?php
$path = isset($argv[1]) ? $argv[1] : sys_get_temp_dir().'/what-changed-request-audit.jsonl';
putenv('WHAT_CHANGED_ATTRIBUTION_LOG='.$path);
@unlink($path);
require __DIR__.'/../deploy/what-changed-request-audit.php';

if (!whatchanged_is_freepbx_admin_script('/srv/freepbx-web/admin/config.php', '/admin/config.php')) {
    throw new RuntimeException('Custom AMPWEBROOT admin request was not recognized');
}
if (whatchanged_is_freepbx_admin_script('/srv/other-app/index.php', '/index.php')) {
    throw new RuntimeException('Non-FreePBX request was recognized as an admin request');
}

$_SESSION = ['AMP_user' => (object) ['username' => 'smoke_admin']];
$_SERVER['REQUEST_METHOD'] = 'POST';
$_SERVER['SCRIPT_NAME'] = '/admin/config.php';
$_REQUEST = [
    'display' => 'extensions',
    'type' => 'extensions',
    'action' => 'edit',
];
$_POST = [
    'display' => 'extensions',
    'type' => 'extensions',
    'action' => 'edit',
    'secret' => 'must-never-be-recorded',
];
http_response_code(200);
whatchanged_audit_request();

$lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (count($lines ?: []) !== 1) {
    throw new RuntimeException('Expected one request breadcrumb');
}
$event = json_decode($lines[0], true);
if (!is_array($event)) {
    throw new RuntimeException('Request breadcrumb was not valid JSON');
}
if ($event['username'] !== 'smoke_admin' || $event['operation'] !== 'stage' || $event['type'] !== 'extensions') {
    throw new RuntimeException('Unexpected request breadcrumb');
}
if (strpos($lines[0], 'must-never-be-recorded') !== false || isset($event['secret'])) {
    throw new RuntimeException('Request values leaked into breadcrumb');
}

// FreePBX periodically issues this authenticated GET in the background. It is
// not evidence that the account staged anything and must never add an actor.
$_SERVER['REQUEST_METHOD'] = 'GET';
$_REQUEST = ['command' => 'authping'];
$_POST = [];
whatchanged_audit_request();
$lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (count($lines ?: []) !== 1) {
    throw new RuntimeException('Read-only authping was recorded as a write');
}

$_SERVER['REQUEST_METHOD'] = 'POST';
$_REQUEST = ['command' => 'navbarToogle'];
whatchanged_audit_request();
$lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (count($lines ?: []) !== 1) {
    throw new RuntimeException('Navbar housekeeping was recorded as a write');
}

// Preserve coverage for the rare administrative GET paths that really are
// state-changing.
$_SERVER['REQUEST_METHOD'] = 'GET';
$_REQUEST = ['display' => 'modules', 'action' => 'disable'];
whatchanged_audit_request();
$lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (count($lines ?: []) !== 2) {
    throw new RuntimeException('Destructive GET was not recorded');
}

// Crossing the cap retains the newest complete historical events instead of
// erasing the entire attribution interval.
$retained = json_encode([
    'schema' => 1,
    'event_id' => 'must-survive-compaction',
    'finished_at' => 1,
    'username' => 'fixture',
])."\n";
file_put_contents($path, str_repeat($retained, (int) ceil(1100000 / strlen($retained))));
$_SERVER['REQUEST_METHOD'] = 'POST';
$_REQUEST = ['display' => 'extensions', 'action' => 'edit'];
whatchanged_audit_request();
$compacted = file_get_contents($path);
if (!is_string($compacted)
    || strpos($compacted, 'must-survive-compaction') === false
    || strpos($compacted, '"display":"extensions"') === false
    || strlen($compacted) >= 1048576
) {
    throw new RuntimeException('Attribution compaction did not retain bounded recent evidence');
}
echo "request audit checks passed\n";
