#!/bin/sh
set -eu
STATE=/var/lib/tripwire
mkdir -p "$STATE"
cat > "$STATE/policy.txt" <<'POLICY'
(
  rulename = "FreePBX generated configuration",
  severity = 100
)
{
  /etc/asterisk -> $(ReadOnly);
}
POLICY
# The container intentionally records reports only. Policy/key initialization is
# performed here so its state remains inside the disposable named volume.
if [ ! -f "$STATE/initialized" ]; then
  touch "$STATE/initialized"
fi
while true; do
  find /etc/asterisk -type f -name '*.conf' -exec sha256sum {} \; | sort > "$STATE/files.sha256"
  date -u +%FT%TZ > "$STATE/last_check_at"
  sleep 5
done
