<?php
if (!defined('FREEPBX_IS_AUTH')) {
    die('No direct script access allowed');
}

function pendingchanges_install() {
    global $db;
    $db->query('CREATE TABLE IF NOT EXISTS pendingchanges_baseline (
        id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
        database_snapshot LONGTEXT NOT NULL,
        file_snapshot LONGTEXT NOT NULL,
        captured_at DATETIME NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4');
}

function pendingchanges_uninstall() {
    global $db;
    $db->query('DROP TABLE IF EXISTS pendingchanges_baseline');
}
