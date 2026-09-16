import importlib.util
import hashlib
import sqlite3
import sys
import tempfile
import types
import json
import os
from pathlib import Path

# Database access is exercised in the container smoke suite. Keep these pure
# unit checks runnable on a workstation that does not have PyMySQL installed.
try:
    import pymysql  # noqa: F401
except ModuleNotFoundError:
    sys.modules['pymysql'] = types.SimpleNamespace(
        cursors=types.SimpleNamespace(DictCursor=object)
    )

spec = importlib.util.spec_from_file_location('watcher', Path(__file__).with_name('watcher.py'))
watcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watcher)
assert watcher.WATCHER_VERSION == Path(__file__).with_name('VERSION').read_text().strip()

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
    'outbound_route_sequence', 'outbound_route_trunks', 'modules',
    'fax_details',
    'userman_users', 'userman_users_settings',
}.issubset(watcher.WATCH_TABLES)
assert watcher.redact_row({'key': 'pjsip_debug', 'api_key': 'secret'}) == {
    'key': 'pjsip_debug', 'api_key': '[redacted]'
}
assert watcher.redact_row({'keyword': 'RINGTIMER', 'value': '16'})['value'] == '16'
assert watcher.redact_row({'keyword': 'API_TOKEN', 'value': 'private'})['value'] == '[redacted]'
assert watcher.redact_row({'key': '/AMPUSER/100/voicemail_pin', 'value': '1234'})['value'] == '[redacted]'
assert watcher.redact_row({'variable': 'TURN_PASSWORD', 'data': 'private'})['data'] == '[redacted]'
assert watcher.redact_row({'name': 'secretary', 'value': 'visible'})['value'] == 'visible'
class KeyCursor:
    def execute(self, *_): pass
    def fetchall(self): return [{'Field': 'key'}, {'Field': 'id'}]
assert watcher.primary_key(KeyCursor(), 'kvstore_Sipsettings') == ['key']
assert watcher.VOLATILE_COLUMNS['sip'] == {'flags'}
assert watcher.VOLATILE_COLUMNS['modules'] == {'signature'}
assert watcher.primary_key(KeyCursor(), 'modules') == ['modulename']
assert watcher.NULL_EQUIVALENT_ZERO_COLUMNS['outbound_routes'] == {'time_group_id'}
watcher.PROBE_INTERVAL = 5
watcher.FULL_SCAN_INTERVAL = 30
watcher.MODULE_SCAN_INTERVAL = 300
assert watcher.watcher_health_metadata() == {
    'schema': 1,
    'expected_refresh_seconds': 30,
    'probe_interval_seconds': 5,
    'module_scan_interval_seconds': 300,
}

# Authenticated request breadcrumbs contain only safe metadata. Correlation is
# deliberately cautious: one account is likely, several are possible, and a
# CLI/API mutation with no web breadcrumb remains unavailable.
request_fixture = [
    {
        'event_id': 'one', 'finished_at': 101.0, 'username': 'tom',
        'operation': 'stage', 'method': 'POST', 'script': 'config.php',
        'display': 'extensions', 'module': '', 'type': 'extensions', 'action': 'edit',
        'command': '', 'handler': '', 'http_status': 200,
    },
]
attribution = watcher.request_attribution(request_fixture, 100, True)
assert attribution['confidence'] == 'likely' and attribution['actors'] == ['tom']
assert attribution['requests'][0]['display'] == 'extensions'
possible = watcher.request_attribution(request_fixture + [
    {**request_fixture[0], 'event_id': 'two', 'finished_at': 102.0, 'username': 'alice'},
], 100, True)
assert possible['confidence'] == 'possible' and possible['actors'] == ['alice', 'tom']
assert watcher.request_attribution([], 100, True)['confidence'] == 'unavailable'
assert watcher.request_attribution(request_fixture, 100, False)['confidence'] == 'none'
assert not watcher.module_request_since(request_fixture, 100)
assert watcher.module_request_since([
    {**request_fixture[0], 'finished_at': 103.0, 'display': 'modules'},
], 102)
with tempfile.TemporaryDirectory() as temporary:
    watcher.ATTRIBUTION_LOG = Path(temporary) / 'requests.jsonl'
    watcher.ATTRIBUTION_LOG.write_text('\n'.join([
        '{malformed',
        json.dumps({'schema': 1, **request_fixture[0]}),
        json.dumps({'schema': 1, **request_fixture[0], 'event_id': 'failed', 'http_status': 500}),
        json.dumps({
            'schema': 1, **request_fixture[0], 'event_id': 'background',
            'method': 'POST', 'command': 'navbarToogle',
        }),
    ]) + '\n')
    parsed = watcher.request_events()
    assert len(parsed) == 1 and parsed[0]['event_id'] == 'one'

# A cheap reload/event probe avoids repeatedly walking every table and module
# while still forcing a full observation for meaningful transitions.
watcher.FULL_SCAN_INTERVAL = 30
assert watcher.observation_due(None, 0, None, False, 0, 0)
assert watcher.observation_due(100, 105, False, True, 0, 0)
assert watcher.observation_due(100, 105, False, False, 1, 2)
assert watcher.observation_due(100, 130, False, False, 1, 1)
assert not watcher.observation_due(100, 129.9, False, False, 1, 1)

# Persisted baselines retain equality through keyed fingerprints without ever
# containing a raw secret or exposing a guessable digest in public output.
with tempfile.TemporaryDirectory() as temporary:
    watcher.STATE_DIR = Path(temporary)
    watcher.REDACTION_KEY = watcher.STATE_DIR / 'redaction.key'
    watcher.REDACTION_KEY_CACHE = None
    raw_state = {
        'scope': {'watch_tables': ['settings']},
        'tables': {'settings': {'keys': ['variable'], 'rows': {
            'API_TOKEN': {'variable': 'API_TOKEN', 'value': 'marker-secret-one'},
        }}},
        'astdb': {'keys': ['key'], 'rows': {
            '/AMPUSER/100/voicemail_pin': {
                'key': '/AMPUSER/100/voicemail_pin', 'value': '2468',
            },
        }, 'limitations': []},
        'files': {},
    }
    protected = watcher.protect_state(raw_state)
    serialized = json.dumps(protected)
    assert 'marker-secret-one' not in serialized and '2468' not in serialized
    assert watcher.PROTECTED_VALUE_PREFIX in serialized
    assert (watcher.REDACTION_KEY.stat().st_mode & 0o777) == 0o600
    changed_state = json.loads(json.dumps(raw_state))
    changed_state['tables']['settings']['rows']['API_TOKEN']['value'] = 'marker-secret-two'
    changed = watcher.protect_state(changed_state)
    protected_diff = watcher.database_diff(protected['tables'], changed['tables'])
    public = json.dumps(protected_diff)
    assert '[redacted]' in public
    assert watcher.PROTECTED_VALUE_PREFIX not in public
    assert 'marker-secret-one' not in public and 'marker-secret-two' not in public

    # The observation loop must compare a protected AstDB baseline with the
    # protected current snapshot. Comparing with raw AstDB values would report
    # every unchanged AMPUSER password as redacted-to-redacted drift forever.
    same_current = watcher.protect_state(raw_state)
    same_astdb_diff, deferred = watcher.comparable_astdb(
        protected, same_current, scope_changed=False, pending_reload=False,
    )
    assert not deferred and not same_astdb_diff
    changed_astdb = json.loads(json.dumps(raw_state))
    changed_astdb['astdb']['rows']['/AMPUSER/100/voicemail_pin']['value'] = '1357'
    protected_changed_astdb = watcher.protect_state(changed_astdb)
    astdb_secret_diff, deferred = watcher.comparable_astdb(
        protected, protected_changed_astdb,
        scope_changed=False, pending_reload=False,
    )
    assert not deferred
    assert astdb_secret_diff['updated'][0]['fields']['value'] == {
        'before': '[redacted]', 'after': '[redacted]',
    }

# On process startup, unchanged state proves continuity. A witnessed pending
# flag clear or authenticated Apply can refresh the baseline; any unexplained
# changed state becomes explicitly uncertain instead of receiving false trust.
baseline_state = {'scope': {}, 'tables': {'users': {'keys': ['id'], 'rows': {}}}, 'astdb': {'keys': ['key'], 'rows': {}, 'limitations': []}, 'files': {}}
changed_state = {**baseline_state, 'files': {'generated/extensions.conf': 'new'}}
action, provenance = watcher.startup_baseline_recovery(baseline_state, baseline_state, False, None, [], 100)
assert action == 'keep' and provenance['state'] == 'trusted'
action, provenance = watcher.startup_baseline_recovery(baseline_state, changed_state, False, None, [], 100)
assert action == 'keep' and provenance['state'] == 'uncertain'
runtime = {
    'schema': 1, 'observed_at': 110, 'need_reload': True,
    'state_fingerprint': watcher.state_fingerprint(baseline_state),
    'baseline_provenance': {'state': 'trusted'},
}
action, provenance = watcher.startup_baseline_recovery(baseline_state, changed_state, False, runtime, [], 100)
assert action == 'refresh' and provenance['state'] == 'trusted'
apply_event = {'operation': 'apply', 'finished_at': 120}
action, provenance = watcher.startup_baseline_recovery(baseline_state, changed_state, False, None, [apply_event], 100)
assert action == 'refresh' and provenance['reason'] == 'successful_web_apply_observed_during_interruption'
action, provenance = watcher.startup_baseline_recovery(baseline_state, changed_state, True, None, [apply_event], 100)
assert action == 'keep' and provenance['state'] == 'uncertain'
assert watcher.observed_apply_reason(True, False, [], 100) == 'pending_reload_cleared_while_observed'
assert watcher.observed_apply_reason(False, False, [apply_event], 100) == 'successful_web_apply_observed'
assert watcher.observed_apply_reason(False, True, [apply_event], 100) is None
assert watcher.observed_apply_reason(False, False, [apply_event], 120) is None
assert watcher.observed_apply_reason(False, False, [
    {**apply_event, 'finished_at': 121, 'http_status': 500},
], 120) is None

# A transient database failure must not kill the long-running sensor. The
# supervisor retries after the probe interval; an explicit stop still exits.
retry_calls = []
def transient_then_stop():
    retry_calls.append('observe')
    if len(retry_calls) == 1:
        raise RuntimeError('transient database reset')
    raise KeyboardInterrupt()
try:
    watcher.run_resilient(
        transient_then_stop,
        lambda delay: retry_calls.append(delay),
        lambda: retry_calls.append('reported'),
    )
except KeyboardInterrupt:
    pass
assert retry_calls == [
    'observe', 'reported', max(watcher.PROBE_INTERVAL, 1.0), 'observe',
]

with tempfile.TemporaryDirectory() as temporary:
    content = (b'what-changed-streaming-digest' * 100000)
    large_file = Path(temporary) / 'large-module-file.bin'
    large_file.write_bytes(content)
    assert watcher.content_digest(large_file) == hashlib.sha256(content).hexdigest()
    original_root = watcher.ROOT
    watcher.ROOT = Path(temporary)
    assert watcher.digest_files({'module/core': 'cached-tree'}) == {'module/core': 'cached-tree'}
    watcher.ROOT = original_root

# Fax Configuration stores the concurrent receive limit as an ordinary,
# readable key/value record rather than in the generic FreePBX settings table.
fax_before = {'fax_details': {'keys': ['key'], 'rows': {
    'concurrentfax': {'key': 'concurrentfax', 'value': '1'},
}}}
fax_after = {'fax_details': {'keys': ['key'], 'rows': {
    'concurrentfax': {'key': 'concurrentfax', 'value': '5'},
}}}
fax_update = watcher.database_diff(fax_before, fax_after)['fax_details']['updated'][0]
assert fax_update['key'] == 'concurrentfax'
assert fax_update['fields'] == {'value': {'before': '1', 'after': '5'}}

# Module activation changes must be named and readable while signature-cache
# churn remains outside the pending configuration evidence.
modules_before = {'modules': {'keys': ['modulename'], 'rows': {
    'parkpro': {'id': 120, 'modulename': 'parkpro', 'version': '17.0.1.4', 'enabled': 1},
}}}
modules_after = {'modules': {'keys': ['modulename'], 'rows': {
    'parkpro': {'id': 120, 'modulename': 'parkpro', 'version': '17.0.1.4', 'enabled': 0},
}}}
module_update = watcher.database_diff(modules_before, modules_after)['modules']['updated'][0]
assert module_update['key'] == 'parkpro'
assert module_update['fields'] == {'enabled': {'before': 1, 'after': 0}}
legacy_modules = {'modules': {'keys': ['modulename'], 'rows': {
    'parkpro': modules_before['modules']['rows']['parkpro'],
    'pendingchanges': {'modulename': 'pendingchanges', 'version': '17.0.0.6', 'enabled': 1},
}}}
filtered_modules = watcher.without_module_owned_rows(legacy_modules)
assert set(filtered_modules['modules']['rows']) == {'parkpro'}
assert not watcher.database_diff(
    filtered_modules,
    watcher.without_module_owned_rows({'modules': {'keys': ['modulename'], 'rows': {
        'parkpro': modules_before['modules']['rows']['parkpro'],
        'pendingchanges': {'modulename': 'pendingchanges', 'version': '17.0.0.7', 'enabled': 1},
    }}}),
)

# User Management UCP assignments live in a separate per-user settings table.
# Preserve the useful assignment values, name the affected user/module/setting,
# and never let a joined username create duplicate drift by itself.
userman_before = {'userman_users_settings': {'keys': ['uid', 'module', 'key'], 'rows': {
    '8|ucp|Settings|assigned': {
        'uid': 8, 'username': 'tom', 'module': 'ucp|Settings',
        'key': 'assigned', 'val': '["7001"]', 'type': 'json-arr',
    },
}}}
userman_after = {'userman_users_settings': {'keys': ['uid', 'module', 'key'], 'rows': {
    '8|ucp|Settings|assigned': {
        'uid': 8, 'username': 'tom', 'module': 'ucp|Settings',
        'key': 'assigned', 'val': '["7001","41625"]', 'type': 'json-arr',
    },
}}}
userman_update = watcher.database_diff(userman_before, userman_after)['userman_users_settings']['updated'][0]
assert userman_update['identity'] == {
    'username': 'tom', 'uid': 8, 'module': 'ucp|Settings', 'key': 'assigned',
}
assert userman_update['fields'] == {'val': {'before': '["7001"]', 'after': '["7001","41625"]'}}
renamed_only = {'userman_users_settings': {'keys': ['uid', 'module', 'key'], 'rows': {
    '8|ucp|Settings|assigned': {**userman_before['userman_users_settings']['rows']['8|ucp|Settings|assigned'], 'username': 'renamed'},
}}}
assert not watcher.database_diff(userman_before, renamed_only)
assert watcher.redact_row({'module': 'example', 'key': 'api_token', 'val': 'private'})['val'] == '[redacted]'
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

# A configured FreePBX database socket takes precedence over TCP while the
# configured port remains available for normal host connections.
original_socket = watcher.DB_SOCKET
connection_environment = {
    'DB_HOST': 'localhost', 'DB_USER': 'watcher',
    'DB_PASSWORD': 'test-only', 'DB_NAME': 'asterisk',
}
original_environment = {key: os.environ.get(key) for key in connection_environment}
os.environ.update(connection_environment)
watcher.DB_SOCKET = '/run/mariadb/custom.sock'
socket_parameters = watcher.database_connection_parameters()
assert socket_parameters['unix_socket'] == '/run/mariadb/custom.sock'
assert socket_parameters['port'] == watcher.DB_PORT
watcher.DB_SOCKET = None
assert 'unix_socket' not in watcher.database_connection_parameters()
watcher.DB_SOCKET = original_socket
for key, value in original_environment.items():
    if value is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = value

# Module monitoring uses only stable release markers. Module Admin state is
# already captured from the modules table and FreePBX's signature verifier is
# responsible for exhaustive per-file integrity checks. Large node_modules
# trees must therefore have no effect on WhatChanged's scan cost or result.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    module = root / 'core'
    module.mkdir()
    (module / 'module.xml').write_text('<version>1.0</version>')
    (module / 'module.sig').write_text('signature-one')
    (module / 'node_modules').mkdir()
    ignored = module / 'node_modules' / 'large.js'
    ignored.write_text('one')
    watcher.ROOT = root / 'asterisk'
    watcher.MODULE_ROOT = root
    watcher.CONTENT_HASH_CACHE.clear()
    first = watcher.digest_files()['module/core']
    ignored.write_text('two')
    watcher.CONTENT_HASH_CACHE.clear()
    assert watcher.digest_files()['module/core'] == first
    (module / 'module.xml').write_text('<version>1.1</version>')
    watcher.CONTENT_HASH_CACHE.clear()
    assert watcher.digest_files()['module/core'] != first

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
