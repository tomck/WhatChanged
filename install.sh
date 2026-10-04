#!/usr/bin/env bash
set -Eeuo pipefail

# Convenience installer for operators who explicitly trust this repository's
# hosted installer. The normal release verification and manual install paths
# remain documented in docs/alpha-install.md.

repo=${WHAT_CHANGED_REPO:-tomck/WhatChanged}
github_root="https://github.com/$repo"
# Pin the reviewed release explicitly. GitHub's /releases/latest endpoint omits
# prereleases, while WhatChanged public alphas are intentionally prereleases.
# Release preparation must update this value only after signed-archive gates.
module_version=${WHAT_CHANGED_VERSION:-17.0.2.6}

say() { printf '%s\n' "$*"; }
die() { printf 'WhatChanged installer: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root, for example: curl -fsSL https://raw.githubusercontent.com/$repo/main/install.sh | sudo bash"
command -v curl >/dev/null 2>&1 || die 'curl is required.'
command -v tar >/dev/null 2>&1 || die 'tar is required.'
if ! command -v gpg >/dev/null 2>&1; then
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  case "${ID:-}:${ID_LIKE:-}" in
    *debian*|*ubuntu*)
      die "gpg is required to authenticate the release. Install it with: apt-get update && apt-get install -y gnupg; then rerun this installer."
      ;;
    *rhel*|*fedora*|*centos*|*sangoma*)
      die "gpg is required to authenticate the release. Install it with: dnf install -y gnupg2 (or yum install -y gnupg2); then rerun this installer."
      ;;
    *)
      die "gpg is required to authenticate the release. Install GnuPG with this system's package manager, then rerun this installer."
      ;;
  esac
fi
fwconsole_cmd=$(command -v fwconsole 2>/dev/null || true)
if [ -z "$fwconsole_cmd" ] && [ -x /var/lib/asterisk/bin/fwconsole ]; then
  fwconsole_cmd=/var/lib/asterisk/bin/fwconsole
fi
[ -n "$fwconsole_cmd" ] || die 'FreePBX fwconsole was not found.'

[[ $module_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  die "invalid module version: $module_version"
tag="pendingchanges-$module_version"
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

gpg_home="$work_dir/gnupg"
mkdir -m 0700 "$gpg_home"
# Some GnuPG builds return a non-zero import status for an uncertified public
# key even when the key was imported. The signature checks below remain the
# fail-closed authority: they cannot pass unless a usable public key exists.
gpg --homedir "$gpg_home" --batch --no-tty --import \
  "$work_dir/WHAT_CHANGED_SIGNING_KEY.asc" >/dev/null 2>&1 || true
gpg --homedir "$gpg_home" --batch --no-tty --verify \
  "$work_dir/SHA256SUMS.asc" "$work_dir/SHA256SUMS" >/dev/null 2>&1 ||
  die 'OpenPGP verification failed for SHA256SUMS.'
gpg --homedir "$gpg_home" --batch --no-tty --verify \
  "$work_dir/$archive_name.asc" "$work_dir/$archive_name" >/dev/null 2>&1 ||
  die "OpenPGP verification failed for $archive_name."
say 'OpenPGP verification passed for the manifest and module archive.'

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
