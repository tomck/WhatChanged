# WhatChanged watcher 0.1.1 alpha

Read-only companion observer for Pending Changes Tripwire. Use the Debian
package on FreePBX 17/Debian 12 and the portable systemd bundle for legacy test
systems after confirming Python 3.6+ and PyMySQL are available.

The installer creates a random credential for a dedicated `SELECT`-only local
database account, installs the value-free authenticated-request sensor, and
starts the watcher. It does not run Apply Config or reload Asterisk.

Download the appropriate package, `SHA256SUMS`, `SHA256SUMS.asc`, and detached
`.asc` signature. Full installation and removal instructions are in the
module-specific release notes and the repository's alpha guides.
