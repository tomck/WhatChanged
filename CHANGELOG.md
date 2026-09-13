# Changelog

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
