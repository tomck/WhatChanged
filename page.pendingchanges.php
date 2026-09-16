<?php

if (!defined('FREEPBX_IS_AUTH')) {
    die('No direct script access allowed');
}

require_once __DIR__ . '/autoload.php';

$controller = new \FreePBX\modules\Pendingchanges\Presentation\PageController(
    FreePBX::Pendingchanges(),
    __DIR__
);
$controller->render($_SERVER, $_POST);
