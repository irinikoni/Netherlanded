#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
# Test suite for the netherlanded analytics disclosure control.
# Run: python3 tools/test_suppression.py

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import suppress_reference as ref

QUOTE = chr(39)
RESULTS = []


def check(name, condition, detail=''):
    RESULTS.append((bool(condition), name, detail))


def cell(table, row, col, num, denom):
    return {'table_id': table, 'row': row, 'col': col, 'num': num, 'denom': denom}


def read(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        return ''
    with open(path, 'r', encoding='utf-8') as handle:
        return handle.read()


# ---------------------------------------------------------------- scenarios

out = ref.suppress([
    cell('t1_category_totals', 'money', '2026-sep', 50, 100),
    cell('t1_category_totals', 'money', '2026-feb', 40, 100),
])
check('two healthy cells in one row both publish',
      all(c['reason'] is None for c in out),
      str([c['reason'] for c in out]))
check('published denominators are multiples of five',
      all(c['denom_pub'] % 5 == 0 for c in out if c['reason'] is None))
check('published numerators are multiples of five',
      all(c['num_pub'] % 5 == 0 for c in out if c['reason'] is None))
check('published rates stay inside 0..1',
      all(0.0 <= c['rate'] <= 1.0 for c in out if c['reason'] is None))

out = ref.suppress([cell('t1_category_totals', 'work', '2026-sep', 9, 14)])
check('a group of fourteen is withheld by the floor', out[0]['reason'] == 'floor')
check('a withheld cell carries no rate', out[0]['rate'] is None)
check('a withheld cell carries no band', out[0]['band'] is None)

out = ref.suppress([cell('t1_category_totals', 'work', '2026-sep', 8, 13)])
check('a group of thirteen is withheld by the floor', out[0]['reason'] == 'floor')

out = ref.suppress([cell('t1_category_totals', 'work', '2026-sep', 12, 15)])
check('a group of fifteen publishes', out[0]['reason'] is None)
check('a group of fifteen has a rounded rate', out[0]['rate'] in (0.6, 0.667))

out = ref.suppress([
    cell('t1_category_totals', 'health', '2026-sep', 60, 100),
    cell('t1_category_totals', 'health', '2026-feb', 4, 14),
])
check('a lone survivor next to a floored cell is withheld too',
      sorted([c['reason'] or 'published' for c in out]) == ['complementary', 'floor'],
      str([c['reason'] for c in out]))

out = ref.suppress([
    cell('t1_category_totals', 'money', 'a', 60, 100),
    cell('t1_category_totals', 'money', 'b', 60, 100),
    cell('t1_category_totals', 'money', 'c', 5, 14),
])
check('two survivors next to a floored cell stay published',
      sum(1 for c in out if c['reason'] is None) == 2)

previous = {('t1_category_totals', 'money', '2026-sep'): {'rate': 0.50}}
out = ref.suppress([cell('t1_category_totals', 'money', '2026-sep', 52, 100)],
                   previous_published=previous)
check('a two point move is withheld as delta', out[0]['reason'] == 'delta')

out = ref.suppress([cell('t1_category_totals', 'money', '2026-sep', 70, 100)],
                   previous_published=previous)
check('a twenty point move publishes', out[0]['reason'] is None)

out = ref.suppress([cell('t1_category_totals', 'money', '2026-sep', 50, 100)],
                   previous_published=previous)
check('an unchanged figure is not treated as delta', out[0]['reason'] is None)

out = ref.suppress(
    [cell('t1_category_totals', 'work', '2026-sep', 50, 100)],
    previous_suppressed=[{'table_id': 't1_category_totals', 'row': 'work',
                          'col': '2026-sep', 'reason': 'complementary'}])
check('a previously withheld cell stays withheld', out[0]['reason'] == 'sticky')

out = ref.suppress(
    [cell('t1_category_totals', 'work', '2026-sep', 50, 100)],
    previous_suppressed=[{'table_id': 't1_category_totals', 'row': 'work',
                          'col': '2026-sep', 'reason': 'floor'}])
check('a floor withholding does not stick', out[0]['reason'] is None)

check('rate is clamped at one', ref.round_rate(120, 100) == 1.0)
check('rate is clamped at zero', ref.round_rate(-5, 100) == 0.0)
check('a zero denominator has no rate', ref.round_rate(0, 0) is None)

batch = []
for index, pair in enumerate([(60, 100), (40, 100), (30, 100), (5, 14), (70, 100), (20, 50)]):
    batch.append(cell('t1_category_totals', 'cat' + str(index), '2026-sep',
                      pair[0], pair[1]))
out = ref.suppress(batch)
check('a mixed batch passes the release audit',
      ref.check_release(out) == [], str(ref.check_release(out)))
check('nothing in the mixed batch is published below the floor',
      all(c['denom_pub'] >= 15 for c in out if c['reason'] is None))

big = []
for index in range(12):
    big.append(cell('t2_step_totals', 'step' + str(index % 4),
                    '2026-' + ('sep' if index < 6 else 'feb'),
                    10 + index * 3, 40 + index * 5))
out = ref.suppress(big)
check('a twelve cell grid passes the release audit',
      ref.check_release(out) == [], str(ref.check_release(out)))
check('the grid still publishes something',
      any(c['reason'] is None for c in out))

empty = ref.suppress([])
check('an empty stage is handled', empty == [])


# ------------------------------------------------------------ static checks

NAMES = [
    'db/001_schema.sql',
    'db/002_ingest.sql',
    'db/003_release.sql',
    'db/004_retention.sql',
    'web/stats.js',
    'tools/suppress_reference.py',
    'tools/test_suppression.py',
    'README.md',
    'LEGAL_DELTA.md',
]

for name in NAMES:
    text = read(name)
    check('file exists and is not empty: ' + name, len(text) > 200, str(len(text)))

schema = read('db/001_schema.sql')
ingest = read('db/002_ingest.sql')
release = read('db/003_release.sql')
retention = read('db/004_retention.sql')
script = read('web/stats.js')
readme = read('README.md')
delta = read('LEGAL_DELTA.md')

categories = ['admin', 'housing', 'money', 'health', 'work', 'social', 'wellbeing']
needle = QUOTE + (QUOTE + ', ' + QUOTE).join(categories) + QUOTE
check('schema declares exactly the seven app categories', needle in schema)

check('tier one store keeps no session identifier',
      'session_id' not in schema.lower() and 'sid ' not in schema.lower())
check('tier two store keeps no timing flag', 'on_time' not in schema)
t2_block = schema.split('create table if not exists nl.raw_t2')[1].split('create index')[0]
check('tier two store keeps no free text label', 'label' not in t2_block.lower())
check('schema has separate tier one and tier two stores',
      'nl.raw_t1' in schema and 'nl.raw_t2' in schema)
check('schema declares the suppression reasons',
      all(r in schema for r in ['floor', 'delta', 'sticky', 'complementary',
                                'over_suppression']))

check('ingest accepts a single object', 'jsonb_build_array(p)' in ingest)
check('ingest accepts an array and an events wrapper',
      "'array'" in ingest and "'events'" in ingest)
check('ingest rejects identity fields', 'reject_identity' in ingest)
check('ingest uses 22023 for shape errors', '22023' in ingest)

check('release folds under an advisory lock', 'pg_advisory_xact_lock' in release)
check('release enforces the floor', 'denom_true < 15' in release)
check('release rounds to five', '(num / 5) * 5' in release)
check('release runs the release audit', 'assert_release_safe' in release)
check('release exposes a json document', 'release_json' in release)

check('retention has a purge routine', 'purge_raw' in retention)
check('retention states the 48 hour ceiling', '48 hours' in retention)
check('retention guards maintenance mode', 'allow_maintenance' in retention)

check('dashboard never uses innerHTML', 'innerHTML' not in script)
check('dashboard never sets document.write', 'document.write' not in script)
check('dashboard sends no credentials', "credentials: 'omit'" in script)
check('dashboard times out', 'AbortController' in script and '10000' in script)
check('dashboard explains withholding', 'withheld' in script)
check('dashboard has a cold start message', 'Not enough data yet' in script)

check('readme documents the database run', 'docker' in readme and 'psql' in readme)
check('readme states what is unverified', 'not been run' in readme or 'has not been run' in readme)
check('legal delta names the controller question', 'controller' in delta.lower())
check('legal delta corrects the health claim', 'health' in delta.lower())


# ---------------------------------------------------------------- reporting

failed = 0
for ok, name, detail in RESULTS:
    if ok:
        print('PASS  ' + name)
    else:
        failed += 1
        line = 'FAIL  ' + name
        if detail:
            line += '  [' + detail + ']'
        print(line)

print('')
print(str(len(RESULTS)) + ' checks, ' + str(len(RESULTS) - failed) + ' passed, '
      + str(failed) + ' failed')

sys.exit(1 if failed else 0)
