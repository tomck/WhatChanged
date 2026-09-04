#!/usr/bin/env bash
set -euo pipefail

# Build the alpha watcher as a Debian package inside the disposable Debian 12
# lab. The host never needs dpkg-deb; the package payload is copied back into
# this checkout's dist/ directory.

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$root_dir/docker/docker-compose.yml"
control="$root_dir/packaging/watcher/DEBIAN/control"
version=$(sed -n 's/^Version: //p' "$control")
package=what-changed-watcher
archive="${package}_${version}_all.deb"

if [[ -z "$version" ]]; then
  echo 'Package version is missing.' >&2
  exit 1
fi

docker compose -f "$compose_file" up -d pbx
docker compose -f "$compose_file" exec -T pbx sh -s -- "$archive" <<'SH'
set -eu
archive=$1
root=/srv/pendingchanges
stage=$(mktemp -d /tmp/what-changed-watcher-package.XXXXXX)
trap 'rm -rf "$stage"' EXIT HUP INT TERM

cp -a "$root/packaging/watcher/." "$stage/"
mkdir -p "$stage/usr/lib/what-changed-watcher" \
  "$stage/lib/systemd/system" "$stage/etc" \
  "$stage/usr/share/doc/what-changed-watcher"
cp "$root/docker/custom-watcher/watcher.py" "$stage/usr/lib/what-changed-watcher/watcher.py"
cp "$root/deploy/what-changed-request-audit.php" "$stage/usr/lib/what-changed-watcher/what-changed-request-audit.php"
cp "$root/deploy/99-what-changed-attribution.ini" "$stage/usr/lib/what-changed-watcher/99-what-changed-attribution.ini"
cp "$root/deploy/what-changed-watcher.service" "$stage/lib/systemd/system/what-changed-watcher.service"
cp "$root/deploy/what-changed-watcher.env.example" "$stage/etc/what-changed-watcher.env"
chmod 0644 "$stage/usr/lib/what-changed-watcher/watcher.py" \
  "$stage/usr/lib/what-changed-watcher/what-changed-request-audit.php" \
  "$stage/usr/lib/what-changed-watcher/99-what-changed-attribution.ini" \
  "$stage/lib/systemd/system/what-changed-watcher.service" \
  "$stage/etc/what-changed-watcher.env" \
  "$stage/usr/share/doc/what-changed-watcher/copyright"
chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"
chmod 0755 "$stage/usr/sbin/what-changed-watcher-configure" \
  "$stage/usr/sbin/what-changed-watcher-install-sensor"
dpkg-deb --root-owner-group --build "$stage" "/tmp/$archive"
SH
mkdir -p "$root_dir/dist"
docker compose -f "$compose_file" cp "pbx:/tmp/$archive" "$root_dir/dist/$archive"
echo "$root_dir/dist/$archive"
