#!/usr/bin/env bash
# Run the complete FreePBX 17 gate with nginx + PHP-FPM serving the GUI. Apache
# remains installed only because the upstream FreePBX installer requires it;
# the gate fails if an Apache process is active or serves any request.
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$root_dir/docker/docker-compose.yml"

export COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-what-changed-nginx}
export FREEPBX_WEB_SERVER=nginx
export FREEPBX_LAB_PORT=${FREEPBX_LAB_PORT:-8081}
export FREEPBX_LAB_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:$FREEPBX_LAB_PORT}

case "$FREEPBX_LAB_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo 'Refusing to run the nginx gate outside the local Docker lab.' >&2; exit 2 ;;
esac

"$root_dir/docker/lab-gate.sh"

docker compose -f "$compose_file" exec -T pbx sh -eu -c '
  pgrep -x nginx >/dev/null
  pgrep -x php-fpm8.2 >/dev/null
  ! pgrep -x apache2 >/dev/null
  ! pgrep -x httpd >/dev/null
  test -s /etc/php/8.2/fpm/conf.d/99-what-changed-attribution.ini
  grep -q "auto_prepend_file=" /etc/php/8.2/fpm/conf.d/99-what-changed-attribution.ini
  # Exercise the shipping sensor installer with its complete portable payload,
  # not merely a copied executable. The normal embedded installer stages these
  # files together before invoking it.
  install -d -m 0755 /usr/local/lib/what-changed-watcher
  install -m 0644 \
    /srv/pendingchanges/deploy/99-what-changed-attribution.ini \
    /usr/local/lib/what-changed-watcher/99-what-changed-attribution.ini
  install -m 0644 \
    /srv/pendingchanges/deploy/what-changed-request-audit.php \
    /usr/local/lib/what-changed-watcher/what-changed-request-audit.php
  install -m 0755 \
    /srv/pendingchanges/packaging/watcher/usr/sbin/what-changed-watcher-install-sensor \
    /usr/sbin/what-changed-watcher-install-sensor
  /usr/sbin/what-changed-watcher-install-sensor
  test -s /etc/php/8.2/fpm/conf.d/99-what-changed-attribution.ini
  grep -q "auto_prepend_file=/usr/local/lib/what-changed-watcher/what-changed-request-audit.php" \
    /etc/php/8.2/fpm/conf.d/99-what-changed-attribution.ini
  ! pgrep -x apache2 >/dev/null
  ! pgrep -x httpd >/dev/null
'

server=$(curl -fsSI "$FREEPBX_LAB_URL/admin/config.php" \
  | sed -n 's/^Server:[[:space:]]*//Ip' | tr -d '\r' | head -n 1)
case "$server" in
  nginx*) ;;
  *) echo "Expected nginx response header; received: ${server:-none}" >&2; exit 1 ;;
esac

"$root_dir/docker/smoke-watcher-health-page.sh"
echo 'WhatChanged nginx + PHP-FPM FreePBX 17 gate passed with Apache stopped'
