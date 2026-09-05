# Security policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately with a
[GitHub Security Advisory](https://github.com/tomck/WhatChanged/security/advisories/new).
Do not open a public issue for a vulnerability before coordinated disclosure.

Never include PBX credentials, private keys, configuration archives, database
dumps, call records, customer identifiers, session cookies, or unredacted
production screenshots. A minimal synthetic reproduction is preferred.

## Supported versions

Only the newest public-alpha module and watcher releases receive security
fixes. FreePBX 14, 15, and 16 packages are compatibility candidates for
voluntary testing on backed-up, noncritical systems; their underlying platforms
may have unrelated end-of-life risks.

## Security boundary

WhatChanged is a read-only, bounded observer. It does not Apply Config, reload
Asterisk, or revert PBX state. Its explicit Coverage contract is the security
boundary: an empty report means no difference was found in the named sources,
not that every FreePBX or third-party state store is unchanged. Administrator
request correlation is investigative evidence, not proof of causation.
