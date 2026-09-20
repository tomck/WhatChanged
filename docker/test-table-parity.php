<?php
// Fail-closed parity gate: the framework-only fallback table list
// (Pendingchanges::WATCH_TABLES) must be a subset of the external watcher's
// DEFAULT_WATCH_TABLES, and the remainder must exactly match the documented
// FRAMEWORK_FALLBACK_UNCOVERED_TABLES constant that the fallback report
// publishes in its coverage contract. Any drift on either side — a table
// added to one list but not the other, or an unlisted gap — fails loudly
// instead of letting a watcher-less pilot silently claim full coverage.
//
// usage: test-table-parity.php extracted-module-directory watcher.py
// Runs on PHP 5.6 through 8.x; keep this file free of post-5.6 syntax.

if ($argc !== 3) {
    fwrite(STDERR, "usage: test-table-parity.php extracted-module-directory watcher.py\n");
    exit(2);
}

$moduleDir = $argv[1];
$watcherPath = $argv[2];

function parity_fail($message)
{
    fwrite(STDERR, 'table parity: ' . $message . "\n");
    exit(1);
}

function parity_quoted_list($source, $startMarker)
{
    $start = strpos($source, $startMarker);
    if ($start === false) {
        parity_fail('marker not found: ' . $startMarker);
    }
    $open = strpos($source, '(', $start);
    if ($open === false) {
        parity_fail('list not opened after: ' . $startMarker);
    }
    $depth = 0;
    $length = strlen($source);
    for ($i = $open; $i < $length; $i++) {
        if ($source[$i] === '(') {
            $depth++;
        } elseif ($source[$i] === ')') {
            $depth--;
            if ($depth === 0) {
                $body = substr($source, $open + 1, $i - $open - 1);
                break;
            }
        }
    }
    if (!isset($body)) {
        parity_fail('list not closed after: ' . $startMarker);
    }
    // Strip full-line comments so commented-out table names cannot count.
    $lines = explode("\n", $body);
    $code = array();
    foreach ($lines as $line) {
        $stripped = ltrim($line);
        if ($stripped === '' || $stripped[0] === '#') {
            continue;
        }
        $code[] = $line;
    }
    preg_match_all("/'([A-Za-z0-9_]+)'/", implode("\n", $code), $matches);

    return array_values(array_unique($matches[1]));
}

$bmoPath = $moduleDir . '/Pendingchanges.class.php';
$servicePath = $moduleDir . '/src/Service/PendingChangesService.php';
foreach (array($bmoPath, $servicePath, $watcherPath) as $required) {
    if (!is_readable($required)) {
        parity_fail('unreadable input: ' . $required);
    }
}

$fallback = parity_quoted_list(
    file_get_contents($bmoPath),
    'const WATCH_TABLES = array('
);
$declaredGaps = parity_quoted_list(
    file_get_contents($servicePath),
    'const FRAMEWORK_FALLBACK_UNCOVERED_TABLES = array('
);
$watcher = parity_quoted_list(
    file_get_contents($watcherPath),
    'DEFAULT_WATCH_TABLES = ('
);

if (count($fallback) === 0 || count($watcher) === 0) {
    parity_fail('parsed an empty table list; markers may have moved');
}

$missingFromWatcher = array_values(array_diff($fallback, $watcher));
if (count($missingFromWatcher) > 0) {
    parity_fail(
        'framework fallback watches tables the watcher does not cover: '
        . implode(', ', $missingFromWatcher)
    );
}

$computedGaps = array_values(array_diff($watcher, $fallback));
sort($computedGaps);
$sortedDeclared = $declaredGaps;
sort($sortedDeclared);
if ($computedGaps !== $sortedDeclared) {
    parity_fail(
        'watcher-only tables [' . implode(', ', $computedGaps) . '] do not match '
        . 'FRAMEWORK_FALLBACK_UNCOVERED_TABLES [' . implode(', ', $sortedDeclared) . ']; '
        . 'update PendingChangesService and the fallback coverage label together'
    );
}

echo 'table parity: fallback ' . count($fallback) . ' tables, watcher '
    . count($watcher) . ' tables, ' . count($computedGaps) . ' documented gaps'
    . PHP_EOL;
