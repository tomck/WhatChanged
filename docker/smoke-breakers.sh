#!/bin/sh
# Verify two high-impact configuration paths through real authenticated
# FreePBX forms. The test stages each change, checks readable watcher evidence,
# applies it, then restores the original lab value and applies again.
set -eu

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compose_file="$root_dir/docker/docker-compose.yml"
docker_cmd="docker compose -f $compose_file"

wait_status() {
  expected=$1
  after_observed=${2:-0}
  attempts=0
  while [ "$attempts" -lt 45 ]; do
    actual=$($docker_cmd exec -T custom-watcher python -c "
import json
s=json.load(open('/var/lib/pendingchanges-watcher/status.json'))
state = 'clean' if not s['need_reload'] and not s['database_drift'] and not s['file_drift'] else 'pending'
print('$expected' == state and s['observed_at'] > int('$after_observed'))")
    [ "$actual" = True ] && return 0
    attempts=$((attempts + 1))
    sleep 1
  done
  echo "watcher did not reach $expected state" >&2
  return 1
}

observed_at() {
  $docker_cmd exec -T custom-watcher python -c "import json; print(json.load(open('/var/lib/pendingchanges-watcher/status.json'))['observed_at'])"
}

apply_config() {
  before=$(observed_at)
  # Some lab reloads return from fwconsole before its AMI work has completed.
  # The watcher assertion below, rather than that transient exit status, is
  # the authoritative test outcome.
  $docker_cmd exec -T pbx sh -lc 'su -s /bin/sh asterisk -c "/var/lib/asterisk/bin/fwconsole reload"' >/dev/null || true
  # FreePBX/Asterisk finalizes the reload asynchronously in this lab.
  sleep 8
  wait_status clean "$before"
}

setting_value() {
  $docker_cmd exec -T database sh -lc "mariadb -u asterisk -plocal-freepbx asterisk -N -e \"SELECT value FROM freepbx_settings WHERE keyword='RINGTIMER';\""
}

sip_value() {
  $docker_cmd exec -T database sh -lc "mariadb -u asterisk -plocal-freepbx asterisk -N -e \"SELECT val FROM kvstore_Sipsettings WHERE \\\`key\\\`='allow.reload';\""
}

assert_keys() {
  expected=$1
  $docker_cmd exec -T custom-watcher python -c "
import json
s=json.load(open('/var/lib/pendingchanges-watcher/status.json'))
updates=s['database_drift'].get('$expected', {}).get('updated', [])
assert updates, s['database_drift']
print('watcher evidence:', updates)
"
}

# Normalize a baseline before calculating reversible target values.
apply_config

original_sip=$(sip_value)
if [ -z "$original_sip" ]; then
  # A genuinely fresh FreePBX database does not materialize this SIP Settings
  # row until the form is first submitted. Establish its documented default as
  # applied state before testing a reversible update.
  before=$(observed_at)
  "$root_dir/docker/seed-sip-breaker.sh" yes
  wait_status pending "$before"
  apply_config
  original_sip=$(sip_value)
fi
case "$original_sip" in yes) staged_sip=no ;; no) staged_sip=yes ;; *) echo "unexpected allow.reload value: $original_sip" >&2; exit 1 ;; esac
before=$(observed_at)
"$root_dir/docker/seed-sip-breaker.sh" "$staged_sip"
wait_status pending "$before"
assert_keys kvstore_Sipsettings
$docker_cmd exec -T custom-watcher python -c '
import json
s=json.load(open("/var/lib/pendingchanges-watcher/status.json"))
keys={item["key"] for item in s["database_drift"]["kvstore_Sipsettings"]["updated"]}
assert keys == {"allow.reload", "pjsip_allow_reload"}, keys
'
apply_config
before=$(observed_at)
"$root_dir/docker/seed-sip-breaker.sh" "$original_sip"
wait_status pending "$before"
apply_config

original_ring=$(setting_value)
case "$original_ring" in 15) staged_ring=16 ;; *) staged_ring=15 ;; esac
before=$(observed_at)
"$root_dir/docker/seed-advanced-breaker.sh" "$staged_ring"
wait_status pending "$before"
assert_keys freepbx_settings
$docker_cmd exec -T custom-watcher python -c "
import json
s=json.load(open('/var/lib/pendingchanges-watcher/status.json'))
u=s['database_drift']['freepbx_settings']['updated']
ring=[item for item in u if item['key'] == 'RINGTIMER']
assert len(ring) == 1, u
change=ring[0]['fields']['value']
assert change == {'before': '$original_ring', 'after': '$staged_ring'}, change
"
apply_config
before=$(observed_at)
"$root_dir/docker/seed-advanced-breaker.sh" "$original_ring"
wait_status pending "$before"
apply_config

echo "SIP and Advanced Settings breaker smoke lifecycle passed"
