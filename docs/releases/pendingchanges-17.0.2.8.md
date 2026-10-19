# Pending Changes Tripwire 17.0.2.8

This is the first WhatChanged release published as a normal GitHub release
rather than a prerelease. The safety boundary has not changed: the report is a
read-only explanation of explicitly observed sources, not a universal audit or
rollback system.

- Add a concise module-version card that reports whether a newer public
  release is available.
- Enable cached automatic checks by default, no more than once every six
  hours, with a visible opt-out and an explicit **Check now** action.
- Read only the public GitHub Pages installer and strictly parse its exact
  release assignment; cache only the result, check time, and version.
- Keep WhatChanged's own preference and check requests out of inferred
  administrator-change evidence.
- Use the shorter `https://tomck.github.io/WhatChanged/install.sh` bootstrap in
  current documentation while retaining an independently verifiable manual
  installation path.
- Require GnuPG in the convenience installer and verify both the signed
  checksum manifest and detached module-archive signature.
- Present 17 as the primary tested target and 14–16 as compatibility-tested
  legacy targets without implying that their operating systems are supported.

One module archive supports FreePBX 14–17 and includes watcher 0.1.12. The
watcher payload did not change in this release. Automatic release checks send
no PBX configuration, credentials, form values, or host identifier; the
hosting provider still receives ordinary HTTPS connection metadata such as
the source address.

The complete disposable Apache, nginx/PHP-FPM, PHP 5.6, 7.4 and 8.2, and
real-image FreePBX 14–16 gates passed. The returned signed set passed checksum,
OpenPGP, embedded `module.sig`, and exact-candidate identity verification, and
the exact signed archive installed through FreePBX Module Admin.
