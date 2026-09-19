<?php
/** @var \FreePBX\modules\Pendingchanges\Presentation\ChangePresenter $presenter */
/** @var array $change */
?>
<div class="pendingchanges-change pendingchanges-<?= $presenter->escape($change['kind']) ?>">
  <span class="pendingchanges-symbol" aria-hidden="true"><?= $presenter->escape($change['symbol']) ?></span>
  <strong><?= $presenter->escape($change['title']) ?></strong>
  <span class="pendingchanges-kind"><?= $presenter->escape(ucfirst($change['kind'])) ?></span>
  <?php if (!empty($change['fieldRows'])): ?>
    <div class="pendingchanges-fields">
      <table class="table table-condensed pendingchanges-diff" aria-label="Changed settings">
        <thead><tr><th>Setting</th><th>Before</th><th>After</th></tr></thead>
        <tbody>
        <?php foreach ($change['fieldRows'] as $field): ?>
          <tr>
            <th scope="row">
              <?= $presenter->escape($field['label']) ?>
              <code><?= $presenter->escape($field['field']) ?></code>
              <?php if ($field['description'] !== ''): ?><small><?= $presenter->escape($field['description']) ?></small><?php endif; ?>
            </th>
            <td class="pendingchanges-before"><?= $presenter->escape($field['before']) ?></td>
            <td class="pendingchanges-after"><?= $presenter->escape($field['after']) ?></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  <?php endif; ?>
  <details class="pendingchanges-evidence">
    <summary><?= $presenter->escape($change['summary']) ?></summary>
    <pre><?= $presenter->json($change['details']) ?></pre>
  </details>
</div>
