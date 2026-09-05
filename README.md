# WhatChanged

`pendingchanges` is a FreePBX diagnostic module. FreePBX 17 is the primary
target; FreePBX 14, 15, and 16 are separately versioned public-alpha
candidates. It explains the **Apply Changes** banner by comparing the current
configuration state with one baseline captured after a known-good apply.

It is deliberately read-only with respect to PBX configuration: it neither
reloads Asterisk nor changes FreePBX settings. FreePBX itself stores the
banner as a single `admin.need_reload` value, without the module, page, or
user that set it. Consequently, a pending reload with no detectable drift is
reported as **Reload requested; origin unavailable** rather than guessed at.

## Local Docker lab

The test environment is disposable and is intended only for local development:

```sh
docker compose -f docker/docker-compose.yml up --build
./docker/bootstrap-freepbx.sh
docker compose -f docker/docker-compose.yml run --rm smoke
./docker/smoke-freepbx-http.sh
docker compose -f docker/docker-compose.yml down -v
```

For the complete release gate (all watcher, authenticated FreePBX, breaker,
route, and trunk smoke coverage), use:

```sh
./docker/lab-gate.sh
```

The PBX is based on Debian 12 and FreePBX 17. It uses named, project-scoped
volumes; do not point any environment variable or mount at a production PBX.
Copy `.env.lab.example` to `.env.lab` and set a test-only password before
bootstrapping. The bootstrap script submits FreePBX's initial setup form with
automatic module updates disabled; it is safe to rerun after setup is complete.
The smoke suite is safe to re-run and removes only its own `pc_smoke_*` fixture
rows/files. It asserts added, updated, removed, unknown-origin, generated-file,
module-file, and module-owned exclusion behavior before restoring a clean
watcher baseline.

There is no official FreePBX Docker image. This lab remains a controlled test
fixture, not a production PBX distribution. A future companion image should
build Debian 12 through FreePBX's official installer, pin its source revision,
publish provenance/SBOM information, and pass this same release gate before it
is offered as an optional production-capable deployment.

`smoke-freepbx-http.sh` separately exercises the authenticated extension, ring
group, and queue fixture requests, confirms that FreePBX sets `need_reload`,
then confirms a normal Apply Changes returns the watcher to a clean baseline.

`smoke-breakers.sh` uses real authenticated SIP Settings and Advanced Settings
requests. It stages **Allow Transports Reload** and the non-secret global
`RINGTIMER` setting, verifies readable before/after watcher evidence, applies
each change, restores the original lab value, and applies again. Run it only
against this local lab:

```sh
./docker/smoke-breakers.sh
```

`smoke-outbound-route.sh` creates an isolated route through FreePBX's real
form handler, applies it as a baseline, then stages a readable route-name and
dial-pattern edit. It verifies the route, order, and pattern records before
removing only its own fixture and returning the lab to a clean applied state:

```sh
./docker/smoke-outbound-route.sh
```

`smoke-trunk.sh` similarly exercises a disabled Custom trunk with an
intentionally unusable dial string and no assigned route. It validates create,
name edit, and removal evidence without ever placing a call:

```sh
./docker/smoke-trunk.sh
```

## Watcher

`docker/custom-watcher` is the watcher used by the project. It is a small,
separate, read-only Python service that automatically captures a configuration
baseline while FreePBX is clean, then records added, removed, and updated
database records while Apply Changes is pending. Password-, secret-, token-,
and key-named fields are redacted. File drift remains a secondary signal only.

The watcher installation also enables a default, low-cost authenticated-request
sensor in Apache's PHP SAPI. For successful FreePBX admin write requests it
appends only username, timestamp, page/module/action, request method, and HTTP
status to a bounded local file. It never records form values, cookies, session
IDs, headers, or credentials. The sensor itself never queries the database.
The watcher correlates those breadcrumbs with a lightweight five-second
reload/event probe; a bounded full state scan runs immediately on a transition
or event and at most every 30 seconds while idle. The heavier module-file tree
scan runs every five minutes or immediately after observed Module Admin work.
It labels one account as
**likely** or several accounts as **possible** actors. This is supporting
evidence, not proof that an account
caused each state change; CLI, API, automation, shared accounts, stolen
sessions, and custom paths can remain unattributed.

For a reviewed manual watcher installation, enable the same default sensor
with:

```sh
sudo ./deploy/install-attribution-sensor.sh
```

That installer validates and reloads Apache only. It never invokes Apply
Config, `fwconsole reload`, or an Asterisk reload.

## Public alpha release artifacts

Alpha testers install two separately signed artifacts: the FreePBX module
archive (`pendingchanges-<version>.tgz`) and the Debian watcher package
(`what-changed-watcher_<version>_all.deb`). The module archive does **not**
contain the watcher. Build the watcher package in the disposable Debian 12 lab
with:

```sh
./scripts/package-watcher.sh
```

See [the alpha installation guide](docs/alpha-install.md) for the supported
one-PBX setup, checksum/signature verification, first-baseline workflow, and
remote-MariaDB limitation.

The Reports page now verifies the observer itself. A green **Healthy** result
requires a recently completed full watcher snapshot; merely finding an
installed service file is not enough. Delayed, stale, malformed, unreadable,
unconfigured, and absent observers are shown explicitly, and degraded states
never produce an all-clear message.

For a release staged on the signing host, create detached GPG signatures and a
signed checksum manifest without moving the secret key into the lab:

```sh
export WHAT_CHANGED_SIGNING_SUBKEY='<full signing-subkey fingerprint>'
./deploy/sign-release-artifacts.sh pendingchanges-17.0.0.12.tgz what-changed-watcher_0.1.2_all.deb
```

The complete 14-17 GitHub prerelease set has a stricter two-stage workflow.
Build the signing bundle locally, sign it interactively on the FreePBX signing
host, retrieve the resulting `signed/` directory, and verify it before
publishing:

```sh
./scripts/package-release-signing-bundle.sh
./scripts/verify-github-release-set.sh dist/signed-release
```

The version/tag map, exact per-generation installation commands, signing-host
procedure, and guarded GitHub publisher are documented in
[the GitHub release runbook](docs/github-releases.md). Release archives belong
on GitHub Releases, not in source-control history; all module and watcher tags
point to the same reviewed source commit from which their assets were built.

### FreePBX 14-16 compatibility candidates

The legacy candidates are separate archives with matching FreePBX major-version
metadata. Their shared PHP source is syntax-tested against PHP 5.6, 7.4, and
8.2. Build and run the compatibility gate with:

```sh
./docker/legacy-compatibility-gate.sh
```

Then run the digest-pinned real-image lifecycle for FreePBX 16, 15, and 14:

```sh
./docker/legacy-real-image-gate.sh
```

That produces FreePBX 14, 15, and 16 module candidates plus a portable
systemd watcher bundle for older FreePBX Distro/SNG7-style hosts. See
[the legacy alpha guide](docs/legacy-alpha-install.md). The representative
historical Docker stacks now pass Module Admin installation, watcher-to-BMO
integration, staged database drift, Apply Config, and clean-baseline checks.
They remain experimental until tested on varied maintained installations. See
[the Docker lab guide](docs/legacy-docker-lab.md) and
[the legacy test matrix](docs/legacy-test-matrix.md) for the exact evidence and
limits.

Open Source Tripwire is intentionally not part of this project: it can report
that a file changed, but cannot explain a pending FreePBX change.

## Module commands

Run within a FreePBX installation as the Asterisk user:

```sh
php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges status
php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges seed
php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges feedback
```

`seed` refuses to replace the baseline while a reload is pending. Capture a
new baseline only after Apply Changes has completed successfully.

## Public-alpha feedback export

The watcher never sends telemetry. For a public-alpha participant who chooses
to share what the watcher recognized, export its local bounded event ledger:

```sh
sudo -u asterisk /var/lib/asterisk/bin/pendingchanges feedback > whatchanged-feedback.json
```

The export contains only timestamps, source categories, added/removed/updated
counts, changed **field names**, and coverage-limit reasons. It intentionally
excludes configuration values, extension/device identifiers, AstDB keys and
values, filenames, module names, hostnames, credentials, and call data. The
local ledger retains at most 500 distinct change-type events; participants
choose whether to send the exported file to the project.

## Production-readiness checklist

Do not deploy the Docker image or its FreePBX/PHP compatibility shims to a
production PBX. Build a module archive from a reviewed Git revision, then
perform a read-only pilot on one noncritical PBX. A FreePBX local signature is
optional tamper-evidence for that individual PBX; it is not a Docker or release
gate.

Build and validate the Module Admin archive in the lab before handing it to a
pilot operator:

```sh
scripts/package-module.sh
./docker/validate-module-archive.sh dist/pendingchanges-17.0.0.12.tgz
```

Before that pilot, verify in the Docker lab that:

- module installation succeeds through Module Admin;
- extension creation, edit, and deletion appear as added, updated, and
  removed database records before Apply Changes;
- generated Asterisk files and Module Admin changes appear under separate file
  categories; Module Admin inventory bookkeeping is excluded from
  configuration-record changes;
- a normal Apply Changes clears the reload flag and refreshes the baseline;
- a reload flag with no detected state difference reports origin unavailable.

For a production pilot, use a dedicated database account with read-only access
to the FreePBX configuration database, mount watched paths read-only, restrict
the watcher state directory to the Asterisk service account, and retain only
the current baseline/status document. Start by recording a clean baseline after
a known Apply Changes, then compare the report with deliberate, documented
admin changes. Keep the module read-only; it must never apply, reload, or
repair PBX configuration.

The watcher reads only an explicit FreePBX configuration-table allowlist. Its
general cap is 5,000 rows, with explicit per-table ceilings for understood
configuration tables. The legacy-named `sip` table holds endpoint setting
records and is covered up to 20,000 rows; its setting values are retained in
the watcher-owned 0600 baseline and redacted from the web-readable report when
sensitive. Outbound-route coverage includes the route record, its ordered
position, dial patterns, and assigned trunk sequence. CDR, CEL, queue-log, and
unknown add-on tables are never eligible for watching.

FreePBX Module Admin activation state is covered through the `modules` table.
Enabling or disabling a module is reported by its module name and version;
cached signature-verification metadata is excluded from this configuration
signal because it can be refreshed without changing module activation. The
`pendingchanges` module's own activation/version row is also excluded so an
observer upgrade cannot manufacture pending configuration evidence.

User Management profile records and per-user module/UCP settings are covered
through `userman_users` and `userman_users_settings`. UCP assignments are
identified by username, module, and setting name; password/token/PIN-like
values are redacted while their field-level change remains visible.

Fax Configuration settings are covered through the bounded `fax_details`
table. This includes the concurrent fax channel limit as a readable before/after
change; fax job/history tables are deliberately not observed.

## Coverage contract

WhatChanged is a bounded drift reporter, not a universal preview or reversal
engine. A clean report means no drift was found **within the explicitly listed
coverage**, not that no FreePBX, Asterisk, or third-party state changed.

The watcher separately records these named immediate-state AstDB families:
`AMPUSER`, `DEVICE`, `CF`, `CFB`, `CFU`, `CFNA`, `DND`, `CW`, `FOLLOWME`, and
`BLKVM`. Those values may already be effective when a form is submitted, so
they are displayed as **Immediate Asterisk state**, never represented as a
pending Apply Config record. Arbitrary AstDB keys, runtime state, custom
module data, and any source not explicitly named by the report’s Coverage
contract may not be detected.

Administrator request attribution is a separate evidence layer over the same
watcher. It identifies authenticated FreePBX web accounts that submitted write
requests during the current pending interval and distinguishes the Framework
`reload` command used by Apply Config. It cannot authoritatively bind a
specific SQL/AstDB/file difference to a person, and changes made through CLI,
API, automation, direct database access, or uninstrumented custom entry points
may have no actor breadcrumb.

FreePBX rewrites `sip.flags` as display/order metadata whenever an endpoint
form is saved. The watcher deliberately excludes that volatile column so an
extension edit reports the meaningful endpoint settings instead of a long list
of false updates.

## Public alpha and responsible disclosure

This is alpha software. It adds a read-only observer and deliberately makes no
claim that every FreePBX, Asterisk, commercial-module, or custom-module state
store is covered. Anything not explicitly listed in the Coverage contract may
not be detected. A locally signed or untrusted-module warning may remain until
the author's OpenPGP primary key is certified through FreePBX's signing process.

Use the coverage-gap issue form for a reproducible missed-change report that
contains no PBX secrets or customer data. Report security problems privately
through [GitHub Security Advisories](SECURITY.md); never attach database dumps,
configuration archives, credentials, call records, or unredacted screenshots
to a public issue.

## License

Pending Changes Tripwire is licensed under the GNU General Public License,
version 3 or later (GPL-3.0-or-later). The module metadata and the distributable
module archive carry the same license declaration.
