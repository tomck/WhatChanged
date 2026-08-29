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
