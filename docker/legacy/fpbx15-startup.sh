#!/bin/bash
set -e

rm -f /what-changed-ready
/upstream-startup.sh &
upstream_pid=$!
watcher_user_ready=false

# MariaDB listens only on the private Compose network because no host port is
# published. Create the watcher credential locally and remove any root@%
# account left by an earlier iteration of this disposable fixture.
for _ in $(seq 1 120); do
  if mysqladmin ping --silent >/dev/null 2>&1; then
    mysql -uroot <<'SQL'
GRANT SELECT ON `asterisk`.* TO 'what_changed'@'%' IDENTIFIED BY 'legacy-watcher-only';
FLUSH PRIVILEGES;
SQL
    remote_root=$(mysql -N -uroot -e "SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host='%'" 2>/dev/null || true)
    if [[ "$remote_root" == 1 ]]; then
      mysql -uroot -e "DROP USER 'root'@'%'; FLUSH PRIVILEGES;"
    fi
    watcher_user_ready=true
    break
  fi
  if ! kill -0 "$upstream_pid" 2>/dev/null; then
    wait "$upstream_pid"
    exit $?
  fi
  sleep 1
done

if [[ "$watcher_user_ready" != true ]]; then
  echo "Timed out creating the read-only WhatChanged database user" >&2
  kill "$upstream_pid" 2>/dev/null || true
  wait "$upstream_pid" || true
  exit 1
fi

# The upstream image starts Apache and fwconsole before performing its initial
# restore. Those early services are not a usable Module Admin readiness signal:
# Core is temporarily reset during the restore. `/init` is created only after
# that work finishes, so require both it and a live Core BMO before advertising
# this disposable fixture as healthy.
freepbx_ready=false
for _ in $(seq 1 600); do
  if [[ -f /init ]] && php -r 'include "/etc/freepbx.conf"; FreePBX::Core();' >/dev/null 2>&1; then
    touch /what-changed-ready
    freepbx_ready=true
    break
  fi
  if ! kill -0 "$upstream_pid" 2>/dev/null; then
    wait "$upstream_pid"
    exit $?
  fi
  sleep 1
done

if [[ "$freepbx_ready" != true ]]; then
  echo "Timed out waiting for the FreePBX Core BMO after initial restore" >&2
  kill "$upstream_pid" 2>/dev/null || true
  wait "$upstream_pid" || true
  exit 1
fi

wait "$upstream_pid"
