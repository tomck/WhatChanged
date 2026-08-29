# Production pilot runbook

This runbook is for a single noncritical FreePBX 17 PBX after the Docker smoke
suite has passed. It does not authorize a production configuration change.
The watcher and module are observers: they must not call Apply Changes,
restart Asterisk, or modify FreePBX configuration.

## Release preparation

1. Start from a reviewed, tagged Git revision and run `scripts/package-module.sh`.
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
- `/etc/asterisk` and `/var/www/html/admin/modules` are mounted/readable
  read-only by the watcher. Its state directory is writable only by its own
  service account.
- The module uses the same status document read-only. Keep it unavailable if
  its permissions cannot be made safe.
- Baseline scope is reviewed for PBX size: configuration tables are expected
  to be modest. Exclude call-detail/log/volatile tables; do not snapshot very
  large operational tables until a bounded strategy is implemented.

## Installation and validation

1. Install the signed module through Module Admin and start the watcher.
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
