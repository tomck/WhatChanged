#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$root_dir/docker/legacy/docker-compose.yml"
target=${1:-16}
archive="$root_dir/dist/pendingchanges-$target.0.0.11.tgz"

case "$target" in
  16)
    pbx_service=fpbx16
    watcher_service=fpbx16-watcher
    ;;
  15)
    pbx_service=fpbx15
    watcher_service=fpbx15-watcher
    ;;
  14)
    pbx_service=fpbx14
    watcher_service=fpbx14-watcher
    ;;
  *)
    echo "FreePBX $target real-image smoke is not implemented yet" >&2
    exit 2
    ;;
esac

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"

wait_healthy() {
  local service=$1 container status
  container=$(docker compose -f "$compose_file" --profile "$target" ps -q "$service")
  if [[ -z "$container" ]]; then
    echo "No container exists for $service" >&2
    return 1
  fi
  for _ in $(seq 1 180); do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")
    case "$status" in
      healthy) return 0 ;;
      unhealthy|exited|dead)
        docker compose -f "$compose_file" --profile "$target" logs --tail=160 "$service" >&2
        return 1
        ;;
    esac
    sleep 5
  done
  docker compose -f "$compose_file" --profile "$target" logs --tail=160 "$service" >&2
  echo "Timed out waiting for $service" >&2
  return 1
}

test -f "$archive"
# Rebuild local wrappers and watcher changes, while preserving named volumes.
docker compose -f "$compose_file" --profile "$target" up -d --build "$watcher_service"
wait_healthy "$pbx_service"
# A PBX image/config recreation can invalidate the watcher container's old DNS
# endpoint without changing its own configuration. Recreate only the watcher
# after the PBX is healthy so every run starts with a current network binding.
docker compose -f "$compose_file" --profile "$target" up -d --force-recreate --no-deps "$watcher_service"
wait_healthy "$watcher_service"

if [[ "$target" == 16 ]]; then
  # The historical image ships the pm2 module tree but can leave it locally
  # available rather than installed. Current Framework 16 requires its BMO
  # during reload, so make that bundled dependency deterministic.
  docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" \
    sh -eu -c "
      if ! /var/lib/asterisk/bin/fwconsole ma list | grep -E 'pm2.*Enabled' >/dev/null; then
        /var/lib/asterisk/bin/fwconsole ma install pm2
      fi
      /var/lib/asterisk/bin/fwconsole ma list | grep -E 'pm2.*Enabled'
    "
fi

docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" sh -eu -c "
  rm -rf /var/www/html/admin/modules/pendingchanges
  tar -xzf /artifacts/pendingchanges-$target.0.0.11.tgz -C /var/www/html/admin/modules
  chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
  /var/lib/asterisk/bin/fwconsole ma install pendingchanges
  /var/lib/asterisk/bin/fwconsole ma list | grep -E 'pendingchanges.*$target\\.0\\.0\\.11.*Enabled'
"

docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" sh -eu -c '
  printf "FreePBX="
  /var/lib/asterisk/bin/fwconsole --version
  printf "Asterisk="
  asterisk -V
  printf "PHP="
  php -r "echo PHP_VERSION, PHP_EOL;"
' 

database_sql() {
  local statement=$1
  if [[ "$target" == 16 ]]; then
    docker compose -f "$compose_file" --profile "$target" exec -T fpbx16-database \
      mariadb -uasterisk -plegacy-freepbx asterisk -e "$statement"
  else
    docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" \
      mysql -uroot asterisk -e "$statement"
  fi
}

database_sql '
    CREATE TABLE IF NOT EXISTS pc_legacy_smoke (id INT NOT NULL PRIMARY KEY, label VARCHAR(64) NOT NULL);
    DELETE FROM pc_legacy_smoke;
    UPDATE admin SET value="false" WHERE variable="need_reload";
  '

# This is a disposable test-owned baseline, so explicitly recreate it around
# the empty fixture table to keep repeated executions deterministic. Stop the
# observer before deleting state so it cannot race by rewriting the baseline.
docker compose -f "$compose_file" --profile "$target" stop "$watcher_service" >/dev/null
if [[ "$target" == 16 ]]; then
  watcher_state=/data/var/lib/asterisk/pendingchanges-watcher
else
  watcher_state=/var/lib/asterisk/pendingchanges-watcher
fi
docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" \
  sh -eu -c "rm -f '$watcher_state/baseline.json' '$watcher_state/status.json' '$watcher_state/feedback.jsonl'"
baseline_started=$(date +%s)
docker compose -f "$compose_file" --profile "$target" start "$watcher_service" >/dev/null
wait_healthy "$watcher_service"

# Wait for a clean observation to establish the applied baseline.
for _ in $(seq 1 30); do
  clean=$(docker compose -f "$compose_file" --profile "$target" exec -T "$watcher_service" \
    python -c 'import json,sys; s=json.load(open("/var/lib/pendingchanges-watcher/status.json")); print(int(s["baseline_available"] and not s["need_reload"] and s["observed_at"] >= int(sys.argv[1])))' "$baseline_started")
  [[ "$clean" == 1 ]] && break
  sleep 2
done
[[ "${clean:-0}" == 1 ]]

staged_at=$(date +%s)
database_sql "
    INSERT INTO pc_legacy_smoke (id, label) VALUES (${target}01, 'FreePBX $target staged fixture');
    INSERT INTO admin (variable, value) VALUES ('need_reload', 'true')
      ON DUPLICATE KEY UPDATE value='true';
  "

for _ in $(seq 1 30); do
  detected=$(docker compose -f "$compose_file" --profile "$target" exec -T "$watcher_service" \
    python -c 'import json,sys; s=json.load(open("/var/lib/pendingchanges-watcher/status.json")); d=s["database_drift"].get("pc_legacy_smoke",{}); print(int(s["observed_at"] >= int(sys.argv[1]) and s["need_reload"] and len(d.get("added",[])) == 1))' "$staged_at")
  [[ "$detected" == 1 ]] && break
  sleep 2
done
[[ "${detected:-0}" == 1 ]]

# Prove the installed FreePBX BMO consumes the watcher result, rather than
# validating only the sidecar's private status document.
docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" php -r '
  include "/etc/freepbx.conf";
  $status = FreePBX::Pendingchanges()->status();
  $table = isset($status["database"]["pc_legacy_smoke"])
    ? $status["database"]["pc_legacy_smoke"]
    : array();
  $added = isset($table["added"]) ? $table["added"] : array();
  exit(!empty($status["watcher"]) && !empty($status["pending"]) && count($added) === 1 ? 0 : 1);
'

docker compose -f "$compose_file" --profile "$target" exec -T "$pbx_service" \
  /var/lib/asterisk/bin/fwconsole reload
reload_completed=$(date +%s)

for _ in $(seq 1 30); do
  clean=$(docker compose -f "$compose_file" --profile "$target" exec -T "$watcher_service" \
    python -c 'import json,sys; s=json.load(open("/var/lib/pendingchanges-watcher/status.json")); print(int(s["observed_at"] >= int(sys.argv[1]) and not s["need_reload"] and not s["database_drift"] and not s["astdb_drift"]))' "$reload_completed")
  [[ "$clean" == 1 ]] && break
  sleep 2
done
[[ "${clean:-0}" == 1 ]]

echo "FreePBX $target real-image module install and staged-drift lifecycle passed"
