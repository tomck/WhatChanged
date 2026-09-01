#!/bin/sh
# Apply the disposable lab through the same authenticated AJAX request as the
# FreePBX button. Never point FREEPBX_LAB_URL at a production PBX.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}
case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing non-local FreePBX URL: $BASE_URL" >&2; exit 2 ;;
esac
[ -r "$ENV_FILE" ] || { echo "Missing local lab credentials: $ENV_FILE" >&2; exit 1; }
set -a
. "$ENV_FILE"
set +a

COOKIE_JAR=$(mktemp)
RESPONSE=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$RESPONSE"' EXIT HUP INT TERM
curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
  -o /dev/null "$BASE_URL/admin/config.php"
curl -fsS --max-time 1800 -b "$COOKIE_JAR" -X POST \
  --referer "$BASE_URL/admin/config.php" \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H 'Accept: application/json' \
  -o "$RESPONSE" "$BASE_URL/admin/ajax.php?command=reload"
python3 - "$RESPONSE" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
if not payload.get('status'):
    raise SystemExit('FreePBX Apply Config failed: {}'.format(payload.get('message', payload)))
PY
echo "Authenticated disposable-lab Apply Config completed"
