#!/bin/sh
# Portable-layout watcher install used by the module-embedded installer.
# This is the CentOS 7 / SangomaOS / SNG7 path: files live under
# /usr/local/lib/what-changed-watcher, mirroring packaging/portable/install.sh.
# Run via bin/install-watcher (which performs preflights and OS detection),
# or directly as root with WATCHER_SRC pointing at the payload directory.
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this installer as root.' >&2
  exit 1
fi

source_dir=${WATCHER_SRC:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
for file in watcher.py what-changed-request-audit.php 99-what-changed-attribution.ini \
  configure-database.php what-changed-watcher-configure what-changed-watcher-install-sensor \
  what-changed-watcher.service what-changed-watcher.env; do
  if [ ! -f "$source_dir/$file" ]; then
    echo "Watcher payload is incomplete; missing $file in $source_dir." >&2
    exit 1
  fi
done

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
