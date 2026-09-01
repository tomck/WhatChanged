#!/bin/sh
# Validate the User Management UCP-assignment storage lifecycle in Docker.
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

run_fixture() {
  action=$1
  compose exec -T -e FREEPBX_USERMAN_ACTION="$action" pbx \
    sh -lc 'su -s /bin/sh asterisk -c "php /srv/pendingchanges/docker/seed-userman-setting.php"'
}

apply_clean() {
  compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null || true
  wait_for "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
}

run_fixture cleanup
apply_clean
run_fixture create
apply_clean

run_fixture assign
wait_for "s['need_reload'] and any(r.get('username') == 'whatchanged_alpha_fixture' and r.get('module') == 'ucp|Settings' and r.get('key') == 'assigned' and '7999' in r.get('val','') for r in s['database_drift'].get('userman_users_settings',{}).get('added',[]))"
apply_clean

run_fixture update
wait_for "s['need_reload'] and any(u.get('identity',{}).get('username') == 'whatchanged_alpha_fixture' and u.get('identity',{}).get('module') == 'ucp|Settings' and u.get('identity',{}).get('key') == 'assigned' and '7998' in u.get('fields',{}).get('val',{}).get('after','') for u in s['database_drift'].get('userman_users_settings',{}).get('updated',[]))"
apply_clean

run_fixture cleanup
wait_for "s['need_reload'] and bool(s['database_drift'].get('userman_users',{}).get('removed')) and bool(s['database_drift'].get('userman_users_settings',{}).get('removed'))"
apply_clean

echo 'User Management UCP assignment lifecycle passed'
