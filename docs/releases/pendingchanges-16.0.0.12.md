# Pending Changes Tripwire 16.0.0.12 public alpha

FreePBX 16 compatibility candidate for the WhatChanged read-only observer.
This release adds an explicit watcher-health panel and refuses to treat an
empty result as all clear when the observer is delayed, stale, invalid,
unreadable, unconfigured, or absent.

Use the matching portable watcher 0.1.2 bundle and follow the
[legacy alpha guide](https://github.com/tomck/WhatChanged/blob/main/docs/legacy-alpha-install.md). Test first on a backed-up,
noncritical system. Anything outside the explicit Coverage contract may not be
detected.
