#!/bin/sh
set -eu

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/files" && pwd)
if [ ! -f "$source_dir/VERSION" ]; then
  echo 'Watcher bundle is incomplete: missing VERSION.' >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this installer as root.' >&2
  exit 1
fi
if [ ! -f /etc/freepbx.conf ]; then
  echo 'FreePBX was not found at /etc/freepbx.conf.' >&2
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo 'This test bundle requires a systemd-based FreePBX host.' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3.6 or newer is required.' >&2
  exit 1
fi
python_version=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 6) else 1)' || {
  echo "Python 3.6 or newer is required; found $python_version." >&2
  exit 1
}
if ! python3 -c 'import pymysql' >/dev/null 2>&1; then
  os_id=$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | head -n 1 | tr -d '"' || true)
  os_like=$(sed -n 's/^ID_LIKE=//p' /etc/os-release 2>/dev/null | head -n 1 | tr -d '"' || true)
  case " $os_id $os_like " in
    *debian*|*ubuntu*)
      dependency_command='apt-get update && apt-get install -y python3-pymysql'
      dependency_family=debian
      ;;
    *rhel*|*fedora*|*centos*|*rocky*|*almalinux*|*sangoma*)
      dependency_family=rhel
      if command -v dnf >/dev/null 2>&1; then
        dependency_command='dnf install -y python3-PyMySQL'
      else
        dependency_command='yum install -y python3-PyMySQL'
      fi
      ;;
    *)
      echo 'PyMySQL is required, but this operating-system family is not recognized.' >&2
      exit 1
      ;;
  esac
  echo 'PyMySQL is required by the WhatChanged watcher.' >&2
  echo "Proposed command: $dependency_command" >&2
  answer=
  if [ -r /dev/tty ]; then
    printf 'Install PyMySQL now and continue? [y/N] ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=
  fi
  case "$answer" in
    y|Y|yes|YES|Yes)
      if [ "$dependency_family" = debian ]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pymysql
      elif command -v dnf >/dev/null 2>&1; then
        dnf install -y python3-PyMySQL
      else
        yum install -y python3-PyMySQL
      fi
      ;;
    *)
      echo 'PyMySQL was not installed. Run the proposed command, then run this installer again.' >&2
      exit 1
      ;;
  esac
  python3 -c 'import pymysql' >/dev/null 2>&1 || {
    echo 'PyMySQL is still unavailable after the package installation attempt.' >&2
    exit 1
  }
fi

install -d -o root -g root -m 0755 /usr/local/lib/what-changed-watcher
install -m 0644 "$source_dir/watcher.py" /usr/local/lib/what-changed-watcher/watcher.py
install -m 0644 "$source_dir/what-changed-request-audit.php" /usr/local/lib/what-changed-watcher/what-changed-request-audit.php
install -m 0644 "$source_dir/99-what-changed-attribution.ini" /usr/local/lib/what-changed-watcher/99-what-changed-attribution.ini
install -m 0644 "$source_dir/configure-database.php" /usr/local/lib/what-changed-watcher/configure-database.php
install -m 0644 "$source_dir/what-changed-watcher.service" /usr/local/lib/what-changed-watcher/what-changed-watcher.service
install -m 0755 "$source_dir/what-changed-watcher-configure" /usr/sbin/what-changed-watcher-configure
install -m 0755 "$source_dir/what-changed-watcher-install-sensor" /usr/sbin/what-changed-watcher-install-sensor
install -m 0644 "$source_dir/what-changed-watcher.service" /etc/systemd/system/what-changed-watcher.service
if [ ! -f /etc/what-changed-watcher.env ]; then
  install -m 0600 "$source_dir/what-changed-watcher.env" /etc/what-changed-watcher.env
fi

version_target=/usr/local/lib/what-changed-watcher/VERSION
version_backup=
if [ -f "$version_target" ]; then
  version_backup=/tmp/what-changed-watcher-portable-version.$$
  cp "$version_target" "$version_backup"
fi
install -m 0644 "$source_dir/VERSION" "$version_target"
if ! (
  /usr/sbin/what-changed-watcher-configure --paths-only
  /usr/sbin/what-changed-watcher-install-sensor
  /usr/sbin/what-changed-watcher-configure
); then
  if [ -n "$version_backup" ]; then
    install -m 0644 "$version_backup" "$version_target"
  else
    rm -f "$version_target"
  fi
  [ -z "$version_backup" ] || rm -f "$version_backup"
  echo 'Portable watcher configuration failed; the installed version marker was rolled back.' >&2
  exit 1
fi
[ -z "$version_backup" ] || rm -f "$version_backup"
echo 'WhatChanged portable watcher installation completed.'
