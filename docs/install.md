# Install WhatChanged

The current public release is **17.0.2.8**. One signed `pendingchanges` module
archive supports FreePBX 14, 15, 16, and 17 and contains the watcher service.
FreePBX 17 is the primary tested target; FreePBX 14–16 are compatibility-tested
legacy targets whose underlying operating systems may be unsupported.

Before installing, make a current PBX backup and review the product boundary:
WhatChanged reports drift only for the sources named in its Coverage contract.
It is not a universal audit trail, rollback engine, or replacement for normal
change control.

## Recommended verified installation

Download the archive, detached signatures, signed checksum manifest, and
public key from the
[17.0.2.8 release](https://github.com/tomck/WhatChanged/releases/tag/pendingchanges-17.0.2.8).
Then follow the [detailed verification and installation
reference](alpha-install.md#verify-the-downloaded-release). That historical
path is retained so links from earlier releases continue to work.

## Convenience installation

If you explicitly trust the installer served by this project's GitHub Pages
site, it can download, authenticate, and install the reviewed release:

```sh
curl -fsSL https://tomck.github.io/WhatChanged/install.sh | sudo bash
```

The bootstrap is pinned to 17.0.2.8; it does not dynamically execute whatever
GitHub happens to label Latest. It requires GnuPG, verifies the signed manifest
and archive signature, asks FreePBX for its configured web root, installs the
module, and starts the explicit watcher installer. Missing supported
dependencies are explained and installed only after consent.

## Verify the result

Open **Reports → Pending Changes Tripwire** and require all of the following
before treating an empty result as meaningful:

- **Watcher health: Healthy**
- **Watcher payload: Current**
- **Current full watcher snapshot**
- **Baseline: Continuity verified**

The detailed reference includes command-line health checks, upgrade behavior,
uninstallation, signature verification, and troubleshooting. Installation and
removal never Apply Config or reload Asterisk.
