#!/bin/sh
# Exercise baseline provenance around real watcher interruptions in the
# disposable FreePBX lab. No production URL or host is accepted.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

sql() {
  compose exec -T database mariadb -uroot -plocal-freepbx-root asterisk -e "$1"
}

assert_status() {
  expression=$1
  attempts=0
  while [ "$attempts" -lt 90 ]; do
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
  compose exec -T custom-watcher python -c \
    'import json; print(json.dumps(json.load(open("/var/lib/pendingchanges-watcher/status.json")), indent=2))'
  return 1
}

apply_cli() {
  compose exec -T pbx /var/lib/asterisk/bin/fwconsole reload >/dev/null
}

apply_web() {
  "$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
}

table=pc_recovery_fixture
cleanup() {
  compose start custom-watcher >/dev/null 2>&1 || true
  sql "DROP TABLE IF EXISTS \`$table\`; UPDATE admin SET value='true' WHERE variable='need_reload';" >/dev/null 2>&1 || true
  apply_cli >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted'"

# A restart with no intervening state change retains verified continuity.
compose restart custom-watcher >/dev/null
assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted'"

# If a CLI Apply occurs entirely while the watcher is stopped, no web
# breadcrumb or observed reload transition proves which Apply produced the
# current state. The watcher must keep the evidence and say it is uncertain.
compose stop custom-watcher >/dev/null
sql "CREATE TABLE \`$table\` (id INT PRIMARY KEY, value VARCHAR(50)); INSERT INTO \`$table\` VALUES (1, 'missed-apply'); UPDATE admin SET value='true' WHERE variable='need_reload';"
apply_cli
compose start custom-watcher >/dev/null
assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'uncertain' and '$table' in s['database_drift']"

# A fully observed pending-to-clean Apply establishes a new authoritative
# baseline and removes the stale cross-interruption comparison.
sql "UPDATE \`$table\` SET value='observed-apply' WHERE id=1; UPDATE admin SET value='true' WHERE variable='need_reload';"
assert_status "s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'uncertain'"
apply_web
assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted' and not s['database_drift']"

# A pending state observed before shutdown also proves the later flag clear;
# recovery may safely refresh the baseline even though the service was down.
sql "UPDATE \`$table\` SET value='pending-before-stop' WHERE id=1; UPDATE admin SET value='true' WHERE variable='need_reload';"
assert_status "s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted'"
compose stop custom-watcher >/dev/null
apply_cli
compose start custom-watcher >/dev/null
assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted' and not s['database_drift']"

# Remove only this smoke-owned table through one final observed Apply.
sql "DROP TABLE \`$table\`; UPDATE admin SET value='true' WHERE variable='need_reload';"
assert_status "s['need_reload'] and '$table' in s['database_drift']"
apply_web
assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted' and not s['database_drift']"

trap - EXIT HUP INT TERM
echo 'Watcher interruption and baseline-provenance lifecycle passed'
