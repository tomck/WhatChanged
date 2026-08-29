#!/bin/sh
# Verify the PBX-local FreePBX signing key can prompt and sign before using
# devtools/sign.php.  It signs only a temporary test string.
set -eu

subkey=5319601D6E2B13F507DC2618AFA3ED68ADB99176
export GPG_TTY="$(tty)"
if [ "$GPG_TTY" = "not a tty" ]; then
    echo "Run this from an interactive SSH terminal, not through a job or pipe." >&2
    exit 1
fi

testfile="$(mktemp /tmp/what-changed-signing-test.XXXXXX.asc)"
trap 'rm -f "$testfile"' EXIT HUP INT TERM
printf 'WhatChanged signing-key verification\n' |
    sudo env GPG_TTY="$GPG_TTY" gpg --local-user "${subkey}!" --armor --clearsign > "$testfile"
sudo gpg --verify "$testfile"
echo "Signing-key verification passed."
