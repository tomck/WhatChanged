# WhatChanged local release signing

Sign a release set on your own workstation or any non-PBX machine. You never
need a production PBX for signing, and the sign.php step is optional.

## What each signature means

- **Detached GPG signatures (`SHA256SUMS` + per-file `.asc`): the real
  distribution trust.** Verifiers check these with the published project key
  (see [alpha release verification](release-assets.md)). Always produce these.
- **FreePBX `module.sig` (devtools `sign.php`): optional cosmetic
  tamper-evidence for Module Admin.** It only changes the **Unsigned** notice
  in Module Admin on the installing PBX. It is not required for installation,
  operation, smoke tests, or any gate in this repository, and its absence
  never blocks an alpha tester.

## Sign locally

1. Build the artifacts:
   `./scripts/package-module.sh`,
   `./scripts/package-watcher.sh` (Debian package, built in the disposable
   lab), `./scripts/package-watcher-portable.sh`.
2. Export your signing subkey and run:
   ```sh
   export WHAT_CHANGED_SIGNING_SUBKEY='<full signing-subkey fingerprint>'
   ./scripts/sign-release-local.sh
   ```
   This stages `dist/signed-release/`, writes `SHA256SUMS`, signs every file
   with your local keyring, and verifies each signature. No root, Docker,
   FreePBX, or secret-key transfer is involved.
3. Verify independently (a second machine or keyring is ideal):
   ```sh
   ./scripts/verify-github-release-set.sh dist/signed-release
   ```

## If you want module.sig too

Run the same script with `--with-module-sig` on a **disposable** FreePBX host
that has the devtools module (for example, this repository's Docker lab
after installing devtools there). Never install signing keys on, or sign
from, a production PBX. Without `--with-module-sig` the script says so and
continues; the output is a complete, verifiable GPG-signed release set.

## Retired flow

`deploy/sign-github-release-set.sh` + `scripts/package-release-signing-bundle.sh`
remain for the coordinated multi-artifact GitHub prerelease workflow. They
assume a FreePBX signing host because they embed `module.sig`; for ordinary
alpha releases prefer `sign-release-local.sh` above.
