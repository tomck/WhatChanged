# WhatChanged alpha release verification

Every release asset has an armored detached OpenPGP signature. `SHA256SUMS`
also covers the unsigned content files and has its own detached signature.

Import the included public key into a temporary keyring, verify the manifest,
then verify the files downloaded for the selected release:

```sh
gpg_home=$(mktemp -d)
chmod 700 "$gpg_home"
gpg --homedir "$gpg_home" --import WHAT_CHANGED_SIGNING_KEY.asc
gpg --homedir "$gpg_home" --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
gpg --homedir "$gpg_home" --verify pendingchanges-REPLACE-WITH-VERSION.tgz.asc pendingchanges-REPLACE-WITH-VERSION.tgz
```

Verify the watcher package in the same way by passing its `.asc` file and
package to `gpg --verify`. Obtain the expected maintainer-key fingerprint from
a trusted release announcement before trusting an imported release key. The
repository and signing bundle deliberately do not prescribe a maintainer's
personal primary-key or signing-subkey fingerprint.

The shared module archive contains the watcher and selects a Debian-family or
RHEL/CentOS/Sangoma-family service layout when its explicit root installer is
run. The separately signed Debian and portable watcher packages are optional
alternatives for operators who prefer operating-system package management.
Follow the installation guide linked from the unified release notes.

These are alpha diagnostics. They are read-only with respect to FreePBX
configuration, but they do install a local observer service and Apache request
sensor. Back up the PBX first, begin with a noncritical host, and remember that
a clean report covers only the explicitly listed sources.
