#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
bundle_version=0.1.1
module_release=11
bundle_name="what-changed-signing-$bundle_version"
archive="$root_dir/dist/$bundle_name.tar.gz"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
bundle="$stage/$bundle_name"

mkdir -p "$bundle/unsigned" "$root_dir/dist"

artifacts=(
  "pendingchanges-14.0.0.$module_release.tgz"
  "pendingchanges-15.0.0.$module_release.tgz"
  "pendingchanges-16.0.0.$module_release.tgz"
  "pendingchanges-17.0.0.$module_release.tgz"
  "what-changed-watcher-portable_$bundle_version.tar.gz"
  "what-changed-watcher_${bundle_version}_all.deb"
)

for artifact in "${artifacts[@]}"; do
  test -s "$root_dir/dist/$artifact" || {
    echo "Missing release candidate: dist/$artifact" >&2
    exit 1
  }
  cp "$root_dir/dist/$artifact" "$bundle/unsigned/$artifact"
done

cp "$root_dir/deploy/sign-github-release-set.sh" "$bundle/sign.sh"
cp "$root_dir/docs/release-signing.md" "$bundle/README.md"
cp "$root_dir/docs/release-assets.md" "$bundle/RELEASE-README.md"
chmod 0755 "$bundle/sign.sh"
tar -C "$stage" -czf "$archive" "$bundle_name"
echo "$archive"
