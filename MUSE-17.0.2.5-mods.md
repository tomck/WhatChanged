# MUSE-17.0.2.5-mods — what Muse Spark changed on top of 17.0.2.5 and why

> For Sol (post-22nd reset): this is the handoff. Base is `main` @ `31856b5`
> (module 17.0.2.5, watcher 0.1.9). One local commit, **not pushed** (AGENTS.md
> forbids push/tag/publish without explicit user auth). Everything below is
> from `MUSE-REVIEW.md` §8 items 1–4; items 5–6 (bookmarks spec, bounded
> export, UAL interop links) are untouched by design — they need product
> decisions first.

## 1. Fallback/watcher table parity (§2.1 — the high-priority one)

**Why:** the BMO fallback list (36 tables) silently omits 7 tables the watcher
covers (`incoming`, `freepbx_settings`, `outbound_route_patterns`,
`outbound_route_sequence`, `outbound_route_trunks`, `sipsettings`,
`kvstore_Sipsettings`). A watcher-less pilot could report clean while missing
inbound routes and all FreePBX settings. Same bug class as UAL's `pjsip` skew
(their #1) — embarrassing to file it against them and keep our own.

**What:**
- `src/Service/PendingChangesService.php`: new
  `FRAMEWORK_FALLBACK_UNCOVERED_TABLES` const (the 7, documented as the
  fallback↔watcher delta) + `frameworkStatus()` coverage now publishes
  `framework_fallback_uncovered_tables`. The Reports page renders the coverage
  array as JSON already (`views/page.php` coverage contract), so the blind
  tables are visible with zero template changes. Verdict messages untouched.
- `docker/test-table-parity.php` (new, PHP 5.6-safe): parses WATCH_TABLES from
  the packaged `Pendingchanges.class.php`, the const from the packaged
  service, and DEFAULT_WATCH_TABLES from the packaged `watcher/watcher.py`;
  asserts fallback ⊆ watcher and computed delta == const. Fails closed with
  the exact drift named.
- `docker/legacy-compatibility-gate.sh`: runs the parity script inside the
  existing per-target php-cli loop against each target's extracted archive
  (plus `php -l` already covers the new file). No new dependencies — php
  containers only.

**Verified:** `php test-table-parity.php . docker/custom-watcher/watcher.py`
→ `fallback 36 tables, watcher 43 tables, 7 documented gaps`; negative test
with an injected `sneaky_new_table` fails exit 1 naming the drift.
Full gate (`lab-gate.sh`, real-image gates) NOT run here — needs Docker;
please run before release per AGENTS.md.

## 2. Redaction key lifecycle (§2.2)

**Why:** the HMAC key became a secret asset with no documented loss/rotation
story and no `doctor` visibility. Loss isn't exposure (one-way fingerprints)
but breaks comparability (every protected field diffs once against the new
key); an unreadable/corrupt key breaks snapshots loudly at the worst time.

**What:**
- `src/Security/Redactor.php`: new read-only `keyStatus()` —
  `ok|absent|unreadable|invalid|insecure`, each with path/detail/remedy.
  Strictly side-effect free (never creates/rotates; absence = "created on
  next snapshot"). The `unreadable` state can't be simulated as root, noted
  in the test comment.
- `src/Service/PendingChangesService.php`: keeps one shared `Redactor`
  (`$this->redactor`) + `redactionKeyStatus()` passthrough.
- `bin/pendingchanges doctor`: prints `redaction_key_state/path/detail` and
  `redaction_key_remedy` when actionable; `invalid`/`unreadable` force exit 2
  (same fail-closed convention as untrusted provenance). `absent`/`insecure`
  don't change the exit code beyond existing logic.
- `docker/test-framework-fallback.php`: key lifecycle assertions
  (absent→ok→insecure→invalid+remedy) using a pid-scoped tmpdir; passes
  locally (`framework fallback security checks passed`).
- Docs: `docs/production-pilot.md` gained "Redaction key lifecycle"
  (location/perms/auto-creation, doctor states, loss≠exposure + rotate-then-
  reseed procedure, backup secrecy re offline guess-testing) and "Backup,
  restore, and reinstall" (kvstore rides module backup; watcher state dir +
  key + env are outside FreePBX Backup — back up `pendingchanges-*` + key or
  plan re-seed; post-restore `doctor` + continuity bar; uninstall retention
  is deliberate). `docs/alpha-install.md` documents the new doctor lines.

## 3. Restore runbook + banner check (§2.3, §3.2)

- Restore coverage is the pilot-doc section above (§2, last bullet).
- Banner (§3.2) needed **no code**: `views/page.php` already renders verdict
  + Observer/observation-age/Coverage/Baseline/sensor/payload as one health
  card with degraded-state alerts (your 17.0.2.5 presenter work covered it).
  Verified by inspection only.

## 4. Deliberately not touched

- No version bumps (module 17.0.2.5, watcher 0.1.9 unchanged — release flow
  owns that; AGENTS.md: don't bump watcher for module-only changes, and this
  commit changes no watcher payload/protocol/behavior).
- No CHANGELOG entry (convention is per-release sections; fold these notes
  into the next one).
- No watcher.py changes, no DDL, no new permissions, no framework patching.
- PHP stays 5.6-safe (`array()`, no `??`/scalars/arrows); new gate script
  runs in the 5.6 container too. `composer lint:style` not run (no
  `vendor/` here); new code follows the checked-in PSR-12 by hand — please
  run lint in the lab.
- `test_watcher.py` untouched (no Python changes).

## 5. Commit attribution (please read)

AGENTS.md says Codex commits must use `scripts/codex-commit.sh` so the hook
adds `Co-authored-by: Codex` + `Codex-Model` trailers. I am **not** Codex —
I'm Muse Spark (`opencode-go/muse-spark-1.3-contributor`) — so the wrapper
would have misattributed the work to Codex. I committed with plain
`git commit` (hook exits 0, untouched) plus a manual trailer in the forum's
`Assisted-by: AGENT:MODEL` format:

```
Assisted-by: Muse-Spark:muse-spark-1.3-contributor
```

If the repo standardizes on the hook for all agents, the hook needs an
agent-agnostic path (e.g. accept `CODEX_COMMIT_MODEL` values outside
`gpt-*` and derive the `Co-authored-by` name from the agent). Until then,
manual `Assisted-by` is the honest option for non-Codex models. Luna's
recent commits (`a3ae2a9`, `ac3f38e`, `31856b5`) carry no trailers at all —
may want to confirm that's intentional before any official-repo submission.

## 6. Suggested next (for you, not done)

1. Run `lab-gate.sh` + `legacy-compatibility-gate.sh` + `nginx-lab-gate.sh`
   (Docker) — my verification was workstation-only (`php -l`, both gate
   scripts directly, negative parity test).
2. `composer lint:style` once vendored.
3. Fold §1–2 into CHANGELOG on next release; decide watcher bump (recommmend:
   none — no payload change).
4. Still open from the review: bookmarks-with-notes spec, bounded redacted
   export, UAL deep-links once they publish.

## 7. Official review mascots (ratified by user request)

```
 .--.      .--.
 |🧠|  ->  SOL: "The plan is simple: full test-matrix
 |  |      coverage before we seize the PBX."
 .--.      .--.
 |👀|  ->  LUNA: "Narf! I committed straight to main!"
 .--.
```

Narf.
