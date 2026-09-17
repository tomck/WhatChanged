# Pending Changes Tripwire 17.0.2.2 alpha

This release extends authenticated administrator-request attribution to FreePBX
sites served by nginx and PHP-FPM while retaining the existing Apache path. The
installer discovers the active supported web stack, validates its complete
configuration, and reloads only the services that are actually in use. If no
supported web PHP integration is available, the read-only configuration watcher
continues to operate and reports request attribution as an explicit coverage
limitation instead of treating it as healthy.

The nginx path passed the same disposable FreePBX 17 release gate used for the
Apache path: authenticated extension, ring-group, queue, User Management, fax,
outbound-route, trunk, Advanced Settings, SIP Settings, AstDB, module-state,
redaction, interruption, recovery, Apply Config, and final-clean-baseline
scenarios. The gate also proves that Apache is stopped while nginx and PHP-FPM
serve the application. The identical module archive continues to pass the
FreePBX 14, 15, and 16 compatibility fixtures.

First-install database readiness is also more deterministic: the disposable
lab waits for FreePBX's exact application database endpoint before starting its
installation transaction.

The module remains one PHP 5.6-compatible archive for FreePBX 14, 15, 16, and
17. The embedded watcher is version 0.1.8. WhatChanged remains a bounded,
read-only diagnostic: it reports only the explicitly listed sources and does
not claim that every FreePBX or third-party change is observable.

See the [alpha installation and verification guide](https://github.com/tomck/WhatChanged/blob/main/docs/alpha-install.md)
before installing on a PBX.
