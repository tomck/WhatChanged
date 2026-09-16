# WhatChanged public-alpha installation

This alpha supports FreePBX 14–17 with one shared module archive. It is an
observer: installation, configuration, and removal do not Apply Config or
reload Asterisk. Installing the attribution sensor validates Apache's complete
host configuration and then reloads Apache. Apache may print warnings from
existing virtual hosts or modules during that validation. WhatChanged does not
create or modify Apache `DocumentRoot` directives; `Syntax OK` followed by the
installer's validation-passed message means the reload preflight succeeded.

## Before installing

1. Create a current PBX backup and normal change record.
2. Download these matching release files to the PBX:
   - `pendingchanges-17.0.2.1.tgz`
   - `SHA256SUMS` and its detached signature, if supplied.
3. Check the SHA-256 checksum and detached GPG signature using the published
   project public key. A Debian package is also signed by an APT repository
   Release file when installed from the future repository.

The embedded watcher requires systemd, PHP CLI, Python 3.6 or newer, PyMySQL
for that Python, a MariaDB/MySQL client, and the normal `asterisk` service
account. The installer checks these prerequisites before changing the host,
shows the distribution-specific package command if PyMySQL is absent, and asks
before installing it. Accepting the prompt installs the dependency and
continues the same watcher installation.

The release publisher creates `SHA256SUMS`, `SHA256SUMS.asc`, one `.asc`
detached signature per release artifact, and a distributable FreePBX
`module.sig` inside the module archive. FreePBX's `--local` signing mode is
different: it creates a PBX-specific sidecar under `/etc/freepbx.secure` and
must not be used to build a portable release archive.

## Install

Install the shared module, then run its embedded watcher installer as root:

```sh
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
module_dir="$freepbx_webroot/admin/modules/pendingchanges"

if [ -d "$freepbx_webroot/admin/modules" ]; then
  sudo tar -xzf pendingchanges-17.0.2.1.tgz -C "$freepbx_webroot/admin/modules"
  sudo chown -R asterisk:asterisk "$module_dir"
  sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
  sudo "$module_dir/bin/install-watcher"
else
  echo "Could not find FreePBX's module directory beneath: $freepbx_webroot" >&2
fi
```

The first command asks FreePBX for its configured `AMPWEBROOT`; it does not
assume `/var/www/html`. The watcher installer reads that same authoritative
settings and writes the corresponding module and Asterisk paths into its systemd unit.

The installer reads `/etc/os-release`: Debian-family systems use `/usr/lib`
and `/lib/systemd/system`; RHEL, CentOS, and Sangoma-family systems use
`/usr/local/lib` and `/etc/systemd/system`. It refuses unknown systems unless
the administrator explicitly chooses a reviewed layout. It generates a random
password, creates a local MariaDB account named `what_changed_watcher` with
**SELECT only** on the FreePBX database, installs the authenticated-request
sensor, and starts the watcher. Existing watcher configuration and evidence
are preserved during upgrades. A configured `AMPDBSOCK` is used for local
Unix-socket connections; otherwise the watcher follows `AMPDBHOST` and
`AMPDBPORT` for TCP.
An existing install keeps the filesystem and systemd-unit layout used by its
active service, even when that is the portable `/usr/local` layout on Debian.

Standalone `.deb` and portable watcher packages remain available for operators
who prefer operating-system package management, but are not required.

If the PBX uses remote MariaDB, the files are installed but the service remains
disabled. Create a reviewed `SELECT`-only account for the PBX host, update
`/etc/what-changed-watcher.env`, and start the service manually:

```sh
sudo systemctl enable --now what-changed-watcher
```

## Verify without changing PBX configuration

```sh
sudo systemctl status what-changed-watcher --no-pager
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
sudo "$freepbx_webroot/admin/modules/pendingchanges/bin/install-watcher" --check
sudo -u asterisk \
  "$freepbx_webroot/admin/modules/pendingchanges/bin/pendingchanges" doctor
```

The installer check reports `payload_state=current` when its bundled and
installed watcher versions match. The command-line doctor reports
`sensor_configured=yes` when it finds the
Apache PHP sensor configuration. It deliberately reports
`sensor_loaded=not_applicable_cli`: PHP CLI does not load Apache's PHP
configuration and therefore cannot prove that the sensor ran in a web request.
The FreePBX page is the authoritative runtime check.
The doctor also reports `watcher_payload_current=yes` when the installed
watcher matches the module. Otherwise it prints `watcher_update_command` with
the exact full command to run.

In FreePBX, open **Reports → Pending Changes Tripwire**. The release archive
contains `module.sig`. Until the maintainer's key is certified by Sangoma, a
stock PBX may report that the signature uses an untrusted or invalid key. It
must not report a missing `pendingchanges.sig` file; that indicates a broken
host-local release signature.

The Watcher health card must say **Healthy**, **Watcher payload: Current**,
**Current full watcher snapshot**, and **Baseline: Continuity verified** before
an empty drift report can be treated as meaningful. A running
systemd unit alone is not sufficient. Delayed, stale, invalid, unreadable,
unconfigured, or absent states are deliberately degraded and cannot produce an
all-clear result. The attribution sensor line should say **Loaded for this
FreePBX web request** if inferred administrator evidence is expected.

Do one normal, known Apply Config only when you were already ready to apply
the PBX's existing pending work. The watcher then captures its first clean
baseline automatically. Do not seed a baseline while changes are pending.

## Optional local signing for private modifications

If an operator modifies the installed module, FreePBX's `--local` signing mode
can attest that private copy on that one PBX. Its sidecar under
`/etc/freepbx.secure` is intentionally not portable and must never be copied
into a public release archive. This does not sign the watcher `.deb`; use the
detached release signature or signed APT repository metadata for that artifact.

## Alpha feedback and uninstall

The watcher does not upload anything. To share its privacy-preserving
recognition summary voluntarily:

```sh
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
sudo -u asterisk \
  "$freepbx_webroot/admin/modules/pendingchanges/bin/pendingchanges" feedback \
  > whatchanged-feedback.json
```

To remove an embedded watcher, run its explicit uninstaller before removing
the FreePBX module through Module Admin:

```sh
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
sudo "$freepbx_webroot/admin/modules/pendingchanges/bin/uninstall-watcher"
```

The watcher configuration, SELECT-only database account, and evidence are
intentionally retained so removal cannot silently destroy forensic data.
