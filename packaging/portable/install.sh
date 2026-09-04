#!/bin/sh
set -eu

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
python3 -c 'import pymysql' >/dev/null 2>&1 || {
  echo 'The Python 3 PyMySQL package is required. See README.md.' >&2
  exit 1
}

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/files" && pwd)
install -d -o root -g root -m 0755 /usr/local/lib/what-changed-watcher
install -d -o asterisk -g asterisk -m 0750 /var/lib/asterisk/pendingchanges-watcher
install -d -o asterisk -g asterisk -m 0750 /var/lib/asterisk/pendingchanges-attribution
install -m 0644 "$source_dir/watcher.py" /usr/local/lib/what-changed-watcher/watcher.py
install -m 0644 "$source_dir/what-changed-request-audit.php" /usr/local/lib/what-changed-watcher/what-changed-request-audit.php
install -m 0644 "$source_dir/99-what-changed-attribution.ini" /usr/local/lib/what-changed-watcher/99-what-changed-attribution.ini
install -m 0644 "$source_dir/configure-database.php" /usr/local/lib/what-changed-watcher/configure-database.php
install -m 0755 "$source_dir/what-changed-watcher-configure" /usr/sbin/what-changed-watcher-configure
install -m 0755 "$source_dir/what-changed-watcher-install-sensor" /usr/sbin/what-changed-watcher-install-sensor
install -m 0644 "$source_dir/what-changed-watcher.service" /etc/systemd/system/what-changed-watcher.service
if [ ! -f /etc/what-changed-watcher.env ]; then
  install -m 0600 "$source_dir/what-changed-watcher.env" /etc/what-changed-watcher.env
fi

/usr/sbin/what-changed-watcher-install-sensor
/usr/sbin/what-changed-watcher-configure
echo 'WhatChanged portable watcher installation completed.'
