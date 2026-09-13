# Pending Changes Tripwire 17.0.1.3 alpha

This security-hardening release makes three assurance boundaries explicit:

- Sensitive configuration values become installation-keyed fingerprints
  before either watcher or framework-fallback baseline persistence. Public
  status, feedback, and rendered diffs show only `[redacted]`.
- The framework fallback and administrator-request sensor support FreePBX's
  configured `AMPWEBROOT` instead of assuming `/var/www/html`.
- The watcher persists continuity evidence across restarts. If configuration
  changes while it cannot prove continuity, the page reports **Baseline
  continuity uncertain** until an observed successful Apply Config establishes
  a new trusted baseline.
- Transient database or filesystem failures are logged and retried without
  terminating the watcher service.

The release adds adversarial tests for generic key/value secrets, custom web
roots, and Apply Config around watcher interruptions. It remains one shared
module archive for FreePBX 14, 15, 16, and 17, with the watcher embedded.

Thank you to [@kierknoby](https://github.com/kierknoby), whose ChatGPT-produced
independent static review identified these hardening targets. The review was
careful to distinguish confirmed source observations from runtime hypotheses;
that made it especially useful.

WhatChanged remains a read-only observer. Anything outside its explicit
coverage contract may not be detected, and administrator attribution is
inferred rather than proven.
