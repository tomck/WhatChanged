# Pending Changes Tripwire 15.0.0.12 public alpha

FreePBX 15 compatibility candidate for the WhatChanged read-only observer.
This release adds an explicit watcher-health panel and refuses to treat an
empty result as all clear when the observer is delayed, stale, invalid,
unreadable, unconfigured, or absent.

Use the matching portable watcher 0.1.2 bundle and follow the
[legacy alpha guide](https://github.com/tomck/WhatChanged/blob/main/docs/legacy-alpha-install.md). FreePBX 15 and its underlying
platform may have unrelated end-of-life risks; test only on a backed-up,
noncritical system. Anything outside the explicit Coverage contract may not be
detected.
