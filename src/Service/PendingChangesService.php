<?php

namespace FreePBX\modules\Pendingchanges\Service;

use FreePBX\modules\Pendingchanges\Baseline\BaselineRepository;
use FreePBX\modules\Pendingchanges\Diff\SnapshotDiffer;
use FreePBX\modules\Pendingchanges\Security\Redactor;
use FreePBX\modules\Pendingchanges\Snapshot\DatabaseSnapshotter;
use FreePBX\modules\Pendingchanges\Snapshot\FileSnapshotter;
use FreePBX\modules\Pendingchanges\Support\PathResolver;
use FreePBX\modules\Pendingchanges\Watcher\Probe;

class PendingChangesService
{
    /**
     * Watcher-covered tables the framework-only fallback does not snapshot.
     * This is the documented delta between the external watcher's
     * DEFAULT_WATCH_TABLES (docker/custom-watcher/watcher.py) and the BMO
     * WATCH_TABLES list (Pendingchanges.class.php). The parity gate
     * (docker/test-table-parity.php) fails if either side drifts without
     * updating this list, so a watcher-less pilot can never silently claim
     * full coverage.
     */
    const FRAMEWORK_FALLBACK_UNCOVERED_TABLES = array(
        'incoming',
        'freepbx_settings',
        'outbound_route_patterns',
        'outbound_route_sequence',
        'outbound_route_trunks',
        'sipsettings',
        'kvstore_Sipsettings',
    );

    private $database;
    private $tables;
    private $paths;
    private $redactor;
    private $baseline;
    private $databaseSnapshotter;
    private $fileSnapshotter;
    private $differ;
    private $probe;

    public function __construct(
        $module,
        $database,
        array $tables,
        $maxRows,
        $baselineConfigKey,
        $legacyBaselineTable
    ) {
        $this->database = $database;
        $this->tables = $tables;
        $this->paths = new PathResolver();

        $redactor = new Redactor($this->paths);
        $this->redactor = $redactor;
        $this->baseline = new BaselineRepository(
            $module,
            $database,
            $redactor,
            $baselineConfigKey,
            $legacyBaselineTable
        );
        $this->databaseSnapshotter = new DatabaseSnapshotter(
            $database,
            $redactor,
            $tables,
            $maxRows
        );
        $this->fileSnapshotter = new FileSnapshotter($this->paths);
        $this->differ = new SnapshotDiffer($redactor);
        $this->probe = new Probe($this->paths);
    }

    public function install()
    {
        $this->baseline->migrateLegacy();
    }

    public function uninstall()
    {
        $this->baseline->delete();
    }

    public function needReload()
    {
        $statement = $this->database->prepare(
            "SELECT value FROM admin WHERE variable = 'need_reload'"
        );
        $statement->execute();

        return $statement->fetchColumn() === 'true';
    }

    public function baseline()
    {
        return $this->baseline->get();
    }

    public function seedBaseline()
    {
        if ($this->needReload()) {
            throw new \RuntimeException(
                'Cannot seed a baseline while Apply Changes is pending. '
                . 'Apply or clear the pending reload first.'
            );
        }

        $database = $this->databaseSnapshotter->capture();
        $files = $this->fileSnapshotter->capture();
        $this->baseline->save($database, $files);

        return array('tables' => count($database), 'files' => count($files));
    }

    public function status()
    {
        $probe = $this->probe->inspect();
        $watcher = $probe['status'];
        $health = $probe['health'];

        if ($watcher !== null) {
            return $this->watcherStatus($watcher, $health);
        }

        return $this->frameworkStatus($health);
    }

    public function feedback()
    {
        $path = $this->paths->asteriskVariableRoot() . '/pendingchanges-watcher/feedback.jsonl';
        if (!is_readable($path)) {
            return array(
                'schema' => 1,
                'events' => array(),
                'message' => 'No local watcher feedback ledger is available.',
            );
        }

        $events = array();
        foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: array() as $line) {
            $event = json_decode($line, true);
            if (is_array($event) && (isset($event['schema']) ? $event['schema'] : null) === 1) {
                $events[] = $event;
            }
        }

        return array(
            'schema' => 1,
            'privacy' => 'Types, counts, field names, coverage-limit reasons, and timestamps only. '
                . 'No configuration values, identifiers, hostnames, credentials, or call data.',
            'events' => $events,
        );
    }

    public function paths()
    {
        return $this->paths;
    }

    public function differ()
    {
        return $this->differ;
    }

    public function redactionKeyStatus()
    {
        return $this->redactor->keyStatus();
    }

    private function watcherStatus(array $watcher, array $health)
    {
        $files = $watcher['file_drift'];
        $current = $health['state'] === 'healthy';
        $provenance = isset($watcher['baseline_provenance'])
            && is_array($watcher['baseline_provenance'])
            ? $watcher['baseline_provenance']
            : array(
                'state' => 'uncertain',
                'reason' => 'watcher_status_does_not_report_baseline_provenance',
                'detail' => 'This watcher version cannot prove baseline continuity across service interruptions.',
            );
        $pending = $current ? $watcher['need_reload'] : $this->needReload();
        $message = $watcher['message'];

        if ($health['state'] === 'delayed') {
            $message = 'Watcher observation is delayed; current configuration state may be incomplete.';
        } elseif ($health['state'] === 'stale') {
            $message = 'Watcher results are stale. Current configuration state is unknown.';
        } elseif (strpos($health['state'], 'payload_') === 0) {
            $message = 'The installed watcher payload does not match this module; '
                . 'current full-scope coverage cannot be confirmed.';
        } elseif ((isset($provenance['state']) ? $provenance['state'] : '') !== 'trusted') {
            $message = 'Baseline provenance is uncertain after a watcher interruption; '
                . 'reported drift may span an Apply Config.';
        }

        return array(
            'pending' => $pending,
            'database' => $watcher['database_drift'],
            'astdb' => isset($watcher['astdb_drift']) ? $watcher['astdb_drift'] : array(),
            'files' => $files,
            'generated_files' => $this->differ->fileScope($files, 'generated/'),
            'module_files' => $this->differ->fileScope($files, 'module/'),
            'coverage_limitations' => isset($watcher['coverage_limitations'])
                ? $watcher['coverage_limitations']
                : array(),
            'coverage' => isset($watcher['coverage']) ? $watcher['coverage'] : array(),
            'attribution' => isset($watcher['attribution']) ? $watcher['attribution'] : array(),
            'message' => $message,
            'baseline' => $watcher['baseline_available'],
            'baseline_provenance' => $provenance,
            'captured_at' => isset($watcher['baseline_captured_at'])
                ? $watcher['baseline_captured_at']
                : null,
            'watcher_observed_at' => $watcher['observed_at'],
            'watcher' => true,
            'watcher_health' => $health,
            'data_current' => $current,
            'coverage_mode' => 'watcher',
        );
    }

    private function frameworkStatus(array $health)
    {
        $baseline = $this->baseline->get();
        $pending = $this->needReload();
        if (!$baseline) {
            return array(
                'pending' => $pending,
                'database' => array(),
                'astdb' => array(),
                'files' => array(),
                'generated_files' => array(),
                'module_files' => array(),
                'coverage_limitations' => array(),
                'coverage' => array(),
                'attribution' => $this->unavailableAttribution($pending),
                'baseline' => false,
                'baseline_provenance' => array(
                    'state' => 'unavailable',
                    'reason' => 'baseline_not_available',
                ),
                'captured_at' => null,
                'message' => 'No applied baseline has been seeded; full watcher coverage is unavailable.',
                'watcher' => false,
                'watcher_health' => $health,
                'data_current' => false,
                'coverage_mode' => 'framework',
            );
        }

        $database = $this->differ->database(
            $baseline['database'],
            $this->databaseSnapshotter->capture()
        );
        $files = $this->differ->files(
            $baseline['files'],
            $this->fileSnapshotter->capture()
        );
        $hasDrift = !empty($database) || !empty($files);
        if ($hasDrift) {
            $message = $pending
                ? 'Configuration drift detected by the framework-only fallback; watcher coverage is degraded.'
                : 'Framework-only drift detected; watcher coverage is degraded.';
        } else {
            $message = $pending
                ? 'Reload requested; full origin analysis is unavailable because watcher health is degraded.'
                : 'Watcher health is degraded; current full-scope configuration state is unknown.';
        }

        return array(
            'pending' => $pending,
            'database' => $database,
            'files' => $files,
            'message' => $message,
            'generated_files' => $this->differ->fileScope($files, 'generated/'),
            'module_files' => $this->differ->fileScope($files, 'module/'),
            'coverage_limitations' => array(),
            'astdb' => array(),
            'coverage' => array(
                'database_tables' => $this->tables,
                'database_exclusions' => array('modules.modulename=pendingchanges'),
                'framework_fallback_uncovered_tables' => self::FRAMEWORK_FALLBACK_UNCOVERED_TABLES,
                'astdb_families' => array(),
                'generated_files' => $this->paths->asteriskConfigRoot() . '/*.conf',
                'module_release_markers' => 'module.xml and module.sig for all modules except pendingchanges',
            ),
            'attribution' => $this->unavailableAttribution($pending),
            'baseline' => true,
            'baseline_provenance' => array(
                'state' => 'degraded',
                'reason' => 'framework_only_fallback',
                'detail' => 'The external watcher is unavailable; full baseline continuity cannot be proven.',
            ),
            'captured_at' => $baseline['captured_at'],
            'watcher' => false,
            'watcher_health' => $health,
            'data_current' => false,
            'coverage_mode' => 'framework',
        );
    }

    private function unavailableAttribution($pending)
    {
        return array(
            'enabled' => false,
            'confidence' => $pending ? 'unavailable' : 'none',
            'actors' => array(),
            'requests' => array(),
            'note' => 'Authenticated request correlation requires the external watcher sensor.',
            'caveat' => 'Request correlation is evidence of who may have staged work, '
                . 'not proof that an account caused each reported state change.',
        );
    }
}
