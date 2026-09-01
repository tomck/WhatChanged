#!/bin/sh
set -eu
umask 0002

# A named /etc/asterisk volume may have been initialized by an older image.
# Repair ownership in place so the asterisk daemon, never root, owns runtime
# state. This preserves the disposable lab's existing database and config.
mkdir -p /var/spool/asterisk /var/run/asterisk
chown -R asterisk:asterisk /etc/asterisk /var/log/asterisk /var/run/asterisk /var/spool/asterisk
chown asterisk:asterisk /var/lib/asterisk
[ -e /var/lib/asterisk/astdb.sqlite3 ] && chown asterisk:asterisk /var/lib/asterisk/astdb.sqlite3
for path in /var/lib/asterisk/agi-bin /var/lib/asterisk/keys /var/lib/asterisk/moh /var/lib/asterisk/sounds /var/lib/asterisk/spool; do
  [ -e "$path" ] && chown -R asterisk:asterisk "$path"
done

# /etc/freepbx.conf sits outside Asterisk's configuration directory. Keep a
# copy in the persistent Asterisk state volume and restore it on recreation.
if [ ! -f /etc/freepbx.conf ] && [ -f /var/lib/asterisk/freepbx.conf ]; then
  cp /var/lib/asterisk/freepbx.conf /etc/freepbx.conf
fi
if [ ! -f /etc/amportal.conf ] && [ -f /var/lib/asterisk/amportal.conf ]; then
  cp /var/lib/asterisk/amportal.conf /etc/amportal.conf
fi

# FreePBX refuses to continue when a prior interrupted install left only one
# half of its generated configuration pair. This can occur only in the
# disposable lab before amportal.conf has first been persisted.
if [ ! -f /etc/amportal.conf ] && [ ! -f /var/lib/asterisk/amportal.conf ] && \
  [ -f /etc/freepbx.conf ]; then
  rm -f /etc/freepbx.conf
fi

# The marker is written only after a successful installer run.  This lets the
# lab resume safely when FreePBX has partially populated its database/files.
if [ ! -f /var/www/html/.what-changed-freepbx-ready ] || \
  [ ! -f /etc/freepbx.conf ] || [ ! -f /etc/amportal.conf ]; then
  # The FreePBX pm2 module requires its private node_modules path during the
  # installer itself.  Reuse the image-provided package instead of downloading
  # dependencies into this disposable lab on every initialization.
  mkdir -p /var/www/html/admin/modules/pm2/node/node_modules
  ln -sfn /var/lib/asterisk/.node/node_modules/pm2 \
    /var/www/html/admin/modules/pm2/node/node_modules/pm2
  cd /usr/src/freepbx
  ./start_asterisk start
  INSTALL_RC=0
  ./install -n -f \
    --dbhost "${FREEPBX_DB_HOST}" --dbuser "${FREEPBX_DB_USER}" \
    --dbpass "${FREEPBX_DB_PASSWORD}" --dbname "${FREEPBX_DB_NAME}" \
    --cdrdbname "${FREEPBX_CDR_DB_NAME}" || INSTALL_RC=$?
  # The FreePBX 17 installer can return nonzero after a successful completion.
  # Accept that only when its framework and PM2 prerequisites are present.
  if [ "$INSTALL_RC" -ne 0 ] && { \
    [ ! -f /var/www/html/admin/modules/framework/module.xml ] || \
    [ ! -x /var/www/html/admin/modules/pm2/node/node_modules/pm2/bin/pm2 ]; \
  }; then
    exit "$INSTALL_RC"
  fi
  cp /etc/freepbx.conf /var/lib/asterisk/freepbx.conf
  chown asterisk:asterisk /var/lib/asterisk/freepbx.conf
  cp /etc/amportal.conf /var/lib/asterisk/amportal.conf
  chown asterisk:asterisk /var/lib/asterisk/amportal.conf
  touch /var/www/html/.what-changed-freepbx-ready
fi

if [ ! -d /var/www/html/admin/modules/pendingchanges ]; then
  mkdir -p /var/www/html/admin/modules/pendingchanges
fi
# Synchronize the read-only workspace source on every disposable-lab start so
# rebuilt module code is actually what Module Admin installs from the persisted
# web volume.
cp -R /srv/pendingchanges/. /var/www/html/admin/modules/pendingchanges/
if [ ! -e /var/lib/asterisk/bin/pendingchanges ]; then
  ln -sf /var/www/html/admin/modules/pendingchanges/bin/pendingchanges /var/lib/asterisk/bin/pendingchanges
fi
# Re-register the synchronized source on every start. This keeps Module Admin's
# recorded version aligned when a persisted web volume survives a module bump.
# A registration failure must not take down the PBX: the source remains
# available for inspection and a later archive-install validation.
fwconsole ma install pendingchanges || fwconsole ma enable pendingchanges || true

# The normal FreePBX Debian install exposes fwconsole in /usr/sbin. The
# source-built disposable image keeps it only under /var/lib/asterisk/bin,
# while Framework's authenticated Apply Config handler resolves /usr/sbin.
# Mirror the packaged path so the lab can test the real web apply request.
ln -sfn /var/lib/asterisk/bin/fwconsole /usr/sbin/fwconsole

# FreePBX 17's Module Admin machine-ID helper assumes shell_exec always
# returns a string. Debian 12's PHP 8.2 can return null instead, which turns
# the subsequent preg_replace call into a fatal deprecation. Patch only the
# disposable lab's installed framework at startup; this is deliberately not a
# production FreePBX change.
patch_moduleadmin_php82_compatibility() {
  target=/var/www/html/admin/libraries/modulefunctions.class.php
  [ -f "$target" ] || return 0
  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines(keepends=True)
for index, line in enumerate(lines[:-1]):
    if "cat /var/lib/dbus/machine-id /etc/machine-id" not in line:
        continue
    candidate = lines[index + 1]
    if "preg_replace" in candidate and "$result);" in candidate:
        lines[index + 1] = candidate.replace("$result);", "$result ?? '');")
        path.write_text("".join(lines))
    break
PY
}

patch_moduleadmin_php82_compatibility

# Find Me/Follow's legacy helper returns `$users` without initializing it when
# no user survives its range filter. PHP 8.2 promotes that notice to the
# exception page, which prevents every normal full-form extension edit in this
# disposable lab. Initialize the local accumulator without altering FreePBX's
# query, filtering, or saved configuration behavior. Keep this lab-only, just
# like the Module Admin compatibility shim above.
patch_findmefollow_php82_compatibility() {
  target=/var/www/html/admin/modules/findmefollow/functions.inc.php
  [ -f "$target" ] || return 0
  python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "function findmefollow_allusers() {\n\tglobal $db;"
replacement = "function findmefollow_allusers() {\n\t$users = [];\n\tglobal $db;"
if needle in text:
    path.write_text(text.replace(needle, replacement, 1))
PY
}

patch_findmefollow_php82_compatibility

# Packaged FreePBX runs its Apache workers as asterisk so authenticated Apply
# Config can regenerate files with the same ownership as the CLI. Mirror that
# production contract in the lab rather than granting www-data broad write
# access or sudo privileges.
sed -i 's/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=asterisk/' /etc/apache2/envvars
sed -i 's/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=asterisk/' /etc/apache2/envvars
[ -f /etc/freepbx.conf ] && chgrp asterisk /etc/freepbx.conf && chmod 640 /etc/freepbx.conf
[ -f /etc/amportal.conf ] && chgrp asterisk /etc/amportal.conf && chmod 640 /etc/amportal.conf
chmod -R g+rwX /var/log/asterisk
# Framework cache files are created after the initial ownership repair.  The
# Apache user is in the asterisk group, so grant that group the required cache
# write access without making the lab configuration world-writable.
chmod -R g+rwX /var/spool/asterisk
find /var/spool/asterisk -type d -exec chmod g+rws {} +
mkdir -p /var/lib/php/sessions
chown asterisk:asterisk /var/lib/php/sessions
chmod 1733 /var/lib/php/sessions

# Install the value-free authenticated-request sensor in Apache's PHP SAPI.
# Its dedicated volume is writable by the web worker and readable by the
# watcher without granting Apache access to the private baseline directory.
install -d -m 0755 /usr/local/lib/what-changed-watcher
install -m 0644 /srv/pendingchanges/deploy/what-changed-request-audit.php \
  /usr/local/lib/what-changed-watcher/what-changed-request-audit.php
install -m 0644 /srv/pendingchanges/deploy/99-what-changed-attribution.ini \
  /etc/php/8.2/apache2/conf.d/99-what-changed-attribution.ini
install -d -o asterisk -g asterisk -m 2770 /var/lib/asterisk/pendingchanges-attribution
if [ -f /var/lib/asterisk/pendingchanges-attribution/requests.jsonl ]; then
  chown asterisk:asterisk /var/lib/asterisk/pendingchanges-attribution/requests.jsonl
  chmod 0640 /var/lib/asterisk/pendingchanges-attribution/requests.jsonl
fi

# FreePBX creates its AMI credentials during installation.  On a resumed lab,
# the named Asterisk configuration volume can otherwise retain an older
# manager.conf account, leaving the web UI unable to connect to Asterisk.
# Keep only this generated account synchronized; all values remain inside the
# disposable container and are never logged.
sync_ami_manager() {
  [ -f /etc/amportal.conf ] && [ -f /etc/asterisk/manager.conf ] || return 0
  python3 - <<'PY'
import re
from pathlib import Path

amportal = Path("/etc/amportal.conf").read_text()
def setting(name):
    match = re.search(rf"^{name}=(.*)$", amportal, re.M)
    if not match:
        raise SystemExit(f"missing {name}")
    return match.group(1).strip()

user, secret = setting("AMPMGRUSER"), setting("AMPMGRPASS")
path = Path("/etc/asterisk/manager.conf")
text = path.read_text()
headers = list(re.finditer(r"^\[[^\]]+\]$", text, re.M))
if len(headers) < 2:
    raise SystemExit("unexpected manager.conf section count")

parts, cursor = [], 0
for index, match in enumerate(headers):
    parts.append(text[cursor:match.start()])
    parts.append("[general]" if index == 0 else (f"[{user}]" if index == 1 else match.group(0)))
    cursor = match.end()
parts.append(text[cursor:])
text = "".join(parts)
text = re.sub(r"^(\s*secret\s*=\s*).*?$", lambda match: match.group(1) + secret,
              text, count=1, flags=re.M)
path.write_text(text)
PY
  chown asterisk:asterisk /etc/asterisk/manager.conf
}

sync_ami_manager

# The installer starts Asterisk on first boot, but a recreated lab container
# needs it started again before Apache exposes configuration modules.
if ! asterisk -rx 'core show version' >/dev/null 2>&1; then
  cd /usr/src/freepbx
  ./start_asterisk start
else
  asterisk -rx 'module reload manager' >/dev/null
fi

# Let FreePBX apply its own precise ownership policy after every install or
# resume.  In particular it keeps the framework cache writable by Apache,
# avoiding a recursive bootstrap failure in the disposable web UI.
/var/lib/asterisk/bin/fwconsole chown >/dev/null
# Apache can create freepbx.log before a CLI reload. Keep the shared log
# directory group-inheriting and owned by the common asterisk account.
find /var/log/asterisk -type d -exec chmod g+rws {} +
# Create this before Apache can create it with a restrictive umask.  Both web
# requests and CLI reloads log here; the CLI runs as asterisk.
touch /var/log/asterisk/freepbx.log
chown asterisk:asterisk /var/log/asterisk/freepbx.log
chmod 664 /var/log/asterisk/freepbx.log

exec apachectl -D FOREGROUND
