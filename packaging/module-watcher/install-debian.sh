#!/bin/sh
# Debian-layout watcher install used by the module-embedded installer.
# This is the Debian 12 / FreePBX 17 path: files live under
# /usr/lib/what-changed-watcher with the service in /lib/systemd/system,
# mirroring the what-changed-watcher Debian package plus its postinst.
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

install -d -o root -g root -m 0755 /usr/lib/what-changed-watcher
install -d -o root -g root -m 0755 /lib/systemd/system
install -d -o root -g root -m 0755 /usr/sbin
install -m 0644 "$source_dir/watcher.py" /usr/lib/what-changed-watcher/watcher.py
install -m 0644 "$source_dir/what-changed-request-audit.php" /usr/lib/what-changed-watcher/what-changed-request-audit.php
install -m 0644 "$source_dir/configure-database.php" /usr/lib/what-changed-watcher/configure-database.php
install -m 0755 "$source_dir/what-changed-watcher-configure" /usr/sbin/what-changed-watcher-configure
install -m 0755 "$source_dir/what-changed-watcher-install-sensor" /usr/sbin/what-changed-watcher-install-sensor
# Review copies use /usr/local paths; distribution-managed packages use /usr/lib.
sed 's#/usr/local/lib/what-changed-watcher#/usr/lib/what-changed-watcher#g' \
  "$source_dir/99-what-changed-attribution.ini" > /usr/lib/what-changed-watcher/99-what-changed-attribution.ini
chmod 0644 /usr/lib/what-changed-watcher/99-what-changed-attribution.ini
sed 's#/usr/local/lib/what-changed-watcher#/usr/lib/what-changed-watcher#g' \
  "$source_dir/what-changed-watcher.service" > /lib/systemd/system/what-changed-watcher.service
chmod 0644 /lib/systemd/system/what-changed-watcher.service
if [ ! -f /etc/what-changed-watcher.env ]; then
  install -m 0600 "$source_dir/what-changed-watcher.env" /etc/what-changed-watcher.env
fi

# Finish exactly as the Debian package postinst does.
install -d -o asterisk -g asterisk -m 0750 /var/lib/asterisk/pendingchanges-watcher
install -d -o asterisk -g asterisk -m 0750 /var/lib/asterisk/pendingchanges-attribution
/usr/sbin/what-changed-watcher-install-sensor
systemctl daemon-reload
# A fresh install deliberately remains inactive until its dedicated,
# read-only database account has been configured.
if grep -q '^DB_PASSWORD=replace-with-generated-secret$' /etc/what-changed-watcher.env; then
  systemctl disable --now what-changed-watcher.service >/dev/null 2>&1 || true
  echo 'WhatChanged watcher installed. Run: sudo what-changed-watcher-configure'
else
  systemctl enable --now what-changed-watcher.service
fi
