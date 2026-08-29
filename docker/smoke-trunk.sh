#!/bin/sh
# Validate the disabled custom-trunk fixture lifecycle entirely in Docker.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"
compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
wait_for() {
  expr=$1; n=0
  while [ "$n" -lt 60 ]; do
    if compose exec -T custom-watcher python -c "import json;s=json.load(open('/var/lib/pendingchanges-watcher/status.json'));assert $expr" >/dev/null 2>&1; then return 0; fi
    n=$((n + 1)); sleep 1
  done
  compose exec -T custom-watcher python -c 'import json;print(json.dumps(json.load(open("/var/lib/pendingchanges-watcher/status.json")),indent=2))'
  return 1
}
apply_clean() {
  compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null
  wait_for "not s['need_reload'] and not s['database_drift'] and not s['file_drift']"
}
FREEPBX_TRUNK_ACTION=cleanup "$ROOT_DIR/docker/seed-trunk.sh"
if compose exec -T database mariadb -uasterisk -plocal-freepbx asterisk -N -e "SELECT value FROM admin WHERE variable='need_reload'" | grep -qx true; then apply_clean; fi
"$ROOT_DIR/docker/seed-trunk.sh"
wait_for "s['need_reload'] and any(r.get('name') == 'WhatChanged_Lab_Custom_Trunk' for r in s['database_drift'].get('trunks',{}).get('added',[]))"
apply_clean
FREEPBX_TRUNK_ACTION=update "$ROOT_DIR/docker/seed-trunk.sh"
wait_for "s['need_reload'] and any('name' in u.get('fields',{}) for u in s['database_drift'].get('trunks',{}).get('updated',[]))"
apply_clean
FREEPBX_TRUNK_ACTION=cleanup "$ROOT_DIR/docker/seed-trunk.sh"
wait_for "s['need_reload'] and bool(s['database_drift'].get('trunks',{}).get('removed'))"
apply_clean
echo 'authenticated custom-trunk create/update/delete lifecycle passed'
