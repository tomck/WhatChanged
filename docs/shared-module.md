# Shared module release 17.0.2.5

The default archive, pendingchanges-17.0.2.5.tgz, declares FreePBX 14.0,
15.0, 16.0 and 17.0 support and requires PHP 5.6 or newer.
The module version is a release identifier, not the minimum FreePBX version.

There is one PHP source tree and one module archive for all four versions.
The release workflow creates one module tag, signs once, and publishes once.

The module embeds the watcher payload and an explicit root installer. It selects
Debian-family or RHEL/CentOS/Sangoma-family paths from the operating system, not
the FreePBX version. It also reads FreePBX's configured `AMPWEBROOT` so
module-file monitoring follows nonstandard web roots. Standalone Debian and
portable packages remain available but are optional.

Validation: the 17.0.2.5 source archive passes PHP syntax and page-rendering
checks, including the readable module/settings diff presentation. The shared
archive's FreePBX 14, 15, 16 and 17 Module Admin installation, watcher-health,
request-audit, staged-drift, Apply Config, and clean-baseline gates were
completed for 17.0.2.4. Version 17.0.2.5 changes only the presentation layer
and must repeat the disposable lifecycle gate before publication. Both
embedded filesystem layouts and automatic OS-family detection were validated
in disposable containers. Live systemd activation of the embedded portable
layout still requires voluntary testing on a maintained
RHEL/CentOS/Sangoma-family PBX.

Version 17.0.2.5 also records watcher payload version 0.1.9 in every embedded,
Debian, and portable package. The UI and CLI compare that marker with the
module's bundled payload and provide the exact update command when they differ.
The interactive installer offers, but never silently performs, the appropriate
operating-system PyMySQL installation.

FreePBX 17: the 17.0.2.4 archive installation, watcher package layout, watcher
unit checks, request-audit checks, and core watcher smoke lifecycle passed on
September 16. The authenticated fixture gate also passed extension/ring-group/
queue changes, SIP and Advanced Settings breakers, immediate AstDB state,
module enable/disable, User Management UCP assignments, Fax Configuration
channels, outbound routes, custom trunks, the watcher-health page,
keyed-redaction persistence, watcher interruption recovery, Apply Config
baseline refreshes, and the final clean-state assertion. The 17.0.2.5 gate is
pending a fresh FreePBX mirror download.

Build with scripts/package-module.sh. Existing signatures cannot be reused
after metadata changes; these candidates must be signed before publication.

Refactoring review: version parsing in packaging, signing, publishing and lab
scripts assumed x.0.0.N and would truncate the requested x.0.1.0 release.
These paths now preserve the full suffix. No runtime PHP fork was necessary.
The page combines rendering helpers with presentation; extracting those is a
possible future cleanup, but is not necessary for cross-version compatibility.
