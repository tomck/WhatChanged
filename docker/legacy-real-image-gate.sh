#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)

for target in 16 15 14; do
  echo "Running FreePBX $target real-image lifecycle"
  "$root_dir/docker/legacy-smoke.sh" "$target"
done

echo 'FreePBX 16, 15, and 14 real-image lifecycle gate passed'
