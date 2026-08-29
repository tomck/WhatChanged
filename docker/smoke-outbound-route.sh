#!/bin/sh
# Validate outbound-route create/update/delete evidence entirely in Docker.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

watcher_assert() {
  expression=$1
  attempts=0
  while [ "$attempts" -lt 40 ]; do
    if compose exec -T custom-watcher python -c "
import json
s=json.load(open('/var/lib/pendingchanges-watcher/status.json'))
assert ($expression)
" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  compose exec -T custom-watcher python -c '
import json
s=json.load(open("/var/lib/pendingchanges-watcher/status.json"))
print(json.dumps({"need_reload":s.get("need_reload"),"database_drift":s.get("database_drift"),"coverage_limitations":s.get("coverage_limitations")},indent=2))
'
  return 1
}

apply_and_wait_clean() {
  compose exec -T pbx sh -lc \
    'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null
  watcher_assert "not s['need_reload'] and not s['database_drift'] and not s['file_drift']"
}

# Remove only the fixed lab-owned route from a prior interrupted run.
FREEPBX_ROUTE_ACTION=cleanup "$ROOT_DIR/docker/seed-outbound-route.sh"
if compose exec -T database mariadb -uasterisk -plocal-freepbx asterisk -N -e \
  "SELECT value FROM admin WHERE variable='need_reload'" | grep -qx true; then
  watcher_assert "s['need_reload']"
  apply_and_wait_clean
else
  watcher_assert "not s['need_reload'] and not s['database_drift']"
fi

# First prove that route creation explains all normalized FreePBX records.
"$ROOT_DIR/docker/seed-outbound-route.sh"
watcher_assert "
s['need_reload'] and
any(r.get('name') == 'WhatChanged Lab Outbound Route' for r in s['database_drift'].get('outbound_routes',{}).get('added',[])) and
any(r.get('match_pattern_pass') == 'X.' for r in s['database_drift'].get('outbound_route_patterns',{}).get('added',[])) and
bool(s['database_drift'].get('outbound_route_sequence',{}).get('added'))
"
apply_and_wait_clean

# A malicious staged edit is the important review case: preserve the route id
# while making both its visible name and routing behavior explainable.
FREEPBX_ROUTE_ACTION=update "$ROOT_DIR/docker/seed-outbound-route.sh"
watcher_assert "
s['need_reload'] and
any(u.get('fields',{}).get('name') == {'before':'WhatChanged Lab Outbound Route','after':'WhatChanged Lab Outbound Route Updated'} for u in s['database_drift'].get('outbound_routes',{}).get('updated',[])) and
any(r.get('match_pattern_pass') == 'X.' for r in s['database_drift'].get('outbound_route_patterns',{}).get('removed',[])) and
any(r.get('match_pattern_pass') == '9X.' for r in s['database_drift'].get('outbound_route_patterns',{}).get('added',[]))
"
apply_and_wait_clean

# Leave the persistent lab exactly as it began.
FREEPBX_ROUTE_ACTION=cleanup "$ROOT_DIR/docker/seed-outbound-route.sh"
watcher_assert "
s['need_reload'] and
bool(s['database_drift'].get('outbound_routes',{}).get('removed')) and
bool(s['database_drift'].get('outbound_route_patterns',{}).get('removed')) and
bool(s['database_drift'].get('outbound_route_sequence',{}).get('removed'))
"
apply_and_wait_clean
echo 'authenticated outbound-route create/update/delete lifecycle passed'
