#!/usr/bin/env bash
set -euo pipefail

# Build a Module Admin installable source archive from a reviewed checkout.
# Signing is intentionally a separate release-controlled step because FreePBX
# signing keys and trust policy must never be embedded in this repository.
root_dir=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's:.*<rawname>\([^<]*\)</rawname>.*:\1:p' "$root_dir/module.xml" | head -n1)
module_version=$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$root_dir/module.xml" | head -n1)
output_dir=${1:-"$root_dir/dist"}

if [[ -z "$version" || -z "$module_version" ]]; then
  echo "module.xml is missing rawname or version" >&2
  exit 1
fi

mkdir -p "$output_dir"
archive="$output_dir/${version}-${module_version}.tgz"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
module_dir="$temp_dir/$version"
mkdir -p "$module_dir"

for path in LICENSE module.xml functions.inc.php Pendingchanges.class.php page.pendingchanges.php bin; do
  cp -R "$root_dir/$path" "$module_dir/"
done

tar -C "$temp_dir" -czf "$archive" "$version"
echo "$archive"
