#!/bin/sh
# Sign the currently installed pendingchanges module with FreePBX local
# signing. The direct preflight gives pinentry a real terminal and primes the
# root GPG agent before sign.php opens its two piped GPG processes.
set -eu

subkey=5319601D6E2B13F507DC2618AFA3ED68ADB99176
module=/var/www/html/admin/modules/pendingchanges
export GPG_TTY="$(tty)"
if [ "$GPG_TTY" = "not a tty" ]; then
    echo "Run this from an interactive SSH terminal, not through a job or pipe." >&2
    exit 1
fi
testfile="$(mktemp /tmp/pendingchanges-signing-preflight.XXXXXX.asc)"
trap 'rm -f "$testfile"' EXIT HUP INT TERM

echo "Unlocking the local signing key..."
printf 'Pendingchanges signing preflight\n' |
    sudo env GPG_TTY="$GPG_TTY" gpg --local-user "${subkey}!" --armor --clearsign > "$testfile"
sudo gpg --verify "$testfile" >/dev/null

sudo env GPG_TTY="$GPG_TTY" /usr/src/devtools/sign.php "$module" --local "$subkey"
sudo gpg --verify /etc/freepbx.secure/pendingchanges.sig
sudo gpg --verify "$module/module.sig"
echo "Pendingchanges local signatures verified."
