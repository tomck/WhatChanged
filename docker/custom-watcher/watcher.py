import hashlib
import json
import os
import time
from pathlib import Path

import pymysql

OUTPUT = Path('/var/lib/pendingchanges-watcher/status.json')
BASELINE = Path('/var/lib/pendingchanges-watcher/baseline.json')
ROOT = Path(os.environ.get('WATCH_PATH', '/etc/asterisk'))

def digest_files():
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ROOT.glob('*.conf')) if p.is_file()}

def database_status():
    connection = pymysql.connect(host=os.environ['DB_HOST'], user=os.environ['DB_USER'], password=os.environ['DB_PASSWORD'], database=os.environ['DB_NAME'])
    with connection.cursor() as cursor:
        cursor.execute("SELECT value FROM admin WHERE variable = 'need_reload'")
        row = cursor.fetchone()
        cursor.execute("SHOW TABLES")
        tables = [row[0] for row in cursor.fetchall() if not row[0].startswith('pendingchanges_')]
        pieces = []
        for table in tables:
            cursor.execute(f"SELECT COUNT(*) FROM `{table}`")
            pieces.append(f"{table}:{cursor.fetchone()[0]}")
    connection.close()
    return {'need_reload': bool(row and row[0] == 'true'), 'table_count_digest': hashlib.sha256('|'.join(pieces).encode()).hexdigest()}

while True:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    state = {'database': database_status(), 'files': digest_files()}
    if not BASELINE.exists() and not state['database']['need_reload']:
        BASELINE.write_text(json.dumps(state, sort_keys=True))
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
    observation = {
        'observed_at': int(time.time()),
        **state,
        'baseline_available': baseline is not None,
        'database_drift': bool(baseline and baseline['database']['table_count_digest'] != state['database']['table_count_digest']),
        'file_drift': sorted(set((baseline or {'files': {}})['files']).symmetric_difference(state['files']) |
                             {path for path in state['files'] if baseline and baseline['files'].get(path) != state['files'][path]}),
    }
    OUTPUT.write_text(json.dumps(observation, sort_keys=True))
    time.sleep(5)
