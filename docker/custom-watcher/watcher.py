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
    'did', 'extension_routes', 'extensions', 'featurecodes', 'globals',
    'iax', 'injected', 'ivr_details', 'ivr_entries', 'miscapps', 'miscdests',
    'outbound_route_sequences', 'outbound_routes', 'parkinglot', 'pjsip',
    'queues_config', 'queues_details', 'queues_members', 'ringgroups', 'sip',
    'timeconditions', 'timegroups', 'timegroups_details',
    'trunk_dialpatterns', 'trunks', 'users', 'zap',
)
WATCH_TABLES = tuple(
    table.strip() for table in os.environ.get('WATCH_TABLES', ','.join(DEFAULT_WATCH_TABLES)).split(',')
    if re.fullmatch(r'[A-Za-z0-9_]+', table.strip())
)
MAX_TABLE_ROWS = int(os.environ.get('MAX_TABLE_ROWS', '5000'))
EXCLUDED_MODULES = {'pendingchanges'}
SENSITIVE_FIELD_MARKERS = ('password', 'secret', 'token', 'key')
NATURAL_KEY_FIELDS = ('extension', 'id', 'account', 'grpnum', 'device', 'user')
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
                    digest.update(content_digest(path).encode())
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
            if row_count > MAX_TABLE_ROWS:
                limitations.append({
                    'table': table,
                    'reason': 'row_limit',
                    'rows': row_count,
                    'limit': MAX_TABLE_ROWS,
                })
                continue
            cursor.execute(f"SELECT * FROM `{table}`")
            rows = [{key: clean(value) for key, value in item.items()} for item in cursor.fetchall()]
            keys = primary_key(cursor, table)
            snapshot[table] = {'keys': keys, 'rows': {row_key(item, keys): item for item in rows}}
    connection.close()
    value = column(row, 'value', 0) if row else None
    return {'need_reload': bool(value == 'true'), 'tables': snapshot, 'limitations': limitations}

def redact(field, value):
    return '[redacted]' if any(marker in field.lower() for marker in SENSITIVE_FIELD_MARKERS) else value

def redact_row(row):
    return {field: redact(field, value) for field, value in row.items()}

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
            changed = {field: {'before': redact(field, old_rows[key].get(field)), 'after': redact(field, new_rows[key].get(field))}
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

def publish(payload):
    temporary = OUTPUT.with_suffix('.tmp')
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
            'file_digest_format': 2,
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
        database_drift = database_diff(baseline['tables'], state['tables']) if baseline else {}
        file_drift = file_diff(baseline['files'], state['files']) if baseline else {}
        has_drift = bool(database_drift or file_drift)
        observation = {
            'observed_at': int(time.time()),
            'need_reload': database['need_reload'],
            'baseline_available': baseline is not None,
            'baseline_captured_at': int(BASELINE.stat().st_mtime) if baseline else None,
            'database_drift': database_drift,
            'file_drift': file_drift,
            'coverage_limitations': database['limitations'],
            'message': 'Reload requested; origin unavailable.' if database['need_reload'] and not has_drift else
                       ('Configuration drift detected since the applied baseline.' if database['need_reload'] else 'No pending reload.'),
        }
        publish(observation)
        previous_reload = database['need_reload']
        time.sleep(5)

if __name__ == '__main__':
    main()
