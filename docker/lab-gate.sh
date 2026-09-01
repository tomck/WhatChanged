#!/bin/sh
# Run the complete disposable-lab release gate.  Every child script refuses a
# non-local URL and cleans up only its own fixture records.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

# Profile-only services are not rebuilt by `up --build` unless their profile
# is active. Build the smoke driver explicitly so the gate always tests the
# checked-out assertions instead of a stale local image.
docker compose -f "$COMPOSE_FILE" build pbx custom-watcher smoke
docker compose -f "$COMPOSE_FILE" up -d
docker compose -f "$COMPOSE_FILE" exec -T custom-watcher python /usr/local/bin/test_watcher.py
docker compose -f "$COMPOSE_FILE" exec -T pbx sh -lc \
  'php /srv/pendingchanges/docker/test-request-audit.php /tmp/what-changed-request-audit-test.jsonl && rm -f /tmp/what-changed-request-audit-test.jsonl'
docker compose -f "$COMPOSE_FILE" run --rm smoke
"$ROOT_DIR/docker/smoke-freepbx-http.sh"
"$ROOT_DIR/docker/smoke-breakers.sh"
"$ROOT_DIR/docker/smoke-astdb.sh"
"$ROOT_DIR/docker/smoke-module-state.sh"
"$ROOT_DIR/docker/smoke-userman-setting.sh"
"$ROOT_DIR/docker/smoke-fax-settings.sh"
"$ROOT_DIR/docker/smoke-outbound-route.sh"
"$ROOT_DIR/docker/smoke-trunk.sh"

docker compose -f "$COMPOSE_FILE" exec -T custom-watcher python -c '
import json
status = json.load(open("/var/lib/pendingchanges-watcher/status.json"))
assert not status["need_reload"] and not status["database_drift"] and not status["astdb_drift"] and not status["file_drift"]
print("WhatChanged Docker release gate passed")
'
