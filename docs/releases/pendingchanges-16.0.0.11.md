# Pending Changes Tripwire 16.0.0.11 alpha

Experimental FreePBX 16 compatibility release for backed-up, noncritical
systems.

Download the matching module archive, the portable watcher bundle,
`SHA256SUMS`, `SHA256SUMS.asc`, and the detached `.asc` signatures. Verify them
as described in `README.md` from the release assets.

```sh
tar -xzf what-changed-watcher-portable_0.1.1.tar.gz
cd what-changed-watcher-portable-0.1.1
sudo ./install.sh
cd ..
sudo tar -xzf pendingchanges-16.0.0.11.tgz -C /var/www/html/admin/modules
sudo chown -R asterisk:asterisk /var/www/html/admin/modules/pendingchanges
sudo /var/lib/asterisk/bin/fwconsole ma install pendingchanges
```

Open **Reports -> Pending Changes Tripwire**. Establish a baseline only after a
known, reviewed Apply Config has completed and no prior pending work remains.
Anything outside the displayed coverage contract may not be detected.
