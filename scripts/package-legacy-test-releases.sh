#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)

for target in 14 15 16; do
  "$root_dir/scripts/package-module.sh" --target "$target" --output-dir "$root_dir/dist"
done

"$root_dir/scripts/package-watcher-portable.sh"

echo 'Legacy test-release artifacts assembled in dist/'
