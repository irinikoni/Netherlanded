#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Reference implementation of the Netherlanded disclosure-control rules.

This module mirrors the logic in db/003_release.sql (tested alongside it in
tools/run_pg_tests.py). Each release rule is isolated so a change here or in
SQL can be checked against tools/test_suppression.py.
"""

from decimal import Decimal, ROUND_HALF_UP

FLOOR = 15
ROUND_TO = 5
DELTA_MIN = Decimal('0.05')
MAX_COMPLEMENT_PASSES = 20

SUPPRESS_REASONS = ('floor', 'delta', 'sticky', 'complementary', 'over_suppression')


def round_down_5(n):
    if n <= 0:
        return 0
    return (n // ROUND_TO) * ROUND_TO


NOISE_MOD = 252  # record keys are 0..251; 252 is divisible by 9
NOISE_HALF_WIDTH = 4


def cell_noise(key):
    """Mirror of nl.cell_noise(): fixed -4..+4 perturbation from a cell key; key 0 gives 0."""
    k = (int(key or 0) % NOISE_MOD) % (2 * NOISE_HALF_WIDTH + 1)
    return (k + NOISE_HALF_WIDTH) % (2 * NOISE_HALF_WIDTH + 1) - NOISE_HALF_WIDTH


def round_nearest_5(n):
    """Unbiased rounding to the nearest multiple of five (half away from zero, like SQL round())."""
    if n <= 0:
        return 0
    return int((Decimal(n) / ROUND_TO).quantize(Decimal('1'), rounding=ROUND_HALF_UP)) * ROUND_TO


def round_rate(num, denom):
    if denom <= 0:
        return None
    val = (Decimal(num) / Decimal(denom)).quantize(Decimal('0.001'), rounding=ROUND_HALF_UP)
    if val < Decimal('0'):
        return 0.0
    if val > Decimal('1'):
        return 1.0
    return float(val)


def rate_band(num, denom):
    if denom <= 0:
        return None
    scaled = (Decimal(num) * Decimal('20') / Decimal(denom)).quantize(Decimal('1'), rounding=ROUND_HALF_UP)
    band = int(scaled) * 5
    return max(0, min(100, band))


def bucket_label(denom):
    if denom is None or denom < 15:
        return '<15'
    if denom < 50:
        return '15-49'
    if denom < 100:
        return '50-99'
    return '100+'


def _cell_key(c):
    return (c['table_id'], c['row'], c['col'])


def _col_group_key(c):
    tid = c['table_id']
    if (tid.startswith('t1_inst_') or tid.startswith('t2_inst_')) and ':' in str(c['row']):
        scope = str(c['row']).split(':', 1)[0]
    else:
        scope = ''
    return (tid, scope, c['col'])


def _previous_rate(previous, key):
    if not previous:
        return None
    entry = previous.get(key)
    if entry is None:
        return None
    if isinstance(entry, dict):
        if 'rate_true' in entry and entry['rate_true'] is not None:
            return Decimal(str(entry['rate_true']))
        if 'rate' in entry and entry['rate'] is not None:
            return Decimal(str(entry['rate']))
        return None
    return Decimal(str(entry))


def suppress(cells, previous_published=None, previous_suppressed=None):
    """Apply the six-step suppression chain to a list of accumulated cells."""
    stage = []
    for raw in cells:
        num = int(raw['num'])
        denom = int(raw['denom'])
        # cell-key perturbation, then rounding; published denominators are clamped to >= FLOOR
        denom_pub = max(FLOOR, round_nearest_5(denom + cell_noise(raw.get('denom_key', 0))))
        num_pub = min(round_nearest_5(num + cell_noise(raw.get('num_key', 0))), denom_pub)
        stage.append({
            'table_id': raw['table_id'],
            'row': raw['row'],
            'col': raw['col'],
            'num_true': num,
            'denom_true': denom,
            'num_pub': num_pub,
            'denom_pub': denom_pub,
            'rate': None,
            'band': None,
            'reason': None,
            'bucket': bucket_label(denom),
        })

    # 1. floor
    for c in stage:
        if c['denom_true'] < FLOOR:
            c['reason'] = 'floor'

    # 2. round to five and derive rate and band
    for c in stage:
        if c['reason'] is None and c['denom_pub'] > 0:
            c['rate'] = round_rate(c['num_pub'], c['denom_pub'])
            c['band'] = rate_band(c['num_pub'], c['denom_pub'])

    # 3. delta against the last published release (rounded & clamped to 5dp like SQL numeric(7,5))
    for c in stage:
        if c['reason'] is not None or c['denom_true'] <= 0:
            continue
        prev = _previous_rate(previous_published, _cell_key(c))
        if prev is None:
            continue
        true_rate = (Decimal(c['num_true']) / Decimal(c['denom_true'])).quantize(Decimal('0.00001'), rounding=ROUND_HALF_UP)
        true_rate = max(Decimal('0.00000'), min(Decimal('1.00000'), true_rate))
        diff = abs(true_rate - prev)
        threshold = max(DELTA_MIN, Decimal(ROUND_TO) / Decimal(c['denom_true']))
        if Decimal('0') < diff < threshold:
            c['reason'] = 'delta'
            c['rate'] = None
            c['band'] = None

    # 4. sticky: withheld in either of the previous two releases for any reason other than floor or sticky
    sticky_keys = set()
    for r in (previous_suppressed or []):
        if r.get('reason') not in ('floor', 'sticky'):
            sticky_keys.add((r['table_id'], r['row'], r['col']))
    for c in stage:
        if c['reason'] is None and _cell_key(c) in sticky_keys:
            c['reason'] = 'sticky'
            c['rate'] = None
            c['band'] = None

    # 5. complementary: never leave a lone published cell in any row or scoped column
    for _ in range(MAX_COMPLEMENT_PASSES):
        changed = False
        for axis in ('row', 'col'):
            groups = {}
            for c in stage:
                key = (c['table_id'], c['row']) if axis == 'row' else _col_group_key(c)
                groups.setdefault(key, []).append(c)
            for members in groups.values():
                if len(members) <= 1:
                    continue
                open_cells = [m for m in members if m['reason'] is None]
                if len(open_cells) == 1:
                    victim = open_cells[0]
                    victim['reason'] = 'complementary'
                    victim['rate'] = None
                    victim['band'] = None
                    changed = True
        # 5b. secondary: a lone withheld cell in an institution-scoped column is
        # recoverable from the institution total, so withhold its smallest sibling too
        groups = {}
        for c in stage:
            gk = _col_group_key(c)
            if gk[1]:
                groups.setdefault(gk, []).append(c)
        for members in groups.values():
            if len(members) <= 1:
                continue
            withheld = [m for m in members if m['reason'] is not None]
            open_cells = [m for m in members if m['reason'] is None]
            if len(withheld) == 1 and open_cells:
                victim = min(open_cells, key=lambda m: (m['denom_true'], str(m['row'])))
                victim['reason'] = 'complementary'
                victim['rate'] = None
                victim['band'] = None
                changed = True
        if not changed:
            break

    # 6. defensive sweep across both axes
    for axis in ('row', 'col'):
        groups = {}
        for c in stage:
            key = (c['table_id'], c['row']) if axis == 'row' else _col_group_key(c)
            groups.setdefault(key, []).append(c)
        for members in groups.values():
            if len(members) > 1:
                open_cells = [m for m in members if m['reason'] is None]
                if len(open_cells) == 1:
                    victim = open_cells[0]
                    victim['reason'] = 'over_suppression'
                    victim['rate'] = None
                    victim['band'] = None

    return stage


def check_release(stage):
    """Mirror nl.assert_release_safe(). Returns a list of violations (empty when safe)."""
    problems = []
    for c in stage:
        if c['reason'] is not None:
            if c['rate'] is not None or c['band'] is not None:
                problems.append(('suppressed_has_value', _cell_key(c)))
            continue
        if c['denom_pub'] < FLOOR:
            problems.append(('below_floor', _cell_key(c)))
        if c['denom_pub'] % ROUND_TO != 0 or c['num_pub'] % ROUND_TO != 0:
            problems.append(('unrounded', _cell_key(c)))
        if c['num_pub'] > c['denom_pub']:
            problems.append(('num_gt_denom', _cell_key(c)))
        if c['rate'] is None or c['rate'] < 0 or c['rate'] > 1:
            problems.append(('bad_rate', _cell_key(c)))

    for axis in ('row', 'col'):
        groups = {}
        for c in stage:
            key = (c['table_id'], c['row']) if axis == 'row' else _col_group_key(c)
            groups.setdefault(key, []).append(c)
        for key, members in groups.items():
            if len(members) > 1:
                open_cells = [m for m in members if m['reason'] is None]
                if len(open_cells) == 1:
                    problems.append(('lone_cell', axis, key))
                if axis == 'col' and key[1]:
                    withheld = [m for m in members if m['reason'] is not None]
                    if len(withheld) == 1:
                        problems.append(('lone_withheld', axis, key))

    return problems
