#!/bin/sh
# Prove recognizable secrets cannot escape the persisted baseline or public
# status in the disposable Docker PBX.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
sql() { compose exec -T database mariadb -uroot -plocal-freepbx-root asterisk -e "$1"; }
assert_status() {
  expression=$1
  attempts=0
  while [ "$attempts" -lt 90 ]; do
    if compose exec -T custom-watcher python -c "
import json
s=json.load(open('/var/lib/pendingchanges-watcher/status.json'))
assert ($expression)
" >/dev/null 2>&1; then return 0; fi
    attempts=$((attempts + 1)); sleep 1
  done
  compose exec -T custom-watcher python -c \
    'import json; print(json.dumps(json.load(open("/var/lib/pendingchanges-watcher/status.json")), indent=2))'
  return 1
}

table=pc_redaction_fixture
before=whatchanged-secret-marker-before
after=whatchanged-secret-marker-after
cleanup() {
  sql "DROP TABLE IF EXISTS \`$table\`; UPDATE admin SET value='true' WHERE variable='need_reload';" >/dev/null 2>&1 || true
  "$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

assert_status "not s['need_reload'] and s.get('baseline_provenance', {}).get('state') == 'trusted'"
sql "CREATE TABLE \`$table\` (variable VARCHAR(64) PRIMARY KEY, value VARCHAR(128)); INSERT INTO \`$table\` VALUES ('API_TOKEN', '$before'); UPDATE admin SET value='true' WHERE variable='need_reload';"
assert_status "s['database_drift']['$table']['added'][0]['value'] == '[redacted]'"
compose exec -T custom-watcher sh -c \
  "! grep -F '$before' /var/lib/pendingchanges-watcher/status.json && ! grep -F '[protected hmac-sha256:' /var/lib/pendingchanges-watcher/status.json"

"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
assert_status "not s['need_reload'] and not s['database_drift']"
compose exec -T custom-watcher sh -c \
  "! grep -F '$before' /var/lib/pendingchanges-watcher/baseline.json && grep -F '[protected hmac-sha256:' /var/lib/pendingchanges-watcher/baseline.json >/dev/null"
compose exec -T custom-watcher python -c \
  "import os,stat; assert stat.S_IMODE(os.stat('/var/lib/pendingchanges-watcher/redaction.key').st_mode) == 0o600"

sql "UPDATE \`$table\` SET value='$after' WHERE variable='API_TOKEN'; UPDATE admin SET value='true' WHERE variable='need_reload';"
assert_status "s['database_drift']['$table']['updated'][0]['fields']['value'] == {'before': '[redacted]', 'after': '[redacted]'}"
compose exec -T custom-watcher sh -c \
  "! grep -F '$before' /var/lib/pendingchanges-watcher/status.json && ! grep -F '$after' /var/lib/pendingchanges-watcher/status.json && ! grep -F '[protected hmac-sha256:' /var/lib/pendingchanges-watcher/status.json"

"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
assert_status "not s['need_reload'] and not s['database_drift']"
sql "DROP TABLE \`$table\`; UPDATE admin SET value='true' WHERE variable='need_reload';"
assert_status "s['need_reload'] and '$table' in s['database_drift']"
"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
assert_status "not s['need_reload'] and not s['database_drift']"

trap - EXIT HUP INT TERM
echo 'Persisted-baseline and public-output redaction lifecycle passed'
