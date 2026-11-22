#!/bin/sh
# Validate an authenticated extension recording-policy edit in Docker only.
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
  before=$(compose exec -T custom-watcher python -c \
    "import json;print(json.load(open('/var/lib/pendingchanges-watcher/status.json'))['observed_at'])")
  "$ROOT_DIR/docker/apply-freepbx.sh" >/dev/null
  wait_for "s['observed_at'] > $before and not s['need_reload'] and not s['database_drift'] and not s['astdb_drift'] and not s['file_drift']"
}

# The real extension handler needs an extension. Reuse only the disposable
# fixture set, apply it as the baseline, and remove it again after the test.
FREEPBX_FIXTURE_ACTION=cleanup "$ROOT_DIR/docker/seed-freepbx.sh" >/dev/null
apply_clean
"$ROOT_DIR/docker/seed-freepbx.sh" >/dev/null
apply_clean

current=$(compose exec -T pbx python3 -c \
  "import sqlite3; connection=sqlite3.connect('/var/lib/asterisk/astdb.sqlite3'); row=connection.execute(\"SELECT value FROM astdb WHERE key='/AMPUSER/7001/recording/in/external'\").fetchone(); print(row[0] if row else '')" \
  | tr -d '\r')
if [ "$current" = always ]; then
  target=never
else
  target=always
fi

FREEPBX_EXTENSION_UPDATE_MODE=recording FREEPBX_RECORDING_TARGET="$target" \
  python3 "$ROOT_DIR/docker/seed-extension-update.py" >/dev/null
wait_for "s['need_reload'] and any(u.get('key') == '/AMPUSER/7001/recording/in/external' and u.get('fields',{}).get('value',{}).get('after') == '$target' for u in s['astdb_drift'].get('updated',[]))"
compose exec -T custom-watcher python -c '
import json
status = json.load(open("/var/lib/pendingchanges-watcher/status.json"))
unexpected_tables = set(status["database_drift"]) - {"sip"}
assert not unexpected_tables, unexpected_tables
for kind in ("added", "removed", "updated"):
    for item in status["astdb_drift"].get(kind, []):
        assert item.get("key", "").startswith("/AMPUSER/7001/"), item
    for item in status["database_drift"].get("sip", {}).get(kind, []):
        key = str(item.get("key", ""))
        row_id = str(item.get("id", item.get("identity", {}).get("id", "")))
        assert key.startswith("7001|") or row_id == "7001", item
'
apply_clean

FREEPBX_FIXTURE_ACTION=cleanup "$ROOT_DIR/docker/seed-freepbx.sh" >/dev/null
apply_clean
echo 'Authenticated extension recording-policy lifecycle passed'
