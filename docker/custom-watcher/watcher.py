import hashlib
import json
import os
import time
from pathlib import Path

import pymysql

OUTPUT = Path('/var/lib/pendingchanges-watcher/status.json')
BASELINE = Path('/var/lib/pendingchanges-watcher/baseline.json')
ROOT = Path(os.environ.get('WATCH_PATH', '/etc/asterisk'))
MODULE_ROOT = Path(os.environ.get('MODULE_PATH', '/var/www/html/admin/modules'))
EXCLUDED_TABLES = {'admin', 'cdr', 'cel', 'cronmanager', 'kvstore', 'notifications', 'queue_log'}
EXCLUDED_MODULES = {'pendingchanges'}
SENSITIVE_FIELD_MARKERS = ('password', 'secret', 'token', 'key')
NATURAL_KEY_FIELDS = ('extension', 'id', 'account', 'grpnum', 'device', 'user')

def digest_files():
    files = {
        f'generated/{p.name}': hashlib.sha256(p.read_bytes()).hexdigest()
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
                    digest.update(hashlib.sha256(path.read_bytes()).digest())
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
        tables = [column(item, next(iter(item)) if isinstance(item, dict) else '', 0) for item in cursor.fetchall()]
        tables = [table for table in tables if not table.startswith('pendingchanges_') and table not in EXCLUDED_TABLES]
        snapshot = {}
        for table in tables:
            cursor.execute(f"SELECT * FROM `{table}`")
            rows = [{key: clean(value) for key, value in item.items()} for item in cursor.fetchall()]
            keys = primary_key(cursor, table)
            snapshot[table] = {'keys': keys, 'rows': {row_key(item, keys): item for item in rows}}
    connection.close()
    value = column(row, 'value', 0) if row else None
    return {'need_reload': bool(value == 'true'), 'tables': snapshot}

def redact(field, value):
    return '[redacted]' if any(marker in field.lower() for marker in SENSITIVE_FIELD_MARKERS) else value

def database_diff(before, after):
    diff = {}
    for table in sorted(set(before).union(after)):
        old_rows = before.get(table, {'rows': {}})['rows']
        new_rows = after.get(table, {'rows': {}})['rows']
        added = [new_rows[key] for key in new_rows.keys() - old_rows.keys()]
        removed = [old_rows[key] for key in old_rows.keys() - new_rows.keys()]
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
    temporary.replace(OUTPUT)

def main():
    previous_reload = None
    while True:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        database = database_snapshot()
        state = {'tables': database['tables'], 'files': digest_files()}
        if not BASELINE.exists() and not database['need_reload']:
            BASELINE.write_text(json.dumps(state, sort_keys=True))
        elif previous_reload and not database['need_reload']:
            BASELINE.write_text(json.dumps(state, sort_keys=True))
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
            'message': 'Reload requested; origin unavailable.' if database['need_reload'] and not has_drift else
                       ('Configuration drift detected since the applied baseline.' if database['need_reload'] else 'No pending reload.'),
        }
        publish(observation)
        previous_reload = database['need_reload']
        time.sleep(5)

if __name__ == '__main__':
    main()
