# Legacy compatibility evidence

This document records what the repository's compatibility gate proves. It is
deliberately narrower than a support claim.

| FreePBX target | Candidate | Validated runtime | Current evidence | Still required |
| --- | --- | --- | --- | --- |
| 14 | `17.0.1.2` shared archive | FreePBX 14.0.13.4, Asterisk 15.7.3, PHP 5.6.40 | Metadata/syntax/render checks plus real Module Admin install, watcher-to-BMO integration, staged database drift, Apply Config, and clean baseline | Voluntary alpha feedback from maintained real installations |
| 15 | `17.0.1.2` shared archive | FreePBX 15.0.17.34, Asterisk 17.9.3, PHP 5.6.40 | Metadata/syntax/render checks plus real Module Admin install, watcher-to-BMO integration, staged database drift, Apply Config, and clean baseline | Voluntary alpha feedback from maintained real installations |
| 16 | `17.0.1.2` shared archive | FreePBX 16.0.50, Asterisk 20.8.1, PHP 7.4.33 | Metadata/syntax/render checks plus real Module Admin install, watcher-to-BMO integration, staged database drift, Apply Config, and clean baseline | Voluntary alpha feedback from maintained real installations |
| 17 | `17.0.1.2` shared archive | FreePBX 17, PHP 8.2 | Complete compatibility, installation, watcher, authenticated fixture, breaker, Apply Config, and final clean-state gates | Continued alpha feedback on varied installations |

The shared portable watcher additionally passes Python 3.6 compilation,
cross-version PHP sensor tests, archive-layout checks, and service-path checks.
Its installer has not yet been exercised on a real SNG7/FreePBX Distro host.

The real-image lifecycle is a compatibility probe, not a production-support
claim. It uses these immutable third-party fixtures:

- FreePBX 16: `maxrip/docker-freepbx:asterisk20.8.1.2-freepbx16@sha256:d0368ee4928676ada5a4db231d7328fafc04cc3716f5d5168e707bf532c17a1c`
- FreePBX 15: `flaviostutz/freepbx:15.0.17.17.6@sha256:c36349911e5c427e444ee64c18754dc534624bd024c4d1019cc5dc593cd1f39b`
- FreePBX 14: `flaviostutz/freepbx:14.1.1@sha256:f2f2c55a7b05ff9ea5020a4f7ff30c27ba144b91ecef864a382f5545388ac557`

The FreePBX 16 wrapper restores the base image's missing `binutils` and npm
runtime packages; the latter lets FreePBX install its locally bundled `pm2`
module before reload. The FreePBX 14 and 15 wrappers expose their embedded
MariaDB only to the private Compose network and leave only a SELECT-only
watcher account available there. None of the fixtures publish MariaDB, SIP,
or RTP ports to the host.

Real voluntary alpha reports should still include:

```sh
sudo /var/lib/asterisk/bin/fwconsole --version
sudo /var/lib/asterisk/bin/fwconsole ma list | grep -E 'framework|pendingchanges'
php -v | head -n 1
cat /etc/os-release
asterisk -V
```

Passing this matrix means the module and watcher can run through the tested
lifecycle on representative historical stacks. It does not make those old
stacks secure or supported, and anything outside the watcher's explicit
coverage contract may not be detected.
