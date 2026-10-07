#!/bin/sh
# Apply the disposable FreePBX 17 lab configuration while handling only the
# short-lived GnuPG keyring race emitted by concurrent Module Admin work.
# Every other reload failure is reported immediately and fails the smoke gate.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE=${COMPOSE_FILE:-$ROOT_DIR/docker/docker-compose.yml}
COMPOSE_PROFILE=${COMPOSE_PROFILE:-}
PBX_SERVICE=${PBX_SERVICE:-pbx}
FWCONSOLE_RUN_AS=${FWCONSOLE_RUN_AS:-asterisk}
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

case "$FWCONSOLE_RUN_AS" in
  asterisk|root) ;;
  *)
    echo "Unsupported fwconsole reload account: $FWCONSOLE_RUN_AS" >&2
    exit 64
    ;;
esac

compose() {
  if [ -n "$COMPOSE_PROFILE" ]; then
    docker compose -f "$COMPOSE_FILE" --profile "$COMPOSE_PROFILE" "$@"
  else
    docker compose -f "$COMPOSE_FILE" "$@"
  fi
}

output=$(mktemp "${TMPDIR:-/tmp}/what-changed-reload.XXXXXX")
trap 'rm -f "$output"' EXIT HUP INT TERM

attempt=1
while [ "$attempt" -le 3 ]; do
  if [ "$FWCONSOLE_RUN_AS" = root ]; then
    reload_command='/var/lib/asterisk/bin/fwconsole reload'
  else
    reload_command='su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"'
  fi
  if compose exec -T "$PBX_SERVICE" sh -lc "$reload_command" >"$output" 2>&1; then
    cat "$output"
    exit 0
  else
    status=$?
  fi

  if ! grep -Eq 'pubring\.kbx\.lock|stat\(\): stat failed for .*\.gnupg/.*\.lock' "$output"; then
    cat "$output" >&2
    exit "$status"
  fi
  if [ "$attempt" -eq 3 ]; then
    echo 'FreePBX reload remained blocked by its GnuPG keyring after three bounded attempts.' >&2
    cat "$output" >&2
    exit "$status"
  fi

  echo "FreePBX GnuPG keyring is briefly busy; waiting before bounded reload retry $((attempt + 1))/3." >&2
  waited=0
  while [ "$waited" -lt 10 ]; do
    if compose exec -T "$PBX_SERVICE" \
        sh -c 'test ! -e /var/lib/asterisk/.gnupg/pubring.kbx.lock'; then
      break
    fi
    waited=$((waited + 1))
    sleep 1
  done
  sleep 1
  attempt=$((attempt + 1))
done
