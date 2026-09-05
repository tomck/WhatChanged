#!/usr/bin/env bash
# Publish only after the signed release set has passed independent verification.
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
release_dir=${1:-"$root_dir/dist/signed-release"}
source "$root_dir/deploy/release-versions.sh"
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

all_tags=("pendingchanges-$module_version")

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

tag="pendingchanges-$module_version"
module="$release_dir/$tag.tgz"
watcher="$release_dir/what-changed-watcher_${watcher_version}_all.deb"
gh release create "$tag" --verify-tag --prerelease \
  --title "Pending Changes Tripwire $module_version alpha" \
  --notes-file "$root_dir/docs/releases/$tag.md" \
  "$module" "$module.asc" "$watcher" "$watcher.asc" \
  "$release_dir/what-changed-watcher-portable_$watcher_version.tar.gz" \
  "$release_dir/what-changed-watcher-portable_$watcher_version.tar.gz.asc" "${common_assets[@]}"

echo "Published unified module $module_version with watcher $watcher_version packages."
