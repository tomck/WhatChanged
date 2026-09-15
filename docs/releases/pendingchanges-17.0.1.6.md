# Pending Changes Tripwire 17.0.1.6 alpha

This maintenance release responds to the FreePBX community review of the
module's storage, filesystem assumptions, and module-scanning cost.

Thanks to FreePBX community member `miken32` for the detailed technical review
that prompted these improvements.

- Follows `AMPWEBROOT`, `ASTETCDIR`, `ASTVARLIBDIR`/`ASTVARLIB`, and
  `AMPDBPORT` from the target FreePBX installation.
- Replaces recursive installed-module hashing with module database state and
  stable `module.xml`/`module.sig` release markers. FreePBX's own signature
  verification remains responsible for exhaustive per-file tamper detection.
- Migrates the framework-only fallback baseline from its legacy one-row table
  into the module's native BMO key/value storage.
- Removes the obsolete `functions.inc.php` lifecycle bootstrap.
- Keeps watcher environment and systemd filesystem protections synchronized
  with the configured FreePBX paths.

The same signed module archive supports FreePBX 14, 15, 16, and 17. It passed
real-image Module Admin install, staged-drift, Apply Config, and clean-baseline
lifecycle tests on all four generations. The full FreePBX 17 gate additionally
passed authenticated configuration, breaker, AstDB, module-state, User
Management, fax, route, trunk, redaction, health, and interruption-recovery
scenarios.
