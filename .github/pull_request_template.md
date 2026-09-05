## Summary

## Coverage and privacy impact

- [ ] The observer remains read-only and never applies, reloads, or reverts PBX configuration.
- [ ] Any new source is explicitly listed, bounded, redacted, and covered by add/update/remove and post-apply tests.
- [ ] No production PBX data, credentials, call records, private keys, or configuration archives are included.
- [ ] PHP 5.6 and Python 3.6 compatibility is preserved, or the compatibility change is documented.

## Validation

- [ ] `./docker/legacy-compatibility-gate.sh`
- [ ] `./docker/lab-gate.sh` when FreePBX 17 behavior changes
- [ ] `./docker/legacy-real-image-gate.sh` when legacy lifecycle behavior changes
