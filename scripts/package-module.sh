#!/usr/bin/env bash
set -euo pipefail

# Build a Module Admin installable source archive from a reviewed checkout.
# Signing is intentionally a separate release-controlled step because FreePBX
# signing keys and trust policy must never be embedded in this repository.
root_dir=$(cd "$(dirname "$0")/.." && pwd)
target=17
output_dir="$root_dir/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      target=${2:?--target requires 14, 15, 16, or 17}
      shift 2
      ;;
    --output-dir)
      output_dir=${2:?--output-dir requires a directory}
      shift 2
      ;;
    *)
      # Preserve the original one-positional-argument output-directory API.
      output_dir=$1
      shift
      ;;
  esac
done

case "$target" in
  14|15) php_version=5.6.0 ;;
  16|17) php_version=7.4.0 ;;
  *) echo "unsupported FreePBX target: $target" >&2; exit 2 ;;
esac

version=$(sed -n 's:.*<rawname>\([^<]*\)</rawname>.*:\1:p' "$root_dir/module.xml" | head -n1)
source_version=$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$root_dir/module.xml" | head -n1)
release_number=${source_version##*.}
module_version="$target.0.0.$release_number"

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

sed -i.bak \
  -e "s#<version>$source_version</version>#<version>$module_version</version>#" \
  -e "s#<phpversion>[^<]*</phpversion>#<phpversion>$php_version</phpversion>#" \
  -e "s#<version>17.0</version>#<version>$target.0</version>#" \
  "$module_dir/module.xml"
rm -f "$module_dir/module.xml.bak"

tar -C "$temp_dir" -czf "$archive" "$version"
echo "$archive"
