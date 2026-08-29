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

# Remove dependent destinations before the extension. This is also exposed as
# a cleanup-only operation so a smoke test can establish an empty applied
# baseline before proving that the following creation requests are detected.
# Queues.class.php passes dynmembers through to queues_add(); submit the empty
# field explicitly so PHP 8 does not promote an undefined local into a 500.
curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=ringgroups" \
  --data-urlencode 'display=ringgroups' --data-urlencode 'action=delGRP' \
  --data-urlencode 'account=7002' -o /dev/null "$BASE_URL/admin/config.php" || true
curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=queues" \
  --data-urlencode 'display=queues' --data-urlencode 'action=delete' \
  --data-urlencode 'account=7003' -o /dev/null "$BASE_URL/admin/config.php" || true
curl -fsS -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=extensions" \
  --data-urlencode 'command=delete' --data-urlencode 'module=core' \
  --data-urlencode 'type=extensions' --data-urlencode 'extensions[]=7001' \
  -o /dev/null "$BASE_URL/admin/ajax.php" || true

if [ "${FREEPBX_FIXTURE_ACTION:-seed}" = cleanup ]; then
  echo "Removed disposable FreePBX fixtures."
  exit 0
fi
echo "Removed any prior fixture."

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
  --referer "$BASE_URL/admin/config.php?display=ringgroups&view=form" \
  --data-urlencode 'display=ringgroups' --data-urlencode 'view=form' \
  --data-urlencode 'action=addGRP' --data-urlencode 'account=7002' \
  --data-urlencode 'description=WhatChanged Lab Ring Group' \
  --data-urlencode 'strategy=ringallv2-prim' --data-urlencode 'grptime=20' \
  --data-urlencode 'grplist=7001' \
  --data-urlencode 'goto0=Extensions' \
  --data-urlencode 'Extensions0=from-did-direct,7001,1' \
  --data-urlencode 'submit=Submit' \
  -o /dev/null "$BASE_URL/admin/config.php"
echo "Created ring group fixture."

curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=queues&view=form" \
  --data-urlencode 'display=queues' --data-urlencode 'extdisplay=' \
  --data-urlencode 'action=add' --data-urlencode 'account=7003' \
  --data-urlencode 'name=WhatChanged Lab Queue' \
  --data-urlencode 'strategy=ringall' --data-urlencode 'members=7001' \
  --data-urlencode 'dynmembers=' \
  --data-urlencode 'maxlen=0' --data-urlencode 'joinempty=yes' \
  --data-urlencode 'leavewhenempty=no' --data-urlencode 'timeout=15' \
  --data-urlencode 'retry=5' --data-urlencode 'wrapuptime=0' \
  --data-urlencode 'announcefreq=0' --data-urlencode 'min-announce=15' \
  --data-urlencode 'announceholdtime=no' --data-urlencode 'announceposition=no' \
  --data-urlencode 'recording=dontcare' \
  --data-urlencode 'goto0=Extensions' \
  --data-urlencode 'Extensions0=from-did-direct,7001,1' \
  --data-urlencode 'submit=Submit' \
  -o /dev/null "$BASE_URL/admin/config.php"

echo "FreePBX disposable lab fixtures seeded: extension 7001, ring group 7002, queue 7003"
