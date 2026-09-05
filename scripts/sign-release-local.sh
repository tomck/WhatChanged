#!/usr/bin/env bash
# Sign a WhatChanged release set without a production PBX.
#
# What it does on THIS machine (no FreePBX, no Docker, no root needed):
#   1. stages the built artifacts (shared module archive, Debian watcher
#      package, portable watcher bundle) into a release directory,
#   2. writes SHA256SUMS and creates detached OpenPGP (.asc) signatures with
#      the key in YOUR local keyring, selected by WHAT_CHANGED_SIGNING_SUBKEY,
#   3. verifies every checksum and signature it just made.
#
# FreePBX module.sig (the devtools sign.php step) is OPTIONAL and is NOT done
# here: sign.php only exists on a FreePBX host with the devtools module, and
# Module Admin installs and runs Unsigned archives normally. A missing
# module.sig shows an "Unsigned" notice in Module Admin and nothing else; the
# SHA256SUMS + detached GPG signatures are the real distribution trust.
# If /usr/src/devtools/sign.php IS present (e.g. you run this on a disposable
# lab PBX), pass --with-module-sig to embed module.sig before checksumming.
# Never run this on a production PBX: use the disposable Docker lab instead.
#
# Usage:
#   export WHAT_CHANGED_SIGNING_SUBKEY='<full signing-subkey fingerprint>'
#   ./scripts/sign-release-local.sh [--release-dir dist/signed-release] [--with-module-sig]
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$root_dir/deploy/release-versions.sh"

subkey=${WHAT_CHANGED_SIGNING_SUBKEY:-}
release_dir="$root_dir/dist/signed-release"
with_module_sig=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-dir) release_dir=${2:?--release-dir requires a directory}; shift 2 ;;
    --with-module-sig) with_module_sig=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$subkey" ]]; then
  echo 'Set WHAT_CHANGED_SIGNING_SUBKEY to the full fingerprint of the signing-capable subkey.' >&2
  exit 2
fi
if ! gpg --list-secret-keys "$subkey" >/dev/null 2>&1; then
  echo "No secret key $subkey in the local keyring." >&2
  exit 1
fi

module_archive="$root_dir/dist/pendingchanges-$module_version.tgz"
deb_package="$root_dir/dist/what-changed-watcher_${watcher_version}_all.deb"
portable_bundle="$root_dir/dist/what-changed-watcher-portable_$watcher_version.tar.gz"
for artifact in "$module_archive" "$deb_package" "$portable_bundle"; do
  test -s "$artifact" || { echo "Missing build artifact: $artifact (build it first)" >&2; exit 1; }
done

if [[ -e "$release_dir" ]]; then
  echo "Refusing to replace existing output: $release_dir" >&2
  exit 1
fi
mkdir -p "$release_dir"
cp "$module_archive" "$deb_package" "$portable_bundle" "$release_dir/"
cp "$root_dir/docs/release-assets.md" "$release_dir/README.md"

if [[ "$with_module_sig" == 1 ]]; then
  if [[ ! -x /usr/src/devtools/sign.php ]]; then
    echo 'No FreePBX devtools sign.php at /usr/src/devtools/sign.php; cannot embed module.sig here.' >&2
    echo 'Re-run without --with-module-sig, or run on a disposable FreePBX host with devtools installed.' >&2
    exit 1
  fi
  work=$(mktemp -d /tmp/what-changed-module-sign.XXXXXX)
  trap 'rm -rf "$work"' EXIT HUP INT TERM
  tar -xzf "$release_dir/pendingchanges-$module_version.tgz" -C "$work"
  rm -f "$work/pendingchanges/module.sig"
  /usr/src/devtools/sign.php "$work/pendingchanges" --local "$subkey"
  test -s "$work/pendingchanges/module.sig"
  gpg --verify "$work/pendingchanges/module.sig" >/dev/null
  tar -C "$work" -czf "$release_dir/pendingchanges-$module_version.tgz" pendingchanges
  trap - EXIT HUP INT TERM
  rm -rf "$work"
else
  echo 'Skipping FreePBX module.sig (optional; Module Admin runs Unsigned archives normally).'
fi

release_files=(
  "pendingchanges-$module_version.tgz"
  "what-changed-watcher_${watcher_version}_all.deb"
  "what-changed-watcher-portable_$watcher_version.tar.gz"
  README.md
)
(
  cd "$release_dir"
  sha256sum "${release_files[@]}" > SHA256SUMS
)
for name in "${release_files[@]}" SHA256SUMS; do
  gpg --batch --yes --armor --local-user "${subkey}!" --detach-sign \
    --output "$release_dir/$name.asc" "$release_dir/$name"
  gpg --verify "$release_dir/$name.asc" "$release_dir/$name" >/dev/null
done

echo "Signed release set created at $release_dir"
ls -la "$release_dir"
