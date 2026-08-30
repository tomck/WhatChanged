#!/bin/sh
# The production service runs as asterisk. Mirror that in Docker while still
# making a fresh named volume writable before dropping privileges.
set -eu

state_dir=${STATE_DIR:-/var/lib/pendingchanges-watcher}
mkdir -p "$state_dir"
chown -R 999:999 "$state_dir"
exec su-exec 999:999 python /usr/local/bin/watcher.py
