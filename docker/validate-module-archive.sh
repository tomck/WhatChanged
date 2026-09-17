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
archive_rel=${ARCHIVE#"$ROOT_DIR"/}
require_signature=0
if tar -tzf "$ARCHIVE" | grep -qx 'pendingchanges/module.sig'; then
  require_signature=1
fi
module_version=$(sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$ROOT_DIR/module.xml" | head -n1)
[ -n "$module_version" ] || exit 1

# The checkout is mounted read-only at /srv/pendingchanges, including dist/.
docker compose -f "$COMPOSE_FILE" exec -T \
  -e MODULE_ARCHIVE_REL="$archive_rel" \
  -e MODULE_VERSION="$module_version" \
  -e REQUIRE_SIGNATURE="$require_signature" \
  pbx sh -lc "
  set -eu
  archive=/srv/pendingchanges/\$MODULE_ARCHIVE_REL
  test -f \"\$archive\"
  tar -tzf \"\$archive\" | grep -qx 'pendingchanges/module.xml'
  tar -tzf \"\$archive\" | grep -qx 'pendingchanges/composer.json'
  tar -tzf \"\$archive\" | grep -qx 'pendingchanges/autoload.php'
  tar -tzf \"\$archive\" | grep -qx 'pendingchanges/src/Service/PendingChangesService.php'
  tar -tzf \"\$archive\" | grep -qx 'pendingchanges/views/page.php'
  if /var/lib/asterisk/bin/fwconsole ma list \
      | grep -E '\|[[:space:]]*pendingchanges[[:space:]]*\|' \
      | grep -qv 'Not Installed'; then
    /var/lib/asterisk/bin/fwconsole ma uninstall pendingchanges
  fi
  rm -rf /var/www/html/admin/modules/pendingchanges
  tar -xzf \"\$archive\" -C /var/www/html/admin/modules
  chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
  /var/lib/asterisk/bin/fwconsole ma install pendingchanges
  /var/lib/asterisk/bin/fwconsole ma list \
    | grep -E \"\\|[[:space:]]*pendingchanges[[:space:]]*\\|[[:space:]]*\$MODULE_VERSION[[:space:]]*\\|[[:space:]]*Enabled\"
  if [ \"\$REQUIRE_SIGNATURE\" = 1 ]; then
    test -s /var/www/html/admin/modules/pendingchanges/module.sig
    /var/lib/asterisk/bin/fwconsole ma list \
      | grep -E '\|[[:space:]]*pendingchanges[[:space:]]*\|' \
      | grep -Eq '\|[[:space:]]*(Unknown|Sangoma)[[:space:]]*\|$'
  fi
"
echo "Module Admin archive install passed: $archive_rel"
