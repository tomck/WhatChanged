# Pending Changes Tripwire 17.0.1.1 alpha

The shared FreePBX 14–17 module now includes the complete WhatChanged watcher
payload. After installing the module, a root-capable administrator can install
and configure the OS service without downloading a second artifact:

```sh
sudo /var/www/html/admin/modules/pendingchanges/bin/install-watcher
```

The installer detects Debian-family and RHEL/CentOS/Sangoma-family systems,
preserves existing watcher configuration and evidence during upgrades, and
refuses an unknown OS unless the operator explicitly selects a reviewed layout.
FreePBX Module Admin does not run the privileged installer automatically.
Local MariaDB installations receive a generated SELECT-only watcher account.
For a remote database, the installer places the reviewed files but deliberately
leaves the service disabled until an administrator supplies a SELECT-only
credential in `/etc/what-changed-watcher.env`.

Standalone Debian and portable watcher packages remain available. WhatChanged
is a read-only observer: anything outside its explicit coverage contract may
not be detected, and administrator attribution is inferred rather than proven.
