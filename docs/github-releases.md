# GitHub prerelease runbook

WhatChanged uses one reviewed source commit for a coordinated release set. The
module implementation is shared; packaging changes only `module.xml` so each
archive declares the matching FreePBX major version. The generated archives
are GitHub Release assets and are not committed as source files.

## Tags and assets

| Tag | FreePBX target | Primary asset | Watcher asset |
| --- | --- | --- | --- |
| `pendingchanges-14.0.0.12` | 14 | `pendingchanges-14.0.0.12.tgz` | portable 0.1.2 bundle |
| `pendingchanges-15.0.0.12` | 15 | `pendingchanges-15.0.0.12.tgz` | portable 0.1.2 bundle |
| `pendingchanges-16.0.0.12` | 16 | `pendingchanges-16.0.0.12.tgz` | portable 0.1.2 bundle |
| `pendingchanges-17.0.0.12` | 17 | `pendingchanges-17.0.0.12.tgz` | Debian 0.1.2 package |
| `watcher-0.1.2` | shared observer | portable bundle and Debian package | n/a |

All five tags point to the same source commit. Each release is marked as an
alpha prerelease. Passing the Docker gates is representative compatibility,
not a claim that every third-party FreePBX module or state store is covered.

## 1. Build the unsigned signing bundle

Run the compatibility gates first, then assemble the exact files that will be
transferred to the isolated signing host:

```sh
./docker/legacy-compatibility-gate.sh
./docker/legacy-real-image-gate.sh
./scripts/package-watcher.sh
./scripts/package-release-signing-bundle.sh
```

The final command creates `dist/what-changed-signing-0.1.2.tar.gz`. It contains
the four module candidates, both watcher formats, the interactive signing
program, and release instructions. It never contains a private key.

## 2. Sign interactively

Copy the signing bundle to the FreePBX signing host, extract it as the normal
administrator, and run:

```sh
tar -xzf what-changed-signing-0.1.2.tar.gz
cd what-changed-signing-0.1.2
./sign.sh
```

The signer uses subkey fingerprint
`5319601D6E2B13F507DC2618AFA3ED68ADB99176`. It first unlocks the key through a
real terminal, then creates a FreePBX `module.sig` inside each module archive,
detached OpenPGP signatures for every release asset, and a signed checksum
manifest. The output is the `signed/` directory. Until Sangoma certifies the
primary key, stock FreePBX systems may still describe these module signatures
as locally signed or untrusted; the cryptographic signature and checksum can
still be verified independently.

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

It pushes `main` and the five annotated tags, then creates five GitHub alpha
prereleases using the version-specific notes in `docs/releases/`.
