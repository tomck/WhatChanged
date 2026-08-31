#!/bin/sh
# Verify that FreePBX Module Admin enable/disable state is attributable by
# module name. The test uses this project's own disposable lab module and
# restores it to enabled before finishing.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"
compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

wait_for() {
  expression=$1
  attempts=0
  while [ "$attempts" -lt 60 ]; do
    if compose exec -T custom-watcher python -c "import json;s=json.load(open('/var/lib/pendingchanges-watcher/status.json'));assert $expression" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  compose exec -T custom-watcher python -c 'import json;print(json.dumps(json.load(open("/var/lib/pendingchanges-watcher/status.json")),indent=2))'
  return 1
}

apply_clean() {
  compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null || true
  wait_for "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
}

# Establish a known applied baseline with the fixture module enabled.
compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole ma enable pendingchanges"' >/dev/null || true
apply_clean

compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole ma disable pendingchanges"' >/dev/null
wait_for "s['need_reload'] and any(u.get('key') == 'pendingchanges' and u.get('fields',{}).get('enabled') == {'before':1,'after':0} for u in s['database_drift'].get('modules',{}).get('updated',[]))"

# Restore the fixture, Apply Config, and require a clean watcher baseline.
compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole ma enable pendingchanges"' >/dev/null
apply_clean
compose exec -T database mariadb -uasterisk -plocal-freepbx asterisk -N -e "SELECT enabled FROM modules WHERE modulename='pendingchanges'" | grep -qx 1

echo 'FreePBX module disable evidence lifecycle passed'
