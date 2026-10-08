# Pending Changes Tripwire 17.0.2.7

This alpha release broadens configuration coverage and makes degraded
observations fail closed instead of looking clean:

- Observe commercial Endpoint Manager extension mappings, including readable
  additions, edits, and removals, while redacting token material.
- Repair existing watcher environments that omitted inbound routes or Endpoint
  Manager without replacing administrator-added table coverage.
- Report lost database visibility as an unknown/degraded state in both the
  Reports page and command-line doctor rather than presenting an all-clear.
- Distinguish observed drift without a reload from a clean applied baseline and
  preserve honest first-install and interrupted-watcher provenance.
- Tighten the generated database account to SELECT access on existing,
  explicitly allowlisted configuration tables plus the reload flag.
- Extend redaction for FreePBX credentials and SIP registration material before
  values reach persistent watcher state.
- Safely install and remove request attribution across Apache and nginx/PHP-FPM,
  refusing to replace another product's `auto_prepend_file` configuration.
- Make pristine FreePBX 16 startup and module-state fixtures deterministic, and
  add complete Apache/nginx watcher removal and reinstall coverage.

One module archive supports FreePBX 14–17 and includes watcher 0.1.12. The
observer remains read-only: it does not Apply Config, reload Asterisk, or claim
to detect sources outside the explicit coverage contract.

The exact signed release set passed independent checksum, detached OpenPGP,
embedded `module.sig`, and manifest verification. The exact signed module
archive also installed successfully through FreePBX Module Admin in the
disposable Docker lab. FreePBX may label the signing key as **Unknown** until
Sangoma certifies it; that trust label is separate from signature integrity.
