# Pending Changes Tripwire 17.0.2.9

This release expands explicit staged-change coverage while preserving the
product's read-only safety boundary.

- Cover System Recording metadata additions, edits, and removals with readable
  recording names. Audio content itself is not ingested.
- Cover User Management profile changes such as email address and timezone in
  addition to existing UCP assignment settings.
- Cover durable commercial MFA policy and authenticator configuration when
  those optional tables are installed, while always redacting authenticator
  secrets and excluding runtime OTP, device, backup-code, and session state.
- Validate the extension form's external-call recording policy through its
  exact bounded `AMPUSER` AstDB key and readable before/after values.
- Prevent a freshly raised Apply Config flag from briefly appearing as a clean
  report while the watcher is still completing its next observation.
- Upgrade existing installer-managed watcher scopes without discarding locally
  added tables.
- Add authenticated lifecycle smoke coverage for User Management profiles,
  System Recordings, and external-call recording policy.

One module archive supports FreePBX 14–17 and includes watcher 0.1.13. The
complete disposable Apache and nginx/PHP-FPM FreePBX 17 gates, PHP 5.6/7.4/8.2
compatibility gate, and real-image FreePBX 14–16 lifecycles passed against the
exact candidate. The returned signed set passed checksum, OpenPGP, embedded
`module.sig`, and exact-candidate verification, and the exact signed archive
installed through FreePBX Module Admin.
