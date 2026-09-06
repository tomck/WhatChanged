#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$root_dir/deploy/release-versions.sh"
actual_watcher=$(sed -n 's/^Version: //p' "$root_dir/packaging/watcher/DEBIAN/control")
[[ "$actual_watcher" == "$watcher_version" ]] || { echo 'Watcher package and release manifest disagree' >&2; exit 1; }
bundle_version=$module_version
bundle_name="what-changed-signing-$bundle_version"
archive="$root_dir/dist/$bundle_name.tar.gz"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
bundle="$stage/$bundle_name"

mkdir -p "$bundle/unsigned" "$root_dir/dist"

artifacts=(
  "pendingchanges-$module_version.tgz"
  "what-changed-watcher-portable_$watcher_version.tar.gz"
  "what-changed-watcher_${watcher_version}_all.deb"
)

for artifact in "${artifacts[@]}"; do
  test -s "$root_dir/dist/$artifact" || {
    echo "Missing release candidate: dist/$artifact" >&2
    exit 1
  }
  cp "$root_dir/dist/$artifact" "$bundle/unsigned/$artifact"
done

cp "$root_dir/deploy/sign-github-release-set.sh" "$bundle/sign.sh"
cp "$root_dir/deploy/release-versions.sh" "$bundle/release-versions.sh"
cp "$root_dir/docs/release-signing.md" "$bundle/README.md"
cp "$root_dir/docs/release-assets.md" "$bundle/RELEASE-README.md"
chmod 0755 "$bundle/sign.sh"
tar -C "$stage" -czf "$archive" "$bundle_name"
echo "$archive"
