#!/bin/sh
# Stage a visible Ring Group edit through FreePBX's authenticated form handler.
# The smoke suite owns group 7002; no production target is permitted.
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

# `edtGRP` is the module's real update action. Preserve membership and
# destination while changing only the descriptive evidence field.
curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=ringgroups&view=form&extdisplay=GRP-7002" \
  --data-urlencode 'display=ringgroups' --data-urlencode 'view=form' \
  --data-urlencode 'action=edtGRP' --data-urlencode 'account=7002' \
  --data-urlencode 'description=WhatChanged Lab Ring Group Updated' \
  --data-urlencode 'strategy=ringallv2-prim' --data-urlencode 'grptime=20' \
  --data-urlencode 'grplist=7001' --data-urlencode 'goto0=Extensions' \
  --data-urlencode 'Extensions0=from-did-direct,7001,1' \
  --data-urlencode 'submit=Submit' \
  -o /dev/null "$BASE_URL/admin/config.php"

echo 'Staged disposable Ring Group 7002 description update'
