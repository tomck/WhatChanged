import importlib.util
import hashlib
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
print('watcher unit checks passed')
