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

wait_pending() {
  attempts=0
  while [ "$attempts" -lt 30 ]; do
    pending=$($docker_cmd exec -T custom-watcher python -c '
import json
s=json.load(open("/var/lib/pendingchanges-watcher/status.json"))
print(int(s["need_reload"]))
')
    [ "$pending" = 1 ] && return 0
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "watcher did not observe a pending reload" >&2
  return 1
}

# `need_reload` can become visible one polling cycle before every table in a
# multi-request fixture has been collected. Wait for the evidence itself, not
# merely the banner, so the release gate is deterministic on a busy lab host.
wait_fixture_evidence() {
  direction=$1
  attempts=0
  while [ "$attempts" -lt 45 ]; do
    if $docker_cmd exec -T custom-watcher python -c "
import json
s = json.load(open('/var/lib/pendingchanges-watcher/status.json'))
required = {'users', 'devices', 'sip', 'ringgroups', 'queues_config'}
if '$direction' == 'added':
    missing = required - set(s['database_drift'])
else:
    missing = {table for table in required if not s['database_drift'].get(table, {}).get('removed')}
assert not missing
" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "watcher did not collect all fixture $direction evidence" >&2
  return 1
}

# A rerun must not compare the seed against the same fixtures from a previous
# pass. Remove only the three lab-owned objects, apply that clean state, then
# use it as the baseline for the real authenticated creation flow.
FREEPBX_FIXTURE_ACTION=cleanup "$root_dir/docker/seed-freepbx.sh"
wait_pending
# `fwconsole reload` can complete a few seconds after returning in this lab.
# Waiting first for the removal to be observed prevents a stale clean status
# from being mistaken for the new post-reload baseline.
$docker_cmd exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null
sleep 8
wait_clean

"$root_dir/docker/seed-freepbx.sh"

reload_flag=$($docker_cmd exec -T database sh -lc 'mariadb -u asterisk -plocal-freepbx asterisk -N -e "SELECT value FROM admin WHERE variable='\''need_reload'\'';"')
[ "$reload_flag" = true ] || { echo "fixture requests did not set need_reload" >&2; exit 1; }

wait_pending
wait_fixture_evidence added

# These names come from the live, authenticated fixtures above. A failure here
# means the watcher observed a banner but did not explain a representative
# endpoint/ring-group/queue change.
$docker_cmd exec -T custom-watcher python -c '
import json
s = json.load(open("/var/lib/pendingchanges-watcher/status.json"))
required = {"users", "devices", "sip", "ringgroups", "queues_config"}
actual = set(s["database_drift"])
missing = sorted(required - actual)
assert not missing, f"fixture drift missing tables: {missing}; observed: {sorted(actual)}"
'

$docker_cmd exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null
wait_clean

# Deletion is the security-sensitive half of the lifecycle: a dismissed
# employee can remove working endpoints/destinations and leave the next admin
# to Apply Config.  Starting from the just-applied fixture baseline proves the
# watcher calls those records removals rather than merely noticing a reload.
FREEPBX_FIXTURE_ACTION=cleanup "$root_dir/docker/seed-freepbx.sh"
wait_pending
wait_fixture_evidence removed
$docker_cmd exec -T custom-watcher python -c '
import json
s = json.load(open("/var/lib/pendingchanges-watcher/status.json"))
required = {"users", "devices", "sip", "ringgroups", "queues_config"}
missing = sorted(
    table for table in required
    if not s["database_drift"].get(table, {}).get("removed")
)
assert not missing, f"fixture deletion drift missing removals: {missing}; observed: {s['"'"'database_drift'"'"']}"
'
$docker_cmd exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null || true
sleep 8
wait_clean
echo "authenticated FreePBX fixture create/delete lifecycle passed"
