#!/bin/sh
# Create detached OpenPGP signatures for an alpha release's module archive,
# watcher Debian package, and checksum manifest. Run this interactively on the
# signing host that holds the user's signing subkey; never copy a secret key
# into the repository or Docker lab.
set -eu

subkey=5319601D6E2B13F507DC2618AFA3ED68ADB99176
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 module.tgz watcher.deb [additional-release-file ...]" >&2
  exit 2
fi
if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo 'Run from an interactive terminal so GPG pinentry can unlock the signing key.' >&2
  exit 1
fi

release_dir=$(dirname "$1")
for artifact in "$@"; do
  if [ ! -f "$artifact" ]; then
    echo "Missing release artifact: $artifact" >&2
    exit 1
  fi
  if [ "$(dirname "$artifact")" != "$release_dir" ]; then
    echo 'All release artifacts must be in one directory.' >&2
    exit 1
  fi
done

export GPG_TTY="$(tty)"
checksum_file="$release_dir/SHA256SUMS"
(
  cd "$release_dir"
  for artifact in "$@"; do
    sha256sum "$(basename "$artifact")"
  done > "$(basename "$checksum_file")"
)
for artifact in "$@" "$checksum_file"; do
  sudo env GPG_TTY="$GPG_TTY" gpg --armor --local-user "${subkey}!" \
    --detach-sign --output "$artifact.asc" "$artifact"
  sudo gpg --verify "$artifact.asc" "$artifact"
done
echo "Signed release artifacts in $release_dir"
