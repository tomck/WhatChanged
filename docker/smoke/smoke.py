"""End-to-end assertions for the disposable WhatChanged lab only."""
import json
import os
import time
from pathlib import Path

import pymysql

STATUS = Path('/var/lib/pendingchanges-watcher/status.json')
BASELINE = Path('/var/lib/pendingchanges-watcher/baseline.json')
GENERATED_FIXTURE = Path('/etc/asterisk/pc-smoke.conf')
MODULE_FIXTURE = Path('/var/www/html/admin/modules/core/pc-smoke-module-drift.txt')
OWN_MODULE_FIXTURE = Path('/var/www/html/admin/modules/pendingchanges/pc-smoke-owned.txt')
TABLE = 'pc_smoke_fixture'


def observation():
    return json.loads(STATUS.read_text())


# The production watcher begins an idle full scan within 30 seconds. Allow
# additional time for the bounded module-tree walk itself; the prior 35-second
# assertion could expire one or two seconds before a valid observation landed.
def wait_for(description, predicate, timeout=60):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        if STATUS.exists():
            last = observation()
            if predicate(last):
                return last
        time.sleep(1)
    raise AssertionError(f'{description}; last observation: {last}')


def set_reload(cursor, pending):
    cursor.execute("UPDATE admin SET value = %s WHERE variable = 'need_reload'", ('true' if pending else 'false',))


def table_changes(state, kind):
    return state['database_drift'].get(TABLE, {}).get(kind, [])


def reset_baseline(cursor):
    """Remove test-only state and wait for a fresh clean watcher baseline."""
    set_reload(cursor, False)
    cursor.execute(f'DROP TABLE IF EXISTS `{TABLE}`')
    for path in (GENERATED_FIXTURE, MODULE_FIXTURE, OWN_MODULE_FIXTURE, BASELINE):
        path.unlink(missing_ok=True)
    previous_observation = observation().get('observed_at', 0) if STATUS.exists() else 0
    set_reload(cursor, True)
    pending = wait_for('fixture cleanup transition was not observed', lambda state:
                       state['observed_at'] > previous_observation and
                       state['need_reload'])
    set_reload(cursor, False)
    return wait_for('clean baseline was not captured', lambda state:
                    state['observed_at'] > pending['observed_at'] and
                    state['baseline_available'] and not state['need_reload'] and
                    not state['database_drift'] and not state['astdb_drift'] and
                    not state['file_drift'])


connection = pymysql.connect(
    host=os.environ['DB_HOST'], user=os.environ['DB_USER'],
    password=os.environ['DB_PASSWORD'], database=os.environ['DB_NAME'],
    autocommit=True,
)
try:
    with connection.cursor() as cursor:
        # Added record.
        reset_baseline(cursor)
        cursor.execute(f'CREATE TABLE `{TABLE}` (id INT PRIMARY KEY, value VARCHAR(50))')
        cursor.execute(f"INSERT INTO `{TABLE}` VALUES (1, 'before')")
        set_reload(cursor, True)
        state = wait_for('added record was not reported', lambda item:
                         item['need_reload'] and len(table_changes(item, 'added')) == 1)
        assert not table_changes(state, 'updated') and not table_changes(state, 'removed')

        # Update the same logical row after applying the first staged change.
        set_reload(cursor, False)
        wait_for('baseline did not refresh after apply', lambda item:
                 not item['need_reload'] and not item['database_drift'])
        cursor.execute(f"UPDATE `{TABLE}` SET value = 'after' WHERE id = 1")
        set_reload(cursor, True)
        state = wait_for('updated record was not reported', lambda item:
                         item['need_reload'] and len(table_changes(item, 'updated')) == 1)
        assert not table_changes(state, 'added') and not table_changes(state, 'removed')

        # Remove the baseline row.
        set_reload(cursor, False)
        wait_for('baseline did not refresh before deletion', lambda item:
                 not item['need_reload'] and not item['database_drift'])
        cursor.execute(f'DELETE FROM `{TABLE}` WHERE id = 1')
        set_reload(cursor, True)
        state = wait_for('removed record was not reported', lambda item:
                         item['need_reload'] and len(table_changes(item, 'removed')) == 1)
        assert not table_changes(state, 'added') and not table_changes(state, 'updated')

        # A bare FreePBX reload request has no attributable provenance.
        set_reload(cursor, False)
        wait_for('baseline did not refresh before unknown-origin test', lambda item:
                 not item['need_reload'] and not item['database_drift'])
        set_reload(cursor, True)
        wait_for('unknown-origin reload was not reported', lambda item:
                 item['need_reload'] and not item['database_drift'] and not item['file_drift'] and
                 item['message'] == 'Reload requested; origin unavailable.')

        # Generated/module file drift remains separate from configuration data.
        reset_baseline(cursor)
        GENERATED_FIXTURE.write_text('; disposable generated-file fixture\n')
        state = wait_for('generated file drift was not reported', lambda item:
                         'generated/pc-smoke.conf' in item['file_drift'])
        assert not state['database_drift'] and not state['need_reload']

        reset_baseline(cursor)
        MODULE_FIXTURE.write_text('disposable module-file fixture\n')
        OWN_MODULE_FIXTURE.write_text('must be excluded\n')
        state = wait_for('module file drift was not reported', lambda item:
                         'module/core' in item['file_drift'])
        assert 'module/pendingchanges' not in state['file_drift']
        assert not state['database_drift'] and not state['need_reload']

        reset_baseline(cursor)
    print('watcher smoke lifecycle passed')
finally:
    connection.close()
