#!/bin/sh
set -eu

manifest=${1:?Usage: check-module-signature-manifest.sh CLEARTEXT-MANIFEST}

if [ ! -s "$manifest" ]; then
  echo "Missing or empty module-signature manifest: $manifest" >&2
  exit 1
fi
if ! grep -qx 'type=public' "$manifest"; then
  echo 'Module signature is host-local; a release requires type=public.' >&2
  exit 1
fi
if grep -Eq '^pendingchanges\.sig[[:space:]]*=' "$manifest"; then
  echo 'Module signature depends on a PBX-specific pendingchanges.sig sidecar.' >&2
  exit 1
fi

echo 'Distributable FreePBX module-signature manifest verified.'
