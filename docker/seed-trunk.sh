#!/bin/sh
# Create, edit, or remove a harmless Custom trunk using FreePBX's real,
# authenticated form handler.  It is for the disposable Docker lab only:
# no route references it and its Dial string intentionally cannot reach a
# carrier.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}
ACTION=${FREEPBX_TRUNK_ACTION:-seed}
BASE_NAME='WhatChanged Lab Custom Trunk'
UPDATED_NAME='WhatChanged Lab Custom Trunk Updated'
TARGET_NAME=${FREEPBX_TRUNK_TARGET_NAME:-$UPDATED_NAME}

case "$ACTION" in seed|update|cleanup) ;; *) exit 2 ;; esac
[ -r "$ENV_FILE" ] || exit 2
case "$BASE_URL" in http://127.0.0.1:*|http://localhost:*) ;; *) exit 2 ;; esac
set -a; . "$ENV_FILE"; set +a

COOKIE_JAR=$(mktemp)
TRUNK_PAGE=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$TRUNK_PAGE"' EXIT HUP INT TERM
curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
  -o /dev/null "$BASE_URL/admin/config.php"

refresh() { curl -fsS -b "$COOKIE_JAR" -o "$TRUNK_PAGE" "$BASE_URL/admin/config.php?display=trunks"; }
ids() {
  awk -v base="$BASE_NAME" -v updated="$UPDATED_NAME" '
    BEGIN { RS="</tr>" }
    # FreePBX normalizes spaces in a trunk name to underscores on save.
    index($0, base) || index($0, updated) ||
    index($0, "WhatChanged_Lab_Custom_Trunk") {
      if (match($0, /OUT_[0-9]+/)) { v=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",v); print v }
    }' "$TRUNK_PAGE" | sort -u
}
remove() {
  refresh; found=$(ids)
  for id in $found; do
    curl -fsS -L -b "$COOKIE_JAR" --referer "$BASE_URL/admin/config.php?display=trunks&extdisplay=OUT_$id" \
      --data-urlencode 'display=trunks' --data-urlencode 'action=deltrunk' \
      --data-urlencode "extdisplay=OUT_$id" -o /dev/null "$BASE_URL/admin/config.php"
  done
}
post() {
  action=$1; id=$2; name=$3; dial=$4
  curl -fsS -L -b "$COOKIE_JAR" --referer "$BASE_URL/admin/config.php?display=trunks&tech=custom" \
    --data-urlencode 'display=trunks' --data-urlencode "action=$action" \
    --data-urlencode 'tech=custom' --data-urlencode "extdisplay=$id" \
    --data-urlencode "trunk_name=$name" --data-urlencode "channelid=$dial" \
    --data-urlencode 'usercontext=notneeded' --data-urlencode 'outcid=' \
    --data-urlencode 'maxchans=1' --data-urlencode 'dialoutprefix=' \
    --data-urlencode 'keepcid=off' --data-urlencode 'disabletrunk=on' \
    --data-urlencode 'continue=off' --data-urlencode 'dialopts=' \
    --data-urlencode 'bulk_patterns=' -o /dev/null "$BASE_URL/admin/config.php"
}

case "$ACTION" in
  cleanup) remove; echo 'Removed disposable custom-trunk fixture' ;;
  seed)
    remove
    # Invalid by design as a dial target; the disabled trunk is never routed.
    post addtrunk '' "$BASE_NAME" 'Local/invalid@from-internal/$OUTNUM$'
    refresh; found=$(ids); [ "$(printf '%s\n' "$found" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || exit 1
    echo "Staged disposable custom trunk $found"
    ;;
  update)
    refresh; found=$(ids); [ "$(printf '%s\n' "$found" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || exit 1
    # Keep the composite trunk identity intact: changing a Custom dial string
    # changes the Core table's natural key and is therefore correctly shown as
    # remove/add.  This fixture is specifically the editable-name path.
    post edittrunk "OUT_$found" "$TARGET_NAME" 'Local/invalid@from-internal/$OUTNUM$'
    echo "Staged disposable custom trunk $found update"
    ;;
esac
