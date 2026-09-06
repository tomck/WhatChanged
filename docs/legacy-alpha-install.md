# WhatChanged legacy public-alpha test

These are compatibility candidates for FreePBX 14, 15, and 16. They are for
voluntary testing on backed-up, noncritical PBXs. FreePBX 14 and 15 are old
platforms and may contain unrelated security or operating-system risks.

All four FreePBX versions use `pendingchanges-17.0.1.0.tgz`.

The same portable watcher bundle is used for all three. The module can display
a smaller framework-only fallback without the watcher, but database, AstDB,
file, module-state, feedback, and inferred-administrator coverage require the
watcher.

## Prerequisites

The portable watcher requires systemd, Python 3.6 or newer, PyMySQL for that
Python, a local MariaDB/MySQL server, and an `asterisk` service account. On a
FreePBX Distro/SNG7 host the PyMySQL package may be available as
`python3-PyMySQL`; on Debian it is normally `python3-pymysql`.

Verify before installing:

```sh
python3 --version
python3 -c 'import pymysql; print(pymysql.__version__)'
test -f /etc/freepbx.conf
```

Do not replace the system Python or enable an unreviewed third-party package
repository merely to satisfy this alpha dependency.

## Install the watcher

Extract the portable bundle, review it, and run its installer:

```sh
tar -xzf what-changed-watcher-portable_0.1.2.tar.gz
cd what-changed-watcher-portable-0.1.2
sudo ./install.sh
sudo systemctl status what-changed-watcher --no-pager
```

The installer creates a random credential for a dedicated local database user
with `SELECT` only, installs a value-free authenticated-request sensor, and
starts the observer. It does not run Apply Config or reload Asterisk.

## Install the shared module

FreePBX 14, 15 and 16 use the same commands:

```sh
sudo tar -xzf pendingchanges-17.0.1.0.tgz -C /var/www/html/admin/modules
sudo chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
```

Then open **Reports -> Pending Changes Tripwire**. Establish a baseline only
after a known, reviewed Apply Config has completed and the PBX is clean.
Before relying on an empty report, require **Healthy** and **Current full
watcher snapshot** in the Watcher health card. An installed or running service
without a recent completed observation is shown as degraded, never as all
clear. On legacy distributions, also confirm the attribution sensor is loaded
if administrator-request correlation is expected.

## Send useful alpha feedback

```sh
sudo -u asterisk /var/lib/asterisk/bin/pendingchanges feedback > whatchanged-feedback.json
```

The feedback export contains change categories, counts, changed field names,
coverage-limit reasons, and timestamps. It omits values, extension numbers,
AstDB keys, filenames, module names, hostnames, credentials, and call data.

When reporting a result, include the exact FreePBX, framework, PHP, operating
system, and Asterisk versions, plus whether Module Admin installation and the
Reports page worked. A clean result means only that the explicitly listed
coverage found no difference; it is not proof that every FreePBX state store
was observed.
