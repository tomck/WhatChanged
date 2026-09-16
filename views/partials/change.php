<?php
/** @var \FreePBX\modules\Pendingchanges\Presentation\ChangePresenter $presenter */
/** @var array $change */
?>
<div class="pendingchanges-change pendingchanges-<?= $presenter->escape($change['kind']) ?>">
  <span class="pendingchanges-symbol" aria-hidden="true"><?= $presenter->escape($change['symbol']) ?></span>
  <strong><?= $presenter->escape($change['title']) ?></strong>
  <span class="pendingchanges-kind"><?= $presenter->escape(ucfirst($change['kind'])) ?></span>
  <details class="pendingchanges-evidence">
    <summary><?= $presenter->escape($change['summary']) ?></summary>
    <pre><?= $presenter->json($change['details']) ?></pre>
  </details>
</div>
