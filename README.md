# WhatChanged

`pendingchanges` is a FreePBX 17 diagnostic module. It explains the **Apply
Changes** banner by comparing the current configuration state with one
baseline captured after a known-good apply.

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

The PBX is based on Debian 12 and FreePBX 17. It uses named, project-scoped
volumes; do not point any environment variable or mount at a production PBX.
Copy `.env.lab.example` to `.env.lab` and set a test-only password before
bootstrapping. The bootstrap script submits FreePBX's initial setup form with
automatic module updates disabled; it is safe to rerun after setup is complete.
The smoke suite is safe to re-run and removes only its own `pc_smoke_*` fixture
rows/files. It asserts added, updated, removed, unknown-origin, generated-file,
module-file, and module-owned exclusion behavior before restoring a clean
watcher baseline.

`smoke-freepbx-http.sh` separately exercises the authenticated extension, ring
group, and queue fixture requests, confirms that FreePBX sets `need_reload`,
then confirms a normal Apply Changes returns the watcher to a clean baseline.

## Watcher

`docker/custom-watcher` is the watcher used by the project. It is a small,
separate, read-only Python service that automatically captures a configuration
baseline while FreePBX is clean, then records added, removed, and updated
database records while Apply Changes is pending. Password-, secret-, token-,
and key-named fields are redacted. File drift remains a secondary signal only.

Open Source Tripwire is intentionally not part of this project: it can report
that a file changed, but cannot explain a pending FreePBX change.

## Module commands

Run within a FreePBX installation as the Asterisk user:

```sh
php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges status
php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges seed
```

`seed` refuses to replace the baseline while a reload is pending. Capture a
new baseline only after Apply Changes has completed successfully.

## Production-readiness checklist

Do not deploy the Docker image or its FreePBX/PHP compatibility shims to a
production PBX. Build a module archive from a reviewed Git revision, then
perform a read-only pilot on one noncritical PBX. A FreePBX local signature is
optional tamper-evidence for that individual PBX; it is not a Docker or release
gate.

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

The watcher reads only an explicit FreePBX configuration-table allowlist. A
watched table with more than 5,000 rows is not read into a baseline; the page
reports this as a coverage limitation. CDR, CEL, queue-log, and unknown add-on
tables are never eligible for watching.
