#!/usr/bin/env bash
# Run interactively on the FreePBX signing host. This script never exports a
# secret key and never contacts GitHub.
set -euo pipefail

subkey=5319601D6E2B13F507DC2618AFA3ED68ADB99176
primary=44D5C8E9005344DE422F443FEF3752E0A8C82A63
bundle_dir=$(cd "$(dirname "$0")" && pwd)
unsigned_dir="$bundle_dir/unsigned"
output_dir="$bundle_dir/signed"
module_release=12
watcher_version=0.1.2

if [[ ! -t 0 || ! -t 1 ]]; then
  echo 'Run this program from an interactive terminal so GPG pinentry can unlock the key.' >&2
  exit 1
fi
if [[ -e "$output_dir" ]]; then
  echo "Refusing to replace existing output: $output_dir" >&2
  exit 1
fi
if [[ ! -x /usr/src/devtools/sign.php ]]; then
  echo 'FreePBX devtools sign.php was not found at /usr/src/devtools/sign.php.' >&2
  exit 1
fi

export GPG_TTY="$(tty)"
sudo gpg --list-secret-keys "$subkey" >/dev/null

preflight=$(mktemp /tmp/what-changed-release-signing.XXXXXX.asc)
work=$(mktemp -d /tmp/what-changed-release.XXXXXX)
trap 'rm -f "$preflight"; rm -rf "$work"' EXIT HUP INT TERM

echo 'Unlocking the signing subkey...'
printf 'WhatChanged release signing preflight\n' |
  sudo env GPG_TTY="$GPG_TTY" gpg --local-user "${subkey}!" --armor --clearsign > "$preflight"
sudo gpg --verify "$preflight" >/dev/null

mkdir -p "$work/signed"
for target in 14 15 16 17; do
  name="pendingchanges-$target.0.0.$module_release.tgz"
  source_archive="$unsigned_dir/$name"
  module_stage="$work/module-$target"
  test -s "$source_archive"
  mkdir -p "$module_stage"
  tar -xzf "$source_archive" -C "$module_stage"
  test -f "$module_stage/pendingchanges/module.xml"
  grep -q "<version>$target.0.0.$module_release</version>" \
    "$module_stage/pendingchanges/module.xml"
  rm -f "$module_stage/pendingchanges/module.sig"
  sudo env GPG_TTY="$GPG_TTY" /usr/src/devtools/sign.php \
    "$module_stage/pendingchanges" --local "$subkey"
  test -s "$module_stage/pendingchanges/module.sig"
  sudo gpg --verify "$module_stage/pendingchanges/module.sig" >/dev/null
  tar -C "$module_stage" -czf "$work/signed/$name" pendingchanges
done

cp "$unsigned_dir/what-changed-watcher-portable_$watcher_version.tar.gz" "$work/signed/"
cp "$unsigned_dir/what-changed-watcher_${watcher_version}_all.deb" "$work/signed/"
sudo gpg --armor --export "$primary" > "$work/signed/WHAT_CHANGED_SIGNING_KEY.asc"
cp "$bundle_dir/RELEASE-README.md" "$work/signed/README.md"

release_files=(
  "pendingchanges-14.0.0.$module_release.tgz"
  "pendingchanges-15.0.0.$module_release.tgz"
  "pendingchanges-16.0.0.$module_release.tgz"
  "pendingchanges-17.0.0.$module_release.tgz"
  "what-changed-watcher-portable_$watcher_version.tar.gz"
  "what-changed-watcher_${watcher_version}_all.deb"
  WHAT_CHANGED_SIGNING_KEY.asc
  README.md
)

(
  cd "$work/signed"
  sha256sum "${release_files[@]}" > SHA256SUMS
)

for name in "${release_files[@]}" SHA256SUMS; do
  sudo env GPG_TTY="$GPG_TTY" gpg --batch --yes --armor \
    --local-user "${subkey}!" --detach-sign \
    --output "$work/signed/$name.asc" "$work/signed/$name"
  sudo gpg --verify "$work/signed/$name.asc" "$work/signed/$name" >/dev/null
done

sudo chmod 0644 "$work/signed"/*
sudo chown "$(id -u):$(id -g)" "$work/signed"/*
mv "$work/signed" "$output_dir"
echo "Signed release set created at $output_dir"
