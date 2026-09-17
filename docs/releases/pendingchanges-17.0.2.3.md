# Pending Changes Tripwire 17.0.2.3 alpha

This release adds FreePBX Core inbound-route coverage. Staged DID additions,
edits, and removals are now read from the `incoming` table and shown as
**Inbound Routes** before Apply Config. A route is identified by its DID and
caller-ID match pair, so separate caller-ID-specific routes remain separate
evidence rather than being merged into one record.

The disposable authenticated HTTP gate now creates and removes a real inbound
route alongside its extension, ring-group, and queue fixtures. It verifies
readable before/after evidence, Apply Config baseline refresh, removal
evidence, and a final clean state.

The module remains one PHP 5.6-compatible archive for FreePBX 14, 15, 16, and
17. The embedded watcher is version 0.1.9. WhatChanged remains a bounded,
read-only diagnostic: it reports only explicitly listed sources, so unlisted
FreePBX, third-party-module, AstDB, filesystem, and custom-method changes may
not be detected.

See the [alpha installation and verification guide](https://github.com/tomck/WhatChanged/blob/main/docs/alpha-install.md)
before installing on a PBX.
