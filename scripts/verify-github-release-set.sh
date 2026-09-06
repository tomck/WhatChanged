#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
release_dir=${1:-"$root_dir/dist/signed-release"}
release_dir=$(cd "$release_dir" && pwd)
source "$root_dir/deploy/release-versions.sh"
gpg_home=$(mktemp -d)
module_stage=$(mktemp -d)
trap 'rm -rf "$gpg_home" "$module_stage"' EXIT HUP INT TERM
chmod 0700 "$gpg_home"

files=(
  "pendingchanges-$module_version.tgz"
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

name="pendingchanges-$module_version.tgz"
target_stage="$module_stage/shared"
mkdir -p "$target_stage"
tar -xzf "$release_dir/$name" -C "$target_stage"
test -s "$target_stage/pendingchanges/module.sig"
grep -q "<version>$module_version</version>" \
  "$target_stage/pendingchanges/module.xml"
gpg --homedir "$gpg_home" --batch --verify \
  "$target_stage/pendingchanges/module.sig" >/dev/null

echo "Signed GitHub release set verified: $release_dir"
