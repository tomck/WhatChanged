# Changelog

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
