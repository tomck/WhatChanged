#!/usr/bin/env bash
set -euo pipefail

# Validate the assembled Debian artifact in the disposable FreePBX lab. The
# lab does not run systemd as PID 1, so this validates package metadata,
# payload, and maintainer-script syntax rather than falsely claiming a full
# service install there.

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$root_dir/docker/docker-compose.yml"
package=${1:?usage: validate-watcher-package.sh path/to/watcher.deb}

if [[ ! -f "$package" ]]; then
  echo "Package not found: $package" >&2
  exit 2
fi
package=$(cd "$(dirname "$package")" && pwd)/$(basename "$package")
case "$package" in "$root_dir"/*) ;; *) echo 'Package must be inside this checkout.' >&2; exit 2 ;; esac
name=$(basename "$package")

docker compose -f "$compose_file" up -d pbx
docker compose -f "$compose_file" cp "$package" "pbx:/tmp/$name"
docker compose -f "$compose_file" exec -T pbx sh -s -- "$name" <<'SH'
set -eu
package=/tmp/$1
stage=$(mktemp -d /tmp/what-changed-watcher-validate.XXXXXX)
trap 'rm -rf "$stage" "$package"' EXIT HUP INT TERM

dpkg-deb --info "$package" | grep -qx ' Package: what-changed-watcher'
dpkg-deb --info "$package" | grep -qx ' Version: 0.1.0'
dpkg-deb --contents "$package" | grep -q 'usr/lib/what-changed-watcher/watcher.py'
dpkg-deb --contents "$package" | grep -q 'lib/systemd/system/what-changed-watcher.service'
dpkg-deb --contents "$package" | grep -q 'usr/sbin/what-changed-watcher-configure'
dpkg-deb --extract "$package" "$stage"

test -f "$stage/etc/what-changed-watcher.env"
test -f "$stage/usr/lib/what-changed-watcher/what-changed-request-audit.php"
test -f "$stage/usr/lib/what-changed-watcher/99-what-changed-attribution.ini"
test -x "$stage/usr/sbin/what-changed-watcher-configure"
test -x "$stage/usr/sbin/what-changed-watcher-install-sensor"
sh -n "$stage/usr/sbin/what-changed-watcher-configure"
sh -n "$stage/usr/sbin/what-changed-watcher-install-sensor"
php -l "$stage/usr/lib/what-changed-watcher/configure-database.php"
python3 -m py_compile "$stage/usr/lib/what-changed-watcher/watcher.py"
echo 'Watcher Debian package layout validation passed'
SH
