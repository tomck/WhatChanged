#!/bin/sh
# The production service runs as asterisk. Mirror that in Docker while still
# making a fresh named volume writable before dropping privileges.
set -eu

state_dir=${STATE_DIR:-/var/lib/pendingchanges-watcher}
run_uid=${RUN_UID:-999}
run_gid=${RUN_GID:-999}
mkdir -p "$state_dir"
chown -R "$run_uid:$run_gid" "$state_dir"
exec su-exec "$run_uid:$run_gid" python /usr/local/bin/watcher.py
