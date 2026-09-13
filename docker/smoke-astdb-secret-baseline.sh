#!/bin/sh
# Regress the protected-baseline comparison that previously made every
# unchanged AMPUSER password look like redacted-to-redacted drift forever.
# This script refuses non-local URLs and changes only one disposable AstDB key.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}
case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo 'Refusing to test AstDB outside the local Docker lab.' >&2; exit 2 ;;
esac

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

wait_status() {
  expression=$1
  attempts=0
  while [ "$attempts" -lt 60 ]; do
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

mark_pending() {
  compose exec -T database mariadb -u asterisk -plocal-freepbx asterisk -e \
    "UPDATE admin SET value='true' WHERE variable='need_reload'" >/dev/null
}

key=whatchanged_smoke_password
delete_fixture() {
  compose exec -T pbx asterisk -rx "database del AMPUSER 7999/$key" >/dev/null 2>&1 || true
}
trap delete_fixture EXIT HUP INT TERM

# Normalize an interrupted prior run before establishing this test's baseline.
delete_fixture
mark_pending
"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
wait_status "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"

compose exec -T pbx asterisk -rx \
  "database put AMPUSER 7999/$key disposable-secret" >/dev/null
wait_status "any(x.get('key') == '/AMPUSER/7999/$key' and x.get('value') == '[redacted]' for x in s['astdb_drift'].get('added', []))"

# Capture the protected value in a normal post-Apply baseline. The unchanged
# live value must compare cleanly against its keyed fingerprint.
mark_pending
"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
wait_status "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"

# Restore the original absence and establish a clean baseline for later tests.
delete_fixture
wait_status "any(x.get('key') == '/AMPUSER/7999/$key' for x in s['astdb_drift'].get('removed', []))"
mark_pending
"$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
wait_status "not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
trap - EXIT HUP INT TERM

echo 'protected AstDB baseline lifecycle passed'
