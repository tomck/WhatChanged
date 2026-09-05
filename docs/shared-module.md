# Shared module release 17.0.1.0

The default archive, pendingchanges-17.0.1.0.tgz, declares FreePBX 14.0,
15.0, 16.0 and 17.0 support and requires PHP 5.6 or newer.
The module version is a release identifier, not the minimum FreePBX version.

There is one PHP source tree and one module archive for all four versions.
The release workflow creates one module tag, signs once, and publishes once.

The watcher remains a separate installation: Debian package for Debian 12,
portable systemd package for the legacy test platforms. Module compatibility
does not make the Debian package compatible with every operating system.

Validation: the identical 17.0.1.0 archive was installed with Module Admin in
the existing disposable FreePBX 14, 15, 16 and 17 fixtures. Each reported
17.0.1.0 Enabled. PHP 5.6, 7.4 and 8.2 syntax, page rendering, watcher-health
classification and request-audit checks passed. This is packaging and module
installation validation. The unified archive also passed the FreePBX 14–16
staged-drift lifecycle gate on September 5, 2026.

FreePBX 17: archive installation, watcher package layout, watcher unit checks,
request-audit checks and the core watcher smoke lifecycle passed on September 5.
The remaining authenticated fixture tests stopped because `.env.lab` is missing
from this checkout and the original workspace. Restore the disposable lab admin
credentials using `.env.lab.example`, then rerun `docker/lab-gate.sh`.

Build with scripts/package-module.sh. Existing signatures cannot be reused
after metadata changes; these candidates must be signed before publication.

Refactoring review: version parsing in packaging, signing, publishing and lab
scripts assumed x.0.0.N and would truncate the requested x.0.1.0 release.
These paths now preserve the full suffix. No runtime PHP fork was necessary.
The page combines rendering helpers with presentation; extracting those is a
possible future cleanup, but is not necessary for cross-version compatibility.
