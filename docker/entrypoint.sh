#!/bin/sh
set -eu

if [ ! -f /etc/freepbx.conf ]; then
  /usr/sbin/asterisk || true
  cd /usr/src/freepbx
  ./start_asterisk start
  ./install -n \
    --dbhost "${FREEPBX_DB_HOST}" --dbuser "${FREEPBX_DB_USER}" \
    --dbpass "${FREEPBX_DB_PASSWORD}" --dbname "${FREEPBX_DB_NAME}" \
    --cdrdbname "${FREEPBX_CDR_DB_NAME}"
fi

if [ ! -d /var/www/html/admin/modules/pendingchanges ]; then
  mkdir -p /var/www/html/admin/modules/pendingchanges
  cp -R /srv/pendingchanges/. /var/www/html/admin/modules/pendingchanges/
  ln -sf /var/www/html/admin/modules/pendingchanges/bin/pendingchanges /var/lib/asterisk/bin/pendingchanges
  fwconsole ma install pendingchanges || fwconsole ma enable pendingchanges
fi

exec apachectl -D FOREGROUND
