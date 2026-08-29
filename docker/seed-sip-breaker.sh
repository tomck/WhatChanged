#!/bin/sh
# Stage one reversible PJSIP global setting through FreePBX's complete SIP
# Settings form contract. Docker lab only; it deliberately never clicks Apply
# Config. The caller supplies yes or no as the sole argument.
set -eu

target=${1:?usage: seed-sip-breaker.sh yes|no}
case "$target" in yes|no) ;; *) exit 2 ;; esac

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${FREEPBX_LAB_ENV_FILE:-"$ROOT_DIR/.env.lab"}
BASE_URL=${FREEPBX_LAB_URL:-http://127.0.0.1:8080}
[ -r "$ENV_FILE" ] || exit 2
set -a
. "$ENV_FILE"
set +a

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT HUP INT TERM
curl -fsS -c "$COOKIE_JAR" "$BASE_URL/admin/config.php" >/dev/null
curl -fsS -L -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  --data-urlencode "username=$FREEPBX_LAB_ADMIN_USER" \
  --data-urlencode "password=$FREEPBX_LAB_ADMIN_PASSWORD" \
  -o /dev/null "$BASE_URL/admin/config.php"

# These are the non-secret, complete-form defaults captured from the running
# FreePBX 17 lab. Do not copy a browser cookie, external address, TURN
# password, or other machine-specific value into this fixture.
curl -fsS -L -b "$COOKIE_JAR" \
  --referer "$BASE_URL/admin/config.php?display=sipsettings" \
  --data-urlencode 'display=sipsettings' \
  --data-urlencode 'category=general' --data-urlencode 'Submit=Submit' \
  --data-urlencode 'allowanon=No' --data-urlencode 'allowguest=no' \
  --data-urlencode 'externip=' --data-urlencode 'localnets[0][net]=' --data-urlencode 'localnets[0][mask]=' \
  --data-urlencode 'rtpstart=10000' --data-urlencode 'rtpend=20000' \
  --data-urlencode 'rtpchecksums=yes' --data-urlencode 'strictrtp=Yes' \
  --data-urlencode 'rtptimeout=30' --data-urlencode 'rtpholdtimeout=300' --data-urlencode 'rtpkeepalive=0' \
  --data-urlencode 'stunaddr=' --data-urlencode 'turnaddr=' --data-urlencode 'turnusername=' --data-urlencode 'turnpassword=' \
  --data-urlencode 'ice_blacklist_count[]=0' --data-urlencode 'ice_blacklist_ip_0=' --data-urlencode 'ice_blacklist_subnet_0=' \
  --data-urlencode 'ice_host_candidates_count[]=0' --data-urlencode 'ice_host_candidates_local_0=' --data-urlencode 'ice_host_candidates_advertised_0=' \
  --data-urlencode 'webrtcstunaddr=' --data-urlencode 'webrtcturnaddr=' --data-urlencode 'webrtcturnusername=' --data-urlencode 'webrtcturnpassword=' \
  --data-urlencode 't38pt_udptl=no' --data-urlencode 'voicecodecs[ulaw]=1' --data-urlencode 'voicecodecs[alaw]=2' \
  --data-urlencode 'voicecodecs[gsm]=3' --data-urlencode 'voicecodecs[g726]=4' --data-urlencode 'voicecodecs[g722]=5' \
  --data-urlencode 'videosupport=no' --data-urlencode 'vcodec[h264]=0' --data-urlencode 'vcodec[mpeg4]=1' --data-urlencode 'maxcallbitrate=384' \
  --data-urlencode 'category=pjsip' --data-urlencode 'Submit=Submit' \
  --data-urlencode "allow_reload=$target" --data-urlencode 'pjsip_debug=no' --data-urlencode 'pjsip_keep_alive_interval=90' \
  --data-urlencode 'use_callerid_contact=no' --data-urlencode 'taskprocessor_overload_trigger=pjsip_only' \
  --data-urlencode 'showadvanced=no' --data-urlencode 'pjsipcertid=' --data-urlencode 'method=default' \
  --data-urlencode 'verify_client=yes' --data-urlencode 'verify_server=yes' \
  --data-urlencode 'udpbindip-0.0.0.0=on' --data-urlencode 'tcpbindip-0.0.0.0=off' \
  --data-urlencode 'tlsbindip-0.0.0.0=off' --data-urlencode 'wsbindip-0.0.0.0=off' --data-urlencode 'wssbindip-0.0.0.0=off' \
  --data-urlencode 'udpport-0.0.0.0=5060' --data-urlencode 'udpdomain-0.0.0.0=' --data-urlencode 'udpextip-0.0.0.0=' \
  --data-urlencode 'udpextport-0.0.0.0=' --data-urlencode 'udplocalnet-0.0.0.0=' \
  --data-urlencode 'pjsip_identifers_order=["EI_ip","EI_username","EI_anonymous","EI_header","EI_auth_username"]' \
  -o /dev/null "$BASE_URL/admin/config.php"

echo "Staged disposable PJSIP Allow Transports Reload=$target"
