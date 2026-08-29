#!/bin/sh
# Stage a visible Queue edit through FreePBX's authenticated form handler.
# The disposable fixture owns queue 7003; this script never applies changes.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}
[ -r "$ENV_FILE" ] || exit 2
set -a
. "$ENV_FILE"
set +a

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT HUP INT TERM
curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
  -o /dev/null "$BASE_URL/admin/config.php"

# Queues' `edit` path deletes and re-adds the configuration. Supply the same
# non-secret fields as the creation fixture, changing only the visible name.
curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=queues&view=form&extdisplay=7003" \
  --data-urlencode 'display=queues' --data-urlencode 'view=form' \
  --data-urlencode 'action=edit' --data-urlencode 'account=7003' \
  --data-urlencode 'name=WhatChanged Lab Queue Updated' \
  --data-urlencode 'strategy=ringall' --data-urlencode 'members=7001' --data-urlencode 'dynmembers=' \
  --data-urlencode 'maxlen=0' --data-urlencode 'joinempty=yes' --data-urlencode 'leavewhenempty=no' \
  --data-urlencode 'timeout=15' --data-urlencode 'retry=5' --data-urlencode 'wrapuptime=0' \
  --data-urlencode 'announcefreq=0' --data-urlencode 'min-announce=15' \
  --data-urlencode 'announceholdtime=no' --data-urlencode 'announceposition=no' \
  --data-urlencode 'recording=dontcare' --data-urlencode 'goto0=Extensions' \
  --data-urlencode 'Extensions0=from-did-direct,7001,1' --data-urlencode 'submit=Submit' \
  -o /dev/null "$BASE_URL/admin/config.php"

echo 'Staged disposable Queue 7003 name update'
