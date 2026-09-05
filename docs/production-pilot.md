# Production pilot runbook

This runbook is for a single noncritical FreePBX 17 PBX after the Docker smoke
suite has passed. It does not authorize a production configuration change.
The watcher and module are observers: they must not call Apply Changes,
restart Asterisk, or modify FreePBX configuration.

## Authenticated request attribution

The watcher installs request attribution by default. It is intentionally much
smaller than a general web audit logger: successful authenticated FreePBX
write requests append only the account name, timestamp, page/module/action,
method, and status to a bounded local JSONL file. Form values, cookies,
sessions, headers, and credentials are never recorded. There is no additional
full database scan for attribution itself: the watcher uses a lightweight
five-second reload/event probe and performs its bounded full observation on a
transition, an event, or at most once every 30 seconds while idle.
The separate module-file tree digest runs every five minutes and is pulled
forward when authenticated request metadata indicates Module Admin activity.

Treat **likely staged by** and **possible actors** as investigative leads, not
proof. A shared or stolen account, concurrent admins, CLI, API, automation,
direct database change, or custom PHP path can defeat exact attribution. The
state diff remains the authoritative evidence of what the bounded watcher saw.

## Release preparation

1. Start from a reviewed, tagged Git revision, run `scripts/package-module.sh`,
   and run `./docker/validate-module-archive.sh dist/pendingchanges-<version>.tgz`.
2. Optionally use FreePBX local signing on the target PBX to add tamper
   evidence. It is PBX-specific and is not required for functional validation.
   Do not copy the Docker lab's PHP compatibility shim or any lab credentials
   to the PBX.
3. Validate the archive in a fresh disposable Docker volume using Module Admin
   before placing it on a PBX.

## Pilot prerequisites

- A current backup and a maintenance/change record exist for the pilot.
- The watcher has a dedicated MariaDB account limited to `SELECT` on the
  FreePBX configuration database. It must not have write, DDL, or reload
  permissions.
- `/etc/asterisk`, `/var/www/html/admin/modules`, and (when enabled)
  `/var/lib/asterisk/astdb.sqlite3` are mounted/readable
  read-only by the watcher. Its state directory is writable only by its own
  service account.
- The module uses the same status document read-only. Keep it unavailable if
  its permissions cannot be made safe.
- The watcher uses an explicit FreePBX configuration-table allowlist and a
  5,000-row cap per watched table. It never reads CDR, CEL, queue-log, or
  unknown add-on tables. A table above the cap is displayed as a coverage
  limitation, not as a pending change; review that notice before relying on
  the report as complete.

## Installation and validation

1. Copy the reviewed archive to the pilot PBX, install it through Module Admin,
   and start the watcher service. Confirm Module Admin lists it as either
   signed or explicitly **Unsigned** (the expected status for an intentionally
   unsigned local archive); do not mistake the warning for an install failure.
   On the Reports page require **Healthy**, **Current full watcher snapshot**,
   and (for administrator correlation) **Loaded for this FreePBX web request**.
   A running unit without a recent completed observation is not healthy.
2. Perform a known, normal Apply Changes. Wait for the watcher to record a
   clean baseline; retain only that baseline and its current status document.
3. Make one documented, reversible test change without Apply Changes. Verify
   the page/CLI reports the correct added, updated, or removed record.
4. Revert or apply that test change through the normal FreePBX workflow. Verify
   the next clean baseline has no remaining drift.
5. Make no automatic remediation based on the report. Treat it as a review
   signal and compare it with the change record before an operator applies
   unrelated pending changes.

## Rollback

Stop the watcher and remove the module through Module Admin. Preserve the
final status document and baseline only if local retention policy permits.
This rollback changes neither generated Asterisk configuration nor PBX call
handling.

## Scope statement

Treat a clean report as “no drift detected in the named coverage,” never as
proof that no PBX state changed. The watcher reads only its explicit database
table allowlist, generated Asterisk files, module tree digests, and these
explicit AstDB families: `AMPUSER`, `DEVICE`, `CF`, `CFB`, `CFU`, `CFNA`,
`DND`, `CW`, `FOLLOWME`, and `BLKVM`. Other AstDB data, arbitrary custom
modules, and runtime state are out of scope unless deliberately added and
smoke-tested.

The database allowlist includes FreePBX's `modules` activation records, so an
enable or disable operation is reported by module name. Module file digests
remain a separate signal for installed code changes; cached module-signature
verification metadata is not treated as pending configuration.
The observer's own `pendingchanges` module record is excluded as module-owned
state; other module enable/disable/version records remain covered.

User Management coverage includes the bounded `userman_users` and
`userman_users_settings` tables. The latter is joined to the username for a
readable local report; secret-looking setting values are redacted, and the
public-alpha feedback export retains only source/count/field-name metadata.

Fax Configuration coverage includes the bounded `fax_details` settings table,
including the concurrent fax channel limit. Fax store/history records are not
configuration evidence and remain outside the allowlist.

If the health card reports delayed, stale, invalid, unreadable, unconfigured,
or not installed, the full watcher result is not current. The module may show
last-known or framework-only evidence to aid diagnosis, but it deliberately
refuses to describe an empty degraded result as clean.
