# Pending Changes Tripwire 17.0.2.6

This alpha candidate retains the readable change report from 17.0.2.5 and
corrects two health-check issues:

- The redaction-key doctor now sees permission repairs or regressions made
  during the same PHP process rather than reusing cached filesystem metadata.
- The FreePBX BMO adapter exposes redaction-key health to the CLI doctor,
  avoiding a missing-class error.

One module archive supports FreePBX 14–17 and includes watcher 0.1.9. The
watcher payload is unchanged. The observer does not Apply Config and does not
claim to detect changes outside its explicit coverage contract.

The source has passed the disposable Apache, nginx/PHP-FPM, legacy PHP, and
real-image compatibility gates. Publication requires signing and validation
of the exact resulting archive.
