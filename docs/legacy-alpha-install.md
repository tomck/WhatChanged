# WhatChanged legacy public-alpha test

These are compatibility candidates for FreePBX 14, 15, and 16. They are for
voluntary testing on backed-up, noncritical PBXs. FreePBX 14 and 15 are old
platforms and may contain unrelated security or operating-system risks.

All four FreePBX versions use `pendingchanges-17.0.1.2.tgz`.

The module archive embeds the same watcher for all three versions. A separate
portable watcher bundle remains available as an optional packaging choice.
The module can display a smaller framework-only fallback without the watcher,
but database, AstDB, file, module-state, feedback, and inferred-administrator
coverage require the watcher.

## Prerequisites

The embedded watcher requires systemd, Python 3.6 or newer, PyMySQL for that
Python, a MariaDB/MySQL client, and an `asterisk` service account. Automatic
credential setup also requires a local MariaDB/MySQL server. On a FreePBX
Distro/SNG7 host the PyMySQL package may be available as
`python3-PyMySQL`; on Debian it is normally `python3-pymysql`.

Verify before installing:

```sh
python3 --version
python3 -c 'import pymysql; print(pymysql.__version__)'
test -f /etc/freepbx.conf
```

Do not replace the system Python or enable an unreviewed third-party package
repository merely to satisfy this alpha dependency.

## Install the shared module and embedded watcher

FreePBX 14, 15 and 16 use the same commands:

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
sudo systemctl status what-changed-watcher --no-pager
```

The embedded installer selects its filesystem layout from the operating-system
family, not the FreePBX version. Both extraction and module-tree monitoring use
FreePBX's configured `AMPWEBROOT`, rather than assuming `/var/www/html`. It
creates a random credential for a dedicated
local database user with `SELECT` only, installs a value-free authenticated-
request sensor, and starts the observer. The separate portable watcher bundle
remains available but is not required.

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
