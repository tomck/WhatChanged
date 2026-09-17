#!/usr/bin/env bash
set -Eeuo pipefail

# Convenience installer for operators who explicitly trust this repository's
# hosted installer. The normal release verification and manual install paths
# remain documented in docs/alpha-install.md.

repo=${WHAT_CHANGED_REPO:-tomck/WhatChanged}
github_root="https://github.com/$repo"

say() { printf '%s\n' "$*"; }
die() { printf 'WhatChanged installer: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root, for example: curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | sudo bash"
command -v curl >/dev/null 2>&1 || die 'curl is required.'
command -v tar >/dev/null 2>&1 || die 'tar is required.'
fwconsole_cmd=$(command -v fwconsole 2>/dev/null || true)
if [ -z "$fwconsole_cmd" ] && [ -x /var/lib/asterisk/bin/fwconsole ]; then
  fwconsole_cmd=/var/lib/asterisk/bin/fwconsole
fi
[ -n "$fwconsole_cmd" ] || die 'FreePBX fwconsole was not found.'

release_url=$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "$github_root/releases/latest")
release_url=${release_url%%\?*}
tag=${release_url##*/}
case "$tag" in
  pendingchanges-[0-9]*.[0-9]*.[0-9]*.[0-9]*) ;;
  *) die "could not resolve a published Pending Changes release from $release_url" ;;
esac
module_version=${tag#pendingchanges-}
base_url="$github_root/releases/download/$tag"
archive_name="pendingchanges-$module_version.tgz"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/what-changed.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

say "Downloading WhatChanged $module_version from $github_root ..."
for asset in "$archive_name" SHA256SUMS SHA256SUMS.asc WHAT_CHANGED_SIGNING_KEY.asc "$archive_name.asc"; do
  curl -fsSL --retry 3 "$base_url/$asset" -o "$work_dir/$asset" ||
    die "release asset is missing: $asset"
done

expected=$(awk -v name="$archive_name" '$2 == name { print $1; exit }' "$work_dir/SHA256SUMS")
[ -n "$expected" ] || die "SHA256SUMS does not contain $archive_name"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$work_dir/$archive_name" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$work_dir/$archive_name" | awk '{print $1}')
elif command -v openssl >/dev/null 2>&1; then
  actual=$(openssl dgst -sha256 -r "$work_dir/$archive_name" | awk '{print $1}')
else
  die 'sha256sum, shasum, or openssl is required to verify the release.'
fi
[ "$actual" = "$expected" ] || die "SHA-256 verification failed for $archive_name"
say 'SHA-256 verification passed.'

if command -v gpg >/dev/null 2>&1; then
  gpg_home="$work_dir/gnupg"
  mkdir -m 0700 "$gpg_home"
  # Some GnuPG builds return a non-zero import status for an uncertified
  # public key even though the key is usable for signature verification.
  gpg --homedir "$gpg_home" --batch --no-tty --import \
    "$work_dir/WHAT_CHANGED_SIGNING_KEY.asc" >/dev/null 2>&1 || true
  gpg --homedir "$gpg_home" --batch --no-tty --verify \
    "$work_dir/SHA256SUMS.asc" "$work_dir/SHA256SUMS" >/dev/null 2>&1 ||
    die 'OpenPGP verification failed for SHA256SUMS.'
  say 'OpenPGP verification passed.'
else
  say 'Warning: gpg is not installed; continuing with SHA-256 verification only.' >&2
fi

freepbx_webroot=$($fwconsole_cmd setting AMPWEBROOT |
  sed -n 's/^Setting of "AMPWEBROOT" is ([^)]*)\[\(.*\)\]$/\1/p')
[ -n "$freepbx_webroot" ] || die 'could not determine FreePBX AMPWEBROOT.'
module_parent="$freepbx_webroot/admin/modules"
module_dir="$module_parent/pendingchanges"
[ -d "$module_parent" ] || die "FreePBX module directory was not found: $module_parent"

tar -xzf "$work_dir/$archive_name" -C "$module_parent"
if id asterisk >/dev/null 2>&1; then
  chown -R asterisk:asterisk "$module_dir"
fi
"$fwconsole_cmd" ma install pendingchanges
"$fwconsole_cmd" ma enable pendingchanges >/dev/null 2>&1 || true
"$module_dir/bin/install-watcher"

say "WhatChanged $module_version is installed. Open Reports -> Pending Changes Tripwire to verify watcher health and baseline continuity."
