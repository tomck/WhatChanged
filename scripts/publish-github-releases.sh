#!/usr/bin/env bash
# Publish only after the signed release set has passed independent verification.
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
release_dir=${1:-"$root_dir/dist/signed-release"}
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
  pendingchanges-14.0.0.11
  pendingchanges-15.0.0.11
  pendingchanges-16.0.0.11
  pendingchanges-17.0.0.11
)
all_tags=("${module_tags[@]}" watcher-0.1.1)

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
  tag="pendingchanges-$target.0.0.11"
  module="$release_dir/$tag.tgz"
  watcher="$release_dir/what-changed-watcher-portable_0.1.1.tar.gz"
  gh release create "$tag" --verify-tag --prerelease \
    --title "Pending Changes Tripwire $target.0.0.11 alpha" \
    --notes-file "$root_dir/docs/releases/$tag.md" \
    "$module" "$module.asc" "$watcher" "$watcher.asc" "${common_assets[@]}"
done

tag=pendingchanges-17.0.0.11
module="$release_dir/$tag.tgz"
watcher="$release_dir/what-changed-watcher_0.1.1_all.deb"
gh release create "$tag" --verify-tag --prerelease \
  --title 'Pending Changes Tripwire 17.0.0.11 alpha' \
  --notes-file "$root_dir/docs/releases/$tag.md" \
  "$module" "$module.asc" "$watcher" "$watcher.asc" "${common_assets[@]}"

gh release create watcher-0.1.1 --verify-tag --prerelease \
  --title 'WhatChanged watcher 0.1.1 alpha' \
  --notes-file "$root_dir/docs/releases/watcher-0.1.1.md" \
  "$release_dir/what-changed-watcher-portable_0.1.1.tar.gz" \
  "$release_dir/what-changed-watcher-portable_0.1.1.tar.gz.asc" \
  "$release_dir/what-changed-watcher_0.1.1_all.deb" \
  "$release_dir/what-changed-watcher_0.1.1_all.deb.asc" \
  "${common_assets[@]}"

echo 'Published WhatChanged module 14-17 and watcher 0.1.1 alpha releases.'
