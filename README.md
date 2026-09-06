# WhatChanged

WhatChanged explains FreePBX's **Apply Config** button by showing configuration
drift since the last known-good apply. It reports added, changed, and removed
records in a readable diff, separates immediate Asterisk state and file drift,
and can show which authenticated administrator accounts may have staged work.

One module archive supports FreePBX 14, 15, 16, and 17. The current public
alpha is **17.0.1.1**.

[Download the alpha](https://github.com/tomck/WhatChanged/releases/tag/pendingchanges-17.0.1.1)
· [Full installation guide](docs/alpha-install.md)
· [Compatibility evidence](docs/legacy-test-matrix.md)
· [Contributing](CONTRIBUTING.md)

> [!IMPORTANT]
> WhatChanged is an observer, not a universal audit or rollback system. A clean
> report covers only the explicitly listed sources. Anything not listed in the
> Coverage contract may not be detected, and administrator attribution is
> supporting evidence rather than proof.

## Install

Download `pendingchanges-17.0.1.1.tgz` from the
[17.0.1.1 alpha release](https://github.com/tomck/WhatChanged/releases/tag/pendingchanges-17.0.1.1),
copy it to the PBX, and run:

```sh
sudo tar -xzf pendingchanges-17.0.1.1.tgz -C /var/www/html/admin/modules
sudo chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
sudo /var/www/html/admin/modules/pendingchanges/bin/install-watcher
```

The module archive contains the watcher; there is no required second download.
The last command is intentionally explicit because it installs a system service
and an Apache request sensor as root. It detects Debian-family and
RHEL/CentOS/Sangoma-family systems and chooses the corresponding service paths.
It never runs Apply Config or reloads Asterisk. Installing the request sensor
does validate and reload Apache.

The watcher requires systemd, PHP CLI, Python 3.6 or newer, PyMySQL, a
MariaDB/MySQL client, and the normal `asterisk` service account. For a local
database, the installer creates a random credential for a dedicated
`what_changed_watcher` account with **SELECT only** access. For remote MariaDB,
it installs the files but leaves the service disabled until an administrator
supplies a reviewed SELECT-only credential.

Before installing on a real PBX, make a current backup and verify the release
checksum and OpenPGP signatures. See the
[complete alpha installation and verification guide](docs/alpha-install.md).
Begin with a backed-up, noncritical PBX; FreePBX 14–16 support remains
experimental pending broader testing on maintained installations.

## Verify the installation

```sh
sudo systemctl status what-changed-watcher --no-pager
sudo -u asterisk php \
  /var/www/html/admin/modules/pendingchanges/bin/pendingchanges doctor
```

Then open **Reports → Pending Changes Tripwire** in FreePBX. Before treating an
empty report as meaningful, require both:

- **Watcher health: Healthy**
- **Current full watcher snapshot**

A running service alone is not enough. Missing, delayed, stale, malformed, or
unconfigured watcher states are shown as degraded and never produce an
all-clear result.

If Apply Config was already pending when WhatChanged was installed, the watcher
will not invent or overwrite a baseline. Review the existing work first. After
a known, successful Apply Config, it automatically captures the clean baseline
used for subsequent comparisons.

## What it reports

- FreePBX configuration records added, changed, or removed since the applied
  baseline, including covered extensions, routes, trunks, queues, ring groups,
  module activation, User Management/UCP, fax, SIP, and Advanced Settings data.
- Selected immediate AstDB state, displayed separately because some form
  submissions take effect before Apply Config.
- Generated Asterisk configuration-file drift and module-tree changes,
  separated from normal FreePBX database changes.
- Authenticated administrator write requests during the pending interval,
  labelled **likely** or **possible**, never presented as definitive authorship.
- Watcher health, observation age, and explicit coverage limitations.

Password-, secret-, token-, PIN-, and key-like fields are redacted. CDR, CEL,
queue logs, call traffic, and unknown add-on tables are deliberately excluded.
The watcher never uploads telemetry.

FreePBX itself stores Apply Config as a single `admin.need_reload` flag. It does
not record which page, module, or person set that flag. When the flag is present
but no covered difference can explain it, WhatChanged reports
**Reload requested; origin unavailable** instead of guessing.

## Coverage and limitations

WhatChanged watches an explicit, bounded collection of FreePBX database tables,
selected AstDB families, generated `/etc/asterisk/*.conf` files, and installed
module trees. The complete list is displayed on the module's Coverage contract
panel.

Important limits:

- A third-party or commercial module may store settings somewhere not yet
  covered.
- Direct SQL, CLI, API, automation, shared accounts, or uninstrumented custom
  entry points may have no administrator breadcrumb.
- Request correlation shows who submitted related FreePBX writes; it cannot
  prove that an account caused each reported state difference.
- Some AstDB-backed settings are already live when submitted and cannot be
  described honestly as pending Apply Config work.
- WhatChanged does not apply, discard, revert, or repair PBX configuration.

See the [production pilot guide](docs/production-pilot.md) and
[compatibility evidence](docs/legacy-test-matrix.md) for the precise assurance
boundary.

## Alpha feedback

Alpha testers can export a privacy-preserving summary of what the watcher
recognized:

```sh
sudo -u asterisk /var/lib/asterisk/bin/pendingchanges feedback \
  > whatchanged-feedback.json
```

The export includes timestamps, change categories, counts, changed field names,
and coverage-limit reasons. It omits configuration values, extension numbers,
AstDB keys, filenames, module names, hostnames, credentials, and call data.
Nothing is sent automatically.

Use the coverage-gap issue template for sanitized missed-change reports. Send
security concerns privately through [GitHub Security Advisories](SECURITY.md),
never through a public database dump or configuration archive.

## Remove

Run the watcher uninstaller before removing the FreePBX module:

```sh
sudo /var/www/html/admin/modules/pendingchanges/bin/uninstall-watcher
sudo /var/lib/asterisk/bin/fwconsole ma uninstall pendingchanges
```

The uninstaller removes the service and Apache sensor but intentionally retains
the local evidence, `/etc/what-changed-watcher.env`, and the SELECT-only database
account so removal cannot silently erase forensic material. The retained items
can be reviewed and removed separately if they are no longer required.

## Development

Development and smoke testing happen only in disposable Docker labs. Build
instructions, the FreePBX 14–17 compatibility matrix, individual smoke tests,
packaging, signing, and release procedures are in
[CONTRIBUTING.md](CONTRIBUTING.md).

Open Source Tripwire is intentionally not used: it can say that a file changed,
but it cannot explain the FreePBX records waiting behind Apply Config.

## License

Pending Changes Tripwire is licensed under the GNU General Public License,
version 3 or later (GPL-3.0-or-later).
