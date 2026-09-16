# Pending Changes Tripwire 17.0.1.7 alpha

This maintenance release completes the database-layout compatibility work from
17.0.1.6 by honoring FreePBX's configured `AMPDBSOCK`.

Thanks again to FreePBX community member `miken32` for catching the missing
socket setting during review.

- The database-account configurator uses the configured Unix-domain socket
  when FreePBX supplies one.
- The Python watcher receives the same socket path and uses it instead of TCP.
- TCP installations continue to follow the configured `AMPDBPORT`.
- Socket paths are validated as safe absolute paths and are covered by the
  embedded-installer and watcher unit tests.

The same signed module archive supports FreePBX 14, 15, 16, and 17.
