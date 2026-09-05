# Pending Changes Tripwire 17.0.0.12 public alpha

Primary FreePBX 17 public-alpha module for the WhatChanged read-only observer.
This release adds an explicit watcher-health panel based on the age of the last
completed full observation, reports whether the administrator-request sensor is
loaded, and refuses to treat an empty degraded result as all clear.

Install it with watcher 0.1.2 using the [FreePBX 17 alpha guide](../alpha-install.md).
Anything outside the explicit Coverage contract may not be detected, and
administrator attribution remains correlation rather than proof.
