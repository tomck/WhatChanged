# WhatChanged 0.1.2 signing bundle

This directory contains reviewed, unsigned release candidates built from the
tagged WhatChanged source. It deliberately contains no secret key.

Run `./sign.sh` from an interactive terminal on the FreePBX signing host. The
signer will ask GPG to unlock signing subkey
`5319601D6E2B13F507DC2618AFA3ED68ADB99176`, create FreePBX module signatures,
and produce a new `signed/` directory. Do not edit or rebuild anything inside
that directory after signing.

Return the entire `signed/` directory for independent verification and GitHub
prerelease publication.
