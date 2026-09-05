# WhatChanged public-alpha installation

This alpha supports FreePBX 17 on a Debian 12 PBX with a **local** MariaDB
server. It is an observer: installation, configuration, and removal must not
Apply Config or reload Asterisk.

## Before installing

1. Create a current PBX backup and normal change record.
2. Download these matching release files to the PBX:
   - `pendingchanges-<module-version>.tgz`
   - `what-changed-watcher_<watcher-version>_all.deb`
   - `SHA256SUMS` and its detached signature, if supplied.
3. Check the SHA-256 checksum and detached GPG signature using the published
   project public key. A Debian package is also signed by an APT repository
   Release file when installed from the future repository.

The release publisher creates `SHA256SUMS`, `SHA256SUMS.asc`, and one `.asc`
detached signature per release artifact with the approved signing subkey. A
FreePBX local module signature is different: it is generated after the module
is installed on each PBX and does not replace the detached archive signature.

## Install

Run these commands as a root-capable administrator, substituting the exact
downloaded filenames:

```sh
sudo apt install ./what-changed-watcher_0.1.2_all.deb
sudo what-changed-watcher-configure

sudo tar -xzf pendingchanges-17.0.0.12.tgz -C /var/www/html/admin/modules
sudo chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
```

The watcher setup generates a new random password, creates a local MariaDB
account named `what_changed_watcher` with **SELECT only** on the FreePBX
database, installs the authenticated-request sensor, and starts the watcher.
It does not read form values, does not Apply Config, and does not reload
Asterisk.

If the PBX uses a remote MariaDB server, stop at the setup command. Create a
reviewed `SELECT`-only account for the PBX host, update
`/etc/what-changed-watcher.env`, and then start the service manually:

```sh
sudo systemctl enable --now what-changed-watcher
```

## Verify without changing PBX configuration

```sh
sudo systemctl status what-changed-watcher --no-pager
sudo -u asterisk php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges status
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

To remove the observer, stop/remove the package and remove the FreePBX module
through Module Admin. The watcher state directory is intentionally retained so
the final local evidence is not erased automatically.
