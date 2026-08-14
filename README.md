# Pending Changes Tripwire

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
docker compose -f docker/docker-compose.yml run --rm smoke
docker compose -f docker/docker-compose.yml down -v
```

The PBX is based on Debian 12 and FreePBX 17. It uses named, project-scoped
volumes; do not point any environment variable or mount at a production PBX.
After the PBX finishes installing, install the module from
`/srv/pendingchanges`, then open **Admin → Pending Changes Tripwire** and use
**Seed applied baseline**. The smoke suite is safe to re-run and removes only
its own `pc_smoke_*` fixture rows.

## Watcher evaluation

`docker/custom-watcher` is a small separate, read-only Python watcher. It
polls the reload flag, configuration-table digest, and `/etc/asterisk` file
hashes and writes structured observations to its own volume.

`docker/tripwire` runs Open Source Tripwire with a policy restricted to
`/etc/asterisk`. Its baseline and reports are also stored in a disposable
volume. The smoke suite compares both watcher outputs: Tripwire should flag a
direct file edit; the custom watcher should flag both config-database and file
drift. Neither is used to decide whether FreePBX may reload.

## Module commands

Run within a FreePBX installation as the Asterisk user:

```sh
php /var/lib/asterisk/bin/pendingchanges status
php /var/lib/asterisk/bin/pendingchanges seed
```

`seed` refuses to replace the baseline while a reload is pending. Capture a
new baseline only after Apply Changes has completed successfully.
