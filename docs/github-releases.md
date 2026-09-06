# GitHub prerelease runbook

WhatChanged uses one reviewed source commit for a coordinated release set. The
module implementation and archive are shared across FreePBX 14–17. Generated
archives are GitHub Release assets and are not committed as source files.

## Tags and assets

| Tag | FreePBX target | Primary asset | Watcher asset |
| --- | --- | --- | --- |
| `pendingchanges-17.0.1.0` | 14–17 | `pendingchanges-17.0.1.0.tgz` | Debian and portable 0.1.2 packages |

One module tag identifies the source commit. The release is marked as an
alpha prerelease. Passing the Docker gates is representative compatibility,
not a claim that every third-party FreePBX module or state store is covered.

## 1. Build the unsigned signing bundle

Run the compatibility gates first. Commit the reviewed release source, create
the annotated release tag on that commit, then assemble the exact files that
will be transferred to the isolated signing host:

```sh
./docker/legacy-compatibility-gate.sh
./docker/legacy-real-image-gate.sh
git tag -a pendingchanges-17.0.1.0 -m 'Pending Changes Tripwire 17.0.1.0 alpha'
./scripts/package-watcher.sh
./scripts/package-release-signing-bundle.sh
```

The final command creates `dist/what-changed-signing-17.0.1.0.tar.gz`. It contains
the single shared module, both watcher formats, the interactive signing
program, and release instructions. It never contains a private key.

## 2. Sign interactively

Copy the signing bundle to the FreePBX signing host, extract it as the normal
administrator, and run:

```sh
tar -xzf what-changed-signing-17.0.1.0.tar.gz
cd what-changed-signing-17.0.1.0
export WHAT_CHANGED_SIGNING_SUBKEY='<full signing-subkey fingerprint>'
./sign.sh
```

The signing host supplies the signing-capable subkey through the environment;
the repository does not prescribe a maintainer's personal key. The signer first
unlocks that key through a real terminal, then creates a FreePBX `module.sig`
inside the module archive, detached OpenPGP signatures for every release
asset, and a signed checksum manifest. The output is the `signed/` directory.
Until the maintainer's primary key is certified by Sangoma, stock FreePBX
systems may still describe these module signatures as locally signed or
untrusted; the cryptographic signature and checksum can still be verified
independently.

## 3. Retrieve and verify

Place the returned directory at `dist/signed-release`, then verify it in an
isolated temporary GPG home:

```sh
./scripts/verify-github-release-set.sh dist/signed-release
```

The verifier checks every checksum and detached signature, checks each embedded
FreePBX `module.sig`, confirms every module version, and refuses a bundle that
contains an OpenPGP private-key block.

## 4. Publish after review

The publishing program refuses a dirty tree, a tag that does not point to the
current commit, a missing signature, or an existing GitHub release. After the
signed set has been reviewed:

```sh
./scripts/publish-github-releases.sh dist/signed-release
```

It pushes `main` and the module tag, then creates one GitHub alpha prerelease
containing the module and both watcher package formats.
