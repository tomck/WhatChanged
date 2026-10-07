#!/bin/sh
# Apply the disposable FreePBX 17 lab configuration while handling only the
# short-lived GnuPG keyring race emitted by concurrent Module Admin work.
# Every other reload failure is reported immediately and fails the smoke gate.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE=${COMPOSE_FILE:-$ROOT_DIR/docker/docker-compose.yml}
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

output=$(mktemp "${TMPDIR:-/tmp}/what-changed-reload.XXXXXX")
trap 'rm -f "$output"' EXIT HUP INT TERM

attempt=1
while [ "$attempt" -le 3 ]; do
  if docker compose -f "$COMPOSE_FILE" exec -T pbx sh -lc \
      'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' \
      >"$output" 2>&1; then
    cat "$output"
    exit 0
  fi
  status=$?

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
    if docker compose -f "$COMPOSE_FILE" exec -T pbx \
        sh -c 'test ! -e /var/lib/asterisk/.gnupg/pubring.kbx.lock'; then
      break
    fi
    waited=$((waited + 1))
    sleep 1
  done
  sleep 1
  attempt=$((attempt + 1))
done
