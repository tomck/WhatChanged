# Shared module release 17.0.2.6

The default archive, pendingchanges-17.0.2.6.tgz, declares FreePBX 14.0,
15.0, 16.0 and 17.0 support and requires PHP 5.6 or newer.
The module version is a release identifier, not the minimum FreePBX version.

There is one PHP source tree and one module archive for all four versions.
The release workflow creates one module tag, signs once, and publishes once.

The module embeds the watcher payload and an explicit root installer. It selects
Debian-family or RHEL/CentOS/Sangoma-family paths from the operating system, not
the FreePBX version. It also reads FreePBX's configured `AMPWEBROOT` so
module-file monitoring follows nonstandard web roots. Standalone Debian and
portable packages remain available but are optional.

Validation: the exact unsigned 17.0.2.6 archive passed full Apache and
nginx/PHP-FPM FreePBX 17 gates, PHP compatibility checks, and FreePBX 14, 15,
and 16 real-image lifecycles. These covered Module Admin installation, watcher
health, staged drift, Apply Config, and a clean baseline. Both embedded
filesystem layouts and automatic OS-family detection were validated
in disposable containers. Live systemd activation of the embedded portable
layout still requires voluntary testing on a maintained
RHEL/CentOS/Sangoma-family PBX.

The release checksums, detached signatures, and embedded `module.sig` were
verified after signing. The exact signed archive installed through FreePBX
Module Admin in the disposable Docker lab; its key may be labeled "Unknown"
until certified. No production PBX was changed for this validation.

Version 17.0.2.6 also records watcher payload version 0.1.9 in every embedded,
Debian, and portable package. The UI and CLI compare that marker with the
module's bundled payload and provide the exact update command when they differ.
The interactive installer offers, but never silently performs, the appropriate
operating-system PyMySQL installation.

FreePBX 17: the Apache and nginx gates passed September 23 with extension,
inbound-route, ring-group, queue, SIP and Advanced Settings, immediate AstDB,
module disable, User Management UCP, fax-channel, outbound-route, and
custom-trunk changes. They also passed watcher-health, keyed redaction,
interruption recovery, Apply Config baseline refreshes, and final clean state.

Build with scripts/package-module.sh. Existing signatures cannot be reused
after metadata changes; any subsequent archive must be signed and validated
as a new release artifact before publication.

Refactoring review: version parsing in packaging, signing, publishing and lab
scripts assumed x.0.0.N and would truncate the requested x.0.1.0 release.
These paths now preserve the full suffix. No runtime PHP fork was necessary.
The page combines rendering helpers with presentation; extracting those is a
possible future cleanup, but is not necessary for cross-version compatibility.
