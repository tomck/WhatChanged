#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^Version: //p' "$root_dir/packaging/watcher/DEBIAN/control")
archive="$root_dir/dist/what-changed-watcher-portable_$version.tar.gz"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
bundle="$stage/what-changed-watcher-portable-$version"

mkdir -p "$bundle/files" "$root_dir/dist"
cp "$root_dir/docker/custom-watcher/watcher.py" "$bundle/files/watcher.py"
cp "$root_dir/deploy/what-changed-request-audit.php" "$bundle/files/what-changed-request-audit.php"
cp "$root_dir/deploy/99-what-changed-attribution.ini" "$bundle/files/99-what-changed-attribution.ini"
cp "$root_dir/deploy/what-changed-watcher.service" "$bundle/files/what-changed-watcher.service"
cp "$root_dir/deploy/what-changed-watcher.env.example" "$bundle/files/what-changed-watcher.env"
cp "$root_dir/packaging/watcher/usr/lib/what-changed-watcher/configure-database.php" "$bundle/files/configure-database.php"
cp "$root_dir/packaging/watcher/usr/sbin/what-changed-watcher-configure" "$bundle/files/what-changed-watcher-configure"
cp "$root_dir/packaging/watcher/usr/sbin/what-changed-watcher-install-sensor" "$bundle/files/what-changed-watcher-install-sensor"
cp "$root_dir/packaging/portable/install.sh" "$bundle/install.sh"
cp "$root_dir/packaging/portable/uninstall.sh" "$bundle/uninstall.sh"
cp "$root_dir/LICENSE" "$bundle/LICENSE"
cp "$root_dir/docs/legacy-alpha-install.md" "$bundle/README.md"
chmod 0755 "$bundle/install.sh" "$bundle/uninstall.sh" \
  "$bundle/files/what-changed-watcher-configure" \
  "$bundle/files/what-changed-watcher-install-sensor"

tar -C "$stage" -czf "$archive" "$(basename "$bundle")"
echo "$archive"
