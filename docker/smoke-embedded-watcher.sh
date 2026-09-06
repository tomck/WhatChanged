#!/usr/bin/env bash
# Validate both filesystem layouts of the watcher embedded in the module.
# Installation is redirected into disposable roots; no host service, Apache
# configuration, database account, or PBX configuration is changed.
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file=${WHAT_CHANGED_COMPOSE_FILE:-$root_dir/docker/docker-compose.yml}
pbx_service=${WHAT_CHANGED_PBX_SERVICE:-pbx}
source "$root_dir/deploy/release-versions.sh"
archive=${WHAT_CHANGED_ARCHIVE_PATH:-/srv/pendingchanges/dist/pendingchanges-$module_version.tgz}

docker compose -f "$compose_file" exec -T "$pbx_service" sh -s -- "$archive" <<'SH'
set -eu
archive=$1
stage=$(mktemp -d /tmp/what-changed-embedded.XXXXXX)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
tar -xzf "$archive" -C "$stage"
module="$stage/pendingchanges"
printf 'ID=debian\nID_LIKE=debian\n' > "$stage/os-release-debian"
printf 'ID=sangoma\nID_LIKE="rhel fedora"\n' > "$stage/os-release-sangoma"
printf 'ID=unknown\n' > "$stage/os-release-unknown"

sh -n "$module/bin/install-watcher" "$module/bin/uninstall-watcher"
php -l "$module/bin/pendingchanges" >/dev/null
php -l "$module/page.pendingchanges.php" >/dev/null
if command -v python3 >/dev/null 2>&1; then
  python3 -m py_compile "$module/watcher/watcher.py"
fi

# The disposable v17 lab deliberately uses a separate database container.
# The embedded installer must be able to inspect that configuration so it can
# install files and leave the service disabled for manual SELECT-only setup.
database=$(php "$module/watcher/configure-database.php" --describe)
printf '%s\n' "$database" | grep -q "$(printf '\t')asterisk$(printf '\t')/var/www/html$"
db_host=${database%%"$(printf '\t')"*}
case "$db_host" in
  localhost|127.0.0.1)
    php "$module/watcher/configure-database.php" >/dev/null
    ;;
  *)
    if php "$module/watcher/configure-database.php" >/dev/null 2>&1; then
      echo 'Remote database configuration unexpectedly passed automatic setup.' >&2
      exit 1
    fi
    ;;
esac

detected=$(sh "$module/bin/install-watcher" --check)
echo "$detected" | grep -qx 'layout=debian'
echo "$detected" | grep -qx 'payload=complete'

detected=$(WHAT_CHANGED_INSTALL_TESTING=1 \
  WHAT_CHANGED_OS_RELEASE="$stage/os-release-debian" \
  sh "$module/bin/install-watcher" --check)
echo "$detected" | grep -qx 'layout=debian'
detected=$(WHAT_CHANGED_INSTALL_TESTING=1 \
  WHAT_CHANGED_OS_RELEASE="$stage/os-release-sangoma" \
  sh "$module/bin/install-watcher" --check)
echo "$detected" | grep -qx 'layout=portable'
if WHAT_CHANGED_INSTALL_TESTING=1 \
  WHAT_CHANGED_OS_RELEASE="$stage/os-release-unknown" \
  sh "$module/bin/install-watcher" --check >/dev/null 2>&1; then
  echo 'Unknown operating-system detection unexpectedly succeeded.' >&2
  exit 1
fi

for layout in debian portable; do
  root="$stage/root-$layout"
  mkdir -p "$root"
  test_webroot=/srv/freepbx-web
  WHAT_CHANGED_INSTALL_TESTING=1 WHAT_CHANGED_INSTALL_ROOT="$root" \
    WHAT_CHANGED_INSTALL_WEBROOT="$test_webroot" \
    sh "$module/bin/install-watcher" --layout "$layout" >/dev/null

  if [ "$layout" = debian ]; then
    library=/usr/lib/what-changed-watcher
    service=/lib/systemd/system/what-changed-watcher.service
  else
    library=/usr/local/lib/what-changed-watcher
    service=/etc/systemd/system/what-changed-watcher.service
  fi

  test -s "$root$library/watcher.py"
  test -s "$root$library/what-changed-request-audit.php"
  test -x "$root/usr/sbin/what-changed-watcher-configure"
  test -x "$root/usr/sbin/what-changed-watcher-install-sensor"
  test -s "$root$service"
  test -s "$root/etc/what-changed-watcher.env"
  grep -q "ExecStart=/usr/bin/python3 $library/watcher.py" "$root$service"
  grep -q "Environment=MODULE_PATH=$test_webroot/admin/modules" "$root$service"
  grep -q "ReadOnlyPaths=.* $test_webroot/admin/modules " "$root$service"
  grep -q "auto_prepend_file=$library/what-changed-request-audit.php" \
    "$root$library/99-what-changed-attribution.ini"
  cmp "$root$library/watcher.py" "$module/watcher/watcher.py"
done

echo 'Embedded watcher Debian/portable layout validation passed'
SH
