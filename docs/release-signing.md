# WhatChanged release signing bundle

This directory contains reviewed, unsigned release candidates built from the
tagged WhatChanged source. It deliberately contains no secret key.

Run `./sign.sh` from an interactive terminal on the FreePBX signing host after
setting `WHAT_CHANGED_SIGNING_SUBKEY` to the full fingerprint of the
signing-capable subkey. The repository deliberately does not prescribe a
maintainer's personal key. The signer will ask GPG to unlock the selected key,
create FreePBX module signatures, and produce a new `signed/` directory. Do not
edit or rebuild anything inside that directory after signing.

Return the entire `signed/` directory for independent verification and GitHub
prerelease publication.
