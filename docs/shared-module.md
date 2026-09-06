# Shared module release 17.0.1.1

The default archive, pendingchanges-17.0.1.1.tgz, declares FreePBX 14.0,
15.0, 16.0 and 17.0 support and requires PHP 5.6 or newer.
The module version is a release identifier, not the minimum FreePBX version.

There is one PHP source tree and one module archive for all four versions.
The release workflow creates one module tag, signs once, and publishes once.

The module now embeds the watcher payload and an explicit root installer. It
selects Debian-family or RHEL/CentOS/Sangoma-family paths from the operating
system, not the FreePBX version. Standalone Debian and portable packages remain
available but are optional.

Validation: the identical 17.0.1.1 archive was installed with Module Admin in
the existing disposable FreePBX 14, 15, 16 and 17 fixtures. Each reported
17.0.1.1 Enabled. PHP 5.6, 7.4 and 8.2 syntax, page rendering, watcher-health
classification and request-audit checks passed. This is packaging and module
installation validation. The unified archive also passed the FreePBX 14–16
staged-drift lifecycle gate and the complete FreePBX 17 release gate on
September 5, 2026. Both embedded filesystem layouts and automatic OS-family
detection were validated in disposable containers. Live systemd activation of
the embedded portable layout still requires voluntary testing on a maintained
RHEL/CentOS/Sangoma-family PBX.

FreePBX 17: archive installation, watcher package layout, watcher unit checks,
request-audit checks and the core watcher smoke lifecycle passed on September 5.
The authenticated fixture gate also passed extension/ring-group/queue changes,
SIP and Advanced Settings breakers, immediate AstDB state, module enable/disable,
User Management UCP assignments, Fax Configuration channels, outbound routes,
custom trunks, the watcher-health page, Apply Config baseline refreshes and the
final clean-state assertion.

Build with scripts/package-module.sh. Existing signatures cannot be reused
after metadata changes; these candidates must be signed before publication.

Refactoring review: version parsing in packaging, signing, publishing and lab
scripts assumed x.0.0.N and would truncate the requested x.0.1.0 release.
These paths now preserve the full suffix. No runtime PHP fork was necessary.
The page combines rendering helpers with presentation; extracting those is a
possible future cleanup, but is not necessary for cross-version compatibility.
