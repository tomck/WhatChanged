#!/usr/bin/env bash
# Publish only after the signed release set has passed independent verification.
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
release_dir=${1:-"$root_dir/dist/signed-release"}
module_release=$(sed -n 's:.*<version>17\.0\.0\.\([^<]*\)</version>.*:\1:p' "$root_dir/module.xml")
watcher_version=$(sed -n 's/^Version: //p' "$root_dir/packaging/watcher/DEBIAN/control")
cd "$root_dir"

"$root_dir/scripts/verify-github-release-set.sh" "$release_dir"

if [[ -n "$(git status --porcelain)" ]]; then
  echo 'Refusing to publish from a dirty working tree.' >&2
  exit 1
fi
if [[ "$(git branch --show-current)" != main ]]; then
  echo 'Refusing to publish from a branch other than main.' >&2
  exit 1
fi

module_tags=(
  "pendingchanges-14.0.0.$module_release"
  "pendingchanges-15.0.0.$module_release"
  "pendingchanges-16.0.0.$module_release"
  "pendingchanges-17.0.0.$module_release"
)
all_tags=("${module_tags[@]}" "watcher-$watcher_version")

for tag in "${all_tags[@]}"; do
  [[ "$(git rev-list -n1 "$tag")" == "$(git rev-parse HEAD)" ]] || {
    echo "Tag $tag does not point to HEAD." >&2
    exit 1
  }
  if gh release view "$tag" >/dev/null 2>&1; then
    echo "Refusing to replace existing GitHub release: $tag" >&2
    exit 1
  fi
done

git push origin main
git push origin "${all_tags[@]}"

common_assets=(
  "$release_dir/SHA256SUMS"
  "$release_dir/SHA256SUMS.asc"
  "$release_dir/WHAT_CHANGED_SIGNING_KEY.asc"
  "$release_dir/WHAT_CHANGED_SIGNING_KEY.asc.asc"
  "$release_dir/README.md"
  "$release_dir/README.md.asc"
)

for target in 14 15 16; do
  tag="pendingchanges-$target.0.0.$module_release"
  module="$release_dir/$tag.tgz"
  watcher="$release_dir/what-changed-watcher-portable_$watcher_version.tar.gz"
  gh release create "$tag" --verify-tag --prerelease \
    --title "Pending Changes Tripwire $target.0.0.$module_release alpha" \
    --notes-file "$root_dir/docs/releases/$tag.md" \
    "$module" "$module.asc" "$watcher" "$watcher.asc" "${common_assets[@]}"
done

tag="pendingchanges-17.0.0.$module_release"
module="$release_dir/$tag.tgz"
watcher="$release_dir/what-changed-watcher_${watcher_version}_all.deb"
gh release create "$tag" --verify-tag --prerelease \
  --title "Pending Changes Tripwire 17.0.0.$module_release alpha" \
  --notes-file "$root_dir/docs/releases/$tag.md" \
  "$module" "$module.asc" "$watcher" "$watcher.asc" "${common_assets[@]}"

gh release create "watcher-$watcher_version" --verify-tag --prerelease \
  --title "WhatChanged watcher $watcher_version alpha" \
  --notes-file "$root_dir/docs/releases/watcher-$watcher_version.md" \
  "$release_dir/what-changed-watcher-portable_$watcher_version.tar.gz" \
  "$release_dir/what-changed-watcher-portable_$watcher_version.tar.gz.asc" \
  "$release_dir/what-changed-watcher_${watcher_version}_all.deb" \
  "$release_dir/what-changed-watcher_${watcher_version}_all.deb.asc" \
  "${common_assets[@]}"

echo "Published WhatChanged module 14-17 release $module_release and watcher $watcher_version alpha releases."
