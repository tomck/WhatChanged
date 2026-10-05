#!/bin/sh
# Verify MariaDB's deliberately ambiguous table-visibility behavior through a
# watcher account with the same per-table privilege shape used in production.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

fixture_user=what_changed_limited_fixture
cleanup() {
  compose exec -T database mariadb -uroot -plocal-freepbx-root -e \
    "DROP USER IF EXISTS '$fixture_user'@'%'; FLUSH PRIVILEGES;" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

devices_count=$(compose exec -T database mariadb -uroot -plocal-freepbx-root \
  --batch --skip-column-names -e \
  "SELECT COUNT(*) FROM information_schema.TABLES
   WHERE TABLE_SCHEMA='asterisk' AND TABLE_NAME='devices'")
if [ "$devices_count" != 1 ]; then
  echo 'Limited-account smoke requires the existing asterisk.devices table.' >&2
  exit 1
fi

compose exec -T database mariadb -uroot -plocal-freepbx-root asterisk -e \
  "DROP USER IF EXISTS '$fixture_user'@'%';
   CREATE USER '$fixture_user'@'%' IDENTIFIED BY 'disposable-limited-account';
   GRANT SELECT ON \`asterisk\`.\`admin\` TO '$fixture_user'@'%';
   GRANT SELECT ON \`asterisk\`.\`users\` TO '$fixture_user'@'%';
   FLUSH PRIVILEGES;"

compose run --rm --no-deps -T \
  --entrypoint python \
  -e DB_USER="$fixture_user" \
  -e DB_PASSWORD=disposable-limited-account \
  -e WATCH_TABLES=users,devices,whatchanged_absent_fixture \
  -v "$ROOT_DIR/docker/custom-watcher/watcher.py:/tmp/watcher.py:ro" \
  custom-watcher -c '
import importlib.util

spec = importlib.util.spec_from_file_location("limited_watcher", "/tmp/watcher.py")
watcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watcher)
snapshot = watcher.database_snapshot()
assert set(snapshot["readable_tables"]) == {"users"}
assert set(snapshot["ambiguous_tables"]) == {"devices", "whatchanged_absent_fixture"}
limitations = watcher.table_visibility_limitations(
    snapshot["ambiguous_tables"], {"devices"})
assert limitations[0]["reason"] == "table_visibility_regressed"
assert limitations[0]["tables"] == ["devices"]
assert limitations[1]["reason"] == "optional_table_visibility_unknown"
assert limitations[1]["tables"] == ["whatchanged_absent_fixture"]
'

cleanup
fixture_count=$(compose exec -T database mariadb -uroot -plocal-freepbx-root \
  --batch --skip-column-names -e \
  "SELECT COUNT(*) FROM mysql.user WHERE User='$fixture_user' AND Host='%'")
if [ "$fixture_count" != 0 ]; then
  echo 'Limited-account smoke left its disposable MariaDB account behind.' >&2
  exit 1
fi
trap - EXIT HUP INT TERM
echo 'Limited watcher account reports absent and ungranted tables without false certainty'
