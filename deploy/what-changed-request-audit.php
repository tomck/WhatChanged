<?php
/**
 * WhatChanged authenticated-request breadcrumb sensor.
 *
 * This file is loaded only by Apache's PHP configuration. It records bounded,
 * value-free metadata for successful authenticated FreePBX write requests so
 * the state watcher can offer cautious actor attribution. It never records
 * form values, cookies, session identifiers, credentials, or HTTP headers.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

if (!function_exists('whatchanged_audit_scalar')) {
    function whatchanged_audit_scalar($value, int $limit = 96): string
    {
        if (!is_scalar($value)) {
            return '';
        }
        $value = preg_replace('/[^A-Za-z0-9_.:|\/-]+/', '_', (string) $value);
        return substr((string) $value, 0, $limit);
    }

    function whatchanged_audit_username(): string
    {
        $user = $_SESSION['AMP_user'] ?? null;
        if (!is_object($user)) {
            return '';
        }
        if (isset($user->username)) {
            return whatchanged_audit_scalar($user->username, 128);
        }
        if (method_exists($user, 'getUsername')) {
            return whatchanged_audit_scalar($user->getUsername(), 128);
        }
        return '';
    }

    function whatchanged_audit_request(): void
    {
        $method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
        $request = is_array($_REQUEST ?? null) ? $_REQUEST : [];
        $command = whatchanged_audit_scalar($request['command'] ?? '');
        $handler = whatchanged_audit_scalar($request['handler'] ?? '');
        $action = whatchanged_audit_scalar($request['action'] ?? '');
        $display = whatchanged_audit_scalar($request['display'] ?? '');
        $module = whatchanged_audit_scalar($request['module'] ?? '');
        $type = whatchanged_audit_scalar($request['type'] ?? '');
        $isApply = $command === 'reload' || $handler === 'reload';
        $isWrite = in_array($method, ['POST', 'PUT', 'PATCH', 'DELETE'], true);
        $readOnlyCommands = ['authping', 'scheduler', 'navbartoogle', 'check-and-set-language'];

        // FreePBX sends some UI housekeeping through POST. Request method
        // alone does not make navbar toggles or keep-alive checks evidence of
        // staged PBX configuration.
        if (in_array(strtolower($command), $readOnlyCommands, true)) {
            return;
        }

        // A few FreePBX administrative operations are intentionally exposed
        // as named GET requests. Keep only the small destructive allowlist;
        // background/read-only commands such as authping are not evidence
        // that an administrator staged a configuration change.
        $namedOperation = strtolower(implode('_', [$action, $command, $handler]));
        $isDestructiveGet = !$isWrite && preg_match(
            '/(^|[_-])(delete|del|remove|enable|disable|install|uninstall|upgrade)($|[_-])/',
            $namedOperation
        ) === 1;

        // Do not turn authentication attempts, page views, or periodic AJAX
        // checks into attribution evidence.
        if (!$isWrite && !$isApply && !$isDestructiveGet) {
            return;
        }
        if (isset($_POST['username']) || isset($_POST['password'])) {
            return;
        }
        $username = whatchanged_audit_username();
        if ($username === '') {
            return;
        }
        $status = http_response_code();
        if ($status !== false && $status >= 400) {
            return;
        }

        $path = getenv('WHAT_CHANGED_ATTRIBUTION_LOG');
        if (!$path) {
            $path = '/var/lib/asterisk/pendingchanges-attribution/requests.jsonl';
        }
        $directory = dirname($path);
        if (!is_dir($directory) || !is_writable($directory)) {
            return;
        }

        try {
            $eventId = bin2hex(random_bytes(12));
        } catch (Throwable $error) {
            $eventId = hash('sha256', microtime(true).'-'.getmypid().'-'.$username);
        }
        $event = [
            'schema' => 1,
            'event_id' => $eventId,
            'finished_at' => microtime(true),
            'username' => $username,
            'operation' => $isApply ? 'apply' : 'stage',
            'method' => $method,
            'script' => whatchanged_audit_scalar(basename((string) ($_SERVER['SCRIPT_NAME'] ?? ''))),
            'display' => $display,
            'module' => $module,
            'type' => $type,
            'action' => $action,
            'command' => $command,
            'handler' => $handler,
            'http_status' => $status === false ? 200 : $status,
        ];
        $encoded = json_encode($event, JSON_UNESCAPED_SLASHES);
        if (!is_string($encoded)) {
            return;
        }

        // The breadcrumb file is intentionally bounded. At roughly 300 bytes
        // per request, one MiB retains thousands of rare administrative writes.
        $handle = @fopen($path, 'c+');
        if ($handle === false) {
            return;
        }
        if (flock($handle, LOCK_EX)) {
            $stat = fstat($handle);
            if (($stat['size'] ?? 0) > 1048576) {
                ftruncate($handle, 0);
                rewind($handle);
            } else {
                fseek($handle, 0, SEEK_END);
            }
            fwrite($handle, $encoded."\n");
            fflush($handle);
            flock($handle, LOCK_UN);
        }
        fclose($handle);
        @chmod($path, 0640);
    }
}

// auto_prepend_file runs before FreePBX restores authentication. The shutdown
// callback runs after gui_auth.php and the requested module handler complete.
if (PHP_SAPI !== 'cli' && str_starts_with((string) ($_SERVER['SCRIPT_FILENAME'] ?? ''), '/var/www/html/admin/')) {
    register_shutdown_function('whatchanged_audit_request');
}
