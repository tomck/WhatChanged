#!/bin/sh
# Exercise the commercial Endpoint Manager extension-map storage contract in
# the disposable lab. The commercial module is not redistributed here; the
# fixture mirrors only the value-free schema boundary verified by read-only
# inspection of an installed commercial module. It includes the table identity,
# a readable configuration field, and the only observed secret-like column;
# the watcher still discovers and handles every column present at runtime.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
sql() { compose exec -T database mariadb -uroot -plocal-freepbx-root asterisk -e "$1"; }
observed_at() {
  compose exec -T custom-watcher python -c \
    'import json; print(json.load(open("/var/lib/pendingchanges-watcher/status.json"))["observed_at"])'
}
wait_for() {
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
cleanup() {
  sql "DROP TABLE IF EXISTS endpoint_extensions;
       UPDATE admin SET value='true' WHERE variable='need_reload';" >/dev/null 2>&1 || true
  "$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

wait_for "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
before=$(observed_at)
sql "DROP TABLE IF EXISTS endpoint_extensions;
     CREATE TABLE endpoint_extensions (
       ext VARCHAR(32) PRIMARY KEY,
       brand VARCHAR(64),
       model VARCHAR(64),
       configure_by VARCHAR(32),
       dpma_token_seq VARCHAR(128)
     );
     INSERT INTO endpoint_extensions
       (ext, brand, model, configure_by, dpma_token_seq)
       VALUES
         ('7999', 'fixture', 'fixture-phone', 'manual', 'private-before'),
         ('10048-1', 'fixture', 'old-phone', 'manual', 'private-removed');"
wait_for "s['observed_at'] > $before and not s['need_reload'] and 'endpoint_extensions' in json.load(open('/var/lib/pendingchanges-watcher/baseline.json')).get('scope', {}).get('readable_tables', [])"

before=$(observed_at)
sql "UPDATE endpoint_extensions
       SET configure_by='push', dpma_token_seq='private-after'
       WHERE ext='7999';
     DELETE FROM endpoint_extensions WHERE ext='10048-1';
     INSERT INTO endpoint_extensions
       (ext, brand, model, configure_by, dpma_token_seq)
       VALUES ('515-1', 'fixture', 'new-phone', 'manual', 'private-added');
     UPDATE admin SET value='true' WHERE variable='need_reload';"
wait_for "s['observed_at'] > $before and s['need_reload'] and any(u.get('identity',{}).get('ext') == '7999' and u.get('fields',{}).get('configure_by') == {'before':'manual','after':'push'} and u.get('fields',{}).get('dpma_token_seq') == {'before':'[redacted]','after':'[redacted]'} for u in s['database_drift'].get('endpoint_extensions',{}).get('updated',[])) and any(a.get('ext') == '515-1' and a.get('model') == 'new-phone' and a.get('dpma_token_seq') == '[redacted]' for a in s['database_drift'].get('endpoint_extensions',{}).get('added',[])) and any(r.get('ext') == '10048-1' and r.get('model') == 'old-phone' and r.get('dpma_token_seq') == '[redacted]' for r in s['database_drift'].get('endpoint_extensions',{}).get('removed',[]))"
compose exec -T custom-watcher sh -c \
  "! grep -F 'private-before' /var/lib/pendingchanges-watcher/status.json && ! grep -F 'private-after' /var/lib/pendingchanges-watcher/status.json && ! grep -F 'private-added' /var/lib/pendingchanges-watcher/status.json && ! grep -F 'private-removed' /var/lib/pendingchanges-watcher/status.json"

before=$(observed_at)
"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
wait_for "s['observed_at'] > $before and not s['need_reload'] and not s['database_drift']"

before=$(observed_at)
sql "DROP TABLE endpoint_extensions;
     UPDATE admin SET value='true' WHERE variable='need_reload';"
"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
wait_for "s['observed_at'] > $before and not s['need_reload'] and not s['database_drift']"

trap - EXIT HUP INT TERM
echo 'Endpoint Manager extension-map add/update/remove and redaction lifecycle passed'
