#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
release_dir=${1:-"$root_dir/dist/signed-release"}
release_dir=$(cd "$release_dir" && pwd)
source "$root_dir/deploy/release-versions.sh"
gpg_home=$(mktemp -d)
module_stage=$(mktemp -d)
trap 'rm -rf "$gpg_home" "$module_stage"' EXIT HUP INT TERM
chmod 0700 "$gpg_home"

files=(
  "pendingchanges-$module_version.tgz"
  "what-changed-watcher-portable_$watcher_version.tar.gz"
  "what-changed-watcher_${watcher_version}_all.deb"
  WHAT_CHANGED_SIGNING_KEY.asc
  README.md
)

for name in "${files[@]}" SHA256SUMS; do
  test -s "$release_dir/$name"
  test -s "$release_dir/$name.asc"
done

if grep -R -l -- 'BEGIN PGP PRIVATE KEY BLOCK' "$release_dir" >/dev/null; then
  echo 'Refusing release set containing an OpenPGP private-key block.' >&2
  exit 1
fi

# Some macOS GPGTools builds import the public key successfully but return 2
# when their optional agent is unavailable in an isolated temporary home.
# Accept that narrow condition only when the fresh keyring now contains an
# imported fingerprint; every artifact signature is still verified below.
if ! gpg --homedir "$gpg_home" --batch --import \
    "$release_dir/WHAT_CHANGED_SIGNING_KEY.asc" >/dev/null 2>&1; then
  gpg --homedir "$gpg_home" --batch --list-keys --with-colons 2>/dev/null \
    | grep -q '^fpr:' || {
      echo 'Could not import the release signing public key.' >&2
      exit 1
    }
fi

(
  cd "$release_dir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c SHA256SUMS
  else
    shasum -a 256 -c SHA256SUMS
  fi
)
for name in "${files[@]}" SHA256SUMS; do
  gpg --homedir "$gpg_home" --batch --verify \
    "$release_dir/$name.asc" "$release_dir/$name" >/dev/null
done

name="pendingchanges-$module_version.tgz"
target_stage="$module_stage/shared"
candidate_stage="$module_stage/candidate"
mkdir -p "$target_stage"
tar -xzf "$release_dir/$name" -C "$target_stage"
test -s "$target_stage/pendingchanges/module.sig"
grep -q "<version>$module_version</version>" \
  "$target_stage/pendingchanges/module.xml"
gpg --homedir "$gpg_home" --batch --verify \
  "$target_stage/pendingchanges/module.sig" >/dev/null
manifest="$module_stage/module-signature-manifest.txt"
gpg --homedir "$gpg_home" --batch --decrypt \
  "$target_stage/pendingchanges/module.sig" > "$manifest"
"$root_dir/scripts/check-module-signature-manifest.sh" "$manifest"

# Prove that signing added only the distributable module.sig to the exact
# candidate built from this checkout. Matching a version string is not enough:
# a stale or wrong same-named archive must fail closed before publication.
candidate_archive="$root_dir/dist/$name"
test -s "$candidate_archive" || {
  echo "Missing exact unsigned candidate for identity comparison: $candidate_archive" >&2
  exit 1
}
mkdir -p "$candidate_stage"
tar -xzf "$candidate_archive" -C "$candidate_stage"
rm -f "$target_stage/pendingchanges/module.sig"
diff -r "$candidate_stage/pendingchanges" "$target_stage/pendingchanges" >/dev/null || {
  echo 'Signed module payload does not match the exact unsigned candidate.' >&2
  exit 1
}

for artifact in \
  "what-changed-watcher-portable_$watcher_version.tar.gz" \
  "what-changed-watcher_${watcher_version}_all.deb"; do
  cmp -s "$root_dir/dist/$artifact" "$release_dir/$artifact" || {
    echo "Signed release asset does not match the exact local candidate: $artifact" >&2
    exit 1
  }
done
cmp -s "$root_dir/docs/release-assets.md" "$release_dir/README.md" || {
  echo 'Signed release README does not match docs/release-assets.md.' >&2
  exit 1
}

echo "Signed GitHub release set and exact candidate identity verified: $release_dir"
