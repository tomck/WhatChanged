#!/bin/sh
# Idempotently provision the disposable FreePBX lab through its authenticated
# HTTP handlers. Never point FREEPBX_LAB_URL at a production PBX.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}

[ -r "$ENV_FILE" ] || { echo "Missing local lab credentials: $ENV_FILE" >&2; exit 1; }
set -a
. "$ENV_FILE"
set +a

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT HUP INT TERM
login() {
  curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
  curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
    --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
    -o /dev/null "$BASE_URL/admin/config.php"
}

login
echo "Authenticated to the disposable lab."

# The Core quick-create handler is an AJAX endpoint. Delete first so a rerun
# has the same predictable fixture rather than creating a second extension.
curl -fsS -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=extensions" \
  --data-urlencode 'command=delete' --data-urlencode 'module=core' \
  --data-urlencode 'type=extensions' --data-urlencode 'extensions[]=7001' \
  -o /dev/null "$BASE_URL/admin/ajax.php" || true
echo "Removed any prior extension fixture."

extension_response=$(curl -fsS -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=extensions" \
  --data-urlencode 'tech=pjsip' --data-urlencode 'extension=7001' \
  --data-urlencode 'name=WhatChanged Lab Extension' \
  --data-urlencode 'outboundcid=' \
  --data-urlencode 'email=lab@example.invalid' \
  --data-urlencode 'vm=no' --data-urlencode 'vmpwd=' \
  "$BASE_URL/admin/ajax.php?module=core&command=quickcreate")
printf '%s' "$extension_response" | grep -q '"status":true' || {
  echo "Extension fixture creation failed" >&2; exit 1;
}
echo "Created extension fixture."

# Ring Group and Queue forms use standard authenticated POST handlers. Their
# surrounding tests will verify the resulting watcher observations.
curl -fsS -L -b "$COOKIE_JAR" \
  --data-urlencode 'display=ringgroups' --data-urlencode 'action=delGRP' \
  --data-urlencode 'account=7002' -o /dev/null "$BASE_URL/admin/config.php" || true
curl -fsS -L -b "$COOKIE_JAR" \
  --data-urlencode 'display=ringgroups' --data-urlencode 'view=form' \
  --data-urlencode 'action=addGRP' --data-urlencode 'account=7002' \
  --data-urlencode 'description=WhatChanged Lab Ring Group' \
  --data-urlencode 'strategy=ringallv2-prim' --data-urlencode 'grptime=20' \
  --data-urlencode 'grplist=7001' \
  -o /dev/null "$BASE_URL/admin/config.php"
echo "Created ring group fixture."

curl -fsS -L -b "$COOKIE_JAR" \
  --data-urlencode 'display=queues' --data-urlencode 'action=delete' \
  --data-urlencode 'account=7003' -o /dev/null "$BASE_URL/admin/config.php" || true
curl -fsS -L -b "$COOKIE_JAR" \
  --data-urlencode 'display=queues' --data-urlencode 'extdisplay=' \
  --data-urlencode 'action=add' --data-urlencode 'account=7003' \
  --data-urlencode 'descr=WhatChanged Lab Queue' \
  --data-urlencode 'strategy=ringall' --data-urlencode 'members=7001' \
  -o /dev/null "$BASE_URL/admin/config.php"

echo "FreePBX disposable lab fixtures seeded: extension 7001, ring group 7002, queue 7003"
