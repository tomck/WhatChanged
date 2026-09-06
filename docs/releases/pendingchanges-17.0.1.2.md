# Pending Changes Tripwire 17.0.1.2 alpha

This compatibility release removes the assumption that every FreePBX system
uses `/var/www/html`. The installation instructions ask `fwconsole` for the
configured `AMPWEBROOT`, and the embedded watcher reads the same FreePBX setting
when it installs its service. Both module extraction and module-tree drift
monitoring therefore follow the PBX's actual web root.

The same archive supports FreePBX 14, 15, 16, and 17 and still contains the
complete watcher payload. See the
[alpha installation guide](../alpha-install.md) for the copy-and-paste install,
verification, feedback, and removal steps.

WhatChanged remains a read-only observer: anything outside its explicit
coverage contract may not be detected, and administrator attribution is
inferred rather than proven.
