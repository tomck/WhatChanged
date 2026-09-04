#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this uninstaller as root.' >&2
  exit 1
fi

systemctl disable --now what-changed-watcher.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/what-changed-watcher.service
rm -f /usr/sbin/what-changed-watcher-configure
rm -f /usr/sbin/what-changed-watcher-install-sensor
rm -rf /usr/local/lib/what-changed-watcher
for sensor in /etc/php/*/apache2/conf.d/99-what-changed-attribution.ini /etc/php.d/99-what-changed-attribution.ini; do
  if [ -f "$sensor" ]; then
    rm -f "$sensor"
  fi
done
systemctl daemon-reload

echo 'Watcher executables and sensor removed.'
echo 'Evidence, /etc/what-changed-watcher.env, and the SELECT-only database account were preserved.'
