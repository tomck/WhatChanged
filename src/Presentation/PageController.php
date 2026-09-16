<?php

namespace FreePBX\modules\Pendingchanges\Presentation;

class PageController
{
    private $module;
    private $moduleRoot;

    public function __construct($module, $moduleRoot)
    {
        $this->module = $module;
        $this->moduleRoot = rtrim($moduleRoot, '/');
    }

    public function render(array $server, array $post)
    {
        $notice = '';
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
        }

        $presenter = new ChangePresenter();
        $model = $presenter->pageModel($this->module->status());
        extract($model, EXTR_SKIP);
        $modulePath = $this->moduleRoot;

        require $this->moduleRoot . '/views/page.php';
    }
}
