import importlib.util
import hashlib
import sqlite3
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('watcher', Path(__file__).with_name('watcher.py'))
watcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watcher)

before = {'extensions': {'keys': ['extension'], 'rows': {
    '100': {'extension': '100', 'name': 'Desk', 'secret': 'old'},
    '102': {'extension': '102', 'name': 'Old desk', 'secret': 'removed-secret'},
}}}
after = {'extensions': {'keys': ['extension'], 'rows': {
    '100': {'extension': '100', 'name': 'Reception', 'secret': 'new'},
    '101': {'extension': '101', 'name': 'Lobby', 'secret': 'lobby-secret'},
}}}
diff = watcher.database_diff(before, after)
assert diff['extensions']['added'][0]['extension'] == '101'
assert diff['extensions']['added'][0]['secret'] == '[redacted]'
assert diff['extensions']['updated'][0]['fields']['name'] == {'before': 'Desk', 'after': 'Reception'}
assert diff['extensions']['updated'][0]['fields']['secret'] == {'before': '[redacted]', 'after': '[redacted]'}
assert diff['extensions']['removed'][0]['secret'] == '[redacted]'
assert watcher.file_diff({'a.conf': 'old'}, {'a.conf': 'new', 'b.conf': 'added'})['a.conf']['after'] == 'new'
assert watcher.TABLE_ROW_LIMITS['sip'] > watcher.MAX_TABLE_ROWS
assert {
    'outbound_routes', 'outbound_route_patterns',
    'outbound_route_sequence', 'outbound_route_trunks',
}.issubset(watcher.WATCH_TABLES)
assert watcher.redact_row({'key': 'pjsip_debug', 'api_key': 'secret'}) == {
    'key': 'pjsip_debug', 'api_key': '[redacted]'
}
assert watcher.redact_row({'keyword': 'RINGTIMER', 'value': '16'})['value'] == '16'
assert watcher.redact_row({'keyword': 'API_TOKEN', 'value': 'private'})['value'] == '[redacted]'
assert watcher.redact_row({'key': '/AMPUSER/100/voicemail_pin', 'value': '1234'})['value'] == '[redacted]'
class KeyCursor:
    def execute(self, *_): pass
    def fetchall(self): return [{'Field': 'key'}, {'Field': 'id'}]
assert watcher.primary_key(KeyCursor(), 'kvstore_Sipsettings') == ['key']
assert watcher.VOLATILE_COLUMNS['sip'] == {'flags'}
assert watcher.NULL_EQUIVALENT_ZERO_COLUMNS['outbound_routes'] == {'time_group_id'}
class NaturalKeyCursor:
    def __init__(self): self.calls = 0
    def execute(self, *_): self.calls += 1
    def fetchall(self):
        return [] if self.calls == 1 else [{'Field': 'trunkid'}, {'Field': 'name'}]
assert watcher.primary_key(NaturalKeyCursor(), 'trunks') == ['trunkid']

old_scope = {'users': {'rows': {'1': {'name': 'Before'}}}}
expanded_scope = {
    'users': {'rows': {'1': {'name': 'After'}}},
    'outbound_routes': {'rows': {'7': {'name': 'Existing route'}}},
}
before_scope, after_scope, deferred = watcher.comparable_tables(
    old_scope, expanded_scope, scope_changed=True, pending_reload=True)
assert set(before_scope) == {'users'} and set(after_scope) == {'users'}
assert deferred == ['outbound_routes']
assert watcher.database_diff(before_scope, after_scope)['users']['updated']

# The historic `sip` table remains fully explainable: an update names the
# peer option and its before/after value, while sensitive values stay private.
sip_before = {'sip': {'keys': ['id', 'keyword'], 'rows': {
    '7001|callerid': {'id': '7001', 'keyword': 'callerid', 'data': 'Desk <7001>'},
    '7001|secret': {'id': '7001', 'keyword': 'secret', 'data': 'private'},
}}}
sip_after = {'sip': {'keys': ['id', 'keyword'], 'rows': {
    '7001|callerid': {'id': '7001', 'keyword': 'callerid', 'data': 'Lobby <7001>'},
    '7001|secret': {'id': '7001', 'keyword': 'secret', 'data': 'changed-private'},
}}}
sip_diff = watcher.database_diff(sip_before, sip_after)['sip']['updated']
sip_changes = {entry['key']: entry['fields']['data'] for entry in sip_diff}
assert sip_changes['7001|callerid'] == {'before': 'Desk <7001>', 'after': 'Lobby <7001>'}
assert sip_changes['7001|secret'] == {'before': '[redacted]', 'after': '[redacted]'}

# The file-hash cache must not change existing module digest values; otherwise
# a watcher update would obscure live pending database evidence with noise.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    module = root / 'core'
    module.mkdir()
    (module / 'a.php').write_text('one')
    (module / 'nested').mkdir()
    (module / 'nested' / 'b.php').write_text('two')
    old = hashlib.sha256()
    for path in sorted(module.rglob('*')):
        if path.is_file():
            old.update(str(path.relative_to(module)).encode())
            old.update(hashlib.sha256(path.read_bytes()).digest())
    watcher.ROOT = root / 'asterisk'
    watcher.MODULE_ROOT = root
    watcher.CONTENT_HASH_CACHE.clear()
    assert watcher.digest_files()['module/core'] == old.hexdigest()

# Immediate FreePBX state is deliberately bounded to named AstDB families.
# A recording preference is visible, while an unrelated application family is
# absent and a sensitive value remains redacted in the public diff.
with tempfile.TemporaryDirectory() as temporary:
    astdb_path = Path(temporary) / 'astdb.sqlite3'
    connection = sqlite3.connect(astdb_path)
    connection.execute('CREATE TABLE astdb(key TEXT, value TEXT, PRIMARY KEY(key))')
    connection.executemany('INSERT INTO astdb VALUES (?, ?)', [
        ('/AMPUSER/100/recording', 'in'),
        ('/AMPUSER/100/voicemail_pin', '1234'),
        ('/unrelated/application', 'do-not-watch'),
    ])
    connection.commit()
    connection.close()
    watcher.ASTDB_PATH = astdb_path
    watcher.ASTDB_FAMILIES = ('AMPUSER',)
    watcher.ASTDB_MAX_ROWS = 10
    astdb_before = watcher.astdb_snapshot()
    assert set(astdb_before['rows']) == {'/AMPUSER/100/recording', '/AMPUSER/100/voicemail_pin'}
    connection = sqlite3.connect(astdb_path)
    connection.execute("UPDATE astdb SET value = 'out' WHERE key = '/AMPUSER/100/recording'")
    connection.commit()
    connection.close()
    astdb_changes = watcher.astdb_diff(astdb_before, watcher.astdb_snapshot())['updated']
    assert astdb_changes[0]['fields']['value'] == {'before': 'in', 'after': 'out'}
    astdb_private = watcher.database_diff({'astdb': astdb_before}, {'astdb': watcher.astdb_snapshot()})
    assert watcher.redact_row({'key': '/AMPUSER/100/voicemail_pin', 'value': '1234'})['value'] == '[redacted]'

# Private-alpha feedback is a bounded local event ledger of types/counts only.
# It must never contain an extension, an AstDB key/value, or a file/module name.
with tempfile.TemporaryDirectory() as temporary:
    watcher.FEEDBACK = Path(temporary) / 'feedback.jsonl'
    watcher.FEEDBACK_MAX_EVENTS = 2
    observation = {
        'observed_at': 1, 'need_reload': True,
        'database_drift': {'users': {'added': [{'extension': '7001'}], 'removed': [], 'updated': [
            {'key': '7001', 'fields': {'name': {'before': 'Old', 'after': 'New'}}},
        ]}},
        'astdb_drift': {'added': [{'key': '/AMPUSER/7001/recording', 'value': 'in'}], 'removed': [], 'updated': []},
        'file_drift': {'generated/voicemail.conf': {'before': 'a', 'after': 'b'}},
        'coverage_limitations': [{'reason': 'row_limit', 'table': 'sip'}],
    }
    signature = watcher.append_feedback(observation, None)
    assert watcher.append_feedback(observation, signature) == signature
    events = watcher.FEEDBACK.read_text().splitlines()
    assert len(events) == 1
    assert '7001' not in events[0] and 'voicemail.conf' not in events[0] and 'recording' not in events[0]
    event = __import__('json').loads(events[0])
    assert event['database']['users']['added'] == 1 and event['database']['users']['updated_fields'] == ['name']
    assert event['astdb']['added'] == 1 and event['files']['generated_count'] == 1
print('watcher unit checks passed')
