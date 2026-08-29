#!/bin/sh
# Stage one reversible Advanced Settings value through FreePBX's real handler.
# Docker lab only; this deliberately never clicks Apply Config.
set -eu

target=${1:?usage: seed-advanced-breaker.sh ringtimer-seconds}
case "$target" in
  ''|*[!0-9]*) exit 2 ;;
esac

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

# `RINGTIMER` is a deliberately non-secret, visible setting.  Its handler
# processes only submitted recognized keywords, so this minimal POST cannot
# overwrite unrelated Advanced Settings.
curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=advancedsettings" \
  --data-urlencode 'display=advancedsettings' \
  --data-urlencode "RINGTIMER=$target" \
  -o /dev/null "$BASE_URL/admin/config.php"

echo "Staged disposable Advanced Settings RINGTIMER=$target"
