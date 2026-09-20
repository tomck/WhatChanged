# MUSE-REVIEW.md — WhatChanges / Pending Changes Tripwire (self-review)

> Local review doc for AI-assisted work (Codex, Sol/Luna and friends).
> Written against `main` @ `31856b5` (module 17.0.2.5, watcher 0.1.9).
> Replaces an earlier review written against the stale 17.0.0.11 checkout —
> most of that is resolved upstream (kvstore baseline, PathResolver,
> functions.inc.php removal, views/, PSR-4, AMPDBSOCK, nginx).
> Untracked local note: not pushed. License: GPL-3.0-or-later (stay GPL — §7).

## 0. What this module is (one paragraph for a fresh AI)

`pendingchanges` answers "what will Apply Changes do?" FreePBX stores the
banner as a single `admin.need_reload='true'` with no who/what. This module
compares current config vs. **one clean baseline captured after a known-good
Apply** and reports added/removed/updated DB records + generated-file hashes +
module release markers + immediate-state AstDB families + value-free request
breadcrumbs (`likely`/`possible`/`unavailable`/`none`). It is deliberately
read-only: never reloads Asterisk, never `fwconsole reload`, never mutates
FreePBX config. Clean means "no drift **in explicitly listed coverage**", not
proof nothing changed. Entry points are thin: `Pendingchanges.class.php` (BMO
adapter → `PendingChangesService`) and `page.pendingchanges.php` (→
`Presentation\PageController::render`). Logic lives in `src/` (PSR-4 via
`autoload.php`, PHP 5.6 floor for the unified 14–17 archive); observer is
`docker/custom-watcher/watcher.py` (systemd) + request sensor
(`deploy/what-changed-request-audit.php` via `auto_prepend_file`, Apache +
php-fpm/nginx). Install: `install.sh` (trust-and-run signed tgz) +
`bin/install-watcher` (root, explicit).

## 1. Strengths to preserve (don't regress these)

1. **Read-only posture is the product.** No dialplan/AGI/AMI/ARI/reload hooks;
   `seedBaseline()` throws while pending; watcher installer stays an explicit
   root action (correctly — the GUI can't/shouldn't create DB accounts +
   systemd units + PHP sensors). Every new feature must pass "can this mutate
   PBX state?" If yes, off-by-default or not at all.
2. **Allowlist + row caps.** Watcher `DEFAULT_WATCH_TABLES` (~44) + BMO
   `WATCH_TABLES` (~33); general cap 5000, `sip` 20000, AstDB 10000.
   CDR/CEL/queue-log/add-ons never eligible. Keep it that way.
3. **Honest attribution.** `likely (1 actor) / possible (>1) / unavailable /
   none` + mandatory caveat "correlation, not proof". Never upgrade a guess.
4. **Privacy split + HMAC redaction.** Raw values never persist in cleartext:
   `Redactor` + watcher secret-regex with semantic name matching, install-keyed
   `HMAC-SHA256` → `[protected hmac-sha256:…]` pre-persistence, public
   `[redacted]` only; protected→protected comparison avoids permanent
   redacted-drift (AstDB `AMPUSER` fix, 17.0.1.5). `0600` state vs `0644`
   status vs `0640` attribution log; feedback ledger counts/field-names only
   (≤500 events, manual export). Keep the ladder.
5. **Scope-expansion + provenance guards.** `comparable_tables` defers new
   tables while pending; `baseline_provenance: trusted|uncertain|degraded`
   with `scope_expanded_while_pending` deferral and `runtime.json` interruption
   recovery; fail-closed (`data_current:false` → never "all clear"). Self-row,
   signature blob, `sip.flags`, `time_group_id NULL↔0` filters kill noise.
6. **Cheap file signal by design.** `generated/*.conf` hashes + per-module
   `module.xml`/`module.sig` markers (not recursive trees) — exhaustive
   integrity left to FreePBX's signature verifier. Don't re-expand without a
   cost budget (see §3.1).
7. **Reproducible lab + signed releases + contributor rails.** Disposable
   Debian-12 lab, breaker/smoke matrix, real-image 14/15/16 gates, nginx gate,
   offline signing, `AGENTS.md` boundaries.

## 2. High priority — correctness / trust

### 2.1 Fallback BMO table list is narrower than the watcher's (own 33-vs-36-class skew)
- Files: `Pendingchanges.class.php:16ff` (`WATCH_TABLES` ~33) vs
  `docker/custom-watcher/watcher.py:49ff` (`DEFAULT_WATCH_TABLES` ~44, adds
  `incoming`, `freepbx_settings`, `outbound_route_patterns`,
  `outbound_route_sequence(s)`, `outbound_route_trunks`, `sipsettings`,
  `kvstore_Sipsettings`).
- We filed exactly this class of bug against UAL (their `pjsip` skew); we have
  our own instance. A watcher-less pilot silently misses inbound routes, all
  FreePBX settings, and route pattern/trunk mapping — then reports clean.
- Fix: single source of truth for the table list shared by BMO fallback and
  watcher config generation (watcher already receives env-generated config
  from `bin/install-watcher` — extend that channel), or at minimum a parity
  test (`test_watcher.py`-style) asserting fallback ⊆ watcher with the delta
  documented in the coverage contract. `frameworkStatus()` already labels
  `provenance: degraded/framework_only_fallback` — extend the label to name
  the missing tables.
- Acceptance: parity test green; fallback UI names its blind tables.

### 2.2 HMAC redaction key is now a load-bearing secret asset — key lifecycle needed
- Files: `src/Security/Redactor.php`, key at
  `$ASTVARLIB/pendingchanges-redaction.key` (`0600`).
- New questions since HMAC landed: key loss → baseline uninterpretable (fail
  loudly, never silently clean)? Key rotation → re-baseline required (document
  + `doctor` check)? Key included in backups (then backups are secret-bearing
  — say so in `production-pilot.md` / README)?
- Fix: `bin/pendingchanges doctor` already reports watcher health — add
  key-present/readable + algorithm-match checks; document rotation =
  rotate-then-`seed` after clean Apply; state backup secrecy explicitly.
- Acceptance: lost-key and rotated-key lab scenarios produce loud, correct
  messages — no silent "no drift".

### 2.3 Baseline storage migrated, watcher state still outside backup
- Done: `src/Baseline/BaselineRepository.php` (`get/save/delete/migrateLegacy`
  on kvstore key, legacy one-row table auto-migrated then dropped). Framework
  baseline now rides module backup if included.
- Remaining: watcher `baseline.json/runtime.json/status.json/feedback.jsonl/
  redaction.key/requests.jsonl` under `/var/lib/…` are outside FreePBX Backup;
  uninstall deliberately retains env+evidence+SELECT-only account (good —
  evidence preservation; keep saying so in UI).
- Fix: document the split (what survives uninstall/reinstall, what a restore
  does/doesn't bring back); consider a `doctor`-level "export evidence bundle"
  for migrations. No silent expectations.
- Acceptance: restore-to-fresh-host procedure documented + lab-tested once.

## 3. Medium — signal quality (all deliberate tradeoffs; sharpen, don't undo)

### 3.1 File signal is marker-only — per-file names need a privacy-preserving design if ever wanted
- `src/Snapshot/FileSnapshotter.php:34` + `watcher.py:297`: per-module
  `sha256(module.xml+module.sig)`. Reviewer learns "module X released/changed"
  but not which file; generated confs hash-only, no diff view.
- This replaced recursive hashing deliberately (cost + signature duplication).
  If triage ever needs more: store per-file hashes in the `0600` baseline,
  report changed *relative paths* only in `0644` status — never contents.
  Generated confs: bounded redacted unified diff (N lines, cap output).
- Acceptance (if built): pending module change names file(s); no contents in
  `0644`; lab cost budget unchanged.

### 3.2 Staleness is labeled — keep the label next to the verdict
- Polling (`PROBE 5s / FULL 30s / MODULE 300s`), `HealthClassifier`
  (`healthy≤max(15,3×expected)`, `delayed`, `stale`), `PayloadInspector`
  (embedded-VERSION vs installed → `payload_outdated|newer`, full-path remedy).
  `watcher_observed_at` + `doctor sensor_configured/sensor_loaded` exist.
- Risk is UI drift over time: a redesign could strand the verdict away from
  its staleness + provenance caveats. Keep verdict/staleness/provenance as one
  visual unit (Luna's 17.0.2.5 presenter work is the right direction —
  `ChangePresenter::tableLabel/identity/fieldRows` + `views/partials/change.php`
  before/after tables; extend the same care to the banner).
- Acceptance: every "clean/pending" verdict renders with observed-at +
  provenance in the same card.

### 3.3 AstDB labeling + inbound/DID coverage are right — hold the line
- Families stay `AMPUSER,DEVICE,CF,CFB,CFU,CFNA,DND,CW,FOLLOWME,BLKVM` as
  **Immediate Asterisk state** (may already be effective, never "pending").
  17.0.2.3 added `incoming:(cidnum,extension)` + DID lifecycle fixtures.
- Any new family/table inherits the immediate-vs-pending label with it. UAL's
  full-snapshot AstDB diff is the opposite philosophy (audit everything) —
  keep the difference explicit so cross-comparisons don't read ours as
  "missing".

## 4. Medium — borrow from UAL (ideas, not code; stay GPL)

> License guardrail: UAL is AGPL-3.0, we are GPL-3.0-or-later. GPL→AGPL flows
> (they can adopt from us); AGPL→GPL does not (we can't vendor their code and
> stay GPL-only). Reimplement concepts independently; interop at
> links/conventions. Our Scunthorpe-anchored semantic redactor + digest
> convention is the thing to offer them (filed as their #5), not the reverse.

1. **Bookmarks-with-notes (per-user).** Report is ephemeral per pending window;
   reviewers want "ringgroup X — asked Alice, legit". Spec: per-user notes
   keyed by (baseline_id, table, row_key), references + free text only, never
   values.
2. **Bounded redacted export.** Same redactor, CSV/JSON of drift for change
   tickets; cap like feedback (500 events).
3. **`doctor` is good — add `watch`/`stats`.** `bin/pendingchanges` now covers
   health; a poll-and-render `watch` + `stats` (coverage tables, caps hit,
   limitations count) aids pilots.
4. **Settings self-audit from day one.** No settings today beyond env; first
   knob added gets feedback-ledger logging with before/after.
5. **Trend-from-feedback-ledger.** Pending-window frequency/duration from
   counts only — cheap, no privacy cost.
6. **What NOT to borrow:** journald collection (leave to audit-log modules),
   heavy `SELECT *` list queries (caps-first for a reason), unconfirmed purges
   (we don't purge — keep it).

## 5. Low — ops notes (mostly resolved; leftovers)

- Remote-DB: service disabled pending manual credential — correct; keep the
  failure loud with copy-paste grant instructions.
- Portable/SNG7 + legacy 14/15: best-effort, gates green on real images; keep
  calling 17 the supported target.
- ACL: `FREEPBX_IS_AUTH` + Reports menu only. Design-acceptable while §2.2
  holds (redacted-means-safe); revisit if raw-value display is ever added.
- Monolithic commits (raised by miken32, still partially true upstream):
  prefer small commits per concern so PBX admins can review what they install.

## 6. Interop (mirror of filed UAL issues)

- **pendingchanges → UAL:** "View audit trail for this window" deep-link with
  `[baseline_captured_at, now)` once UAL publishes a stable GET filter
  convention.
- **UAL → pendingchanges:** their DB-detail modal links "Compare against
  applied baseline" when `$freepbx->Pendingchanges` exists. Guarded, no hard
  dependency.

## 7. Licensing (decision, don't churn)

Stay **GPL-3.0-or-later**. FreePBX-norm adoption, no hosted-pilot friction,
asymmetry favors us. Revisit only to vendor AGPL code verbatim (combined work
goes AGPL, network-copyleft included) or if Affero becomes a goal.
Ideas/procedures aren't copyrightable (102(b); merger/scènes à faire for
forced FreePBX patterns) — independent reimplementation + "inspired by" credit
in commit messages is the posture. Private-repo access is look-don't-lift for
code.

## 8. Suggested next actions (ordered)

1. §2.1 fallback/watcher parity test + label (kills our own 33-vs-44 skew).
2. §2.2 key lifecycle: `doctor` checks + rotation/re-loss docs + backup secrecy note.
3. §2.3 restore-to-fresh-host runbook, lab-tested once.
4. §3.2 banner unit (verdict + observed-at + provenance, following the
   ChangePresenter pattern).
5. §4.1–4.2 bookmarks spec + bounded export (pilot UX).
6. §6 links once UAL publishes.

---
*Prepared by Muse Spark review pass; verify file:line refs against `main`
before acting — tree moves fast during alpha.*
