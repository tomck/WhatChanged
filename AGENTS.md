# WhatChanged contributor rules

These rules apply to the entire repository.

## Product boundaries

- WhatChanged is a read-only explanation and evidence tool. Do not add an
  automatic rollback, discard, Apply Config, reload, or configuration-writing
  path without a separately reviewed design and explicit authorization.
- Never imply universal coverage. The UI and documentation must state that
  only explicitly listed sources are observed and that unlisted FreePBX,
  third-party-module, AstDB, filesystem, or custom-method changes may not be
  detected.
- Administrator attribution is inferred request evidence, not proof that an
  account caused a reported state change. Preserve that qualification anywhere
  attribution is displayed or documented.
- Do not patch the FreePBX framework. Integrate through supported module,
  database, filesystem, web-PHP sensor, and watcher boundaries.
- Keep credentials, form values, cookies, sessions, private keys, call data,
  and other secrets out of logs, fixtures, feedback ledgers, test output, and
  committed files. Redact or installation-key fingerprint sensitive values
  before persistence.

## Supported versions and packaging

- Maintain one unified `pendingchanges` module source tree and one module
  archive for FreePBX 14, 15, 16, and 17. Do not create version-specific copies
  of the module implementation.
- Shipped PHP code must remain compatible with PHP 5.6 unless the supported
  FreePBX floor is deliberately changed in a separately reviewed release.
  Avoid scalar and return type declarations, typed properties, null-coalescing,
  arrow functions, and other post-PHP-5.6 syntax in distributed module code.
- Keep the module raw name, archive directory, and FreePBX entry-point filenames
  lowercase or conventionally cased exactly as FreePBX expects:
  `pendingchanges/`, `Pendingchanges.class.php`, and
  `page.pendingchanges.php`.
- The watcher has its own version. Do not bump it for module-only refactors; do
  bump it when its installed payload, protocol, persistence, or behavior
  changes.
- Generated archives belong in ignored `dist/` output and GitHub Releases, not
  source history.

## PHP architecture and style

- Keep `Pendingchanges.class.php` as a thin conventional FreePBX BMO adapter and
  `page.pendingchanges.php` as a thin page bootstrap.
- Put internal module classes under `src/` using the
  `FreePBX\modules\Pendingchanges\` PSR-4 namespace mapped in `composer.json` and
  `autoload.php`.
- Keep baseline persistence, snapshots, redaction, diffing, watcher health,
  orchestration, presentation, and views in focused components. Do not move
  these responsibilities back into the BMO or page entry point.
- Follow the checked-in PSR-12 PHP_CodeSniffer ruleset. Run
  `composer lint:style` when Composer dependencies are available.
- The only standing PSR-12 exclusions are documented in `phpcs.xml.dist`:
  PHP 5.6 cannot declare class-constant visibility, and FreePBX's BMO entry
  point must register the module autoloader while declaring its class. Do not
  add another exclusion merely to avoid formatting code.
- Keep templates under `views/`; escape user-visible dynamic values and avoid
  adding configuration access or business logic to templates.

## Watcher and data handling

- The watcher database account must remain local and SELECT-only.
- Exclude module-owned state and known volatile fields from drift so the tool
  does not report its own observations as configuration changes.
- Preserve the distinction between FreePBX record drift, AstDB drift,
  generated-Asterisk-file drift, and module/file changes.
- A pending global reload with no attributable observed difference must remain
  explicit, for example: `Reload requested; origin unavailable.`
- The feedback export may contain source types, table/family names, field names,
  counts, coverage-limit reasons, and timestamps. It must not contain actual
  configuration values, record identifiers, hostnames, credentials, or call
  data.

## Validation

- Develop and exercise configuration-changing scenarios only in disposable
  Docker labs. Never point automated fixtures or smoke tests at a production
  PBX.
- Preserve lab volumes during ordinary restarts. Clean up only fixtures owned
  by the test unless the user explicitly authorizes a full reset.
- Before a release, run the complete FreePBX 17 gate:
  `./docker/lab-gate.sh`.
- Run `./docker/nginx-lab-gate.sh` to execute the same FreePBX 17 gate through
  nginx and PHP-FPM while asserting that no Apache process is active.
- Run `./docker/legacy-compatibility-gate.sh` for PHP 5.6, 7.4, and 8.2 syntax,
  metadata, page-rendering, security, and request-sensor checks.
- Run `./docker/legacy-real-image-gate.sh` to install the identical archive and
  validate staged drift, Apply Config baseline refresh, and a final clean state
  on the real FreePBX 16, 15, and 14 fixture images.
- Validate the exact signed module archive through Module Admin before
  publishing it. Passing an unsigned source build is not a substitute.
- A smoke gate must fail closed on missing evidence, stale watcher state,
  uncertain baseline provenance, unexpected extra mutation, or uncleared drift.

## Signing, release, and Git discipline

- Never copy a private signing key into this repository, a Docker container, a
  release archive, or test output. Signing bundles must be key-free and signed
  interactively on the approved signing host.
- Do not use FreePBX local-signing mode for a distributable archive. Verify the
  returned checksums, detached OpenPGP signatures, embedded `module.sig`,
  version metadata, and absence of private-key material before publication.
- Do not tag, push, publish, deploy to a real PBX, or replace an existing
  release unless the user explicitly authorizes that external change.
- Check the active GitHub CLI account before publishing; this repository is
  owned by `tomck`.
- Codex-created commits must use `scripts/codex-commit.sh` with the precise
  model and reasoning effort so the repository hook adds the expected
  attribution trailers. Do not invent a model name or rewrite published
  history.
- Preserve unrelated user changes and work from a clean checkout or branch
  when the primary worktree contains unrelated modifications.
