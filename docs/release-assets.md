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
package to `gpg --verify`. Confirm that the key fingerprint is:

```text
44D5 C8E9 0053 44DE 422F 443F EF37 52E0 A8C8 2A63
```

The signing subkey fingerprint is:

```text
5319 601D 6E2B 13F5 07DC 2618 AFA3 ED68 ADB9 9176
```

FreePBX 14-16 use the portable watcher bundle. FreePBX 17 on Debian 12 uses
the Debian package. Follow the exact installation commands in the GitHub
release notes for the selected FreePBX major version.

These are alpha diagnostics. They are read-only with respect to FreePBX
configuration, but they do install a local observer service and Apache request
sensor. Back up the PBX first, begin with a noncritical host, and remember that
a clean report covers only the explicitly listed sources.
