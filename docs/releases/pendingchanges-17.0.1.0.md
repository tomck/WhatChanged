# Pending Changes Tripwire 17.0.1.0 alpha

One shared PHP implementation supports FreePBX 14–17. The recommended shared
archive is pendingchanges-17.0.1.0.tgz for every supported version.
See [shared module compatibility](https://github.com/tomck/WhatChanged/blob/main/docs/shared-module.md).

The same archive passed disposable real-image lifecycle tests on FreePBX 14,
15, 16 and 17. FreePBX 17 coverage includes representative extensions, ring
groups, queues, SIP and Advanced Settings, AstDB, module state, User Management,
Fax Configuration, outbound routes and custom trunks. WhatChanged remains a
read-only observer: anything outside its explicit coverage contract may not be
detected, and administrator attribution is inferred rather than proven.

Install the separate watcher using the [alpha guide](https://github.com/tomck/WhatChanged/blob/main/docs/alpha-install.md)
or [legacy guide](https://github.com/tomck/WhatChanged/blob/main/docs/legacy-alpha-install.md).
