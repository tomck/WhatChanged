# Disposable FreePBX 14-16 compatibility lab

This lab exercises the versioned Pending Changes module archives and the
shared watcher against actual historical FreePBX/PHP/Asterisk stacks. It is a
test fixture, not a production FreePBX distribution.

## Run the gates

Build the legacy artifacts and run cross-version syntax, render, sensor, and
portable-watcher checks:

```sh
./docker/legacy-compatibility-gate.sh
```

Run the three real-image lifecycles, in order:

```sh
./docker/legacy-real-image-gate.sh
```

Each lifecycle preserves ordinary Docker volumes, installs the matching
module archive through Module Admin, creates one test-owned table, stages one
record with `need_reload`, verifies that both the watcher and the installed
FreePBX BMO report it, runs Apply Config, and verifies a refreshed clean
baseline.

An individual generation can be run with:

```sh
./docker/legacy-smoke.sh 16
./docker/legacy-smoke.sh 15
./docker/legacy-smoke.sh 14
```

The optional local web interfaces bind only to loopback:

- FreePBX 16: `http://127.0.0.1:8160/admin/`
- FreePBX 15: `http://127.0.0.1:8150/admin/`
- FreePBX 14: `http://127.0.0.1:8140/admin/`

No database, SIP, or RTP port is published. The FreePBX 14, 15, and 16 wrapper
images contain only fixture compatibility repairs; never deploy them as PBX
images.

## Reset one fixture

Ordinary reruns preserve installed files and databases. To delete only one
disposable legacy generation and its named volumes:

```sh
./docker/legacy-reset.sh 16
./docker/legacy-reset.sh 15
./docker/legacy-reset.sh 14
```

The reset command does not address the main FreePBX 17 Compose project.

## Interpreting a pass

A pass demonstrates archive metadata acceptance, PHP/runtime compatibility,
Module Admin installation, sidecar observation, FreePBX BMO consumption of the
watcher result, and the baseline transition around Apply Config. It does not
prove every FreePBX module or third-party state store is covered. Real alpha
testers must still compare deliberate changes against the explicit coverage
contract and report misses.
