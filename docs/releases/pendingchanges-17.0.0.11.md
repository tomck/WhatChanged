# Pending Changes Tripwire 17.0.0.11 alpha

FreePBX 17 private-alpha release for Debian 12 PBXs. Start with a backed-up,
noncritical system.

Download the matching module archive, watcher Debian package, `SHA256SUMS`,
`SHA256SUMS.asc`, and detached `.asc` signatures. Verify them as described in
`README.md` from the release assets.

```sh
sudo apt install ./what-changed-watcher_0.1.1_all.deb
sudo what-changed-watcher-configure
sudo tar -xzf pendingchanges-17.0.0.11.tgz -C /var/www/html/admin/modules
sudo chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
```

Open **Reports -> Pending Changes Tripwire**. Establish a baseline only after a
known, reviewed Apply Config has completed and no prior pending work remains.
Anything outside the displayed coverage contract may not be detected.
