# Pending Changes Tripwire 17.0.2.1 alpha

This release makes the module and its embedded watcher self-checking. The
Reports page, command-line doctor, and installer check show the watcher version
bundled with the module, the version currently producing observations, and
whether they match. An absent, unversioned, or older payload is never treated
as a current all-clear; the exact full-path update command is displayed.
If the installed watcher is newer than the module, WhatChanged instead asks
for a module update and does not offer a watcher downgrade command.

The embedded and portable installers now recognize Debian- and RHEL-family
PyMySQL packages. When PyMySQL is absent, they show the package-manager command
and ask for permission. Accepting the prompt installs the dependency and
continues the same installation; declining makes no package change.

Upgrades preserve the layout used by the active watcher service. In particular,
an older portable `/usr/local` watcher on Debian is upgraded in place rather
than leaving systemd on the old `/etc` unit while writing an unused second unit
under `/lib`.

The module remains one PHP 5.6-compatible archive for FreePBX 14, 15, 16, and
17. The watcher is version 0.1.7.
