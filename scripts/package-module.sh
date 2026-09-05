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
  14|15|16|17) : ;; # Accepted for old callers; all targets use the same archive.
  *) echo "unsupported FreePBX target: $target" >&2; exit 2 ;;
esac

version=$(sed -n 's:.*<rawname>\([^<]*\)</rawname>.*:\1:p' "$root_dir/module.xml" | head -n1)
source_version=$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$root_dir/module.xml" | head -n1)
source "$root_dir/deploy/release-versions.sh"
[[ "$source_version" == "$module_version" ]] || { echo 'Release manifest and module.xml disagree' >&2; exit 1; }

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

# Embed the watcher payload so the module archive alone is enough to install
# the observer: bin/install-watcher (copied with bin/) picks the Debian or
# portable layout at install time. Sources stay canonical in deploy/,
# packaging/, and docker/; this is only a copy.
mkdir -p "$module_dir/watcher"
cp "$root_dir/docker/custom-watcher/watcher.py" "$module_dir/watcher/watcher.py"
cp "$root_dir/deploy/what-changed-request-audit.php" "$module_dir/watcher/what-changed-request-audit.php"
cp "$root_dir/deploy/99-what-changed-attribution.ini" "$module_dir/watcher/99-what-changed-attribution.ini"
cp "$root_dir/deploy/what-changed-watcher.service" "$module_dir/watcher/what-changed-watcher.service"
cp "$root_dir/deploy/what-changed-watcher.env.example" "$module_dir/watcher/what-changed-watcher.env"
cp "$root_dir/packaging/watcher/usr/lib/what-changed-watcher/configure-database.php" "$module_dir/watcher/configure-database.php"
cp "$root_dir/packaging/watcher/usr/sbin/what-changed-watcher-configure" "$module_dir/watcher/what-changed-watcher-configure"
cp "$root_dir/packaging/watcher/usr/sbin/what-changed-watcher-install-sensor" "$module_dir/watcher/what-changed-watcher-install-sensor"
cp "$root_dir/packaging/module-watcher/install-debian.sh" "$module_dir/watcher/install-debian.sh"
cp "$root_dir/packaging/module-watcher/install-portable.sh" "$module_dir/watcher/install-portable.sh"
chmod 0755 "$module_dir/bin/install-watcher" "$module_dir/bin/pendingchanges" \
  "$module_dir/watcher/install-debian.sh" "$module_dir/watcher/install-portable.sh" \
  "$module_dir/watcher/what-changed-watcher-configure" "$module_dir/watcher/what-changed-watcher-install-sensor"

tar -C "$temp_dir" -czf "$archive" "$version"
echo "$archive"
