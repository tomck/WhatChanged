# Pending Changes Tripwire 17.0.2.0 alpha

This release reorganizes the FreePBX module around a PSR-4-style internal
class structure and PSR-12 formatting while preserving the established
FreePBX 14–17 behavior and PHP 5.6 compatibility floor.

The conventional `Pendingchanges.class.php` BMO and
`page.pendingchanges.php` page files remain as thin FreePBX entry points.
Baseline persistence, database and file snapshots, redaction, diffing, watcher
health, request handling, presentation, and HTML views now live in focused
components under `src/` and `views/`.

The watcher remains version 0.1.6. Its observation protocol, explicit
installation boundary, SELECT-only database account, coverage contract,
redaction behavior, and Apply Config baseline lifecycle are unchanged.

The identical archive passed the complete disposable FreePBX 17 lab gate plus
real-image Module Admin, staged-drift, Apply Config, and clean-baseline gates
for FreePBX 14, 15, and 16. The PHP source also passes the project's PSR-12
PHP_CodeSniffer ruleset and syntax checks on PHP 5.6, 7.4, and 8.2.
