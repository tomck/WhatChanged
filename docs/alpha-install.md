# WhatChanged public-alpha installation

This alpha supports FreePBX 14–17 with one shared module archive. It is an
observer: installation, configuration, and removal do not Apply Config or
reload Asterisk. Installing the attribution sensor does validate and reload
Apache.

## Before installing

1. Create a current PBX backup and normal change record.
2. Download these matching release files to the PBX:
   - `pendingchanges-17.0.1.2.tgz`
   - `SHA256SUMS` and its detached signature, if supplied.
3. Check the SHA-256 checksum and detached GPG signature using the published
   project public key. A Debian package is also signed by an APT repository
   Release file when installed from the future repository.

The embedded watcher requires systemd, PHP CLI, Python 3.6 or newer, PyMySQL
for that Python, a MariaDB/MySQL client, and the normal `asterisk` service
account. The installer checks these prerequisites before changing the host and
prints the distribution-specific PyMySQL package name if it is absent.

The release publisher creates `SHA256SUMS`, `SHA256SUMS.asc`, and one `.asc`
detached signature per release artifact with the approved signing subkey. A
FreePBX local module signature is different: it is generated after the module
is installed on each PBX and does not replace the detached archive signature.

## Install

Install the shared module, then run its embedded watcher installer as root:

```sh
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
module_dir="$freepbx_webroot/admin/modules/pendingchanges"

if [ -d "$freepbx_webroot/admin/modules" ]; then
  sudo tar -xzf pendingchanges-17.0.1.2.tgz -C "$freepbx_webroot/admin/modules"
  sudo chown -R asterisk:asterisk "$module_dir"
  sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
  sudo "$module_dir/bin/install-watcher"
else
  echo "Could not find FreePBX's module directory beneath: $freepbx_webroot" >&2
fi
```

The first command asks FreePBX for its configured `AMPWEBROOT`; it does not
assume `/var/www/html`. The watcher installer reads that same authoritative
setting and writes the corresponding module-tree path into its systemd unit.

The installer reads `/etc/os-release`: Debian-family systems use `/usr/lib`
and `/lib/systemd/system`; RHEL, CentOS, and Sangoma-family systems use
`/usr/local/lib` and `/etc/systemd/system`. It refuses unknown systems unless
the administrator explicitly chooses a reviewed layout. It generates a random
password, creates a local MariaDB account named `what_changed_watcher` with
**SELECT only** on the FreePBX database, installs the authenticated-request
sensor, and starts the watcher. Existing watcher configuration and evidence
are preserved during upgrades.

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
sudo -u asterisk /var/lib/asterisk/bin/pendingchanges doctor
```

In FreePBX, open **Reports → Pending Changes Tripwire**. The Module Admin
status may say **Unsigned** until the module is locally signed on that PBX;
that is expected for an alpha archive and does not prevent operation.

The Watcher health card must say **Healthy** and **Current full watcher
snapshot** before an empty drift report can be treated as meaningful. A running
systemd unit alone is not sufficient. Delayed, stale, invalid, unreadable,
unconfigured, or absent states are deliberately degraded and cannot produce an
all-clear result. The attribution sensor line should say **Loaded for this
FreePBX web request** if inferred administrator evidence is expected.

Do one normal, known Apply Config only when you were already ready to apply
the PBX's existing pending work. The watcher then captures its first clean
baseline automatically. Do not seed a baseline while changes are pending.

## Optional local FreePBX module signature

FreePBX local signatures belong to the installed module directory, not the
`.tgz` file. After reviewing and installing the module, an operator with a
trusted local signing key can run the project's interactive signing helper on
that PBX. This does not sign the watcher `.deb`; use the detached release
signature or signed APT repository metadata for that artifact.

## Alpha feedback and uninstall

The watcher does not upload anything. To share its privacy-preserving
recognition summary voluntarily:

```sh
sudo -u asterisk /var/lib/asterisk/bin/pendingchanges feedback > whatchanged-feedback.json
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
