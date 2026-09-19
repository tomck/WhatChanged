<?php
/** @var \FreePBX\modules\Pendingchanges\Presentation\ChangePresenter $presenter */
/** @var array $status */
?>
<style>
  .pendingchanges-summary { display:flex; gap:12px; flex-wrap:wrap; margin:14px 0; }
  .pendingchanges-card { border:1px solid #b9d6cd; border-radius:4px; margin:12px 0; overflow:hidden; }
  .pendingchanges-card h3 { margin:0; padding:10px 14px; background:#e7f3ef; font-size:18px; }
  .pendingchanges-change { display:grid; grid-template-columns:28px minmax(200px, 1fr) auto; gap:10px; align-items:center; padding:9px 14px; border-top:1px solid #e4ece9; }
  .pendingchanges-change details { grid-column:2 / 4; }
  .pendingchanges-fields { grid-column:2 / 4; overflow-x:auto; }
  .pendingchanges-diff { margin:0; background:#fff; }
  .pendingchanges-diff th, .pendingchanges-diff td { vertical-align:top !important; }
  .pendingchanges-diff th:first-child { width:34%; }
  .pendingchanges-diff code { display:block; color:#65756f; font-size:11px; font-weight:normal; margin-top:3px; }
  .pendingchanges-diff small { display:block; color:#65756f; font-weight:normal; margin-top:4px; }
  .pendingchanges-before { color:#9b2634; background:#fff1f2; font-family:monospace; white-space:pre-wrap; }
  .pendingchanges-after { color:#176b2c; background:#effaf1; font-family:monospace; white-space:pre-wrap; }
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
  .pendingchanges-health { padding:12px 14px; display:grid; grid-template-columns:minmax(110px, auto) 1fr; gap:7px 14px; }
  .pendingchanges-health-label { font-weight:bold; }
  .pendingchanges-health-state { font-weight:bold; text-transform:uppercase; }
  .pendingchanges-health-state-success { color:#218739; }
  .pendingchanges-health-state-warning { color:#a86d00; }
  .pendingchanges-health-state-danger { color:#bb2d3b; }
  .pendingchanges-evidence-controls { display:none; gap:8px; margin:12px 0; }
</style>
<div class="container-fluid">
  <h1>Pending Changes Tripwire</h1>
  <p class="text-muted">Read-only comparison against the last applied baseline, with cautious correlation to authenticated administrator write requests.</p>
  <?= $notice ?>
  <div class="alert <?= $presenter->escape($messageClass) ?>"><?= $presenter->escape($status['message']) ?></div>
  <div class="pendingchanges-evidence-controls" id="pendingchanges-evidence-controls">
    <button class="btn btn-default" id="pendingchanges-toggle-evidence" type="button" aria-expanded="false">Expand all evidence</button>
  </div>
  <section class="pendingchanges-card">
    <h3>Watcher health</h3>
    <div class="pendingchanges-health">
      <div class="pendingchanges-health-label">Observer</div>
      <div>
        <span class="pendingchanges-health-state pendingchanges-health-state-<?= $presenter->escape(isset($watcherHealth['severity']) ? $watcherHealth['severity'] : 'danger') ?>"><?= $presenter->escape(isset($watcherHealth['label']) ? $watcherHealth['label'] : 'Unknown') ?></span>
        — <?= $presenter->escape(isset($watcherHealth['detail']) ? $watcherHealth['detail'] : '') ?>
        <?php if (isset($watcherHealth['observation_age_seconds'])): ?>
          Latest completed observation: <?= (int) $watcherHealth['observation_age_seconds'] ?> seconds ago.
        <?php endif; ?>
      </div>
      <div class="pendingchanges-health-label">Coverage</div>
      <div><?= $dataCurrent ? 'Current full watcher snapshot' : 'Reduced or last-known coverage; do not treat an empty result as all clear' ?></div>
      <div class="pendingchanges-health-label">Baseline</div>
      <div>
        <?= $baselineTrusted ? 'Continuity verified' : 'Continuity uncertain; wait for an observed successful Apply Config before treating the baseline as authoritative' ?>
        <?php if (!$baselineTrusted && !empty($baselineProvenance['detail'])): ?>
          — <?= $presenter->escape($baselineProvenance['detail']) ?>
        <?php endif; ?>
      </div>
      <div class="pendingchanges-health-label">Attribution sensor</div>
      <div><?= !empty($watcherHealth['sensor_loaded']) ? 'Loaded for this FreePBX web request' : 'Not loaded for this FreePBX web request; administrator correlation may be unavailable' ?></div>
      <div class="pendingchanges-health-label">Watcher payload</div>
      <div>
        <span class="pendingchanges-health-state pendingchanges-health-state-<?= $presenter->escape(isset($watcherPayload['severity']) ? $watcherPayload['severity'] : 'danger') ?>"><?= $presenter->escape(isset($watcherPayload['label']) ? $watcherPayload['label'] : 'Unknown') ?></span>
        — <?= $presenter->escape(isset($watcherPayload['detail']) ? $watcherPayload['detail'] : '') ?>
        <?php if (!empty($watcherPayload['embedded_version'])): ?>
          Bundled: <?= $presenter->escape($watcherPayload['embedded_version']) ?>.
        <?php endif; ?>
        <?php if (!empty($watcherPayload['installed_version'])): ?>
          Installed: <?= $presenter->escape($watcherPayload['installed_version']) ?>.
        <?php endif; ?>
      </div>
    </div>
  </section>
  <?php if (!$dataCurrent): ?>
    <div class="alert alert-warning">Current full-scope drift cannot be declared clear while watcher health is degraded. Any evidence below is framework-only or from the last completed watcher observation.</div>
  <?php endif; ?>
  <?php if ($dataCurrent && !$baselineTrusted): ?>
    <div class="alert alert-warning">The current snapshot is fresh, but the watcher could not prove that its saved baseline follows the latest Apply Config. Evidence is shown conservatively; an observed successful Apply Config will establish a new trusted baseline.</div>
  <?php endif; ?>
  <?php if (isset($watcherHealth['state']) && ($watcherHealth['state'] === 'not_installed' || $watcherHealth['state'] === 'installed_unconfigured')): ?>
    <div class="alert alert-info">The watcher is bundled with this module but is not publishing observations. As root, run <code>sudo <?= $presenter->escape($modulePath) ?>/bin/install-watcher</code>. The installer detects Debian and RHEL/Sangoma-family layouts. Standalone watcher packages remain available.</div>
  <?php endif; ?>
  <?php if ((isset($watcherPayload['state']) ? $watcherPayload['state'] : '') === 'newer'): ?>
    <div class="alert alert-warning">The installed watcher is newer than this module's bundled payload. Update the Pending Changes module before changing the watcher.</div>
  <?php elseif (empty($watcherPayload['current']) && !in_array(isset($watcherHealth['state']) ? $watcherHealth['state'] : '', array('not_installed', 'installed_unconfigured'), true)): ?>
    <div class="alert alert-warning">The bundled and installed watcher payloads do not match. Run <code><?= $presenter->escape(isset($watcherPayload['update_command']) ? $watcherPayload['update_command'] : 'sudo ' . $modulePath . '/bin/install-watcher') ?></code> as an administrator. The installer can offer to install a missing PyMySQL package before continuing.</div>
  <?php endif; ?>
  <?php if ($status['pending']): ?>
    <section class="pendingchanges-card">
      <h3>Administrator request evidence (inferred)</h3>
      <div class="pendingchanges-attribution">
        <div class="pendingchanges-confidence"><?= $presenter->escape(isset($attribution['confidence']) ? $attribution['confidence'] : 'unavailable') ?></div>
        <?php if (!empty($attribution['actors'])): ?>
          <p><strong><?= count($attribution['actors']) === 1 ? 'Likely staged by' : 'Possible actors' ?>:</strong>
            <?= $presenter->escape(implode(', ', $attribution['actors'])) ?></p>
        <?php endif; ?>
        <p><?= $presenter->escape(isset($attribution['note']) ? $attribution['note'] : 'No authenticated request evidence is available.') ?></p>
        <p class="text-muted"><?= $presenter->escape(isset($attribution['caveat']) ? $attribution['caveat'] : 'This is correlation, not proof of causation.') ?></p>
        <?php if (!empty($attribution['requests'])): ?>
          <details class="pendingchanges-evidence"><summary>Matching authenticated write requests (<?= (int) (isset($attribution['request_count']) ? $attribution['request_count'] : count($attribution['requests'])) ?>)</summary>
            <table class="table table-striped table-condensed">
              <thead><tr><th>Time</th><th>Administrator</th><th>Area</th><th>Method</th></tr></thead>
              <tbody>
              <?php foreach ($attribution['requests'] as $event): ?>
                <tr>
                  <td><?= $presenter->escape(date('Y-m-d H:i:s T', (int) (isset($event['finished_at']) ? $event['finished_at'] : 0))) ?></td>
                  <td><?= $presenter->escape(isset($event['username']) ? $event['username'] : 'unknown') ?></td>
                  <td><?= $presenter->escape($presenter->requestTarget($event)) ?></td>
                  <td><?= $presenter->escape(isset($event['method']) ? $event['method'] : '') ?></td>
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
    <p>Baseline captured: <?= $presenter->escape($status['captured_at']) ?></p>
    <?php if (isset($status['watcher_observed_at'])): ?><p>Watcher observed: <?= $presenter->escape($status['watcher_observed_at']) ?></p><?php endif; ?>
    <?php if (!empty($status['coverage'])): ?>
      <details class="pendingchanges-card"><summary style="padding:10px 14px; font-weight:bold;">Coverage contract</summary>
        <div class="pendingchanges-file">Only explicitly listed sources are observed. Anything not listed may not be detected.</div>
        <pre><?= $presenter->json($status['coverage']) ?></pre>
      </details>
    <?php endif; ?>
    <?php if (!empty($status['coverage_limitations'])): ?>
      <div class="alert alert-info">Some configuration coverage is limited. These are coverage limitations, not pending changes.</div>
      <?php foreach ($status['coverage_limitations'] as $limitation): ?>
        <div class="pendingchanges-file">
          <?php if ((isset($limitation['reason']) ? $limitation['reason'] : '') === 'row_limit'): ?>
            <?= $presenter->escape(isset($limitation['table']) ? $limitation['table'] : 'unknown table') ?>: <?= (int) (isset($limitation['rows']) ? $limitation['rows'] : 0) ?> rows exceeds the <?= (int) (isset($limitation['limit']) ? $limitation['limit'] : 0) ?>-row cap.
          <?php elseif ((isset($limitation['reason']) ? $limitation['reason'] : '') === 'scope_expanded_while_pending'): ?>
            Additional watcher coverage begins after the current pending reload is resolved: <?= $presenter->escape(implode(', ', isset($limitation['tables']) ? $limitation['tables'] : array())) ?>.
          <?php elseif ((isset($limitation['reason']) ? $limitation['reason'] : '') === 'astdb_scope_expanded_while_pending'): ?>
            Immediate Asterisk-state coverage begins after the current pending reload is resolved: <?= $presenter->escape(implode(', ', isset($limitation['families']) ? $limitation['families'] : array())) ?>.
          <?php elseif ((isset($limitation['reason']) ? $limitation['reason'] : '') === 'astdb_row_limit'): ?>
            AstDB coverage was not read because <?= (int) (isset($limitation['rows']) ? $limitation['rows'] : 0) ?> rows exceeds the <?= (int) (isset($limitation['limit']) ? $limitation['limit'] : 0) ?>-row cap.
          <?php elseif ((isset($limitation['reason']) ? $limitation['reason'] : '') === 'astdb_unavailable'): ?>
            AstDB immediate-state coverage is unavailable on this host.
          <?php else: ?>
            <?= $presenter->escape(json_encode($limitation, JSON_UNESCAPED_SLASHES)) ?>
          <?php endif; ?>
        </div>
      <?php endforeach; ?>
    <?php endif; ?>
    <?php if ($dataCurrent && $baselineTrusted && empty($status['database']) && empty($astdbChanges) && empty($status['generated_files']) && empty($status['module_files'])): ?>
      <p class="text-muted">No attributable configuration or watched-file drift is currently present.</p>
    <?php elseif ((!$dataCurrent || !$baselineTrusted) && empty($status['database']) && empty($astdbChanges) && empty($status['generated_files']) && empty($status['module_files'])): ?>
      <p class="text-muted">No drift appears in the available evidence, but watcher health and baseline continuity must both be verified before this can be treated as an authoritative result.</p>
    <?php endif; ?>
    <?php if (!empty($extensionChanges)): ?>
      <section class="pendingchanges-card">
        <h3>Extensions</h3>
        <?php foreach (array('added', 'removed', 'updated') as $kind): ?>
          <?php foreach (isset($extensionChanges[$kind]) ? $extensionChanges[$kind] : array() as $item): ?>
            <?php $change = $presenter->extension($kind, $item); require __DIR__.'/partials/change.php'; ?>
          <?php endforeach; ?>
        <?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php foreach ($otherDatabaseChanges as $table => $changes): ?>
      <?php if (empty($changes['added']) && empty($changes['removed']) && empty($changes['updated'])) continue; ?>
      <section class="pendingchanges-card">
        <h3><?= $presenter->escape($presenter->tableLabel($table)) ?></h3>
        <?php foreach (array('added', 'removed', 'updated') as $kind): ?>
          <?php foreach (isset($changes[$kind]) ? $changes[$kind] : array() as $item): ?>
            <?php $change = $presenter->record($kind, $table, $item); require __DIR__.'/partials/change.php'; ?>
          <?php endforeach; ?>
        <?php endforeach; ?>
      </section>
    <?php endforeach; ?>
    <?php if (!empty($astdbChanges['added']) || !empty($astdbChanges['removed']) || !empty($astdbChanges['updated'])): ?>
      <section class="pendingchanges-card">
        <h3>Immediate Asterisk state (AstDB)</h3>
        <p class="pendingchanges-file">These named FreePBX state families may already be effective; they are not necessarily waiting for Apply Config.</p>
        <?php foreach (array('added', 'removed', 'updated') as $kind): ?>
          <?php foreach (isset($astdbChanges[$kind]) ? $astdbChanges[$kind] : array() as $item): ?>
            <?php $change = $presenter->record($kind, 'AstDB', $item); require __DIR__.'/partials/change.php'; ?>
          <?php endforeach; ?>
        <?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php if (!empty($status['generated_files'])): ?>
      <section class="pendingchanges-card"><h3>Generated Asterisk files</h3>
        <?php foreach ($status['generated_files'] as $name => $change): ?><div class="pendingchanges-file">~ <?= $presenter->escape($name) ?></div><?php endforeach; ?>
      </section>
    <?php endif; ?>
    <?php if (!empty($status['module_files'])): ?>
      <section class="pendingchanges-card"><h3>Module/file drift</h3>
        <?php foreach ($status['module_files'] as $name => $change): ?><div class="pendingchanges-file">~ <?= $presenter->escape($name) ?></div><?php endforeach; ?>
      </section>
    <?php endif; ?>
  <?php endif; ?>
</div>
<script>
(function () {
  var controls = document.getElementById('pendingchanges-evidence-controls');
  var toggle = document.getElementById('pendingchanges-toggle-evidence');
  var evidence = document.querySelectorAll('details.pendingchanges-evidence');
  if (!controls || !toggle || evidence.length === 0) {
    return;
  }
  controls.style.display = 'flex';
  toggle.addEventListener('click', function () {
    var expand = toggle.getAttribute('aria-expanded') !== 'true';
    for (var index = 0; index < evidence.length; index += 1) {
      evidence[index].open = expand;
    }
    toggle.setAttribute('aria-expanded', expand ? 'true' : 'false');
    toggle.textContent = expand ? 'Collapse all evidence' : 'Expand all evidence';
  });
}());
</script>
