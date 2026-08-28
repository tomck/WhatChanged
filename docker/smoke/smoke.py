import os
import time
from pathlib import Path
import pymysql

connection = pymysql.connect(host=os.environ['DB_HOST'], user=os.environ['DB_USER'], password=os.environ['DB_PASSWORD'], database=os.environ['DB_NAME'], autocommit=True)
try:
    with connection.cursor() as cursor:
        cursor.execute('CREATE TABLE IF NOT EXISTS pc_smoke_fixture (id INT PRIMARY KEY, value VARCHAR(50))')
        cursor.execute('DELETE FROM pc_smoke_fixture')
        cursor.execute("INSERT INTO pc_smoke_fixture VALUES (1, 'before')")
        cursor.execute("UPDATE admin SET value = 'true' WHERE variable = 'need_reload'")
    time.sleep(7)
    watcher = Path('/var/lib/pendingchanges-watcher/status.json')
    assert watcher.exists(), 'custom watcher produced no observation'
    assert 'pc_smoke_fixture' in watcher.read_text(), 'custom watcher did not report database drift'
    Path('/etc/asterisk/pc-smoke.conf').write_text('; local smoke file drift\n')
    time.sleep(7)
    assert 'pc-smoke.conf' in watcher.read_text(), 'custom watcher did not report file drift'
    with connection.cursor() as cursor:
        cursor.execute("UPDATE admin SET value = 'false' WHERE variable = 'need_reload'")
        cursor.execute('DELETE FROM pc_smoke_fixture')
    print('watcher smoke checks passed')
finally:
    connection.close()
