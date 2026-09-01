<?php
$path = $argv[1] ?? sys_get_temp_dir().'/what-changed-request-audit.jsonl';
putenv('WHAT_CHANGED_ATTRIBUTION_LOG='.$path);
@unlink($path);
require __DIR__.'/../deploy/what-changed-request-audit.php';

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
$event = json_decode($lines[0], true, 512, JSON_THROW_ON_ERROR);
if ($event['username'] !== 'smoke_admin' || $event['operation'] !== 'stage' || $event['type'] !== 'extensions') {
    throw new RuntimeException('Unexpected request breadcrumb');
}
if (str_contains($lines[0], 'must-never-be-recorded') || isset($event['secret'])) {
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
$_REQUEST = ['display' => 'modules', 'action' => 'disable'];
whatchanged_audit_request();
$lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
if (count($lines ?: []) !== 2) {
    throw new RuntimeException('Destructive GET was not recorded');
}
echo "request audit checks passed\n";
