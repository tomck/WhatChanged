# Contributing

Thank you for helping improve WhatChanged.

- Develop and test only in the disposable Docker labs. Never submit production
  PBX data, credentials, extensions, trunks, call records, or configuration
  archives.
- Keep the module and watcher read-only. They must never Apply Config, reload
  Asterisk, or automatically revert a setting.
- Add new sources to the explicit Coverage contract, bound their size, redact
  secret-looking fields, and include a fixture that proves add/update/remove
  behavior plus a clean post-apply baseline.
- Preserve PHP 5.6 syntax for FreePBX 14/15 candidates and Python 3.6 syntax for
  the portable watcher unless the compatibility policy is deliberately raised.
- Run `./docker/legacy-compatibility-gate.sh` for every change. FreePBX 17 work
  should also pass `./docker/lab-gate.sh`; legacy lifecycle changes should pass
  `./docker/legacy-real-image-gate.sh`.

Use synthetic identifiers in bug reports. Coverage gaps are welcome, but a
clean report will never be advertised as universal detection.
