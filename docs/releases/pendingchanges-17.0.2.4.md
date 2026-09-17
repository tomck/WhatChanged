# Pending Changes Tripwire 17.0.2.4

This alpha release adds a convenience installer for operators who explicitly
trust the hosted GitHub script:

```sh
curl -fsSL https://raw.githubusercontent.com/tomck/WhatChanged/main/install.sh | sudo bash
```

The script resolves the latest published release, verifies the module archive
against the signed SHA-256 manifest (and verifies the OpenPGP signature when
`gpg` is available), discovers FreePBX's configured `AMPWEBROOT`, installs the
module, and launches the embedded watcher installer. The manual verification
path remains available for administrators who want to inspect every file
before execution.

The module archive remains the shared FreePBX 14–17 build and carries the
embedded watcher. Installation never runs Apply Config or reloads Asterisk.
