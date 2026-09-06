#!/bin/sh
# Prove the generated archive can be installed by Module Admin in the
# disposable lab. This intentionally alters only the lab's module volume.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCHIVE=${1:?usage: validate-module-archive.sh path/to/pendingchanges-version.tgz}
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
export PATH="$PATH:/Applications/Docker.app/Contents/Resources/bin"

[ -f "$ARCHIVE" ] || exit 2
ARCHIVE=$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")
case "$ARCHIVE" in "$ROOT_DIR"/*) ;; *) echo 'archive must be inside this checkout' >&2; exit 2 ;; esac
archive_name=$(basename "$ARCHIVE")
module_version=$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$ROOT_DIR/module.xml" | head -n1)
[ -n "$module_version" ] || exit 1

# The checkout is mounted read-only at /srv/pendingchanges, including dist/.
docker compose -f "$COMPOSE_FILE" exec -T pbx sh -lc "
  set -eu
  archive=/srv/pendingchanges/dist/$archive_name
  test -f \"\$archive\"
  tar -tzf \"\$archive\" | grep -qx 'pendingchanges/module.xml'
  if /var/lib/asterisk/bin/fwconsole ma list \
      | grep -Eq '\|[[:space:]]*pendingchanges[[:space:]]*\|'; then
    /var/lib/asterisk/bin/fwconsole ma uninstall pendingchanges
  fi
  rm -rf /var/www/html/admin/modules/pendingchanges
  tar -xzf \"\$archive\" -C /var/www/html/admin/modules
  chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
  /var/lib/asterisk/bin/fwconsole ma install pendingchanges
  /var/lib/asterisk/bin/fwconsole ma list | grep -E '\|[[:space:]]*pendingchanges[[:space:]]*\|[[:space:]]*$module_version[[:space:]]*\|[[:space:]]*Enabled'
"
echo "Module Admin archive install passed: $archive_name"
