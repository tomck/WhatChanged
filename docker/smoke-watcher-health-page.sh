#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}

case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo 'Refusing to test watcher health outside the local Docker lab.' >&2; exit 2 ;;
esac
[ -r "$ENV_FILE" ] || { echo "Missing local lab credentials: $ENV_FILE" >&2; exit 2; }
set -a
. "$ENV_FILE"
set +a

COOKIE_JAR=$(mktemp)
PAGE_FILE=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$PAGE_FILE"' EXIT HUP INT TERM
curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
  -o /dev/null "$BASE_URL/admin/config.php"
curl -fsS -b "$COOKIE_JAR" -o "$PAGE_FILE" \
  "$BASE_URL/admin/config.php?display=pendingchanges"
grep -q 'Watcher health' "$PAGE_FILE"
grep -q '>Healthy<' "$PAGE_FILE"
grep -q 'Current full watcher snapshot' "$PAGE_FILE"
grep -q 'Loaded for this FreePBX web request' "$PAGE_FILE"
DOCTOR=$(docker compose -f "$ROOT_DIR/docker/docker-compose.yml" exec -T pbx \
  sh -lc 'su -s /bin/sh asterisk -c "php /var/www/html/admin/modules/pendingchanges/bin/pendingchanges doctor"')
echo "$DOCTOR" | grep -qx 'watcher_state=healthy'
echo "$DOCTOR" | grep -qx 'data_current=yes'
echo 'Authenticated FreePBX watcher-health page passed'
