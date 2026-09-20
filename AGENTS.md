# WhatChanged contributor rules

These rules apply to the entire repository.

## Project purpose

- WhatChanged helps FreePBX administrators understand which observed
  configuration changes are waiting behind **Apply Config** before somebody
  activates them unknowingly. It combines a FreePBX presentation module with
  a least-privilege watcher that records an applied baseline and explains
  subsequent drift.
- The product is an operational safety aid, not an oracle, rollback engine, or
  substitute for backups and change control. Prefer precise, supportable claims
  over reassuring but unprovable ones.
- Optimize for the administrator who has inherited an unfamiliar PBX during an
  incident: important conclusions should be visible first, evidence should be
  inspectable, and limitations should be candid without requiring source-code
  knowledge.

## Human-centered engineering

- Make the safe path the easy path. Installation, upgrades, diagnostics, and
  removal should be idempotent, preserve user data, and leave the system in an
  intelligible state after interruption.
- Do not make administrators translate an implementation failure into a repair
  procedure. Error messages must identify the affected component, explain the
  consequence in plain language, and provide an exact, context-aware remedy.
- When the watcher installer discovers a missing supported dependency, it must
  identify the host platform, show the package-manager action it proposes,
  request explicit consent, run that action when approved, and then resume and
  verify the original installation automatically. It must never install
  packages silently. In a non-interactive session, fail safely with the exact
  command and rerun instruction instead of hanging or emitting only
  `component missing`.
- Derive FreePBX paths, database endpoints, service layout, and web-server/PHP
  integration from the running system. Do not assume `/var/www/html`, port
  3306, Apache, or a particular Linux family when FreePBX or the operating
  system exposes the authoritative value.
- Present concise summaries before raw evidence. Use readable labels,
  before/after values, progressive disclosure, and actionable health states;
  reserve raw JSON and low-level diagnostics for expandable evidence or
  troubleshooting output.
- Keep user-facing commands copyable and complete. Documentation should state
  prerequisites, expected outcomes, verification steps, limitations, and a
  reversible recovery or uninstall path.
- When observing a production PBX (as opposed to a disposable lab), never Apply
  Config, reload Asterisk, or reseed/reset the baseline. Snapshot the baseline
  hash before and after, preserve evidence, and keep timestamped rollback
  copies so installing the observer cannot silently alter what it measures.

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
- Do not add a generic discard, revert, or undo path. Reversing arbitrary
  FreePBX records safely requires module-specific dependency handling, and any
  reversal must never overwrite evidence or undo unrelated work.

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
  does not report its own observations as configuration changes. In particular,
  the watcher must exclude its own `pendingchanges` module record; prove that
  genuine module enable/disable/version changes are still detected with a
  disposable fixture module, never with the observer itself.
- New coverage introduced while a reload is pending must defer rather than
  invent before-values, and scope changes require migration markers so a saved
  baseline made by an older, differently shaped observer is replaced instead
  of misread.
- The request sensor records only account name, time, page/module/action,
  method, and success — never request bodies, passwords, cookies, or session
  identifiers. Exclude read-only and housekeeping requests, and always display
  attribution with a confidence level rather than as proven causation.
- Never present stale or missing watcher data as clean. Health requires a
  fresh completed observation, not merely an active process; degraded results
  must describe the state as unknown and must never say "No pending reload."
- Preserve the distinction between FreePBX record drift, AstDB drift,
  generated-Asterisk-file drift, and module/file changes.
- A pending global reload with no attributable observed difference must remain
  explicit, for example: `Reload requested; origin unavailable.`
- The feedback export is opt-in and local-only. It may contain source types, table/family names, field names,
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
- Exercise dependency-recovery flows in disposable supported environments:
  both an interactive, consented install-and-resume path and a non-interactive
  failure that prints the complete remediation command.
- A smoke gate must fail closed on missing evidence, stale watcher state,
  uncertain baseline provenance, unexpected extra mutation, or uncleared drift.

## Signing, release, and Git discipline

- Never copy a private signing key into this repository, a Docker container, a
  release archive, or test output. Signing bundles must be key-free and signed
  interactively on the approved signing host.
- Never copy host-local `--local` signatures or trust files back into GitHub,
  Docker, or release archives. They are that PBX's trust artifacts, not
  release artifacts; the source tree stays unsigned.
- The repository must not prescribe a maintainer's personal key identity.
  Signing keys are supplied through the signing host's environment (never
  hardcoded in scripts or docs); a public key may be published, a private key
  or passphrase never.
- Do not use FreePBX local-signing mode for a distributable archive. Verify the
  returned checksums, detached OpenPGP signatures, embedded `module.sig`,
  version metadata, and absence of private-key material before publication.
- Transfer signing bundles over a versioned, checksum-verified path and refuse
  if the destination already exists, so a release can never overwrite another
  or mix versions.
- If a completed `signed/` set already exists on the signing host, stop and
  ask — never delete a finished signature set blindly.
- Hold tags and releases until the signed set returns and verifies; publish
  the commit, the tag, and the complete release together so no link can serve
  a 404 or an unsigned substitute.
- Validate the exact signed module archive through Module Admin before
  publishing it. Passing an unsigned source build is not a substitute.
  Validators must fail closed on artifact identity, never silently validating
  a wrong same-named archive. Never publish around a gate failure; rerun the
  failing leg instead.
- Do not tag, push, publish, deploy to a real PBX, or replace an existing
  release unless the user explicitly authorizes that external change.
- Check the active GitHub CLI account before publishing; this repository is
  owned by `tomck`.
- Every AI-assisted commit must carry an `Assisted-by: AGENT:MODEL` trailer
  with the precise agent and model, and must never invent a model name.
  Codex-created commits must use `scripts/codex-commit.sh` so the repository
  hook adds the expected attribution trailers. Leave published history alone:
  rewriting changes every hash and breaks tags, releases, and clones, so it
  needs explicit approval plus a backup.
- Preserve unrelated user changes and work from a clean checkout or branch
  when the primary worktree contains unrelated modifications.
