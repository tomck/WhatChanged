#!/bin/sh
# Create, update, or remove one outbound route through FreePBX's authenticated
# handlers. The fixed name/patterns belong only to the disposable Docker lab.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}
ACTION=${FREEPBX_ROUTE_ACTION:-seed}
BASE_NAME='WhatChanged Lab Outbound Route'
UPDATED_NAME='WhatChanged Lab Outbound Route Updated'

case "$ACTION" in
  seed|update|cleanup) ;;
  *) echo "FREEPBX_ROUTE_ACTION must be seed, update, or cleanup" >&2; exit 2 ;;
esac
[ -r "$ENV_FILE" ] || { echo "Missing local lab credentials: $ENV_FILE" >&2; exit 2; }
case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing non-local FreePBX URL: $BASE_URL" >&2; exit 2 ;;
esac

set -a
. "$ENV_FILE"
set +a
COOKIE_JAR=$(mktemp)
ROUTE_PAGE=$(mktemp)
trap 'rm -f "$COOKIE_JAR" "$ROUTE_PAGE"' EXIT HUP INT TERM

curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
  -o /dev/null "$BASE_URL/admin/config.php"

refresh_routes() {
  curl -fsS -b "$COOKIE_JAR" -o "$ROUTE_PAGE" \
    "$BASE_URL/admin/config.php?display=routing"
}

# The route grid is server-rendered. Extract only ids from rows containing our
# exact fixture names, avoiding any database write or private API dependency.
fixture_ids() {
  awk -v base="$BASE_NAME" -v updated="$UPDATED_NAME" '
    BEGIN { RS="</tr>" }
    index($0, base) || index($0, updated) {
      if (match($0, /data-id="[0-9]+"/)) {
        value=substr($0, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", value)
        print value
      }
    }
  ' "$ROUTE_PAGE" | sort -u
}

route_sequence() {
  route_id=$1
  if [ -n "$route_id" ]; then
    form_url="$BASE_URL/admin/config.php?display=routing&view=form&id=$route_id"
  else
    form_url="$BASE_URL/admin/config.php?display=routing&view=form"
  fi
  curl -fsS -b "$COOKIE_JAR" "$form_url" |
    sed -n 's/.*id="route_seq" name="route_seq" value="\([0-9][0-9]*\)".*/\1/p' |
    head -1
}

delete_fixture_routes() {
  refresh_routes
  ids=$(fixture_ids)
  [ -z "$ids" ] && return 0
  for route_id in $ids; do
    curl -fsS -L -b "$COOKIE_JAR" \
      --referer "$BASE_URL/admin/config.php?display=routing" \
      --data-urlencode 'display=routing' \
      --data-urlencode 'action=delroute' \
      --data-urlencode "id=$route_id" \
      -o /dev/null "$BASE_URL/admin/config.php"
  done
}

post_route() {
  form_action=$1
  route_id=$2
  route_name=$3
  pattern=$4
  sequence=$(route_sequence "$route_id")
  [ -n "$sequence" ] || { echo "Could not read outbound-route sequence" >&2; exit 1; }

  if [ -n "$route_id" ]; then
    referer="$BASE_URL/admin/config.php?display=routing&view=form&id=$route_id"
  else
    referer="$BASE_URL/admin/config.php?display=routing&view=form"
  fi
  dialpatterns=$(printf '[{"prepend_digit":"","pattern_prefix":"","pattern_pass":"%s","match_cid":""}]' "$pattern")
  curl -fsS -L -b "$COOKIE_JAR" \
    --referer "$referer" \
    --data-urlencode 'display=routing' \
    --data-urlencode "action=$form_action" \
    --data-urlencode "id=$route_id" \
    --data-urlencode "extdisplay=$route_id" \
    --data-urlencode "route_seq=$sequence" \
    --data-urlencode "routename=$route_name" \
    --data-urlencode 'outcid=' \
    --data-urlencode 'outcid_mode=' \
    --data-urlencode 'routepass=' \
    --data-urlencode 'mohsilence=' \
    --data-urlencode 'time_group_id=' \
    --data-urlencode 'time_mode=' \
    --data-urlencode 'timezone=' \
    --data-urlencode 'calendar_id=' \
    --data-urlencode 'calendar_group_id=' \
    --data-urlencode 'notification_on=call' \
    --data-urlencode 'emailfrom=' \
    --data-urlencode 'emailto=' \
    --data-urlencode 'emailsubject=' \
    --data-urlencode 'emailbody=' \
    --data-urlencode 'goto0=' \
    --data-urlencode "dialpatterndata=$dialpatterns" \
    -o /dev/null "$BASE_URL/admin/config.php"
}

case "$ACTION" in
  cleanup)
    delete_fixture_routes
    echo 'Removed disposable outbound-route fixture'
    ;;
  seed)
    delete_fixture_routes
    post_route addroute '' "$BASE_NAME" 'X.'
    refresh_routes
    ids=$(fixture_ids)
    [ "$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || {
      echo "Outbound-route fixture creation was not uniquely observable" >&2; exit 1;
    }
    echo "Staged disposable outbound-route fixture $ids"
    ;;
  update)
    refresh_routes
    ids=$(fixture_ids)
    [ "$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || {
      echo "Expected exactly one outbound-route fixture" >&2; exit 1;
    }
    post_route editroute "$ids" "$UPDATED_NAME" '9X.'
    echo "Staged disposable outbound-route $ids name and dial-pattern update"
    ;;
esac
