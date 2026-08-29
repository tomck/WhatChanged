import importlib.util
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
print('watcher unit checks passed')
