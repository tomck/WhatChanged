#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)

"$root_dir/scripts/package-module.sh" --output-dir "$root_dir/dist"

"$root_dir/scripts/package-watcher-portable.sh"

echo 'Legacy test-release artifacts assembled in dist/'
