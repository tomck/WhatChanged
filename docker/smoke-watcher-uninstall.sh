#!/usr/bin/env bash
# Prove that the documented embedded uninstaller cannot strand Apache or
# nginx/PHP-FPM with a dangling auto_prepend_file, then restore the watcher so
# the disposable lab finishes in its normal operational state.
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file=${WHAT_CHANGED_COMPOSE_FILE:-$root_dir/docker/docker-compose.yml}
installer_override=${WHAT_CHANGED_INSTALLER_COMPOSE_OVERRIDE:-$root_dir/docker/docker-compose-installer.override.yml}
pbx_service=${WHAT_CHANGED_PBX_SERVICE:-pbx}
lab_url=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}

case "$lab_url" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo 'Refusing to exercise watcher uninstall outside the local Docker lab.' >&2; exit 2 ;;
esac

compose() {
  docker compose -f "$compose_file" "$@"
}

installer_compose() {
  docker compose -f "$compose_file" -f "$installer_override" "$@"
}

restore_lab() {
  # Return ownership of watcher state to the normal sidecar architecture even
  # when an assertion in the embedded lifecycle fails.
  compose up -d --force-recreate "$pbx_service" custom-watcher >/dev/null 2>&1 || true
}
trap restore_lab EXIT HUP INT TERM

compose stop custom-watcher >/dev/null
installer_compose up -d --force-recreate "$pbx_service" >/dev/null
for _attempt in $(seq 1 60); do
  if installer_compose exec -T "$pbx_service" sh -c \
      'test -f /var/www/html/.what-changed-entrypoint-ready && php /var/lib/asterisk/bin/fwconsole --version >/dev/null' \
      >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
installer_compose exec -T "$pbx_service" sh -c \
  'test -f /var/www/html/.what-changed-entrypoint-ready && php /var/lib/asterisk/bin/fwconsole --version >/dev/null'

installer_compose exec -T "$pbx_service" sh -eu -c '
  module=/var/www/html/admin/modules/pendingchanges
  test -x "$module/bin/uninstall-watcher"
  test -r "$module/watcher/web-sensor-lifecycle.sh"
  # The disposable PBX entrypoint deliberately does not run systemd as PID 1.
  # Record the exact service-manager requests here; the package gate validates
  # the real unit file and production hosts exercise actual systemd.
  install -d -m 0755 /tmp/what-changed-smoke-bin
  printf "%s\n" \
    "#!/bin/sh" \
    "[ \"\${1:-}\" != is-active ] || exit 1" \
    "printf '\''%s\\n'\'' \"\$*\" >>/tmp/what-changed-systemctl.log" \
    "exit 0" \
    >/tmp/what-changed-smoke-bin/systemctl
  chmod 0755 /tmp/what-changed-smoke-bin/systemctl
  : >/tmp/what-changed-systemctl.log
  PATH=/tmp/what-changed-smoke-bin:$PATH
  export PATH
  # Dependency-consent and refusal are covered by smoke-embedded-watcher.sh.
  # This lifecycle specifically needs a working installed watcher, so provide
  # the dependency inside the disposable image without changing the host.
  if ! python3 -c "import pymysql" >/dev/null 2>&1; then
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pymysql >/dev/null
  fi
  # The regular lab sidecar uses the same reviewed disposable DB account. Seed
  # an explicit environment so the embedded service can be exercised without
  # making the installer create or rotate credentials for a remote DB host.
  install -o root -g root -m 0600 "$module/watcher/what-changed-watcher.env" \
    /etc/what-changed-watcher.env
  sed -i \
    -e "s/^DB_HOST=.*/DB_HOST=database/" \
    -e "s/^DB_USER=.*/DB_USER=asterisk/" \
    -e "s/^DB_PASSWORD=.*/DB_PASSWORD=local-freepbx/" \
    -e "s/^DB_NAME=.*/DB_NAME=asterisk/" \
    /etc/what-changed-watcher.env
  "$module/bin/install-watcher"
  grep -Fxq "enable what-changed-watcher.service" /tmp/what-changed-systemctl.log
  grep -Fxq "restart what-changed-watcher.service" /tmp/what-changed-systemctl.log
  test -x /usr/sbin/what-changed-watcher-install-sensor

  if pgrep -x php-fpm8.2 >/dev/null; then
    conflict=/etc/php/8.2/fpm/conf.d/98-what-changed-conflict-fixture.ini
  else
    conflict=/etc/php/8.2/apache2/conf.d/98-what-changed-conflict-fixture.ini
  fi
  trap '\''rm -f "$conflict" /tmp/what-changed-sensor-conflict.out /tmp/what-changed-install-conflict.out'\'' EXIT HUP INT TERM
  printf "auto_prepend_file=/tmp/existing-security-bootstrap.php\n" > "$conflict"
  sensor_result=0
  /usr/sbin/what-changed-watcher-install-sensor \
    >/tmp/what-changed-sensor-conflict.out 2>&1 || sensor_result=$?
  if [ "$sensor_result" -ne 3 ]; then
    echo "Sensor installer overwrote an existing auto_prepend_file policy." >&2
    exit 1
  fi
  grep -q "another auto_prepend_file is active" /tmp/what-changed-sensor-conflict.out
  grep -Fq "conflicting_configuration=$conflict" /tmp/what-changed-sensor-conflict.out

  # The top-level installer must treat the conflict as attribution-only
  # degradation: finish the watcher upgrade, retain the competing policy, and
  # make the limitation explicit rather than leaving a half-installed payload.
  "$module/bin/install-watcher" >/tmp/what-changed-install-conflict.out 2>&1
  grep -q "installation completed without administrator request attribution" \
    /tmp/what-changed-install-conflict.out
  test -s "$conflict"
  cmp -s "$module/watcher/VERSION" /usr/lib/what-changed-watcher/VERSION \
    || cmp -s "$module/watcher/VERSION" /usr/local/lib/what-changed-watcher/VERSION

  rm -f "$conflict" /tmp/what-changed-sensor-conflict.out /tmp/what-changed-install-conflict.out
  trap - EXIT HUP INT TERM

  "$module/bin/uninstall-watcher"

  grep -Fxq "disable --now what-changed-watcher.service" /tmp/what-changed-systemctl.log
  grep -Fxq "daemon-reload" /tmp/what-changed-systemctl.log

  test ! -e /etc/php/8.2/apache2/conf.d/99-what-changed-attribution.ini
  test ! -e /etc/php/8.2/fpm/conf.d/99-what-changed-attribution.ini
  test ! -e /etc/php.d/99-what-changed-attribution.ini
  test ! -e /usr/lib/what-changed-watcher
  test ! -e /usr/local/lib/what-changed-watcher

  if pgrep -x apache2 >/dev/null || pgrep -x httpd >/dev/null; then
    apachectl configtest
  fi
  if pgrep -x nginx >/dev/null; then
    nginx -t
  fi
  if pgrep -x php-fpm8.2 >/dev/null; then
    php-fpm8.2 -t
  fi
'

curl -fsSI "$lab_url/admin/config.php" >/dev/null
restore_lab
trap - EXIT HUP INT TERM

"$root_dir/docker/apply-freepbx.sh" >/dev/null
for _attempt in $(seq 1 60); do
  if compose exec -T custom-watcher python -c '
import json
s = json.load(open("/var/lib/pendingchanges-watcher/status.json"))
assert not s["need_reload"]
assert not s["database_drift"] and not s["astdb_drift"] and not s["file_drift"]
assert s.get("baseline_provenance", {}).get("state") == "trusted"
' >/dev/null 2>&1 \
      && curl -fsSI "$lab_url/admin/config.php" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
compose exec -T custom-watcher python -c '
import json
s = json.load(open("/var/lib/pendingchanges-watcher/status.json"))
assert not s["need_reload"]
assert not s["database_drift"] and not s["astdb_drift"] and not s["file_drift"]
assert s.get("baseline_provenance", {}).get("state") == "trusted"
'
curl -fsSI "$lab_url/admin/config.php" >/dev/null
echo 'Embedded watcher install/uninstall preserved the active web stack and restored the lab sidecar'
