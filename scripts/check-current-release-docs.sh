#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$root_dir/deploy/release-versions.sh"

active_docs=(
  README.md
  docs/alpha-install.md
  docs/legacy-alpha-install.md
  docs/legacy-test-matrix.md
  docs/shared-module.md
  docs/github-releases.md
)

for relative in "${active_docs[@]}"; do
  document="$root_dir/$relative"
  grep -Fq "$module_version" "$document" || {
    echo "$relative does not name current module version $module_version." >&2
    exit 1
  }

  stale=$(grep -Eo 'pendingchanges-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$document" \
    | sort -u | grep -Fvx "pendingchanges-$module_version" || true)
  if [[ -n $stale ]]; then
    echo "$relative contains a stale active release reference:" >&2
    printf '%s\n' "$stale" >&2
    exit 1
  fi
done

grep -Fq "watcher payload version $watcher_version" \
  "$root_dir/docs/shared-module.md" || {
    echo "docs/shared-module.md does not name current watcher version $watcher_version." >&2
    exit 1
  }
grep -Fq "portable $watcher_version packages" \
  "$root_dir/docs/github-releases.md" || {
    echo "docs/github-releases.md does not name current watcher version $watcher_version." >&2
    exit 1
  }

echo "Active release documentation matches module $module_version and watcher $watcher_version."
