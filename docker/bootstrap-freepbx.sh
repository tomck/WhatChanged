#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}

if [ ! -r "$ENV_FILE" ]; then
  echo "Missing local lab credentials: $ENV_FILE" >&2
  exit 1
fi

set -a
. "$ENV_FILE"
set +a

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT HUP INT TERM

INITIAL_PAGE=$(curl -fsS -c "$COOKIE_JAR" -b "$COOKIE_JAR" "$BASE_URL/admin/config.php")
if ! printf '%s' "$INITIAL_PAGE" | grep -q 'name=.action. value=.setup_admin.'; then
  echo "FreePBX initial setup is already complete."
  exit 0
fi

curl -fsS -o /dev/null -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  --data-urlencode 'action=setup_admin' \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password1=$FREEPBX_LAB_ADMIN_PASSWORD" \
  --data-urlencode "password2=$FREEPBX_LAB_ADMIN_PASSWORD" \
  --data-urlencode "email=$FREEPBX_LAB_ADMIN_EMAIL" \
  --data-urlencode 'system_ident=WhatChanged Docker Lab' \
  --data-urlencode 'auto_module_updates=disabled' \
  --data-urlencode 'auto_module_security_updates=emailonly' \
  --data-urlencode 'unsigned_module_emails=disabled' \
  --data-urlencode 'update_every=saturday' \
  --data-urlencode 'update_period=8to12' \
  "$BASE_URL/admin/config.php"

echo "FreePBX local lab administrator created."
