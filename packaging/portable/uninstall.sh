#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run this uninstaller as root.' >&2
  exit 1
fi

bundle_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
lifecycle=$bundle_dir/files/web-sensor-lifecycle.sh
if [ ! -r "$lifecycle" ]; then
  echo "Watcher uninstall helper is missing: $lifecycle" >&2
  echo 'Extract the complete portable watcher archive, then run this command again.' >&2
  exit 1
fi
. "$lifecycle"
if ! what_changed_remove_sensor_configuration; then
  echo 'The sensor ini files were removed, but an active web stack failed validation or reload.' >&2
  echo 'The watcher library was preserved so PHP does not reference a missing file.' >&2
  echo "Correct the reported web-server/PHP error, then rerun: sudo $bundle_dir/uninstall.sh" >&2
  exit 1
fi

systemctl disable --now what-changed-watcher.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/what-changed-watcher.service
rm -f /usr/sbin/what-changed-watcher-configure
rm -f /usr/sbin/what-changed-watcher-install-sensor
rm -rf /usr/local/lib/what-changed-watcher
systemctl daemon-reload

echo 'Watcher executables and sensor removed.'
echo 'Evidence, /etc/what-changed-watcher.env, and the SELECT-only database account were preserved.'
