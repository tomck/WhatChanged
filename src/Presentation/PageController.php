<?php

namespace FreePBX\modules\Pendingchanges\Presentation;

use FreePBX\modules\Pendingchanges\Update\ReleaseChecker;

class PageController
{
    private $module;
    private $moduleRoot;
    private $releaseChecker;

    public function __construct($module, $moduleRoot, $releaseChecker = null)
    {
        $this->module = $module;
        $this->moduleRoot = rtrim($moduleRoot, '/');
        $this->releaseChecker = $releaseChecker === null
            ? new ReleaseChecker($module, $this->moduleRoot)
            : $releaseChecker;
    }

    public function render(array $server, array $post)
    {
        $notice = '';
        $forceReleaseCheck = false;
        if (
            isset($server['REQUEST_METHOD'])
            && $server['REQUEST_METHOD'] === 'POST'
            && isset($post['seed_baseline'])
        ) {
            try {
                $result = $this->module->seedBaseline();
                $notice = '<div class="alert alert-success">Applied baseline saved ('
                    . (int) $result['tables'] . ' tables, ' . (int) $result['files'] . ' files).</div>';
            } catch (\Exception $error) {
                $notice = '<div class="alert alert-danger">'
                    . htmlentities($error->getMessage(), ENT_QUOTES, 'UTF-8') . '</div>';
            }
        } elseif (
            isset($server['REQUEST_METHOD'])
            && $server['REQUEST_METHOD'] === 'POST'
            && isset($post['save_update_preference'])
        ) {
            try {
                $enabled = isset($post['automatic_release_checks'])
                    && (string) $post['automatic_release_checks'] === '1';
                $this->releaseChecker->setAutomaticEnabled($enabled);
                $forceReleaseCheck = $enabled;
                $notice = '<div class="alert alert-success">Update-check preference saved.</div>';
            } catch (\Exception $error) {
                $notice = '<div class="alert alert-danger">The update-check preference could not be saved: '
                    . htmlentities($error->getMessage(), ENT_QUOTES, 'UTF-8') . '</div>';
            }
        } elseif (
            isset($server['REQUEST_METHOD'])
            && $server['REQUEST_METHOD'] === 'POST'
            && isset($post['check_for_updates'])
        ) {
            $forceReleaseCheck = true;
        }

        try {
            $releaseUpdate = $this->releaseChecker->status($forceReleaseCheck);
        } catch (\Exception $error) {
            $releaseUpdate = array(
                'state' => 'unavailable',
                'installed_version' => null,
                'available_version' => null,
                'automatic' => false,
                'checked_at' => null,
                'stale' => false,
                'installer_url' => ReleaseChecker::INSTALLER_URL,
                'releases_url' => ReleaseChecker::RELEASES_URL,
            );
        }

        $presenter = new ChangePresenter();
        $model = $presenter->pageModel($this->module->status());
        extract($model, EXTR_SKIP);
        $modulePath = $this->moduleRoot;

        require $this->moduleRoot . '/views/page.php';
    }
}
