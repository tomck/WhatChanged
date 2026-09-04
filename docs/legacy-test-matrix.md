# Legacy compatibility evidence

This document records what the repository's compatibility gate proves. It is
deliberately narrower than a support claim.

| FreePBX target | Candidate | Runtime gate | Current evidence | Still required |
| --- | --- | --- | --- | --- |
| 14 | `14.0.0.11` | PHP 5.6 | Metadata, syntax, BMO class load, full page rendering, request-sensor behavior | Module Admin install and real staged-change lifecycle on FreePBX 14 |
| 15 | `15.0.0.11` | PHP 5.6 | Metadata, syntax, BMO class load, full page rendering, request-sensor behavior | Module Admin install and real staged-change lifecycle on FreePBX 15 |
| 16 | `16.0.0.11` | PHP 7.4 | Metadata, syntax, BMO class load, full page rendering, request-sensor behavior | Module Admin install and real staged-change lifecycle on FreePBX 16 |
| 17 | `17.0.0.11` | PHP 8.2 | All compatibility checks, real Module Admin archive install, and complete Docker smoke gate | Continued alpha feedback on varied installations |

The shared portable watcher additionally passes Python 3.6 compilation,
cross-version PHP sensor tests, archive-layout checks, and service-path checks.
Its installer has not yet been exercised on a real SNG7/FreePBX Distro host.

The third-party historical FreePBX Docker images found during research are
old, unmaintained, and not authoritative FreePBX artifacts. They are therefore
not treated as release evidence. Real voluntary alpha reports should include:

```sh
sudo /var/lib/asterisk/bin/fwconsole --version
sudo /var/lib/asterisk/bin/fwconsole ma list | grep -E 'framework|pendingchanges'
php -v | head -n 1
cat /etc/os-release
asterisk -V
```

No FreePBX 14-16 candidate should be described as supported until its matching
row's real-install gap has been closed. Anything outside the watcher's explicit
coverage contract may not be detected.
