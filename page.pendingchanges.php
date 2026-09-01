<?php
if (!defined('FREEPBX_IS_AUTH')) {
    die('No direct script access allowed');
}
$tripwire = FreePBX::Pendingchanges();
$notice = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['seed_baseline'])) {
    try {
        $result = $tripwire->seedBaseline();
        $notice = '<div class="alert alert-success">Applied baseline saved ('.(int) $result['tables'].' tables, '.(int) $result['files'].' files).</div>';
    } catch (\Throwable $e) {
        $notice = '<div class="alert alert-danger">'.htmlentities($e->getMessage()).'</div>';
    }
}
$status = $tripwire->status();

function pendingchanges_h($value): string {
    return htmlentities((string) $value, ENT_QUOTES, 'UTF-8');
}

function pendingchanges_identity(string $table, array $row): string {
    if ($table === 'userman_users_settings') {
        $user = (string) ($row['username'] ?? ('User '.($row['uid'] ?? 'record')));
        return $user.' — '.(string) ($row['module'] ?? 'setting').' / '.(string) ($row['key'] ?? 'value');
    }
    foreach (['extension', 'id', 'account', 'grpnum', 'device', 'user'] as $field) {
        if (array_key_exists($field, $row) && $row[$field] !== '') {
            $label = (string) $row[$field];
            if (!empty($row['name'])) {
                $label .= ' — '.(string) $row['name'];
            } elseif (!empty($row['description'])) {
                $label .= ' — '.(string) $row['description'];
            }
            return $label;
        }
    }
    return $table.' record';
}

function pendingchanges_table_label(string $table): string {
    if ($table === 'fax_details') {
        return 'Fax Configuration';
    }
    if ($table === 'userman_users') {
        return 'User Management users';
    }
    if ($table === 'userman_users_settings') {
        return 'User Management / UCP settings';
    }
    return ucwords(str_replace('_', ' ', $table));
}

function pendingchanges_request_target(array $event): string {
    if (($event['operation'] ?? '') === 'apply') {
        return 'Apply Config';
    }
    foreach (['display', 'type', 'module', 'action', 'command', 'handler', 'script'] as $field) {
        if (!empty($event[$field])) {
            return (string) $event[$field];
        }
    }
    return 'FreePBX admin request';
}

function pendingchanges_fax_setting_label(string $key): string {
    $labels = [
        'concurrentfax' => 'Concurrent fax channels',
        'ecm' => 'Error correction mode',
        'fax_rx_email' => 'Fax receive email',
        'force_detection' => 'Always generate detection code',
        'headerinfo' => 'Default fax header',
        'legacy_mode' => 'Legacy mode',
        'localstationid' => 'Local station identifier',
        'maxpages' => 'Maximum pages',
        'maxrate' => 'Maximum transfer rate',
        'minrate' => 'Minimum transfer rate',
        'papersize' => 'Default paper size',
        'sender_address' => 'Outgoing email address',
    ];
    return $labels[$key] ?? ucwords(str_replace('_', ' ', $key));
}

function pendingchanges_record_id(string $kind, array $item): string {
    if ($kind === 'updated') {
        return (string) ($item['key'] ?? 'record');
    }
    foreach (['extension', 'id'] as $field) {
        if (isset($item[$field]) && $item[$field] !== '') {
            return (string) $item[$field];
        }
    }
    return 'record';
}

function pendingchanges_extension_changes(array $database): array {
    $merged = [];
    foreach (['users' => 'Extension', 'devices' => 'Endpoint device'] as $table => $label) {
        foreach (['added', 'removed', 'updated'] as $kind) {
            foreach (($database[$table][$kind] ?? []) as $item) {
                $id = pendingchanges_record_id($kind, $item);
                if (!isset($merged[$kind][$id])) {
                    $merged[$kind][$id] = ['id' => $id, 'name' => '', 'evidence' => []];
                }
                $row = $kind === 'updated' ? [] : $item;
                $name = $row['name'] ?? $row['description'] ?? '';
                if ($name !== '' && $merged[$kind][$id]['name'] === '') {
                    $merged[$kind][$id]['name'] = (string) $name;
                }
                $merged[$kind][$id]['evidence'][$label] = $kind === 'updated' ? ($item['fields'] ?? []) : $item;
            }
        }
    }
    foreach ($merged as $kind => $items) {
        ksort($items, SORT_NATURAL);
        $merged[$kind] = array_values($items);
    }
    return $merged;
}

function pendingchanges_render_record(string $kind, string $table, array $item): void {
    $symbols = ['added' => '+', 'removed' => '−', 'updated' => '~'];
    $row = $kind === 'updated' ? ['id' => $item['key'] ?? 'record'] : $item;
    $details = $kind === 'updated' ? ($item['fields'] ?? []) : $item;
    if ($kind === 'updated' && $table === 'userman_users_settings') {
        $title = pendingchanges_identity($table, $item['identity'] ?? []);
    } elseif ($table === 'fax_details') {
        $title = pendingchanges_fax_setting_label((string) ($item['key'] ?? 'record'));
    } else {
        $title = $kind === 'updated' ? (string) ($item['key'] ?? 'record') : pendingchanges_identity($table, $row);
    }
    ?>
    <div class="pendingchanges-change pendingchanges-<?= pendingchanges_h($kind) ?>">
      <span class="pendingchanges-symbol" aria-hidden="true"><?= $symbols[$kind] ?></span>
      <strong><?= pendingchanges_h($title) ?></strong>
      <span class="pendingchanges-kind"><?= pendingchanges_h(ucfirst($kind)) ?></span>
      <details><summary>Evidence</summary><pre><?= pendingchanges_h(json_encode($details, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)) ?></pre></details>
    </div>
    <?php
}

function pendingchanges_render_extension(string $kind, array $item): void {
    $symbols = ['added' => '+', 'removed' => '−', 'updated' => '~'];
    $title = $item['id'].($item['name'] !== '' ? ' — '.$item['name'] : '');
    ?>
    <div class="pendingchanges-change pendingchanges-<?= pendingchanges_h($kind) ?>">
      <span class="pendingchanges-symbol" aria-hidden="true"><?= $symbols[$kind] ?></span>
      <strong><?= pendingchanges_h($title) ?></strong>
      <span class="pendingchanges-kind"><?= pendingchanges_h(ucfirst($kind)) ?></span>
      <details><summary>Extension and endpoint evidence</summary><pre><?= pendingchanges_h(json_encode($item['evidence'], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)) ?></pre></details>
    </div>
    <?php
}

$extensionChanges = pendingchanges_extension_changes($status['database']);
$otherDatabaseChanges = $status['database'];
unset($otherDatabaseChanges['users'], $otherDatabaseChanges['devices']);
$astdbChanges = $status['astdb'] ?? [];
$attribution = $status['attribution'] ?? [];
?>
<style>
  .pendingchanges-summary { display:flex; gap:12px; flex-wrap:wrap; margin:14px 0; }
  .pendingchanges-card { border:1px solid #b9d6cd; border-radius:4px; margin:12px 0; overflow:hidden; }
  .pendingchanges-card h3 { margin:0; padding:10px 14px; background:#e7f3ef; font-size:18px; }
  .pendingchanges-change { display:grid; grid-template-columns:28px minmax(200px, 1fr) auto; gap:10px; align-items:center; padding:9px 14px; border-top:1px solid #e4ece9; }
  .pendingchanges-change details { grid-column:2 / 4; }
  .pendingchanges-symbol { font-size:22px; font-weight:bold; text-align:center; }
  .pendingchanges-added .pendingchanges-symbol { color:#218739; }
  .pendingchanges-removed .pendingchanges-symbol { color:#bb2d3b; }
  .pendingchanges-updated .pendingchanges-symbol { color:#a86d00; }
  .pendingchanges-kind { color:#65756f; font-size:12px; text-transform:uppercase; }
  .pendingchanges-change pre { max-height:260px; margin:8px 0 0; }
  .pendingchanges-file { padding:9px 14px; border-top:1px solid #e4ece9; }
  .pendingchanges-attribution { padding:12px 14px; }
  .pendingchanges-attribution table { margin:10px 0 0; }
  .pendingchanges-confidence { font-weight:bold; text-transform:uppercase; font-size:12px; color:#5d6d67; }
</style>
<div class="container-fluid">
  <h1>Pending Changes Tripwire</h1>
  <p class="text-muted">Read-only comparison against the last applied baseline, with cautious correlation to authenticated administrator write requests.</p>
  <?= $notice ?>
  <div class="alert <?= $status['pending'] ? 'alert-warning' : 'alert-success' ?>"><?= htmlentities($status['message']) ?></div>
  <?php if ($status['pending']): ?>
    <section class="pendingchanges-card">
      <h3>Administrator request evidence (inferred)</h3>
      <div class="pendingchanges-attribution">
        <div class="pendingchanges-confidence"><?= pendingchanges_h($attribution['confidence'] ?? 'unavailable') ?></div>
        <?php if (!empty($attribution['actors'])): ?>
          <p><strong><?= count($attribution['actors']) === 1 ? 'Likely staged by' : 'Possible actors' ?>:</strong>
            <?= pendingchanges_h(implode(', ', $attribution['actors'])) ?></p>
        <?php endif; ?>
        <p><?= pendingchanges_h($attribution['note'] ?? 'No authenticated request evidence is available.') ?></p>
        <p class="text-muted"><?= pendingchanges_h($attribution['caveat'] ?? 'This is correlation, not proof of causation.') ?></p>
        <?php if (!empty($attribution['requests'])): ?>
          <details><summary>Matching authenticated write requests (<?= (int) ($attribution['request_count'] ?? count($attribution['requests'])) ?>)</summary>
            <table class="table table-striped table-condensed">
              <thead><tr><th>Time</th><th>Administrator</th><th>Area</th><th>Method</th></tr></thead>
              <tbody>
              <?php foreach ($attribution['requests'] as $event): ?>
                <tr>
                  <td><?= pendingchanges_h(date('Y-m-d H:i:s T', (int) ($event['finished_at'] ?? 0))) ?></td>
                  <td><?= pendingchanges_h($event['username'] ?? 'unknown') ?></td>
                  <td><?= pendingchanges_h(pendingchanges_request_target($event)) ?></td>
                  <td><?= pendingchanges_h($event['method'] ?? '') ?></td>
                </tr>
              <?php endforeach; ?>
              </tbody>
            </table>
          </details>
        <?php elseif (empty($attribution['enabled'])): ?>
          <p class="text-muted">The authenticated-request sensor is not installed on this host.</p>
        <?php endif; ?>
      </div>
    </section>
  <?php endif; ?>
  <?php if (!$status['baseline']): ?>
    <?php if ($status['watcher']): ?>
      <p>The watcher will seed its baseline automatically when no reload is pending.</p>
    <?php else: ?>
      <form method="post"><button class="btn btn-primary" name="seed_baseline" value="1">Seed applied baseline</button></form>
    <?php endif; ?>
  <?php else: ?>
    <p>Baseline captured: <?= htmlentities($status['captured_at']) ?></p>
    <?php if (isset($status['watcher_observed_at'])): ?><p>Watcher observed: <?= htmlentities($status['watcher_observed_at']) ?></p><?php endif; ?>
    <?php if (!empty($status['coverage'])): ?>
      <details class="pendingchanges-card"><summary style="padding:10px 14px; font-weight:bold;">Coverage contract</summary>
        <div class="pendingchanges-file">Only explicitly listed sources are observed. Anything not listed may not be detected.</div>
        <pre><?= pendingchanges_h(json_encode($status['coverage'], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)) ?></pre>
      </details>
    <?php endif; ?>
    <?php if (!empty($status['coverage_limitations'])): ?>
      <div class="alert alert-info">Some configuration coverage is limited. These are coverage limitations, not pending changes.</div>
      <?php foreach ($status['coverage_limitations'] as $limitation): ?>
        <div class="pendingchanges-file">
          <?php if (($limitation['reason'] ?? '') === 'row_limit'): ?>
            <?= pendingchanges_h($limitation['table'] ?? 'unknown table') ?>: <?= (int) ($limitation['rows'] ?? 0) ?> rows exceeds the <?= (int) ($limitation['limit'] ?? 0) ?>-row cap.
          <?php elseif (($limitation['reason'] ?? '') === 'scope_expanded_while_pending'): ?>
            Additional watcher coverage begins after the current pending reload is resolved: <?= pendingchanges_h(implode(', ', $limitation['tables'] ?? [])) ?>.
          <?php elseif (($limitation['reason'] ?? '') === 'astdb_scope_expanded_while_pending'): ?>
            Immediate Asterisk-state coverage begins after the current pending reload is resolved: <?= pendingchanges_h(implode(', ', $limitation['families'] ?? [])) ?>.
          <?php elseif (($limitation['reason'] ?? '') === 'astdb_row_limit'): ?>
            AstDB coverage was not read because <?= (int) ($limitation['rows'] ?? 0) ?> rows exceeds the <?= (int) ($limitation['limit'] ?? 0) ?>-row cap.
          <?php elseif (($limitation['reason'] ?? '') === 'astdb_unavailable'): ?>
            AstDB immediate-state coverage is unavailable on this host.
          <?php else: ?>
            <?= pendingchanges_h(json_encode($limitation, JSON_UNESCAPED_SLASHES)) ?>
          <?php endif; ?>
        </div>
      <?php endforeach; ?>
    <?php endif; ?>
    <?php if (empty($status['database']) && empty($astdbChanges) && empty($status['generated_files']) && empty($status['module_files'])): ?>
      <p class="text-muted">No attributable configuration or watched-file drift is currently present.</p>
    <?php endif; ?>
    <?php if (!empty($extensionChanges)): ?>
      <section class="pendingchanges-card">
        <h3>Extensions</h3>
        <?php foreach (['added', 'removed', 'updated'] as $kind): ?>
          <?php foreach ($extensionChanges[$kind] ?? [] as $item) pendingchanges_render_extension($kind, $item); ?>
        <?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php foreach ($otherDatabaseChanges as $table => $changes): ?>
      <?php if (empty($changes['added']) && empty($changes['removed']) && empty($changes['updated'])) continue; ?>
      <section class="pendingchanges-card">
        <h3><?= pendingchanges_h(pendingchanges_table_label($table)) ?></h3>
        <?php foreach (['added', 'removed', 'updated'] as $kind): ?>
          <?php foreach ($changes[$kind] ?? [] as $item) pendingchanges_render_record($kind, $table, $item); ?>
        <?php endforeach; ?>
      </section>
    <?php endforeach; ?>
    <?php if (!empty($astdbChanges['added']) || !empty($astdbChanges['removed']) || !empty($astdbChanges['updated'])): ?>
      <section class="pendingchanges-card">
        <h3>Immediate Asterisk state (AstDB)</h3>
        <p class="pendingchanges-file">These named FreePBX state families may already be effective; they are not necessarily waiting for Apply Config.</p>
        <?php foreach (['added', 'removed', 'updated'] as $kind): ?>
          <?php foreach ($astdbChanges[$kind] ?? [] as $item) pendingchanges_render_record($kind, 'AstDB', $item); ?>
        <?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php if (!empty($status['generated_files'])): ?>
      <section class="pendingchanges-card"><h3>Generated Asterisk files</h3>
        <?php foreach ($status['generated_files'] as $name => $change): ?><div class="pendingchanges-file">~ <?= pendingchanges_h($name) ?></div><?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php if (!empty($status['module_files'])): ?>
      <section class="pendingchanges-card"><h3>Module/file drift</h3>
        <?php foreach ($status['module_files'] as $name => $change): ?><div class="pendingchanges-file">~ <?= pendingchanges_h($name) ?></div><?php endforeach; ?>
      </section>
    <?php endif; ?>
  <?php endif; ?>
</div>
