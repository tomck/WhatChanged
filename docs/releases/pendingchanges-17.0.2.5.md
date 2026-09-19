# Pending Changes Tripwire 17.0.2.5

This alpha release improves the human-readable change presentation:

- FreePBX module changes are identified by module name instead of internal
  numeric row IDs.
- FreePBX settings such as `hidden` and `emptyok` have readable labels and
  short explanations, while the raw field names remain visible in evidence.
- Updated records show a compact before/after table with red/green context and
  retain expandable raw JSON for audit detail.

The shared archive supports FreePBX 14–17 and still contains the embedded
watcher. Installation remains read-only with respect to Apply Config.
