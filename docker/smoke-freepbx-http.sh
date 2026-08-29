#!/bin/sh
# Exercise FreePBX's real authenticated handlers in the disposable Docker lab.
# It must never be pointed at a production PBX.
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compose_file="$root_dir/docker/docker-compose.yml"
docker_cmd="docker compose -f $compose_file"

wait_clean() {
  attempts=0
  while [ "$attempts" -lt 30 ]; do
    status=$($docker_cmd exec -T custom-watcher python -c '
import json
s=json.load(open("/var/lib/pendingchanges-watcher/status.json"))
print(int(not s["need_reload"] and not s["database_drift"] and not s["file_drift"]))
')
    [ "$status" = 1 ] && return 0
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "watcher did not reach a clean baseline" >&2
  return 1
}

$docker_cmd exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null
wait_clean

"$root_dir/docker/seed-freepbx.sh"

reload_flag=$($docker_cmd exec -T database sh -lc 'mariadb -u asterisk -plocal-freepbx asterisk -N -e "SELECT value FROM admin WHERE variable='\''need_reload'\'';"')
[ "$reload_flag" = true ] || { echo "fixture requests did not set need_reload" >&2; exit 1; }

attempts=0
while [ "$attempts" -lt 30 ]; do
  pending=$($docker_cmd exec -T custom-watcher python -c '
import json
s=json.load(open("/var/lib/pendingchanges-watcher/status.json"))
print(int(s["need_reload"]))
')
  [ "$pending" = 1 ] && break
  attempts=$((attempts + 1))
  sleep 1
done
[ "$pending" = 1 ] || { echo "watcher did not observe pending reload" >&2; exit 1; }

$docker_cmd exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null
wait_clean
echo "authenticated FreePBX fixture lifecycle passed"
