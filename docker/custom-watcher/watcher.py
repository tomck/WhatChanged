import hashlib
import json
import os
import re
import sqlite3
import time
from pathlib import Path

import pymysql

STATE_DIR = Path(os.environ.get('STATE_DIR', '/var/lib/pendingchanges-watcher'))
OUTPUT = STATE_DIR / 'status.json'
BASELINE = STATE_DIR / 'baseline.json'
FEEDBACK = STATE_DIR / 'feedback.jsonl'
FEEDBACK_MAX_EVENTS = int(os.environ.get('FEEDBACK_MAX_EVENTS', '500'))
ROOT = Path(os.environ.get('WATCH_PATH', '/etc/asterisk'))
MODULE_ROOT = Path(os.environ.get('MODULE_PATH', '/var/www/html/admin/modules'))
ASTDB_PATH = Path(os.environ.get('ASTDB_PATH', '/var/lib/asterisk/astdb.sqlite3'))
# AstDB contains both FreePBX configuration-adjacent state and arbitrary
# application/runtime data.  Observe only named FreePBX families; never use a
# broad `database show` scrape as evidence that *everything* changed.
DEFAULT_ASTDB_FAMILIES = ('AMPUSER', 'DEVICE', 'CF', 'CFB', 'CFU', 'CFNA', 'DND', 'CW', 'FOLLOWME', 'BLKVM')
ASTDB_FAMILIES = tuple(
    family.strip() for family in os.environ.get('ASTDB_FAMILIES', ','.join(DEFAULT_ASTDB_FAMILIES)).split(',')
    if re.fullmatch(r'[A-Za-z0-9_]+', family.strip())
)
ASTDB_MAX_ROWS = int(os.environ.get('ASTDB_MAX_ROWS', '10000'))
# This deliberately is an allowlist, not a "scan every table except..."
# policy.  A production PBX can contain multi-gigabyte CDR/CEL or add-on
# tables, and the watcher must never read them just because they exist.
DEFAULT_WATCH_TABLES = (
    'announcement', 'callbacks', 'conferences', 'customappsreg', 'devices',
    'did', 'extension_routes', 'extensions', 'fax_details', 'featurecodes', 'freepbx_settings', 'globals',
    'iax', 'injected', 'ivr_details', 'ivr_entries', 'miscapps', 'miscdests', 'modules',
    # FreePBX 17 uses the singular `outbound_route_sequence` table. Retain
    # the historic plural entry for compatibility with older/restored PBXs,
    # and cover the separate pattern and route-to-trunk records as well.
    'outbound_route_patterns', 'outbound_route_sequence',
    'outbound_route_sequences', 'outbound_route_trunks', 'outbound_routes',
    'parkinglot', 'pjsip',
    'queues_config', 'queues_details', 'queues_members', 'ringgroups', 'sip', 'sipsettings', 'kvstore_Sipsettings',
    'timeconditions', 'timegroups', 'timegroups_details',
    'trunk_dialpatterns', 'trunks', 'userman_users', 'userman_users_settings', 'users', 'zap',
)
WATCH_TABLES = tuple(
    table.strip() for table in os.environ.get('WATCH_TABLES', ','.join(DEFAULT_WATCH_TABLES)).split(',')
    if re.fullmatch(r'[A-Za-z0-9_]+', table.strip())
)
MAX_TABLE_ROWS = int(os.environ.get('MAX_TABLE_ROWS', '5000'))
# A named override permits a configuration table whose shape is understood to
# exceed the conservative general cap.  Keep this explicit: unknown tables
# must never become eligible simply because they are large.
def table_row_limits():
    limits = {}
    for item in os.environ.get('TABLE_ROW_LIMITS', 'sip=20000').split(','):
        name, separator, value = item.partition('=')
        if separator and re.fullmatch(r'[A-Za-z0-9_]+', name.strip()) and value.strip().isdigit():
            limits[name.strip()] = int(value.strip())
    return limits

TABLE_ROW_LIMITS = table_row_limits()
EXCLUDED_MODULES = {'pendingchanges'}
SENSITIVE_FIELD_MARKERS = ('password', 'secret', 'token', 'value_digest', 'pin')
# Some older Core tables lack a declared primary key.  These identifiers are
# stable logical keys used only as a fallback, so updates remain updates rather
# than misleading remove/add pairs.
NATURAL_KEY_FIELDS = ('extension', 'id', 'trunkid', 'route_id', 'account', 'grpnum', 'device', 'user', 'key')
# The legacy `sip.flags` column is an internal display/order ordinal. FreePBX
# rewrites it when an endpoint form is saved even when the option's value is
# unchanged, so including it turns a one-field edit into dozens of false
# updates. It is deliberately excluded as volatile metadata.
VOLATILE_COLUMNS = {
    'sip': {'flags'},
    # FreePBX caches signature-verification details in this blob.  Module
    # enable/disable and version are the reviewable administrative state; the
    # blob is bulky and may be refreshed without an administrator changing a
    # module's activation state.
    'modules': {'signature'},
}
# FreePBX represents an unset outbound-route time group as either SQL NULL or
# 0, depending on whether the route was created or later edited.  Both mean
# "no time group"; canonicalize that presentation detail so a reviewer sees
# the route change they made rather than a spurious companion update.
NULL_EQUIVALENT_ZERO_COLUMNS = {'outbound_routes': {'time_group_id'}}
NON_DIFF_COLUMNS = {'userman_users_settings': {'username'}}
IDENTITY_CONTEXT_FIELDS = (
    'username', 'uid', 'module', 'key', 'modulename', 'extension', 'id',
    'account', 'grpnum', 'device', 'user', 'name', 'description',
)
CONTENT_HASH_CACHE = {}

def change_counts(changes):
    """Return a privacy-preserving change-type summary, never row values."""
    result = {}
    for source, change in sorted(changes.items()):
        counts = {kind: len(change.get(kind, [])) for kind in ('added', 'removed', 'updated')}
        fields = sorted({field for item in change.get('updated', []) for field in item.get('fields', {})})
        if any(counts.values()):
            result[source] = {**counts, 'updated_fields': fields}
    return result

def feedback_summary(observation):
    generated = sum(1 for name in observation['file_drift'] if name.startswith('generated/'))
    modules = sum(1 for name in observation['file_drift'] if name.startswith('module/'))
    return {
        'schema': 1,
        'pending_reload': observation['need_reload'],
        'database': change_counts(observation['database_drift']),
        'astdb': {
            kind: len(observation['astdb_drift'].get(kind, []))
            for kind in ('added', 'removed', 'updated')
        } if observation['astdb_drift'] else {},
        'files': {'generated_count': generated, 'module_count': modules},
        'coverage_limitations': sorted({item.get('reason', 'unknown') for item in observation['coverage_limitations']}),
    }

def append_feedback(observation, previous_signature):
    """Append bounded local alpha telemetry; it is never transmitted by us."""
    summary = feedback_summary(observation)
    has_signal = bool(summary['database'] or summary['astdb'] or any(summary['files'].values()) or summary['coverage_limitations'])
    signature = json.dumps(summary, sort_keys=True, separators=(',', ':'))
    if not has_signal or signature == previous_signature:
        return previous_signature
    event = {'observed_at': observation['observed_at'], **summary}
    existing = FEEDBACK.read_text().splitlines() if FEEDBACK.exists() else []
    existing.append(json.dumps(event, sort_keys=True, separators=(',', ':')))
    FEEDBACK.write_text('\n'.join(existing[-FEEDBACK_MAX_EVENTS:]) + '\n')
    os.chmod(FEEDBACK, 0o600)
    return signature

def content_digest(path):
    """Hash changed file content once; unchanged files are not re-read each poll."""
    stat = path.stat()
    cache_key = str(path)
    fingerprint = (stat.st_mtime_ns, stat.st_size, stat.st_ino)
    cached = CONTENT_HASH_CACHE.get(cache_key)
    if cached and cached[0] == fingerprint:
        return cached[1]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    CONTENT_HASH_CACHE[cache_key] = (fingerprint, digest)
    return digest

def digest_files():
    files = {
        f'generated/{p.name}': content_digest(p)
        for p in sorted(ROOT.glob('*.conf')) if p.is_file()
    }
    # Module Admin changes many files per package. A module-level tree digest
    # keeps the status document compact while still detecting any altered,
    # added, or removed file inside a module. Module-owned files are excluded.
    if MODULE_ROOT.is_dir():
        for module in sorted(MODULE_ROOT.iterdir()):
            if not module.is_dir() or module.name in EXCLUDED_MODULES:
                continue
            digest = hashlib.sha256()
            for path in sorted(module.rglob('*')):
                if path.is_file():
                    digest.update(str(path.relative_to(module)).encode())
                    # Preserve the original module-tree digest format (raw
                    # SHA-256 bytes) so introducing the cache does not make
                    # every existing baseline look like file drift.
                    digest.update(bytes.fromhex(content_digest(path)))
            files[f'module/{module.name}'] = digest.hexdigest()
    return files

def clean(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)

def column(item, name, index):
    """Read either PyMySQL's DictCursor row or a tuple used by unit fakes."""
    return item[name] if isinstance(item, dict) else item[index]

def primary_key(cursor, table):
    # FreePBX kvstore rows have an `id` column that is commonly blank.  Their
    # meaningful identity is the setting key; using the blank id would merge
    # unrelated SIP/PJSIP settings into one false update.
    if table.startswith('kvstore_'):
        cursor.execute(f"SHOW COLUMNS FROM `{table}`")
        columns = {column(item, 'Field', 0) for item in cursor.fetchall()}
        if 'key' in columns:
            return ['key']
    # The numeric row id is an implementation detail.  Using the stable module
    # name makes an enable/disable change read as `parkpro`, not `120`.
    if table == 'modules':
        return ['modulename']
    cursor.execute(f"SHOW KEYS FROM `{table}` WHERE Key_name = 'PRIMARY'")
    fields = sorted(cursor.fetchall(), key=lambda item: column(item, 'Seq_in_index', 3))
    if fields:
        return [column(field, 'Column_name', 4) for field in fields]
    # Several legacy FreePBX tables have no declared primary key even though a
    # stable logical identifier exists. Without this, editing an extension is
    # incorrectly presented as one removal plus one addition.
    cursor.execute(f"SHOW COLUMNS FROM `{table}`")
    columns = {column(item, 'Field', 0) for item in cursor.fetchall()}
    return [field for field in NATURAL_KEY_FIELDS if field in columns][:1]

def row_key(row, fields):
    if fields:
        return '|'.join(str(row.get(field, '')) for field in fields)
    return json.dumps(row, sort_keys=True, separators=(',', ':'))

def snapshot_rows(cursor, table):
    # `sip` is a normal FreePBX configuration table despite its historic
    # name.  Its rows identify an endpoint, option, and option value.  Capture
    # that structure so a review can explain *which* setting changed.  The
    # public status document is redacted below; only the 0600 baseline retains
    # raw values needed for an accurate comparison.
    if table == 'userman_users_settings':
        cursor.execute(
            "SELECT s.*, u.username FROM `userman_users_settings` s "
            "LEFT JOIN `userman_users` u ON u.id = s.uid"
        )
    elif table == 'modules':
        cursor.execute("SELECT * FROM `modules` WHERE `modulename` <> 'pendingchanges'")
    else:
        cursor.execute(f"SELECT * FROM `{table}`")
    volatile = VOLATILE_COLUMNS.get(table, set())
    normalized = []
    zero_columns = NULL_EQUIVALENT_ZERO_COLUMNS.get(table, set())
    for item in cursor.fetchall():
        row = {}
        for key, value in item.items():
            if key in volatile:
                continue
            if table == 'userman_users_settings' and key == 'val' and isinstance(value, (bytes, bytearray)):
                value = value.decode('utf-8', 'replace')
            row[key] = clean(value)
        for key in zero_columns:
            if row.get(key) in (None, 0, '0'):
                row[key] = None
        normalized.append(row)
    return normalized

def database_snapshot():
    connection = pymysql.connect(host=os.environ['DB_HOST'], user=os.environ['DB_USER'], password=os.environ['DB_PASSWORD'], database=os.environ['DB_NAME'], cursorclass=pymysql.cursors.DictCursor)
    with connection.cursor() as cursor:
        cursor.execute("SELECT value FROM admin WHERE variable = 'need_reload'")
        row = cursor.fetchone()
        cursor.execute("SHOW TABLES")
        tables = {column(item, next(iter(item)) if isinstance(item, dict) else '', 0) for item in cursor.fetchall()}
        snapshot = {}
        limitations = []
        for table in WATCH_TABLES:
            if table not in tables:
                continue
            cursor.execute(f"SELECT COUNT(*) AS row_count FROM `{table}`")
            row_count = int(column(cursor.fetchone(), 'row_count', 0))
            row_limit = TABLE_ROW_LIMITS.get(table, MAX_TABLE_ROWS)
            if row_count > row_limit:
                limitations.append({
                    'table': table,
                    'reason': 'table_row_limit' if table in TABLE_ROW_LIMITS else 'row_limit',
                    'rows': row_count,
                    'limit': row_limit,
                })
                continue
            rows = snapshot_rows(cursor, table)
            keys = primary_key(cursor, table)
            snapshot[table] = {'keys': keys, 'rows': {row_key(item, keys): item for item in rows}}
    connection.close()
    value = column(row, 'value', 0) if row else None
    return {'need_reload': bool(value == 'true'), 'tables': snapshot, 'limitations': limitations}

def astdb_snapshot():
    """Capture bounded, named AstDB families without asking Asterisk to mutate state.

    A number of FreePBX settings are written immediately on form submit rather
    than on Apply Config.  AstDB is SQLite on current Asterisk, so opening it
    read-only gives the watcher a separate, explicitly scoped evidence stream.
    """
    if not ASTDB_PATH.is_file():
        return {'keys': ['key'], 'rows': {}, 'limitations': [{'reason': 'astdb_unavailable'}]}
    connection = sqlite3.connect(f'{ASTDB_PATH.resolve().as_uri()}?mode=ro', uri=True)
    try:
        clauses = ' OR '.join('key LIKE ?' for _ in ASTDB_FAMILIES)
        if not clauses:
            return {'keys': ['key'], 'rows': {}, 'limitations': [{'reason': 'astdb_no_families'}]}
        rows = connection.execute(
            f'SELECT key, value FROM astdb WHERE {clauses} ORDER BY key LIMIT ?',
            tuple(f'/{family}/%' for family in ASTDB_FAMILIES) + (ASTDB_MAX_ROWS + 1,),
        ).fetchall()
    except sqlite3.Error as error:
        return {'keys': ['key'], 'rows': {}, 'limitations': [{'reason': 'astdb_read_error', 'detail': str(error)}]}
    finally:
        connection.close()
    if len(rows) > ASTDB_MAX_ROWS:
        return {
            'keys': ['key'], 'rows': {},
            'limitations': [{'reason': 'astdb_row_limit', 'rows': len(rows) - 1, 'limit': ASTDB_MAX_ROWS}],
        }
    values = {key: {'key': key, 'value': value} for key, value in rows}
    return {'keys': ['key'], 'rows': values, 'limitations': []}

def sensitive_field(field, row=None):
    name = field.lower()
    if any(marker in name for marker in SENSITIVE_FIELD_MARKERS):
        return True
    # Avoid treating innocent field names such as `keyword` as a secret while
    # still protecting conventional API/private-key columns.
    if name.endswith('_key') or name.startswith('key_'):
        return True
    # FreePBX's endpoint-option schema places the sensitive option name in
    # `keyword` and its material in `data`.
    if name == 'data' and row:
        option = str(row.get('keyword', '')).lower()
        return any(marker in option for marker in SENSITIVE_FIELD_MARKERS) or option == 'key' or option.endswith('_key')
    # The FreePBX settings table stores the setting name separately from its
    # value.  Preserve ordinary setting values (so a breaker is reviewable),
    # but do not disclose a password/token setting merely because its column
    # is generically named `value`.
    if name in ('value', 'val') and row:
        setting = '{} {}'.format(row.get('module', ''), row.get('keyword', row.get('key', ''))).lower()
        return any(marker in setting for marker in SENSITIVE_FIELD_MARKERS) or setting == 'key' or setting.endswith('_key')
    return False

def redact(field, value, row=None):
    return '[redacted]' if sensitive_field(field, row) else value

def redact_row(row):
    return {field: redact(field, value, row) for field, value in row.items()}

def database_diff(before, after):
    diff = {}
    for table in sorted(set(before).union(after)):
        old_rows = before.get(table, {'rows': {}})['rows']
        new_rows = after.get(table, {'rows': {}})['rows']
        # `status.json` is intentionally readable by the FreePBX web user;
        # never publish raw credentials from the private baseline there.
        added = [redact_row(new_rows[key]) for key in new_rows.keys() - old_rows.keys()]
        removed = [redact_row(old_rows[key]) for key in old_rows.keys() - new_rows.keys()]
        updated = []
        for key in old_rows.keys() & new_rows.keys():
            ignored = NON_DIFF_COLUMNS.get(table, set())
            changed = {field: {'before': redact(field, old_rows[key].get(field), old_rows[key]), 'after': redact(field, new_rows[key].get(field), new_rows[key])}
                       for field in old_rows[key].keys() | new_rows[key].keys()
                       if field not in ignored and old_rows[key].get(field) != new_rows[key].get(field)}
            if changed:
                identity = {
                    field: redact(field, new_rows[key].get(field), new_rows[key])
                    for field in IDENTITY_CONTEXT_FIELDS
                    if field in new_rows[key] and new_rows[key].get(field) not in (None, '')
                }
                entry = {'key': key, 'fields': changed}
                if identity:
                    entry['identity'] = identity
                updated.append(entry)
        if added or removed or updated:
            diff[table] = {'added': added, 'removed': removed, 'updated': updated}
    return diff

def without_module_owned_rows(tables):
    """Remove this observer's module row from old and new snapshot formats.

    Older baselines may contain the row because module-table coverage predates
    this exclusion. Filtering both sides prevents an observer upgrade from
    appearing as an administrator's pending PBX change.
    """
    filtered = dict(tables)
    modules = tables.get('modules')
    if modules:
        rows = {
            key: row for key, row in modules.get('rows', {}).items()
            if row.get('modulename') not in EXCLUDED_MODULES
        }
        filtered['modules'] = {**modules, 'rows': rows}
    return filtered

def astdb_diff(before, after):
    return database_diff({'astdb': before}, {'astdb': after}).get('astdb', {})

def file_diff(before, after):
    return {name: {'before': before.get(name), 'after': after.get(name)}
            for name in sorted(set(before).union(after)) if before.get(name) != after.get(name)}

def comparable_tables(baseline, current, scope_changed, pending_reload):
    """Avoid calling newly enabled coverage a pending administrator change.

    A watcher upgrade may add tables while FreePBX already has Apply Config
    pending.  Those rows have no old baseline, so a normal comparison would
    misleadingly show the entire existing table as newly added.  Keep the
    proven old scope comparable until the pending work is applied; the next
    clean baseline then begins coverage for the new tables.
    """
    if not (scope_changed and pending_reload):
        return baseline, current, []
    shared = set(baseline).intersection(current)
    added_coverage = sorted(set(current).difference(baseline))
    return (
        {table: baseline[table] for table in shared},
        {table: current[table] for table in shared},
        added_coverage,
    )

def publish(payload):
    # The polling service may be joined by a one-shot diagnostic invocation.
    # A shared `status.tmp` name lets one writer rename the other writer's
    # temporary file away, crashing the loser. PID-scoped siblings retain the
    # atomic-replace property without that collision.
    temporary = OUTPUT.with_name(f'.{OUTPUT.name}.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(payload, sort_keys=True))
    os.chmod(temporary, 0o644)
    temporary.replace(OUTPUT)

def save_baseline(state):
    BASELINE.write_text(json.dumps(state, sort_keys=True))
    # Baselines include raw configuration values; only the watcher service
    # account may read them. The separate status document is redacted.
    os.chmod(BASELINE, 0o600)

def main():
    previous_reload = None
    previous_feedback_signature = None
    while True:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        database = database_snapshot()
        astdb = astdb_snapshot()
        # A baseline created under a different scope cannot be compared
        # honestly: switching from the pre-0.1 broad scan to the bounded
        # allowlist would otherwise look like hundreds of removals.  Replace
        # such a baseline only while FreePBX is clean.
        scope = {
            'watch_tables': list(WATCH_TABLES),
            'max_table_rows': MAX_TABLE_ROWS,
            'table_row_limits': TABLE_ROW_LIMITS,
            'astdb_families': list(ASTDB_FAMILIES),
            'astdb_max_rows': ASTDB_MAX_ROWS,
        }
        state = {'scope': scope, 'tables': database['tables'], 'astdb': astdb, 'files': digest_files()}
        existing = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
        if not BASELINE.exists() and not database['need_reload']:
            save_baseline(state)
        elif existing and existing.get('scope') != scope and not database['need_reload']:
            save_baseline(state)
        elif previous_reload and not database['need_reload']:
            save_baseline(state)
        baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
        scope_changed = bool(baseline and baseline.get('scope') != scope)
        if baseline:
            before_tables, after_tables, deferred_coverage = comparable_tables(
                baseline['tables'], state['tables'], scope_changed, database['need_reload'])
            database_drift = database_diff(
                without_module_owned_rows(before_tables),
                without_module_owned_rows(after_tables),
            )
            astdb_deferred = scope_changed and database['need_reload'] and 'astdb' not in baseline
            astdb_drift = {} if astdb_deferred else astdb_diff(baseline.get('astdb', {'keys': ['key'], 'rows': {}}), astdb)
        else:
            deferred_coverage = []
            database_drift = {}
            astdb_deferred = False
            astdb_drift = {}
        file_drift = file_diff(baseline['files'], state['files']) if baseline else {}
        has_drift = bool(database_drift or astdb_drift or file_drift)
        limitations = list(database['limitations']) + list(astdb['limitations'])
        if deferred_coverage:
            limitations.append({
                'reason': 'scope_expanded_while_pending',
                'tables': deferred_coverage,
            })
        if astdb_deferred:
            limitations.append({'reason': 'astdb_scope_expanded_while_pending', 'families': list(ASTDB_FAMILIES)})
        observation = {
            'observed_at': int(time.time()),
            'need_reload': database['need_reload'],
            'baseline_available': baseline is not None,
            'baseline_captured_at': int(BASELINE.stat().st_mtime) if baseline else None,
            'database_drift': database_drift,
            'astdb_drift': astdb_drift,
            'file_drift': file_drift,
            'coverage_limitations': limitations,
            'coverage': {
                'database_tables': list(WATCH_TABLES),
                'database_exclusions': ['modules.modulename=pendingchanges'],
                'astdb_families': list(ASTDB_FAMILIES),
                'generated_files': '/etc/asterisk/*.conf',
                'module_tree_digests': 'all modules except pendingchanges',
            },
            'message': 'Reload requested; origin unavailable.' if database['need_reload'] and not has_drift else
                       ('Configuration drift detected since the applied baseline.' if database['need_reload'] else
                        ('Immediate Asterisk state drift detected; it may already be effective.' if astdb_drift else 'No pending reload.')),
        }
        # A smoke driver or administrator may Apply Config as soon as the
        # published status shows pending drift. Record that transition in
        # process memory before publishing, so a fast apply cannot clear the
        # flag between the atomic status write and this assignment and leave
        # the just-applied state compared against the old baseline.
        previous_reload = database['need_reload']
        publish(observation)
        previous_feedback_signature = append_feedback(observation, previous_feedback_signature)
        time.sleep(5)

if __name__ == '__main__':
    main()
