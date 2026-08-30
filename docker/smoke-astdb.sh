#!/bin/sh
# Verify a named, immediate FreePBX AstDB setting is reported independently of
# Apply Config. This runs only against the disposable Docker lab.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

assert_status() {
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
  compose exec -T custom-watcher python -c 'import json; print(json.dumps(json.load(open("/var/lib/pendingchanges-watcher/status.json")), indent=2))'
  return 1
}

# An always-unique fixture key means a previous normal baseline cannot contain
# it. It remains inside AMPUSER, one of the explicitly declared state families.
key="whatchanged_smoke_$(date +%s)"
cleanup() {
  compose exec -T pbx asterisk -rx "database del AMPUSER 7999/$key" >/dev/null 2>&1 || true
}
trap cleanup EXIT

assert_status "not s['need_reload'] and not s['database_drift'] and not s['file_drift'] and not s['astdb_drift']"
compose exec -T pbx asterisk -rx "database put AMPUSER 7999/$key recording-in" >/dev/null
assert_status "not s['need_reload'] and any(x.get('key') == '/AMPUSER/7999/$key' and x.get('value') == 'recording-in' for x in s['astdb_drift'].get('added', []))"

cleanup
trap - EXIT
assert_status "not s['need_reload'] and not s['database_drift'] and not s['file_drift'] and not s['astdb_drift']"
echo 'bounded immediate AstDB state lifecycle passed'
