# Contributing

Thank you for helping improve WhatChanged. The project accepts coverage fixes,
compatibility reports, tests, documentation, and carefully bounded support for
additional FreePBX state stores.

## Safety contract

- Develop and test only in the disposable Docker labs. Never submit production
  PBX data, credentials, extensions, trunks, call records, or configuration
  archives.
- Keep the module and watcher read-only. They must never Apply Config, reload
  Asterisk, or automatically revert a setting.
- Add new sources to the explicit Coverage contract, bound their size, redact
  secret-looking fields, and include a fixture proving add/update/remove
  behavior plus a clean post-apply baseline.
- Preserve PHP 5.6 syntax for FreePBX 14/15 and Python 3.6 syntax for the
  portable watcher unless the compatibility policy is deliberately raised.
- Use synthetic identifiers in tests and bug reports. A clean report must never
  be advertised as universal detection.

## FreePBX 17 Docker lab

Copy the example environment file and set test-only credentials:

```sh
cp .env.lab.example .env.lab
docker compose -f docker/docker-compose.yml up --build
./docker/bootstrap-freepbx.sh
```

The lab uses Debian 12, FreePBX 17, project-scoped Docker volumes, MariaDB, the
watcher, and synthetic fixtures. Never point its mounts or environment values
at a production PBX. Ordinary restarts preserve the lab volumes; use the
documented reset only when a genuinely fresh environment is required.

Run the complete FreePBX 17 release gate with:

```sh
./docker/lab-gate.sh
```

That single command covers packaging and Module Admin installation, watcher
unit tests, request-audit behavior, embedded Debian/portable layouts,
authenticated extension/ring-group/queue fixtures, create/update/delete drift,
SIP and Advanced Settings breakers, AstDB immediate state, module disable,
User Management/UCP, fax channels, outbound routes, disabled custom trunks,
Apply Config baseline refreshes, and final watcher-health rendering.

Useful focused scenarios include:

```sh
./docker/smoke-freepbx-http.sh
./docker/smoke-breakers.sh
./docker/smoke-outbound-route.sh
./docker/smoke-trunk.sh
./docker/smoke-embedded-watcher.sh
./docker/smoke-watcher-health-page.sh
```

Each fixture owns a synthetic namespace and must remove only its own data. A
scenario is not complete until Apply Config has succeeded and the watcher has
returned to a clean current baseline.

Stop the ordinary lab without deleting volumes:

```sh
docker compose -f docker/docker-compose.yml down
```

The repository's FreePBX image is a test fixture, not a supported production
PBX distribution.

## FreePBX 14–16 compatibility

There is one module source tree and one archive for FreePBX 14–17. Run the
cross-version syntax, metadata, page-rendering, request-sensor, and embedded
payload checks with:

```sh
./docker/legacy-compatibility-gate.sh
```

Then run the digest-pinned real-image lifecycle probes:

```sh
./docker/legacy-real-image-gate.sh
```

The current fixtures exercise PHP 5.6, 7.4, and 8.2 plus representative
FreePBX 14, 15, 16, and 17 installations. They are compatibility probes, not
claims that those historical platforms are secure or officially supported.
See [the legacy Docker guide](docs/legacy-docker-lab.md) and
[test matrix](docs/legacy-test-matrix.md) for the exact image digests and proof
boundary.

## Watcher architecture

`docker/custom-watcher/watcher.py` is the canonical watcher implementation.
The module packaging program embeds that source with the service, environment,
database configurator, and Apache request sensor. The root installer chooses
an operating-system filesystem layout; Module Admin never performs those
privileged changes implicitly.

The lightweight probe checks reload and request-event transitions every five
seconds. A bounded full state scan runs on a transition/event and at most every
30 seconds while idle. The heavier module-tree scan runs every five minutes or
after observed Module Admin work.

The Apache sensor records only authenticated username, timestamp, page/module
action, method, and HTTP status for successful administrative writes. It must
never record form values, headers, cookies, sessions, or credentials.

## Build and package

Build the unified module and both optional standalone watcher formats with:

```sh
./scripts/package-module.sh
./scripts/package-watcher.sh
./scripts/package-watcher-portable.sh
```

Generated archives belong in `dist/` and on GitHub Releases, not in source
history. Validate the Module Admin archive in the disposable lab:

```sh
./docker/validate-module-archive.sh \
  dist/pendingchanges-17.0.1.1.tgz
```

The standalone watcher packages are optional for users because the module now
contains the canonical payload. They remain release artifacts for operators
who prefer operating-system package management.

## Signing and releases

Never copy a private key into the repository or Docker lab. Assemble the
unsigned transfer bundle with:

```sh
./scripts/package-release-signing-bundle.sh
```

Sign that bundle interactively on the approved FreePBX signing host, retrieve
its `signed/` directory, and verify every checksum, detached signature, and
embedded `module.sig` before publication:

```sh
./scripts/verify-github-release-set.sh dist/signed-release
```

The full tag, signing-host, and guarded publishing workflow is documented in
[the GitHub release runbook](docs/github-releases.md). The tag must identify the
reviewed source commit used to build the signed module.

## Codex-assisted commits

This repository keeps Codex attribution in Git instead of relying on a client
setting. Enable the versioned hook once per checkout:

```sh
./scripts/install-git-hooks.sh
```

Codex-assisted commits use the wrapper and name the actual model:

```sh
./scripts/codex-commit.sh \
  --model gpt-5.6-sol \
  --reasoning-effort high \
  -- -m "Describe the change"
```

The commit receives a stable `Co-authored-by` identity plus machine-readable
`Codex-Model` and `Codex-Reasoning-Effort` trailers. Ordinary `git commit`
remains untouched. Run `./scripts/test-git-attribution.sh` to test the hook
without creating a commit.
