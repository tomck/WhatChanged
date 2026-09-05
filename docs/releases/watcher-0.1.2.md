# WhatChanged watcher 0.1.2 public alpha

This release publishes observer-health metadata with each completed snapshot so
the FreePBX module can distinguish current, delayed, and stale evidence. It also
records the expected lightweight and full-scan intervals without changing the
watcher's read-only database privileges.

FreePBX 17 uses the Debian package. FreePBX 14-16 candidates use the portable
systemd bundle. The watcher sends no telemetry, never Apply Configs or reloads
Asterisk, and observes only the explicitly listed bounded sources.
