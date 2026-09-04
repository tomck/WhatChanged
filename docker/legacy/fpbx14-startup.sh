#!/bin/bash
set -e

# The upstream image binds its embedded MariaDB only to loopback. Expose it
# solely on the private Compose network so the read-only watcher sidecar can
# connect; docker-compose.yml publishes no database port to the host.
sed -i 's/^[[:space:]]*bind-address[[:space:]]*=.*/bind-address = 0.0.0.0/' /etc/mysql/my.cnf

/run/upstream-startup.sh &
upstream_pid=$!
watcher_user_ready=false

for _ in $(seq 1 120); do
  if mysqladmin ping --silent >/dev/null 2>&1; then
    mysql -uroot <<'SQL'
GRANT SELECT ON `asterisk`.* TO 'what_changed'@'%' IDENTIFIED BY 'legacy-watcher-only';
FLUSH PRIVILEGES;
SQL
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

wait "$upstream_pid"
