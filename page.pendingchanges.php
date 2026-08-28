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
?>
<div class="container-fluid">
  <h1>Pending Changes Tripwire</h1>
  <p class="text-muted">Read-only comparison against the last applied baseline. The watcher records current configuration drift, not the page or user that set FreePBX’s global reload flag.</p>
  <?= $notice ?>
  <div class="alert <?= $status['pending'] ? 'alert-warning' : 'alert-success' ?>"><?= htmlentities($status['message']) ?></div>
  <?php if (!$status['baseline']): ?>
    <?php if ($status['watcher']): ?>
      <p>The watcher will seed its baseline automatically when no reload is pending.</p>
    <?php else: ?>
      <form method="post"><button class="btn btn-primary" name="seed_baseline" value="1">Seed applied baseline</button></form>
    <?php endif; ?>
  <?php else: ?>
    <p>Baseline captured: <?= htmlentities($status['captured_at']) ?></p>
    <?php if (isset($status['watcher_observed_at'])): ?><p>Watcher observed: <?= htmlentities($status['watcher_observed_at']) ?></p><?php endif; ?>
    <h3>Database drift</h3>
    <pre><?= htmlentities(json_encode($status['database'], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)) ?></pre>
    <h3>Generated-file drift</h3>
    <pre><?= htmlentities(json_encode($status['files'], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)) ?></pre>
  <?php endif; ?>
</div>
