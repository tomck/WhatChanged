#!/usr/bin/env bash
set -euo pipefail

# Development-checkout helper. Stage the complete portable sensor payload and
# delegate web-stack discovery, validation, and reload behavior to the same
# installer shipped in module and watcher packages.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this installer as root" >&2
  exit 1
fi

source_dir=$(cd "$(dirname "$0")" && pwd)
root_dir=$(cd "$source_dir/.." && pwd)
sensor_dir=/usr/local/lib/what-changed-watcher
installer=$root_dir/packaging/watcher/usr/sbin/what-changed-watcher-install-sensor

install -d -o root -g root -m 0755 "$sensor_dir"
install -o root -g root -m 0644 "$source_dir/what-changed-request-audit.php" \
  "$sensor_dir/what-changed-request-audit.php"
install -o root -g root -m 0644 "$source_dir/99-what-changed-attribution.ini" \
  "$sensor_dir/99-what-changed-attribution.ini"

"$installer"
