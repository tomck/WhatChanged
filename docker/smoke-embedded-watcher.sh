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
watcher_version=$(tr -d '[:space:]' < "$module/watcher/VERSION")
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
printf '%s\n' "$database" | grep -q "$(printf '\t')asterisk$(printf '\t')/var/www/html$(printf '\t')/etc/asterisk$(printf '\t')/var/lib/asterisk$(printf '\t')-$"
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

# Exercise discovery of non-default FreePBX database transport values without
# modifying the disposable PBX's live /etc/freepbx.conf.
socket_configurator="$stage/configure-database-socket.php"
awk '
  $0 == "require '\''/etc/freepbx.conf'\'';" {
    print "$amp_conf = array('\''AMPDBHOST'\'' => '\''localhost'\'', '\''AMPDBPORT'\'' => '\''4406'\'', '\''AMPDBSOCK'\'' => '\''/run/mariadb/custom.sock'\'', '\''AMPDBNAME'\'' => '\''asterisk'\'', '\''AMPWEBROOT'\'' => '\''/srv/freepbx-web'\'', '\''ASTETCDIR'\'' => '\''/srv/asterisk-config'\'', '\''ASTVARLIBDIR'\'' => '\''/srv/asterisk-data'\'');"
    next
  }
  { print }
' "$module/watcher/configure-database.php" > "$socket_configurator"
socket_database=$(php "$socket_configurator" --describe)
expected_socket_database="localhost$(printf '\t')4406$(printf '\t')asterisk$(printf '\t')/srv/freepbx-web$(printf '\t')/srv/asterisk-config$(printf '\t')/srv/asterisk-data$(printf '\t')/run/mariadb/custom.sock"
[ "$socket_database" = "$expected_socket_database" ]

detected=$(sh "$module/bin/install-watcher" --check)
echo "$detected" | grep -qx 'layout=debian'
echo "$detected" | grep -qx 'payload=complete'
echo "$detected" | grep -qx "embedded_version=$watcher_version"
echo "$detected" | grep -qx 'update_command=sudo '"$module"'/bin/install-watcher'

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

# Preserve the filesystem layout referenced by the active unit. PBX3 is a
# Debian host with an older portable /etc unit; writing a second /lib unit
# would not update the service systemd actually runs.
existing_root="$stage/root-existing-portable"
mkdir -p "$existing_root/etc/systemd/system"
cat > "$existing_root/etc/systemd/system/what-changed-watcher.service" <<'UNIT'
[Service]
ExecStart=/usr/bin/python3 /usr/local/lib/what-changed-watcher/watcher.py
UNIT
detected=$(WHAT_CHANGED_INSTALL_TESTING=1 \
  WHAT_CHANGED_INSTALL_ROOT="$existing_root" \
  WHAT_CHANGED_OS_RELEASE="$stage/os-release-debian" \
  sh "$module/bin/install-watcher" --check)
echo "$detected" | grep -qx 'layout=portable'
echo "$detected" | grep -qx 'service=/etc/systemd/system/what-changed-watcher.service'

# Missing dependencies are never installed silently. A declined prompt fails
# before staging files; acceptance runs the reviewed OS package command in
# simulation and then continues the normal test-root installation.
dependency_root="$stage/root-dependency"
if WHAT_CHANGED_INSTALL_TESTING=1 \
  WHAT_CHANGED_INSTALL_ROOT="$dependency_root" \
  WHAT_CHANGED_INSTALL_WEBROOT=/srv/freepbx-web \
  WHAT_CHANGED_PYMYSQL_STATE=missing \
  WHAT_CHANGED_INSTALL_PROMPT_RESPONSE=no \
  WHAT_CHANGED_OS_RELEASE="$stage/os-release-debian" \
  sh "$module/bin/install-watcher" >"$stage/dependency-declined.out" 2>&1; then
  echo 'Declining automatic PyMySQL installation unexpectedly succeeded.' >&2
  exit 1
fi
grep -q 'Proposed command: apt-get update && apt-get install -y python3-pymysql' \
  "$stage/dependency-declined.out"
test ! -e "$dependency_root/usr/lib/what-changed-watcher/watcher.py"

accepted=$(WHAT_CHANGED_INSTALL_TESTING=1 \
  WHAT_CHANGED_INSTALL_ROOT="$dependency_root" \
  WHAT_CHANGED_INSTALL_WEBROOT=/srv/freepbx-web \
  WHAT_CHANGED_PYMYSQL_STATE=missing \
  WHAT_CHANGED_INSTALL_PROMPT_RESPONSE=yes \
  WHAT_CHANGED_OS_RELEASE="$stage/os-release-debian" \
  sh "$module/bin/install-watcher")
echo "$accepted" | grep -qx \
  'test_dependency_command=apt-get update && apt-get install -y python3-pymysql'
test -s "$dependency_root/usr/lib/what-changed-watcher/VERSION"

newer_root="$stage/root-newer"
mkdir -p "$newer_root/usr/lib/what-changed-watcher"
printf '# fixture\n' > "$newer_root/usr/lib/what-changed-watcher/watcher.py"
printf '99.0.0\n' > "$newer_root/usr/lib/what-changed-watcher/VERSION"
detected=$(WHAT_CHANGED_INSTALL_TESTING=1 WHAT_CHANGED_INSTALL_ROOT="$newer_root" \
  sh "$module/bin/install-watcher" --layout debian --check)
echo "$detected" | grep -qx 'payload_state=newer'
echo "$detected" | grep -qx 'module_update_required=yes'
if echo "$detected" | grep -q '^update_command='; then
  echo 'A newer installed watcher was offered a downgrade command.' >&2
  exit 1
fi

for layout in debian portable; do
  root="$stage/root-$layout"
  mkdir -p "$root"
  test_webroot=/srv/freepbx-web
  test_astetc=/srv/asterisk-config
  test_astvarlib=/srv/asterisk-data
  test_dbsock=/srv/mariadb/custom.sock
  WHAT_CHANGED_INSTALL_TESTING=1 WHAT_CHANGED_INSTALL_ROOT="$root" \
    WHAT_CHANGED_INSTALL_WEBROOT="$test_webroot" \
    WHAT_CHANGED_INSTALL_ASTETCDIR="$test_astetc" \
    WHAT_CHANGED_INSTALL_ASTVARLIBDIR="$test_astvarlib" \
    WHAT_CHANGED_INSTALL_DBPORT=3307 \
    WHAT_CHANGED_INSTALL_DBSOCK="$test_dbsock" \
    sh "$module/bin/install-watcher" --layout "$layout" >/dev/null

  if [ "$layout" = debian ]; then
    library=/usr/lib/what-changed-watcher
    service=/lib/systemd/system/what-changed-watcher.service
  else
    library=/usr/local/lib/what-changed-watcher
    service=/etc/systemd/system/what-changed-watcher.service
  fi

  test -s "$root$library/watcher.py"
  test -s "$root$library/VERSION"
  test -s "$root$library/what-changed-watcher.service"
  test -s "$root$library/what-changed-request-audit.php"
  test -x "$root/usr/sbin/what-changed-watcher-configure"
  test -x "$root/usr/sbin/what-changed-watcher-install-sensor"
  grep -q 'Validating the complete Apache configuration on this host' \
    "$root/usr/sbin/what-changed-watcher-install-sensor"
  grep -q 'WhatChanged does not create or modify Apache DocumentRoot directives' \
    "$root/usr/sbin/what-changed-watcher-install-sensor"
  test -s "$root$service"
  test -s "$root/etc/what-changed-watcher.env"
  grep -q "ExecStart=/usr/bin/python3 $library/watcher.py" "$root$service"
  grep -q "ReadOnlyPaths=.* $test_webroot/admin/modules " "$root$service"
  grep -q "ReadOnlyPaths=$test_astetc $test_astvarlib " "$root$service"
  grep -qx 'DB_PORT=3307' "$root/etc/what-changed-watcher.env"
  grep -qx "DB_SOCKET=$test_dbsock" "$root/etc/what-changed-watcher.env"
  grep -qx "WATCH_PATH=$test_astetc" "$root/etc/what-changed-watcher.env"
  grep -qx "MODULE_PATH=$test_webroot/admin/modules" "$root/etc/what-changed-watcher.env"
  grep -qx "ASTDB_PATH=$test_astvarlib/astdb.sqlite3" "$root/etc/what-changed-watcher.env"
  grep -qx "STATE_DIR=$test_astvarlib/pendingchanges-watcher" "$root/etc/what-changed-watcher.env"
  grep -q "auto_prepend_file=$library/what-changed-request-audit.php" \
    "$root$library/99-what-changed-attribution.ini"
  cmp "$root$library/watcher.py" "$module/watcher/watcher.py"
  cmp "$root$library/VERSION" "$module/watcher/VERSION"

  detected=$(WHAT_CHANGED_INSTALL_TESTING=1 WHAT_CHANGED_INSTALL_ROOT="$root" \
    sh "$module/bin/install-watcher" --layout "$layout" --check)
  echo "$detected" | grep -qx "installed_version=$watcher_version"
  echo "$detected" | grep -qx 'payload_state=current'
done

echo 'Embedded watcher Debian/portable layout validation passed'
SH
