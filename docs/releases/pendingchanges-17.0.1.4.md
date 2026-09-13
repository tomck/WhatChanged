# Pending Changes Tripwire 17.0.1.4 alpha

This corrective release fixes the FreePBX module-signing mode used by the
17.0.1.3 archive.

The earlier release was signed with FreePBX's host-local `--local` mode. Its
embedded `module.sig` therefore referenced a PBX-specific
`pendingchanges.sig` sidecar that could not travel with the archive. On another
PBX, FreePBX correctly raised a red **Module has been tampered** warning and
reported that `pendingchanges.sig` was missing.

17.0.1.4 uses a normal distributable `module.sig`. The signing and independent
verification programs now reject any release that is host-local or references
the missing sidecar. Until the maintainer's key is certified by Sangoma, a
stock PBX may still identify the key as untrusted or invalid; that trust status
is distinct from a missing-file or tampering failure.

Watcher 0.1.3 and the configuration-drift implementation are unchanged from
17.0.1.3. One shared module archive continues to support FreePBX 14, 15, 16,
and 17.
