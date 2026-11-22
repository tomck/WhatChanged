#!/bin/sh
# Validate System Recordings create/update/delete coverage in Docker.
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
  compose exec -T -e FREEPBX_RECORDING_ACTION="$action" pbx \
    sh -lc 'su -s /bin/sh asterisk -c "php /srv/pendingchanges/docker/seed-system-recording.php"'
}

apply_clean() {
  before=$(compose exec -T custom-watcher python -c \
    "import json;print(json.load(open('/var/lib/pendingchanges-watcher/status.json'))['observed_at'])")
  "$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
  wait_for "s['observed_at'] > $before and not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
}

run_fixture cleanup >/dev/null
apply_clean

run_fixture add >/dev/null
wait_for "s['need_reload'] and any(r.get('displayname') == 'WhatChanged disposable recording' and r.get('description') == 'Initial WhatChanged coverage fixture' for r in s['database_drift'].get('recordings',{}).get('added',[]))"
apply_clean

run_fixture update >/dev/null
wait_for "s['need_reload'] and any(u.get('identity',{}).get('displayname') == 'WhatChanged disposable recording' and u.get('fields',{}).get('description') == {'before': 'Initial WhatChanged coverage fixture', 'after': 'Updated WhatChanged coverage fixture'} for u in s['database_drift'].get('recordings',{}).get('updated',[]))"
apply_clean

run_fixture delete >/dev/null
wait_for "s['need_reload'] and any(r.get('displayname') == 'WhatChanged disposable recording' for r in s['database_drift'].get('recordings',{}).get('removed',[]))"
apply_clean
echo 'System Recordings lifecycle passed'
