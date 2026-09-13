#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
checker="$root_dir/scripts/check-module-signature-manifest.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

printf '[config]\nrepo=manual\ntype=public\n[hashes]\nmodule.xml = abc\n' > "$work/public"
"$checker" "$work/public" >/dev/null

printf '[config]\nrepo=local\ntype=local\n[hashes]\npendingchanges.sig = abc\n' > "$work/local"
if "$checker" "$work/local" >/dev/null 2>&1; then
  echo 'Host-local signature manifest was incorrectly accepted.' >&2
  exit 1
fi

printf '[config]\nrepo=manual\ntype=public\n[hashes]\npendingchanges.sig = abc\n' > "$work/sidecar"
if "$checker" "$work/sidecar" >/dev/null 2>&1; then
  echo 'Signature manifest with a PBX-specific sidecar was incorrectly accepted.' >&2
  exit 1
fi

echo 'Module-signature portability regression checks passed.'
