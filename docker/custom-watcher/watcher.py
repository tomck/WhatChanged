import hashlib
import json
import os
import re
import time
from pathlib import Path

import pymysql

STATE_DIR = Path(os.environ.get('STATE_DIR', '/var/lib/pendingchanges-watcher'))
OUTPUT = STATE_DIR / 'status.json'
BASELINE = STATE_DIR / 'baseline.json'
ROOT = Path(os.environ.get('WATCH_PATH', '/etc/asterisk'))
MODULE_ROOT = Path(os.environ.get('MODULE_PATH', '/var/www/html/admin/modules'))
# This deliberately is an allowlist, not a "scan every table except..."
# policy.  A production PBX can contain multi-gigabyte CDR/CEL or add-on
# tables, and the watcher must never read them just because they exist.
DEFAULT_WATCH_TABLES = (
    'announcement', 'callbacks', 'conferences', 'customappsreg', 'devices',
    'did', 'extension_routes', 'extensions', 'featurecodes', 'freepbx_settings', 'globals',
    'iax', 'injected', 'ivr_details', 'ivr_entries', 'miscapps', 'miscdests',
    # FreePBX 17 uses the singular `outbound_route_sequence` table. Retain
    # the historic plural entry for compatibility with older/restored PBXs,
    # and cover the separate pattern and route-to-trunk records as well.
    'outbound_route_patterns', 'outbound_route_sequence',
    'outbound_route_sequences', 'outbound_route_trunks', 'outbound_routes',
    'parkinglot', 'pjsip',
    'queues_config', 'queues_details', 'queues_members', 'ringgroups', 'sip', 'sipsettings', 'kvstore_Sipsettings',
    'timeconditions', 'timegroups', 'timegroups_details',
    'trunk_dialpatterns', 'trunks', 'users', 'zap',
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
SENSITIVE_FIELD_MARKERS = ('password', 'secret', 'token', 'value_digest')
# Some older Core tables lack a declared primary key.  These identifiers are
# stable logical keys used only as a fallback, so updates remain updates rather
# than misleading remove/add pairs.
NATURAL_KEY_FIELDS = ('extension', 'id', 'trunkid', 'route_id', 'account', 'grpnum', 'device', 'user', 'key')
# The legacy `sip.flags` column is an internal display/order ordinal. FreePBX
# rewrites it when an endpoint form is saved even when the option's value is
# unchanged, so including it turns a one-field edit into dozens of false
# updates. It is deliberately excluded as volatile metadata.
VOLATILE_COLUMNS = {'sip': {'flags'}}
# FreePBX represents an unset outbound-route time group as either SQL NULL or
# 0, depending on whether the route was created or later edited.  Both mean
# "no time group"; canonicalize that presentation detail so a reviewer sees
# the route change they made rather than a spurious companion update.
NULL_EQUIVALENT_ZERO_COLUMNS = {'outbound_routes': {'time_group_id'}}
CONTENT_HASH_CACHE = {}

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
    cursor.execute(f"SELECT * FROM `{table}`")
    volatile = VOLATILE_COLUMNS.get(table, set())
    normalized = []
    zero_columns = NULL_EQUIVALENT_ZERO_COLUMNS.get(table, set())
    for item in cursor.fetchall():
        row = {key: clean(value) for key, value in item.items() if key not in volatile}
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
    if name == 'value' and row:
        setting = str(row.get('keyword', '')).lower()
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
            changed = {field: {'before': redact(field, old_rows[key].get(field), old_rows[key]), 'after': redact(field, new_rows[key].get(field), new_rows[key])}
                       for field in old_rows[key].keys() | new_rows[key].keys()
                       if old_rows[key].get(field) != new_rows[key].get(field)}
            if changed:
                updated.append({'key': key, 'fields': changed})
        if added or removed or updated:
            diff[table] = {'added': added, 'removed': removed, 'updated': updated}
    return diff

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
    while True:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        database = database_snapshot()
        # A baseline created under a different scope cannot be compared
        # honestly: switching from the pre-0.1 broad scan to the bounded
        # allowlist would otherwise look like hundreds of removals.  Replace
        # such a baseline only while FreePBX is clean.
        scope = {
            'watch_tables': list(WATCH_TABLES),
            'max_table_rows': MAX_TABLE_ROWS,
            'table_row_limits': TABLE_ROW_LIMITS,
        }
        state = {'scope': scope, 'tables': database['tables'], 'files': digest_files()}
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
            database_drift = database_diff(before_tables, after_tables)
        else:
            deferred_coverage = []
            database_drift = {}
        file_drift = file_diff(baseline['files'], state['files']) if baseline else {}
        has_drift = bool(database_drift or file_drift)
        limitations = list(database['limitations'])
        if deferred_coverage:
            limitations.append({
                'reason': 'scope_expanded_while_pending',
                'tables': deferred_coverage,
            })
        observation = {
            'observed_at': int(time.time()),
            'need_reload': database['need_reload'],
            'baseline_available': baseline is not None,
            'baseline_captured_at': int(BASELINE.stat().st_mtime) if baseline else None,
            'database_drift': database_drift,
            'file_drift': file_drift,
            'coverage_limitations': limitations,
            'message': 'Reload requested; origin unavailable.' if database['need_reload'] and not has_drift else
                       ('Configuration drift detected since the applied baseline.' if database['need_reload'] else 'No pending reload.'),
        }
        publish(observation)
        previous_reload = database['need_reload']
        time.sleep(5)

if __name__ == '__main__':
    main()
