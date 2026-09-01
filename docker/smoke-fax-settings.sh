#!/bin/sh
# Validate readable Fax Configuration channel-limit drift in Docker.
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
  channels=${2:-1}
  compose exec -T -e FREEPBX_FAX_ACTION="$action" -e FREEPBX_FAX_CHANNELS="$channels" pbx \
    sh -lc 'su -s /bin/sh asterisk -c "php /srv/pendingchanges/docker/seed-fax-channels.php"'
}

apply_clean() {
  compose exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null || true
  wait_for "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
}

run_fixture cleanup
apply_clean
run_fixture set 1
wait_for "s['need_reload'] and any(r.get('key') == 'concurrentfax' and r.get('value') == '1' for r in s['database_drift'].get('fax_details',{}).get('added',[]))"
apply_clean

run_fixture set 5
wait_for "s['need_reload'] and any(u.get('key') == 'concurrentfax' and u.get('fields',{}).get('value') == {'before':'1','after':'5'} for u in s['database_drift'].get('fax_details',{}).get('updated',[]))"
apply_clean

run_fixture cleanup
wait_for "s['need_reload'] and any(r.get('key') == 'concurrentfax' and r.get('value') == '5' for r in s['database_drift'].get('fax_details',{}).get('removed',[]))"
apply_clean

echo 'Fax Configuration concurrent-channel lifecycle passed'
