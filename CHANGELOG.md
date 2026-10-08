# Changelog

## Module 17.0.2.7 / watcher 0.1.12

- Make embedded and standalone watcher removal safe for Apache and
  nginx/PHP-FPM by removing every web-SAPI sensor ini, validating and
  reloading active stacks, and only then deleting the referenced library.
- Refuse to override another product's `auto_prepend_file` configuration and
  retain recent attribution evidence when the bounded request log compacts.
- Protect additional FreePBX credential fields and SIP registration material
  before persistence, with watcher/framework parity regressions.
- Repair the missing `incoming` table in existing watcher environments and
  restrict the generated local database account to existing allowlisted
  tables plus the reload flag rather than the entire FreePBX schema.
- Distinguish observed drift without a reload from a clean state, report
  first-install baseline provenance accurately, and inspect the external
  watcher's redaction key in doctor output.
- Represent MariaDB's indistinguishable absent-table and missing-grant response
  honestly, aggregate optional sources into one calm limitation, and retain a
  stronger warning when a previously readable source disappears.
- Fail closed in the page when previously readable table coverage disappears,
  preserve legacy-baseline visibility during upgrades, and defer unrelated
  scope expansion while that regression remains unresolved.
- Make the command-line doctor fail with exit 2 when previously readable table
  coverage disappears, with machine-readable table names and an exact repair
  command shared from the service status.
- Observe the commercial Endpoint Manager extension map so an authenticated
  "Update Config and Refresh Phone" action can be explained as record drift
  rather than only an unattributed reload request.
- Make the disposable module-state and FreePBX 16 real-image fixtures
  reproducible from pristine volumes instead of relying on saved module state.
- Add an Apache/nginx uninstall, conflict, live-response, and reinstall smoke
  scenario to the complete FreePBX 17 gates.

## Unreleased repository installer and documentation

- Pin the convenience installer to the reviewed public-alpha release instead
  of GitHub's stable-only `/releases/latest` redirect.
- Require GnuPG and verify both the signed checksum manifest and detached
  module-archive signature; no checksum-only fallback remains.
- Put the independently authenticated manual path first, document the GitHub
  bootstrap trust boundary, and clarify support evidence.

## Module 17.0.2.6 / watcher 0.1.9

- Refresh redaction-key permission checks within a single PHP process so the
  doctor reports a repaired or newly insecure key accurately.
- Expose redaction-key health through the conventional FreePBX BMO adapter,
  avoiding a missing-class error in the command-line doctor.
- Add a regression assertion for the BMO method and repeat the disposable
  Apache, nginx/PHP-FPM, legacy compatibility, and real-image gates.

## Module 17.0.2.5 / watcher 0.1.9

- Replace numeric module and settings headings with meaningful module names and
  setting labels, while retaining the raw database key in the evidence view.
- Render changed fields as readable before/after rows with short explanations
  for module versions and FreePBX settings such as `hidden` and `emptyok`.
- Keep raw evidence expandable beneath the presentation so the friendly view
  does not reduce auditability.

## Module 17.0.2.4 / watcher 0.1.9

- Add the explicitly trust-based GitHub convenience installer while retaining
  the inspect-and-verify manual installation path.
- Resolve the latest published module release, validate its signed checksum
  manifest, discover FreePBX's configured web root, and launch the embedded
  watcher installer.
- Keep Apply Config and Asterisk reload outside the installation path.

## Module 17.0.2.3 / watcher 0.1.9

- Observe FreePBX Core's `incoming` table so staged inbound-route/DID
  additions, edits, and removals are reported before Apply Config.
- Use the `(cidnum, extension)` pair as the stable identity for inbound routes,
  preserving separate routes that share a DID but match different caller IDs.
- Add an authenticated Docker smoke fixture for inbound-route lifecycle and
  present the result as **Inbound Routes** in the report.

## Module 17.0.2.2 / watcher 0.1.8

- Support authenticated-request attribution on nginx with PHP-FPM as well as
  Apache, validating and safely reloading only active supported web services.
- Keep the core watcher usable with an explicit attribution limitation when no
  supported web PHP SAPI is available.
- Add a complete FreePBX 17 nginx/PHP-FPM release gate that runs the same
  authenticated fixtures, breaker scenarios, redaction, and recovery checks
  while proving that Apache is stopped and does not serve requests.
- Preserve Docker lab restart reliability by waiting for FreePBX's exact
  application database endpoint before a first-install transaction.

## Module 17.0.2.1 / watcher 0.1.7

- Record the embedded and installed watcher payload versions and show whether
  they match in the Reports page, command-line doctor, and installer check.
- Print the exact full-path updater command when the watcher is absent,
  unversioned, or older than the payload bundled with the installed module.
- Offer to install PyMySQL with the reviewed Debian- or RHEL-family system
  package command after explicit administrator confirmation, then continue the
  watcher installation automatically.
- Preserve the filesystem and systemd-unit layout used by an existing watcher
  so upgrading a portable installation on Debian updates the service that is
  actually active instead of installing an unused second unit.
- Remove the obsolete vendored-Python search path from newly installed service
  units; supported installations now use the declared operating-system
  PyMySQL dependency.

## Module 17.0.2.0 / watcher 0.1.6

- Refactor the FreePBX module into a PSR-4-style internal class structure while
  retaining the conventional BMO and page entry points required by FreePBX.
- Separate baseline persistence, snapshot collection, redaction, diffing,
  watcher health, request handling, presentation, and views into focused,
  testable components.
- Apply PSR-12 formatting to the refactored PHP code without raising the PHP
  5.6 floor required for unified FreePBX 14–17 support.
- Add a source-controlled PHP_CodeSniffer ruleset and Composer style command,
  with documented exceptions only for PHP 5.6 constant syntax and the required
  FreePBX BMO bootstrap side effect.
- Preserve the watcher protocol, coverage contract, read-only behavior,
  redaction rules, and Apply Config baseline lifecycle from 17.0.1.7.

## Module 17.0.1.7 / watcher 0.1.6

- Honor FreePBX's configured `AMPDBSOCK` for both the local SELECT-only account
  setup and the watcher connection, while continuing to use `AMPDBPORT` for
  TCP database connections.

## Module 17.0.1.6 / watcher 0.1.5

- Follow FreePBX's configured `ASTETCDIR`, `ASTVARLIBDIR` (or legacy
  `ASTVARLIB`), and `AMPDBPORT` instead of assuming standard Asterisk paths or
  MariaDB port 3306.
- Replace recursive hashing of every installed module file with the modules
  database state plus stable `module.xml` and `module.sig` release markers.
  FreePBX's module-signature verifier remains the exhaustive tamper checker.
- Store the framework-only fallback baseline in the module's BMO key/value
  store, migrating and then removing the legacy one-row custom table.
- Remove the obsolete `functions.inc.php` install/uninstall bootstrap; supported
  FreePBX versions use the BMO class lifecycle.
- Keep watcher environment paths and systemd filesystem protections aligned
  when the watcher is installed, upgraded, or reconfigured.

## Module 17.0.1.5 / watcher 0.1.4

- Identify Apache's pre-reload check as validation of the host's complete
  configuration and explain that warnings can come from existing virtual hosts
  or modules. WhatChanged does not create or modify `DocumentRoot` directives.
- Make the command-line doctor report whether the attribution sensor is
  configured without falsely claiming it is unloaded. Only an Apache-served
  FreePBX request can verify that the web-request sensor is loaded.
- Resolve the command-line utility through FreePBX's configured module path in
  user instructions instead of relying on a Docker-only convenience symlink.
- Compare protected AstDB snapshots consistently so unchanged AMPUSER password
  values no longer appear as permanent redacted-to-redacted drift after Apply
  Config.
- Add one control to expand or collapse every evidence panel on the report.
- Name the affected AstDB key so a legitimate sensitive-value change remains
  identifiable even though its before/after values stay redacted.
- Refresh the baseline from a successful authenticated Apply Config breadcrumb
  when the global reload flag turns on and off between watcher scans.

## Module 17.0.1.4

- Generate distributable FreePBX `module.sig` files without `--local`, so the
  archive no longer depends on a PBX-specific
  `/etc/freepbx.secure/pendingchanges.sig` sidecar.
- Reject release sets whose embedded signature is host-local or references a
  missing `pendingchanges.sig` file.
- Clarify the difference between a distributable module signature and optional
  host-local signing.

## 0.1.3 / module 17.0.1.3

- Replace sensitive database and AstDB values with installation-keyed HMAC
  fingerprints before watcher or framework-fallback baseline persistence.
- Keep all user-visible sensitive values as the constant `[redacted]`; never
  expose the internal fingerprint in status, feedback, or rendered diffs.
- Recognize secret-like semantic names stored alongside generic `value`, `val`,
  and `data` columns in both observation paths.
- Follow FreePBX's configured `AMPWEBROOT` in the framework module scanner and
  make the attribution sensor validate the actual `/admin/` request path
  without assuming `/var/www/html`.
- Persist watcher continuity metadata and explicitly mark baseline provenance
  uncertain when state changes across an unobserved interruption.
- Recover trust after an observed pending-to-clean transition or successful
  authenticated web Apply Config, and add adversarial regression coverage.
- Keep the long-running watcher alive across transient database or filesystem
  failures instead of requiring an operator restart.

Security hardening was prompted by an independent static review produced by
[@kierknoby](https://github.com/kierknoby)'s ChatGPT.

## 0.1.2 / module 14-17.0.0.12

- Add an explicit watcher-health contract based on the age of a completed
  observation, not merely on installed files or a running service.
- Show healthy, delayed, stale, invalid, unreadable, installed-but-unconfigured,
  and not-installed states on the FreePBX Reports page.
- Refuse to present an empty degraded observation as an all-clear result.
- Show whether the authenticated-request attribution sensor is loaded for the
  current FreePBX web request.
- Add cross-version health classification and degraded-page regression tests.
- Make release-gate package versions derive from the source manifests.

## 0.1.1 / module 14-17.0.0.11

- Add FreePBX 14, 15, and 16 compatibility candidates and a portable watcher.
- Add bounded SQL, AstDB, generated-file, module-state, User Management, fax,
  route, trunk, and inferred administrator-request evidence.
- Add privacy-preserving local feedback export and explicit coverage limits.
