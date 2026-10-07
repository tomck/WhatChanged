# WhatChanged

WhatChanged explains FreePBX's **Apply Config** button by showing configuration
drift since the last known-good apply. It reports added, changed, and removed
records in a readable diff, separates immediate Asterisk state and file drift,
and can show which authenticated administrator accounts may have staged work.

One module archive supports FreePBX 14, 15, 16, and 17. The current published
alpha is **17.0.2.6**. **WhatChanged** is the project; **Pending Changes
Tripwire** is the FreePBX module title, and its raw module name is
`pendingchanges`.

[Download the latest published alpha](https://github.com/tomck/WhatChanged/releases)
· [Full installation guide](docs/alpha-install.md)
· [Compatibility evidence](docs/legacy-test-matrix.md)
· [Contributing](CONTRIBUTING.md)

> [!IMPORTANT]
> WhatChanged is an observer, not a universal audit or rollback system. A clean
> report covers only the explicitly listed sources. Anything not listed in the
> Coverage contract may not be detected, and administrator attribution is
> supporting evidence rather than proof.

| FreePBX | Alpha status | Validation evidence |
| --- | --- | --- |
| 17 | Primary tested target | Exact 17.0.2.6 archive passed the complete Apache and nginx/PHP-FPM gates; the signed archive passed Module Admin installation |
| 16 | Compatibility-tested alpha | Exact 17.0.2.6 archive passed the real-image lifecycle; maintained-host feedback is still wanted |
| 15 | Compatibility-tested alpha | Exact 17.0.2.6 archive passed the PHP 5.6 real-image lifecycle; the underlying platform may itself be unsupported |
| 14 | Compatibility-tested alpha | Exact 17.0.2.6 archive passed the PHP 5.6 real-image lifecycle; the underlying platform may itself be unsupported |

See the [compatibility evidence](docs/legacy-test-matrix.md) for the exact
runtime versions and limits. These are test results, not a promise that an old
FreePBX operating system remains secure or vendor-supported.

## Install

### Recommended: inspect, verify, then install

Download the matching archive, checksum manifest, detached signatures, and
public key from the
[17.0.2.6 release](https://github.com/tomck/WhatChanged/releases/tag/pendingchanges-17.0.2.6).
Authenticate the public-key fingerprint through a channel you trust, then
follow the exact OpenPGP and checksum commands in the
[full installation guide](docs/alpha-install.md). A key downloaded from the
same release can prove that the files agree with one another, but by itself it
cannot prove who controls that key.

After verification, copy `pendingchanges-17.0.2.6.tgz` to the PBX and run:

```sh
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)

if [ -z "$freepbx_webroot" ]; then
  echo "Could not read AMPWEBROOT from FreePBX. Run 'sudo fwconsole setting AMPWEBROOT' and resolve any reported error." >&2
  exit 1
fi

module_parent="$freepbx_webroot/admin/modules"
module_dir="$module_parent/pendingchanges"

if [ ! -d "$module_parent" ]; then
  echo "FreePBX reported AMPWEBROOT=$freepbx_webroot, but its module directory was not found at: $module_parent" >&2
  exit 1
fi

sudo tar -xzf pendingchanges-17.0.2.6.tgz -C "$module_parent"
sudo chown -R asterisk:asterisk "$module_dir"
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
sudo "$module_dir/bin/install-watcher"
```

Expected completion includes a successful Module Admin install, an embedded
watcher installation summary, and a prompt to open **Reports → Pending Changes
Tripwire**. The watcher installer may ask permission to install PyMySQL; it
does not install packages without consent.

### Convenience install (trust GitHub and run)

For a disposable or otherwise explicitly trusted PBX, the release pinned by
the reviewed installer can be downloaded, checksum-verified,
OpenPGP-verified, and installed with one command:

```sh
curl -fsSL https://raw.githubusercontent.com/tomck/WhatChanged/main/install.sh | sudo bash
```

This convenience command trusts the copy of `install.sh` served from the
GitHub repository as its bootstrap. It is currently pinned to 17.0.2.6 rather
than GitHub's `/releases/latest` redirect, which excludes alpha prereleases.
The script requires GnuPG, verifies
both the signed checksum manifest and the detached archive signature, discovers
FreePBX's configured `AMPWEBROOT`, installs the module, and launches its
explicit watcher installer. If GnuPG is missing, it stops with the appropriate
package command instead of silently falling back to checksum-only validation.
Use the inspected manual path above when that GitHub trust boundary is not
appropriate.

The module archive contains the watcher; there is no required second download.
The last command is intentionally explicit because it installs a system service
and a web-request sensor as root. It detects Debian-family and
RHEL/CentOS/Sangoma-family systems and chooses the corresponding service paths.
It never runs Apply Config or reloads Asterisk. On Apache it validates and
reloads Apache; on nginx/PHP-FPM it validates and reloads nginx and the active
PHP-FPM service. Existing host warnings remain visible. WhatChanged does not
create or modify web-server virtual hosts or `DocumentRoot` directives. If no
supported web PHP SAPI is present, the core watcher remains usable but inferred
administrator attribution is explicitly unavailable.

The watcher requires systemd, PHP CLI, Python 3.6 or newer, PyMySQL, and the
normal `asterisk` service account. Automatic setup of its local database
account also requires a MariaDB/MySQL client. For a local database, the
installer creates a random credential for a dedicated `what_changed_watcher`
account with **SELECT only** access to each existing allowlisted table. It
preserves that credential on upgrades while reconciling the table grants. If
an administrator has supplied a different reviewed account, upgrades preserve
that account and do not alter its grants. For remote MariaDB,
it installs the files but leaves the service disabled until an administrator
supplies a reviewed SELECT-only credential. Database transport follows
FreePBX's configured `AMPDBSOCK` when present, or `AMPDBHOST` and `AMPDBPORT`
for TCP.

With table-scoped MariaDB grants, an absent optional-module table and an
existing table without permission produce the same database error. WhatChanged
therefore reports never-observed sources together as optional visibility of
unknown status, rather than falsely claiming that a missing table exists. A
source that was previously readable but disappears receives a stronger
coverage-regression warning. Both reports give the exact `install-watcher`
command to reconcile installer-managed grants when the table should exist.
The regression warning describes continuity against the current applied
baseline; after a legitimate Apply Config establishes a new baseline, an
unresolved source becomes an optional visibility limitation because MariaDB
still cannot distinguish an absent table from an ungranted one.
Newly readable coverage is deferred while Apply Config is already pending so
pre-existing rows are not misrepresented as newly staged changes.

The commercial Endpoint Manager's extension map (`endpoint_extensions`) is an
explicit optional source. This lets WhatChanged explain changes such as
"Update Config and Refresh Phone" when Endpoint Manager updates an extension
record and raises the global reload flag. Token-like fields remain redacted.

PHP supports only one `auto_prepend_file`. If another application already owns
that setting, WhatChanged leaves it untouched, completes the core watcher
installation, and reports administrator request attribution as unavailable.
Review the competing integration before rerunning `install-watcher`; never
delete another product's PHP configuration blindly.

If PyMySQL is missing, the installer shows the operating-system package
command and asks before running it. Answering yes installs the dependency and
continues the same installation; it never installs packages without explicit
confirmation. On an upgrade, the installer preserves the active watcher's
existing Debian or portable filesystem layout.

Before installing on a real PBX, make a current backup and verify the release
checksum and OpenPGP signatures. See the
[complete alpha installation and verification guide](docs/alpha-install.md).
Begin with a backed-up, noncritical PBX; FreePBX 14–16 support remains
experimental pending broader testing on maintained installations.

## Verify the installation

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
installed watcher versions match. The CLI doctor can confirm that the web-PHP
sensor is configured, but PHP CLI
cannot prove that a web request loaded it. Confirm the runtime line
**Loaded for this FreePBX web request** on the report page.
It also reports the bundled and installed watcher versions. If they do not
match, it prints the exact full-path `install-watcher` command needed to update
the payload.
The doctor reports `coverage_regressed=yes` and exits 2 if a table that was
readable in the applied baseline is no longer visible. It prints the affected
table names and the exact `install-watcher` command that reconciles
installer-managed grants. A reviewed Apply Config also establishes a new
baseline; if the table remains unavailable, it is then reported as an optional
visibility limitation rather than silently treated as covered.

A Module Admin upgrade does not silently replace the root-owned system service.
When a release contains a newer embedded watcher, the report page and doctor
mark the payload outdated and provide the exact `install-watcher` command. An
administrator must run that command explicitly; it preserves existing evidence
and configuration while updating the service payload.

Then open **Reports → Pending Changes Tripwire** in FreePBX. Before treating an
empty report as meaningful, require all four:

- **Watcher health: Healthy**
- **Watcher payload: Current**
- **Current full watcher snapshot**
- **Baseline: Continuity verified**

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
- Generated Asterisk configuration-file drift and module release/state changes,
  separated from normal FreePBX database changes.
- Authenticated administrator write requests during the pending interval,
  labelled **likely** or **possible**, never presented as definitive authorship.
- Watcher health, observation age, and explicit coverage limitations.

Password-, secret-, token-, PIN-, and key-like values are converted to keyed
fingerprints before baseline persistence and displayed only as `[redacted]`.
CDR, CEL, queue logs, call traffic, and unknown add-on tables are deliberately excluded.
The watcher never uploads telemetry.

FreePBX itself stores Apply Config as a single `admin.need_reload` flag. It does
not record which page, module, or person set that flag. When the flag is present
but no covered difference can explain it, WhatChanged reports
**Reload requested; origin unavailable** instead of guessing.

## Coverage and limitations

WhatChanged watches an explicit, bounded collection of FreePBX database tables,
selected AstDB families, generated files beneath FreePBX's configured
`ASTETCDIR`, and installed-module database state plus `module.xml`/`module.sig`
release markers. FreePBX's own module-signature checker remains responsible for
exhaustive file-integrity verification. The complete list is displayed on the
module's Coverage contract panel.

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
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
sudo -u asterisk \
  "$freepbx_webroot/admin/modules/pendingchanges/bin/pendingchanges" feedback \
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
freepbx_webroot=$(
  sudo /var/lib/asterisk/bin/fwconsole setting AMPWEBROOT |
    sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p'
)
sudo "$freepbx_webroot/admin/modules/pendingchanges/bin/uninstall-watcher"
sudo /var/lib/asterisk/bin/fwconsole ma uninstall pendingchanges
```

The uninstaller removes the service and web-PHP sensor but intentionally retains
the local evidence, `/etc/what-changed-watcher.env`, and the SELECT-only database
account so removal cannot silently erase forensic material. The retained items
can be reviewed and removed separately if they are no longer required.

## Development

Development and smoke testing happen only in disposable Docker labs. Build
instructions, the FreePBX 14–17 compatibility matrix, individual smoke tests,
packaging, signing, and release procedures are in
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Pending Changes Tripwire is licensed under the GNU General Public License,
version 3 or later (GPL-3.0-or-later).
