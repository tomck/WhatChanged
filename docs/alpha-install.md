# WhatChanged public-alpha installation

This alpha supports FreePBX 14, 15, 16, and 17 with one shared module
archive (`pendingchanges-17.0.1.0.tgz`) on a PBX with a **local** MariaDB
server. It is an observer: installation, configuration, and removal must not
Apply Config or reload Asterisk. See
[shared module compatibility](shared-module.md).

## Before installing

1. Create a current PBX backup and normal change record.
2. Download these matching release files to the PBX:
   - `pendingchanges-17.0.1.0.tgz`
   - the watcher for your OS: `what-changed-watcher_0.1.2_all.deb`
     (Debian 12 / FreePBX 17) or `what-changed-watcher-portable_0.1.2.tar.gz`
     (CentOS 7 / SangomaOS / SNG7 and other legacy hosts)
   - `SHA256SUMS` and its detached signature, if supplied.
3. Check the SHA-256 checksum and detached GPG signature using the published
   project public key. See [alpha release verification](release-assets.md).

The release publisher creates `SHA256SUMS`, `SHA256SUMS.asc`, and one `.asc`
detached signature per release artifact with the approved signing subkey. A
FreePBX local module signature is different: it is generated after the module
is installed on each PBX and does not replace the detached archive signature.
Module Admin installs and runs Unsigned archives normally; see
[local signing](local-signing.md).

## Install

Install the shared module archive on any supported FreePBX version:

```sh
sudo tar -xzf pendingchanges-17.0.1.0.tgz -C /var/www/html/admin/modules
sudo chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
```

### Easiest watcher path: from the module you just installed

The module archive embeds the watcher, so no second download is needed.
As root, run the bundled installer; it detects Debian vs
CentOS/SangomaOS layouts automatically:

```sh
sudo /var/www/html/admin/modules/pendingchanges/bin/install-watcher
```

### Standalone watcher packages

If you prefer the separate artifacts:

Debian 12 / FreePBX 17:

```sh
sudo apt install ./what-changed-watcher_0.1.2_all.deb
sudo what-changed-watcher-configure
```

CentOS 7 / SangomaOS / legacy hosts:

```sh
tar -xzf what-changed-watcher-portable_0.1.2.tar.gz
cd what-changed-watcher-portable-0.1.2
sudo ./install.sh
```

All three paths generate a new random password, create a local MariaDB
account named `what_changed_watcher` with **SELECT only** on the FreePBX
database, install the authenticated-request sensor, and start the watcher.
They do not read form values, do not Apply Config, and do not reload
Asterisk.

If the PBX uses a remote MariaDB server, create a reviewed `SELECT`-only
account for the PBX host, update `/etc/what-changed-watcher.env`, and then
start the service manually:

```sh
sudo systemctl enable --now what-changed-watcher
```

## Verify without changing PBX configuration

```sh
sudo systemctl status what-changed-watcher --no-pager
sudo -u asterisk php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges doctor
```

`doctor` exits 0 only when the watcher has published a current observation;
it prints the watcher state and, when the watcher is missing, the exact
installer command for that host. The full JSON status is available with the
`status` command.

In FreePBX, open **Reports → Pending Changes Tripwire**. The Watcher health
card must show **Healthy** and **Current full watcher snapshot** before you
treat an empty report as all clear. A running systemd unit alone is not
sufficient: delayed, stale, invalid, unreadable, unconfigured, or absent
states are deliberately degraded and never produce an all-clear result. The
attribution sensor line should say **Loaded for this FreePBX web request**
if inferred administrator evidence is expected. The Module Admin status may
say **Unsigned** until the module is locally signed on that PBX; that is
expected and does not prevent operation.

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
