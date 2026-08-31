# Production pilot runbook

This runbook is for a single noncritical FreePBX 17 PBX after the Docker smoke
suite has passed. It does not authorize a production configuration change.
The watcher and module are observers: they must not call Apply Changes,
restart Asterisk, or modify FreePBX configuration.

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
