#!/usr/bin/env bash
set -euo pipefail

# Install the default, value-free FreePBX request sensor alongside the watcher.
# This does not Apply Config or reload Asterisk; it reloads Apache only after
# validating the web-server configuration.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this installer as root" >&2
  exit 1
fi

source_dir=$(cd "$(dirname "$0")" && pwd)
sensor_dir=/usr/local/lib/what-changed-watcher
event_dir=/var/lib/asterisk/pendingchanges-attribution

mapfile -t php_apache_dirs < <(find /etc/php -mindepth 3 -maxdepth 3 -type d -path '*/apache2/conf.d' -print 2>/dev/null | sort -V)
if [[ ${#php_apache_dirs[@]} -eq 0 ]]; then
  echo "No Apache PHP conf.d directory was found" >&2
  exit 1
fi
php_apache_dir=${php_apache_dirs[-1]}

install -d -o root -g root -m 0755 "$sensor_dir"
install -o root -g root -m 0644 "$source_dir/what-changed-request-audit.php" \
  "$sensor_dir/what-changed-request-audit.php"
install -o root -g root -m 0644 "$source_dir/99-what-changed-attribution.ini" \
  "$php_apache_dir/99-what-changed-attribution.ini"
install -d -o asterisk -g asterisk -m 0750 "$event_dir"

apachectl configtest
systemctl reload apache2
echo "WhatChanged authenticated-request sensor installed"
