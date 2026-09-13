# Pending Changes Tripwire 17.0.1.5 alpha

This maintenance alpha makes the embedded watcher's Apache installation and
health-check output less ambiguous.

The attribution-sensor installer now labels `apachectl configtest` as a check
of the host's complete Apache configuration. Existing virtual hosts or modules
may print warnings during that check. WhatChanged does not create or modify
Apache `DocumentRoot` directives, and Apache is not reloaded if validation
fails.

The command-line doctor now distinguishes sensor configuration from runtime
loading. It reports `sensor_configured=yes` only when the Apache PHP
configuration points to a readable sensor file and reports
`sensor_loaded=not_applicable_cli`, because PHP CLI cannot prove that Apache
loaded the sensor. The FreePBX Reports page remains the authoritative runtime
check.

Installation and feedback commands now resolve the command-line utility from
FreePBX's configured `AMPWEBROOT`. They no longer depend on a convenience
symlink that existed only in the development Docker image.

The watcher now compares protected AstDB snapshots consistently. Unchanged
sensitive entries such as AMPUSER passwords no longer appear as permanent
redacted-to-redacted changes after Apply Config. The report also provides one
button to expand or collapse all evidence panels.

A successful authenticated Apply Config breadcrumb can now refresh the applied
baseline even when FreePBX's global reload flag turns on and off between two
watcher scans.

The shared module archive supports FreePBX 14, 15, 16, and 17. The embedded
watcher is version 0.1.4. WhatChanged remains a bounded, read-only observer; it
does not Apply Config, reload Asterisk, or claim universal coverage.
