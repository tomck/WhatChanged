#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
release_dir=${1:-"$root_dir/dist/signed-release"}
release_dir=$(cd "$release_dir" && pwd)
module_release=11
watcher_version=0.1.1
gpg_home=$(mktemp -d)
module_stage=$(mktemp -d)
trap 'rm -rf "$gpg_home" "$module_stage"' EXIT HUP INT TERM
chmod 0700 "$gpg_home"

files=(
  "pendingchanges-14.0.0.$module_release.tgz"
  "pendingchanges-15.0.0.$module_release.tgz"
  "pendingchanges-16.0.0.$module_release.tgz"
  "pendingchanges-17.0.0.$module_release.tgz"
  "what-changed-watcher-portable_$watcher_version.tar.gz"
  "what-changed-watcher_${watcher_version}_all.deb"
  WHAT_CHANGED_SIGNING_KEY.asc
  README.md
)

for name in "${files[@]}" SHA256SUMS; do
  test -s "$release_dir/$name"
  test -s "$release_dir/$name.asc"
done

if grep -R -l -- 'BEGIN PGP PRIVATE KEY BLOCK' "$release_dir" >/dev/null; then
  echo 'Refusing release set containing an OpenPGP private-key block.' >&2
  exit 1
fi

gpg --homedir "$gpg_home" --batch --import \
  "$release_dir/WHAT_CHANGED_SIGNING_KEY.asc" >/dev/null 2>&1

(
  cd "$release_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c SHA256SUMS
  else
    shasum -a 256 -c SHA256SUMS
  fi
)
for name in "${files[@]}" SHA256SUMS; do
  gpg --homedir "$gpg_home" --batch --verify \
    "$release_dir/$name.asc" "$release_dir/$name" >/dev/null
done

for target in 14 15 16 17; do
  name="pendingchanges-$target.0.0.$module_release.tgz"
  target_stage="$module_stage/$target"
  mkdir -p "$target_stage"
  tar -xzf "$release_dir/$name" -C "$target_stage"
  test -s "$target_stage/pendingchanges/module.sig"
  grep -q "<version>$target.0.0.$module_release</version>" \
    "$target_stage/pendingchanges/module.xml"
  gpg --homedir "$gpg_home" --batch --verify \
    "$target_stage/pendingchanges/module.sig" >/dev/null
done

echo "Signed GitHub release set verified: $release_dir"
