#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Run all Netherlanded SQL migrations, live role tests, and adversarial SDC regressions
against an embedded PostgreSQL server (`pgserver` + `psycopg[binary]`).
"""

from concurrent.futures import ThreadPoolExecutor
import json
import os
import re
import shutil
import sys
import tempfile

import pgserver
import psycopg

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DB_DIR = os.path.join(ROOT, 'db')

RESULTS = []


def check(name, condition, detail=''):
    RESULTS.append((bool(condition), name, detail))


def read_sql(filename):
    with open(os.path.join(DB_DIR, filename), 'r', encoding='utf-8') as f:
        return f.read()


def reset_data(conn):
    conn.execute(
        'truncate nl.raw_t1, nl.raw_t2, nl.accumulated_cell, nl.t1_cohort, '
        'nl.t2_base, nl.stage_cell, nl.published_cell, nl.suppressed_cell, '
        'nl.snapshot, nl.unmapped_value, nl.accumulation_run, nl.ingest_rate_limits restart identity cascade'
    )


def ingest_t1_chunked(conn, items):
    for i in range(0, len(items), 100):
        conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(items[i:i + 100]),))


def ingest_t2_chunked(conn, items):
    for i in range(0, len(items), 100):
        conn.execute('select nl.ingest_t2_rpc(%s::jsonb)', (json.dumps(items[i:i + 100]),))


def main():
    pgdata = tempfile.mkdtemp(prefix='nlpg_')
    pg = None
    try:
        pg = pgserver.get_server(pgdata)
        uri = pg.get_uri()
        with psycopg.connect(uri, autocommit=True) as conn:
            ver = conn.execute('select version()').fetchone()[0]
            print(f'PostgreSQL booted: {ver}')

            # 1. Apply migrations in exact order
            migrations = [
                '001_schema.sql',
                '002_ingest.sql',
                '003_release.sql',
                '004_retention.sql',
                '006_security_rls_and_scoping.sql',
                '007_seed_vocab.sql',
                '008_scoped_insights.sql',
                'test_sql.sql',
            ]
            for fname in migrations:
                try:
                    conn.execute(read_sql(fname))
                    check(f'execute {fname}', True)
                except Exception as exc:
                    check(f'execute {fname}', False, str(exc))

            # Deterministic record keys (cell-key noise = 0) for every suite that asserts exact
            # published numbers; section 9 restores random keys and tests the perturbation itself.
            conn.execute('alter table nl.raw_t1 alter column rkey set default 0')
            conn.execute('alter table nl.raw_t2 alter column rkey set default 0')

            # 2. Isolated live test of db/005_content_editor_security_fix.sql
            try:
                sql5_body = re.sub(r'^\s*(begin|commit)\s*;\s*$', '', read_sql('005_content_editor_security_fix.sql'), flags=re.I | re.M)
                conn.execute('begin;')
                conn.execute("""
                    create schema auth;
                    create or replace function auth.jwt() returns jsonb
                    language sql stable as $$
                      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
                    $$;
                    create table public.institution_campuses (
                      institution_id text not null,
                      city_id text not null
                    );
                    insert into public.institution_campuses values
                      ('rug', 'groningen'),
                      ('uva', 'amsterdam'),
                      ('vu', 'amsterdam');
                """)
                conn.execute(sql5_body)

                conn.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'app_metadata': {'role': 'super_admin'}}),))
                check('005 super_admin can edit shared city amsterdam', conn.execute("select public.can_edit_city('amsterdam')").fetchone()[0] is True)

                conn.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'app_metadata': {'role': 'editor', 'institution_id': 'uva'}}),))
                check('005 uva editor blocked from shared city amsterdam', conn.execute("select public.can_edit_city('amsterdam')").fetchone()[0] is False)

                conn.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({'app_metadata': {'role': 'editor', 'institution_id': 'rug'}}),))
                check('005 rug editor allowed on single-school city groningen', conn.execute("select public.can_edit_city('groningen')").fetchone()[0] is True)
                check('005 rug editor blocked on amsterdam', conn.execute("select public.can_edit_city('amsterdam')").fetchone()[0] is False)

                conn.execute("select set_config('request.jwt.claims', '{}', true)")
                check('005 anonymous user blocked on groningen', conn.execute("select public.can_edit_city('groningen')").fetchone()[0] is False)
                conn.execute('rollback;')
            except Exception as exc:
                try:
                    conn.execute('rollback;')
                except Exception:
                    pass
                check('005 live privilege test', False, str(exc))

            # 3. Live Supabase-style role-isolation & dashboard-payload test
            try:
                conn.execute("""
                    do $$ begin
                      if not exists (select 1 from pg_roles where rolname = 'anon') then
                        create role anon nologin;
                      end if;
                      if not exists (select 1 from pg_roles where rolname = 'authenticated') then
                        create role authenticated nologin;
                      end if;
                    end $$;
                """)
                # Reproduce Supabase's default ACLs: every new table/function/sequence in the
                # public schema is granted to anon and authenticated (applies to 009 below).
                conn.execute("""
                    grant usage on schema public to anon, authenticated;
                    alter default privileges in schema public grant all on tables to anon, authenticated;
                    alter default privileges in schema public grant all on functions to anon, authenticated;
                    alter default privileges in schema public grant all on sequences to anon, authenticated;
                """)
                conn.execute(read_sql('006_security_rls_and_scoping.sql'))
                conn.execute(read_sql('008_scoped_insights.sql'))

                t1_batch = (
                    [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(12)]
                    + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'money', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'money', 'app_version': '3b32b5914fb6bdfc'} for _ in range(3)]
                    + [{'institution': 'uva', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'uva', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                )
                t2_batch = (
                    [{'institution': 'thuas', 'region': 'eu_eea', 'intake': '2026-sep', 'event': 'joined'} for _ in range(20)]
                    + [{'institution': 'thuas', 'region': 'eu_eea', 'intake': '2026-sep', 'event': 'arrived'} for _ in range(15)]
                    + [{'institution': 'thuas', 'region': 'eu_eea', 'intake': '2026-sep', 'event': 'step_applies', 'step': 'find_housing'} for _ in range(20)]
                    + [{'institution': 'thuas', 'region': 'eu_eea', 'intake': '2026-sep', 'event': 'step_completed', 'step': 'find_housing'} for _ in range(10)]
                )

                conn.execute('begin;')
                conn.execute('set local role anon')
                cnt1 = 0
                for i in range(0, len(t1_batch), 100):
                    cnt1 += conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(t1_batch[i:i + 100]),)).fetchone()[0]
                cnt2 = conn.execute('select nl.ingest_t2_rpc(%s::jsonb)', (json.dumps(t2_batch),)).fetchone()[0]
                check('role anon can call ingest_t1_rpc & ingest_t2_rpc', cnt1 == len(t1_batch) and cnt2 == len(t2_batch), f'{cnt1}/{cnt2}')

                for label, q in [
                    ('role anon blocked from SELECT nl.raw_t1', 'select * from nl.raw_t1'),
                    ('role anon blocked from nl.publish_snapshot', "select nl.publish_snapshot('x')"),
                    ('role anon blocked from nl.release_json_for_institution', "select nl.release_json_for_institution('thuas')"),
                    ('role anon blocked from nl.health', 'select nl.health()'),
                ]:
                    conn.execute('savepoint sp_anon')
                    blocked = False
                    try:
                        conn.execute(q)
                    except psycopg.errors.InsufficientPrivilege:
                        blocked = True
                    finally:
                        if blocked:
                            conn.execute('rollback to savepoint sp_anon')
                    check(label, blocked)
                conn.execute('commit;')

                conn.execute('select nl.accumulate()')
                snap_id = conn.execute("select nl.publish_snapshot('live-role-test')").fetchone()[0]
                check('owner accumulate + publish_snapshot succeeded', snap_id is not None, str(snap_id))

                conn.execute('begin;')
                conn.execute('set local role authenticated')
                conn.execute(
                    "select set_config('request.jwt.claims', %s, true)",
                    (json.dumps({'role': 'authenticated', 'app_metadata': {'role': 'reader', 'institution_id': 'thuas'}}),),
                )
                doc = conn.execute("select nl.release_json_for_institution('thuas', %s)", (snap_id,)).fetchone()[0]
                check('role authenticated thuas gets scoped release JSON', doc['meta']['institution'] == 'thuas' and doc['meta']['published'] is True)

                table_ids = {t['table_id'] for t in doc['tables']}
                check('authenticated thuas excludes pooled cross-institution tables',
                      't1_category_totals' not in table_ids and 't2_step_totals' not in table_ids and 't1_inst_category' in table_ids,
                      str(sorted(table_ids)))

                # Check tail-capped num/rate/band redaction, <50 rate redaction, and suppressed reason redaction for non-super_admin
                cat_tbl = [t for t in doc['tables'] if t['table_id'] == 't1_inst_category'][0]
                money_cell = [c for c in cat_tbl['cells'] if c['row'] == 'thuas:money'][0]
                housing_cell = [c for c in cat_tbl['cells'] if c['row'] == 'thuas:housing'][0]
                check('authenticated reader gets null num/rate/band and a count-range label on tail-capped cell',
                      money_cell['num'] is None and money_cell['rate'] is None and money_cell['band'] is None
                      and money_cell['rate_display'] == 'fewer than 12 of ' + str(money_cell['denom']),
                      str(money_cell))
                check('authenticated reader gets null num and rate (only band) when denom < 50',
                      housing_cell['num'] is None and housing_cell['rate'] is None and housing_cell['band'] is not None,
                      str(housing_cell))

                leaked_uva = []
                for t in doc['tables']:
                    for c in t['cells'] + t['withheld']:
                        if c['row'] == 'uva' or c['row'].startswith('uva:'):
                            leaked_uva.append((t['table_id'], c['row']))
                        if c in t['withheld'] and c.get('reason') is not None:
                            leaked_uva.append(('reason_leaked', c.get('reason')))
                check('authenticated thuas JSON contains zero uva rows and redacts withheld reasons', len(leaked_uva) == 0, str(leaked_uva))

                # Fail-closed checks: empty JWT & student role
                for label, claims, target_inst in [
                    ('authenticated thuas blocked from uva (42501)', {'role': 'authenticated', 'app_metadata': {'role': 'reader', 'institution_id': 'uva'}}, 'thuas'),
                    ('authenticated empty JWT blocked (42501)', {}, 'thuas'),
                    ('authenticated student role blocked (42501)', {'role': 'authenticated', 'app_metadata': {'role': 'student', 'institution_id': 'thuas'}}, 'thuas'),
                ]:
                    conn.execute('savepoint sp_auth')
                    conn.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps(claims),))
                    blocked = False
                    try:
                        conn.execute("select nl.release_json_for_institution(%s, %s)", (target_inst, snap_id))
                    except psycopg.errors.InsufficientPrivilege:
                        blocked = True
                    finally:
                        if blocked:
                            conn.execute('rollback to savepoint sp_auth')
                    check(label, blocked)
                conn.execute('commit;')
            except Exception as exc:
                try:
                    conn.execute('rollback;')
                except Exception:
                    pass
                check('live role-isolation test', False, str(exc))

            # 4. Adversarial SDC & Security Regression Suite
            try:
                # R1: Unchanged 10/15 cell does NOT self-suppress as 'delta' on release 2
                reset_data(conn)
                b = []
                for cat in ('housing', 'money'):
                    b += [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': cat, 'app_version': '3b32b5914fb6bdfc'} for _ in range(15)]
                    b += [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': cat, 'app_version': '3b32b5914fb6bdfc'} for _ in range(10)]
                b += [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(15)]
                ingest_t1_chunked(conn, b)
                conn.execute('select nl.accumulate()')
                s1 = conn.execute("select nl.publish_snapshot('unchanged-1')").fetchone()[0]
                s2 = conn.execute("select nl.publish_snapshot('unchanged-2')").fetchone()[0]
                pub_cnt = conn.execute("select count(*) from nl.published_cell where snapshot_id = %s and table_id = 't1_inst_category'", (s2,)).fetchone()[0]
                check('regression: unchanged 10/15 cell stays published on release 2 (no precision delta)', pub_cnt == 2, f'pub_cnt={pub_cnt}')

                # R2: carry-forward. A change of fewer than 5 contributions republishes the previous
                # value unchanged (DISCLOSURE_CONTROL.md §5); 5 or more publishes fresh.
                def housing_row(snap):
                    return conn.execute("select num, denom, rate, band, carried from nl.published_cell where snapshot_id=%s "
                                        "and table_id='t1_inst_category' and row_key='thuas:housing'", (snap,)).fetchone()
                base = housing_row(s2)
                ingest_t1_chunked(conn, [
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                ])
                conn.execute('select nl.accumulate()')
                s3 = conn.execute("select nl.publish_snapshot('carry-r3')").fetchone()[0]
                r3 = housing_row(s3)
                check('regression: +1 contribution republishes the previous housing value (carried, not withheld)',
                      r3 is not None and r3[:4] == base[:4] and r3[4] is True, f'base={base}, r3={r3}')
                ingest_t1_chunked(conn, [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'}] * 2)
                conn.execute('select nl.accumulate()')
                s4 = conn.execute("select nl.publish_snapshot('carry-r4')").fetchone()[0]
                basis4 = conn.execute("select num_true, denom_true from nl.published_cell where snapshot_id=%s and table_id='t1_inst_category' "
                                      "and row_key='thuas:housing'", (s4,)).fetchone()
                check('regression: small changes accumulate against the carried basis (3 total -> still carried, basis 10/15)',
                      housing_row(s4)[4] is True and basis4 == (10, 15), f'basis={basis4}')
                ingest_t1_chunked(conn, [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'}] * 2)
                conn.execute('select nl.accumulate()')
                s5 = conn.execute("select nl.publish_snapshot('carry-r5')").fetchone()[0]
                r5 = housing_row(s5)
                check('regression: 5 accumulated contributions publish fresh (11/20)',
                      r5 is not None and r5[4] is False and (r5[0], r5[1]) == (10, 20), f'r5={r5}')

                # R2b: livelock regression. The retired sticky rule cycled two cells of one column through
                # complementary/sticky forever once the small one passed the floor.
                reset_data(conn)
                ingest_t1_chunked(conn, [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'}] * 20
                                  + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'}] * 20
                                  + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'money', 'app_version': '3b32b5914fb6bdfc'}] * 10)
                conn.execute('select nl.accumulate()')
                l1 = conn.execute("select nl.publish_snapshot('livelock-1')").fetchone()[0]
                ingest_t1_chunked(conn, [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'money', 'app_version': '3b32b5914fb6bdfc'}] * 10)
                conn.execute('select nl.accumulate()')
                l2 = conn.execute("select nl.publish_snapshot('livelock-2')").fetchone()[0]
                withheld1 = conn.execute("select count(*) from nl.suppressed_cell where snapshot_id=%s and table_id='t1_inst_category'", (l1,)).fetchone()[0]
                published2 = conn.execute("select count(*) from nl.published_cell where snapshot_id=%s and table_id='t1_inst_category'", (l2,)).fetchone()[0]
                check('regression: once the small cell passes the floor, both cells publish (no sticky livelock)',
                      withheld1 == 2 and published2 == 2, f'withheld1={withheld1}, published2={published2}')

                # R3: 15-student contributor floor blocks 3 students emitting 15 health step_applies
                reset_data(conn)
                b = [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(3)]
                for _ in range(15):
                    b.append({'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'health', 'app_version': '3b32b5914fb6bdfc'})
                ingest_t1_chunked(conn, b)
                conn.execute('select nl.accumulate()')
                s_floor = conn.execute("select nl.publish_snapshot('3-students-15-steps')").fetchone()[0]
                health_pub = conn.execute("select count(*) from nl.published_cell where snapshot_id=%s and table_id='t1_inst_category' and row_key='thuas:health'", (s_floor,)).fetchone()[0]
                check('regression: 3 students with 15 health steps blocked by 15-student contributor floor', health_pub == 0, f'health_pub={health_pub}')

                # R3b: 14 eu_eea + 1 non_eu (total joined=15) blocks single non_eu student in t2_inst_region
                reset_data(conn)
                t2_reg = (
                    [{'institution': 'thuas', 'region': 'eu_eea', 'intake': '2026-sep', 'event': 'joined'} for _ in range(14)]
                    + [{'institution': 'thuas', 'region': 'non_eu', 'intake': '2026-sep', 'event': 'joined'}]
                    + [{'institution': 'thuas', 'region': 'non_eu', 'intake': '2026-sep', 'event': 'step_applies', 'step': 'find_housing'} for _ in range(15)]
                )
                conn.execute('select nl.ingest_t2_rpc(%s::jsonb)', (json.dumps(t2_reg),))
                conn.execute('select nl.accumulate()')
                s_reg = conn.execute("select nl.publish_snapshot('1-non-eu-region-floor')").fetchone()[0]
                non_eu_pub = conn.execute("select count(*) from nl.published_cell where snapshot_id=%s and table_id='t2_inst_region' and row_key='thuas:non_eu'", (s_reg,)).fetchone()[0]
                check('regression: 1 non_eu student blocked by per-region t2_region_base >= 15 floor', non_eu_pub == 0, f'non_eu_pub={non_eu_pub}')

                # R4: Scoped complementary suppression isolates thuas vs uva in inst_* tables
                reset_data(conn)
                b = (
                    [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'money', 'app_version': '3b32b5914fb6bdfc'} for _ in range(5)]
                    + [{'institution': 'uva', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'uva', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                )
                ingest_t1_chunked(conn, b)
                conn.execute('select nl.accumulate()')
                s_comp = conn.execute("select nl.publish_snapshot('scoped-comp')").fetchone()[0]
                doc_comp = conn.execute("select nl.release_json_for_institution('thuas', %s)", (s_comp,)).fetchone()[0]
                cat_comp = [t for t in doc_comp['tables'] if t['table_id'] == 't1_inst_category'][0]
                check('regression: scoped complementary suppression withholds lone thuas cell even with uva present',
                      len(cat_comp['cells']) == 0 and len(cat_comp['withheld']) == 2,
                      f"cells={len(cat_comp['cells'])}, withheld={len(cat_comp['withheld'])}")

                # R5: 4x5 alternating matrix converges cleanly without assert_release_safe 23514 crash
                reset_data(conn)
                b = []
                for intake in ('2025-feb', '2025-sep', '2026-feb', '2026-sep', '2027-feb'):
                    b += [{'institution': 'thuas', 'intake': intake, 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                # R1: C1,C2 | R2: C2,C3 | R3: C3,C4,C5 | R4: C4,C5 (non-listed floored at 5)
                healthy = {
                    ('housing', '2025-feb'), ('housing', '2025-sep'),
                    ('money', '2025-sep'), ('money', '2026-feb'),
                    ('health', '2026-feb'), ('health', '2026-sep'), ('health', '2027-feb'),
                    ('work', '2026-sep'), ('work', '2027-feb'),
                }
                for cat in ('housing', 'money', 'health', 'work'):
                    for intake in ('2025-feb', '2025-sep', '2026-feb', '2026-sep', '2027-feb'):
                        n = 20 if (cat, intake) in healthy else 5
                        b += [{'institution': 'thuas', 'intake': intake, 'event': 'step_applies', 'category': cat, 'app_version': '3b32b5914fb6bdfc'} for _ in range(n)]
                ingest_t1_chunked(conn, b)
                conn.execute('select nl.accumulate()')
                s_mat = conn.execute("select nl.publish_snapshot('4x5-matrix')").fetchone()[0]
                check('regression: 4x5 matrix complementary loop converges safely without 23514', s_mat is not None)

                # R6: LIKE '_' wildcard institution isolation (a_b vs axb)
                reset_data(conn)
                conn.execute("insert into nl.institution values ('a_b','A_B',true), ('axb','AXB',true) on conflict do nothing")
                b = (
                    [{'institution': 'axb', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                    + [{'institution': 'axb', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(20)]
                )
                ingest_t1_chunked(conn, b)
                conn.execute('select nl.accumulate()')
                s_like = conn.execute("select nl.publish_snapshot('like-wildcard')").fetchone()[0]
                doc_ab = conn.execute("select nl.release_json_for_institution('a_b', %s)", (s_like,)).fetchone()[0]
                cat_ab = [t for t in doc_ab['tables'] if t['table_id'] == 't1_inst_category'][0]
                check('regression: institution a_b sees zero axb rows (LIKE wildcard fixed)',
                      len(cat_ab['cells']) == 0 and len(cat_ab['withheld']) == 0, str(cat_ab))

                # R7: technical_error creates zero phantom 0/0 cells, and nl.health() flags >48h raw_t2
                reset_data(conn)
                conn.execute("select nl.ingest_t1_rpc(%s::jsonb)", (json.dumps({'institution': 'thuas', 'intake': '2026-sep', 'event': 'technical_error', 'app_version': '3b32b5914fb6bdfc'}),))
                conn.execute('select nl.accumulate()')
                phantom = conn.execute("select count(*) from nl.accumulated_cell where table_id in ('t1_institution_intake', 't1_category_totals', 't1_inst_category')").fetchone()[0]
                check('regression: technical_error creates zero phantom 0/0 cells', phantom == 0, f'phantom={phantom}')

                conn.execute("insert into nl.raw_t1 (institution, intake, event, category, app_version, received_at) values ('thuas', '2026-sep', 'cohort_joined', null, '3b32b5914fb6bdfc', now() - interval '26 hours')")
                h1 = conn.execute('select nl.health()').fetchone()[0]
                check('regression: nl.health() detects >24h raw_t1 breach (ok=false)',
                      h1['ok'] is False and float(h1['raw_t1_oldest_hours']) >= 24.0, str(h1))

                conn.execute("insert into nl.raw_t2 (institution, region, intake, event, received_at) values ('thuas', 'eu_eea', '2026-sep', 'joined', now() - interval '50 hours')")
                h = conn.execute('select nl.health()').fetchone()[0]
                check('regression: nl.health() detects >48h raw_t2 breach (ok=false)', h['ok'] is False and float(h['raw_oldest_hours']) >= 48.0, str(h))
            except Exception as exc:
                check('adversarial SQL regression suite', False, str(exc))

            # 5. Live Content Editor schema, RLS, privilege scoping, versioning & immutability tests
            try:
                conn.execute("""
                    create schema if not exists auth;
                    create or replace function auth.jwt() returns jsonb
                    language sql stable as $$
                      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
                    $$;
                """)
                conn.execute(read_sql('009_content_editor.sql'))
                check('execute 009_content_editor.sql', True)

                conn.execute('begin;')
                # Anon & empty authenticated blocked (42501)
                conn.execute('set local role anon')
                conn.execute('savepoint sp_ed_anon')
                anon_blk = False
                try:
                    conn.execute("select nl_content.editor_list()")
                except psycopg.errors.InsufficientPrivilege:
                    anon_blk = True
                conn.execute('rollback to savepoint sp_ed_anon')
                check('009 role anon blocked from nl_content.editor_list', anon_blk)

                conn.execute('set local role authenticated')
                conn.execute("select set_config('request.jwt.claims', '{}', true)")
                conn.execute('savepoint sp_ed_empty')
                empty_blk = False
                try:
                    conn.execute("select nl_content.editor_list()")
                except psycopg.errors.InsufficientPrivilege:
                    empty_blk = True
                conn.execute('rollback to savepoint sp_ed_empty')
                check('009 authenticated without role claim blocked (42501)', empty_blk)

                # THUAS editor scope tests
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'thuas-1', 'app_metadata': {'role': 'editor', 'institution_id': 'thuas'}}),))
                ed_doc = conn.execute("select nl_content.editor_list()").fetchone()[0]
                check('009 thuas editor_list returns services, facts, campus_cities & editable_cities=[zoetermeer]',
                      ed_doc['meta']['editable_cities'] == ['zoetermeer']
                      and ed_doc['meta']['campus_cities'] == ['delft', 'leidschendam-voorburg', 'rijswijk', 'the-hague', 'zoetermeer']
                      and len(ed_doc['services']) >= 5,
                      str(ed_doc['meta']))
                check('009 thuas editor blocked on Heerlen/Sittard-Geleen while zuyd owns them',
                      conn.execute("select public.can_edit_city('heerlen')").fetchone()[0] is False
                      and conn.execute("select public.can_edit_city('sittard-geleen')").fetchone()[0] is False)

                # Allowed: own-institution service + single-school city service + step_local override
                own_res = conn.execute(
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'thuas_io', 'name': 'THUAS International Office Updated',
                        'service_type': 'support', 'city_id': 'the-hague', 'municipality_id': 'the-hague',
                        'for_institution_id': 'thuas', 'description': 'Updated arrival schedule desk.',
                        'url': 'https://www.thuas.com/study-choice/international-office'
                    }), 'Updated THUAS office copy')
                ).fetchone()[0]
                zoo_res = conn.execute(
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'zoetermeer_desk', 'name': 'Gemeente Zoetermeer BRP Desk',
                        'service_type': 'municipal', 'city_id': 'zoetermeer', 'municipality_id': 'zoetermeer',
                        'for_institution_id': None, 'description': 'Verified single-school municipal desk.',
                        'url': 'https://www.zoetermeer.nl/'
                    }), 'Verified Zoetermeer desk')
                ).fetchone()[0]
                sl_res = conn.execute(
                    "select nl_content.editor_upsert_step_local(%s::jsonb, %s)",
                    (json.dumps({
                        'step_id': 'register_municipality', 'municipality_id': 'the-hague',
                        'for_institution_id': 'thuas',
                        'body': 'THUAS students book through The Hague International Centre student intake days.',
                        'links': [{'label': 'THUAS Arrival', 'url': 'https://www.thuas.com/study-choice/international-office/arrival-services'}]
                    }), 'Added THUAS override for Den Haag BRP')
                ).fetchone()[0]
                check('009 thuas editor can edit own service, single-school city & override step_local',
                      own_res['name'].endswith('Updated') and zoo_res['service_id'] == 'zoetermeer_desk' and sl_res['for_institution_id'] == 'thuas')

                # Blocked for thuas editor: shared municipal service, hijack via for_institution_id, foreign school, shared step_local, fact publish
                def assert_blocked(label, sql, params, exc_cls=psycopg.errors.InsufficientPrivilege):
                    conn.execute('savepoint sp_ed_blk')
                    hit = False
                    try:
                        conn.execute(sql, params)
                    except exc_cls:
                        hit = True
                    conn.execute('rollback to savepoint sp_ed_blk')
                    check(label, hit)

                assert_blocked(
                    '009 thuas editor blocked on shared-city municipal service (the-hague)',
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'the_student_doctors', 'name': 'Tamper', 'service_type': 'gp',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': None,
                        'description': 'Tamper', 'url': 'https://www.thestudentdoctors.nl/'
                    }), 'Attempt shared municipal edit')
                )
                assert_blocked(
                    '009 thuas editor blocked from hijacking municipal service via for_institution_id',
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'the_student_doctors', 'name': 'Hijack', 'service_type': 'gp',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'thuas',
                        'description': 'Hijack', 'url': 'https://www.thestudentdoctors.nl/'
                    }), 'Attempt hijack')
                )
                assert_blocked(
                    '009 thuas editor blocked on foreign institution service (leiden-th)',
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'leiden_th_desk', 'name': 'Leiden Desk', 'service_type': 'support',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'leiden-th',
                        'description': 'Foreign edit', 'url': 'https://www.universiteitleiden.nl/den-haag'
                    }), 'Attempt foreign school create')
                )
                assert_blocked(
                    '009 thuas editor blocked on shared-city step_local without override',
                    "select nl_content.editor_upsert_step_local(%s::jsonb, %s)",
                    (json.dumps({
                        'step_id': 'register_municipality', 'municipality_id': 'the-hague',
                        'for_institution_id': '', 'body': 'Unauthorized municipal rewrite', 'links': []
                    }), 'Attempt shared step rewrite')
                )
                assert_blocked(
                    '009 thuas editor blocked from publishing national fact (42501)',
                    "select nl_content.editor_publish_fact(%s::jsonb, %s)",
                    (json.dumps({
                        'fact_key': 'cak_fine_eur', 'label': 'CAK fine', 'value': '999.00',
                        'unit': 'EUR', 'source_id': 'cak-fine-en'
                    }), 'Attempt national fact change')
                )
                assert_blocked(
                    '009 javascript: URL rejected on service upsert (22023)',
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'thuas_io', 'name': 'XSS', 'service_type': 'support',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'thuas',
                        'description': 'XSS test', 'url': 'javascript:alert(1)'
                    }), 'Attempt XSS URL'),
                    psycopg.errors.InvalidParameterValue
                )
                assert_blocked(
                    '009 whitespace URL rejected on service upsert (22023)',
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'thuas_io', 'name': 'Bad URL', 'service_type': 'support',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'thuas',
                        'description': 'Space URL test', 'url': 'https://www.thuas.com/bad url'
                    }), 'Attempt whitespace URL'),
                    psycopg.errors.InvalidParameterValue
                )
                comm_res = conn.execute(
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'thuas_comm', 'name': 'THUAS Buddy Community', 'service_type': 'community',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'thuas',
                        'description': 'Peer community network for incoming students.',
                        'url': 'https://www.thuas.com/community', 'accepting_students': 'yes'
                    }), 'Add THUAS community service')
                ).fetchone()[0]
                gov_res = conn.execute(
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'zoetermeer_gov', 'name': 'Zoetermeer Civic Desk', 'service_type': 'government',
                        'city_id': 'zoetermeer', 'municipality_id': 'zoetermeer', 'for_institution_id': None,
                        'description': 'Government desk for Zoetermeer arrivals.',
                        'url': 'https://www.zoetermeer.nl/civic', 'accepting_students': 'yes'
                    }), 'Add Zoetermeer government service')
                ).fetchone()[0]
                check('009 service_type allows community and government with accepting_students',
                      comm_res['service_type'] == 'community' and gov_res['service_type'] == 'government' and comm_res['accepting_students'] == 'yes')

                # Campus ownership checks for zuyd (heerlen/sittard-geleen single-school) & tud (delft shared)
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'zuyd-1', 'app_metadata': {'role': 'editor', 'institution_id': 'zuyd'}}),))
                zuyd_ok = (
                    conn.execute("select public.can_edit_city('heerlen')").fetchone()[0] is True
                    and conn.execute("select public.can_edit_city('sittard-geleen')").fetchone()[0] is True
                    and conn.execute("select public.can_edit_city('maastricht')").fetchone()[0] is False
                )
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'tud-1', 'app_metadata': {'role': 'editor', 'institution_id': 'tud'}}),))
                tud_shared_blk = conn.execute("select public.can_edit_city('delft')").fetchone()[0] is False
                check('009 zuyd owns heerlen/sittard-geleen and tud blocked on shared delft', zuyd_ok and tud_shared_blk)
                assert_blocked(
                    '009 future last_verified rejected on editor_upsert_service (22023)',
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'thuas_io', 'name': 'Future Test', 'service_type': 'support',
                        'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'thuas',
                        'description': 'Future date test.', 'url': 'https://www.thuas.com/',
                        'last_verified': '2099-01-01'
                    }), 'Attempt future last_verified'),
                    psycopg.errors.InvalidParameterValue
                )
                assert_blocked(
                    '009 future last_verified rejected on editor_upsert_step_local (22023)',
                    "select nl_content.editor_upsert_step_local(%s::jsonb, %s)",
                    (json.dumps({
                        'step_id': 'register_municipality', 'municipality_id': 'the-hague',
                        'for_institution_id': 'thuas', 'body': 'Future date test.', 'links': [],
                        'last_verified': '2099-01-01'
                    }), 'Attempt future last_verified on step_local'),
                    psycopg.errors.InvalidParameterValue
                )

                # Super admin edits shared city & publishes new fact version (auto-closes previous version)
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'admin-1', 'app_metadata': {'role': 'super_admin'}}),))
                assert_blocked(
                    '009 future last_verified rejected on editor_publish_fact (22023)',
                    "select nl_content.editor_publish_fact(%s::jsonb, %s)",
                    (json.dumps({
                        'fact_key': 'cak_fine_eur', 'label': 'CAK fine', 'value': '540.00',
                        'unit': 'EUR', 'source_id': 'cak-fine-en', 'last_verified': '2099-01-01'
                    }), 'Attempt future last_verified on fact'),
                    psycopg.errors.InvalidParameterValue
                )
                sa_svc = conn.execute(
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'the_student_doctors', 'name': 'The Student Doctors (Verified)',
                        'service_type': 'gp', 'city_id': 'the-hague', 'municipality_id': 'the-hague',
                        'for_institution_id': None, 'description': 'Verified municipal GP list.',
                        'url': 'https://www.thestudentdoctors.nl/'
                    }), 'Super admin shared city verification')
                ).fetchone()[0]
                sa_fact = conn.execute(
                    "select nl_content.editor_publish_fact(%s::jsonb, %s)",
                    (json.dumps({
                        'fact_key': 'cak_fine_eur', 'label': 'CAK fine for being uninsured',
                        'value': '540.00', 'unit': 'EUR', 'source_id': 'cak-fine-en',
                        'step_id': 'cak_letter', 'valid_from': '2027-01-01'
                    }), 'Annual CAK rate update test')
                ).fetchone()[0]
                check('009 super_admin can edit shared city & publish versioned fact',
                      sa_svc['name'].endswith('(Verified)') and sa_fact['value'] == '540.00')

                # Tenant-scoped stale_count check: insert stale uva service & verify thuas does not count uva or national facts
                conn.execute(
                    "select nl_content.editor_upsert_service(%s::jsonb, %s)",
                    (json.dumps({
                        'service_id': 'uva_stale_test', 'name': 'UvA Old Desk', 'service_type': 'support',
                        'city_id': 'amsterdam', 'municipality_id': 'amsterdam', 'for_institution_id': 'uva',
                        'description': 'Stale cross-tenant test record.', 'url': 'https://www.uva.nl/en',
                        'last_verified': '2025-01-01'
                    }), 'Seed stale UvA service for stale_count scoping test')
                )
                sa_stale = conn.execute("select nl_content.editor_list()").fetchone()[0]['meta']['stale_count']
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'thuas-1', 'app_metadata': {'role': 'editor', 'institution_id': 'thuas'}}),))
                thuas_stale = conn.execute("select nl_content.editor_list()").fetchone()[0]['meta']['stale_count']
                check('009 editor_list stale_count is tenant-scoped (thuas < super_admin)',
                      thuas_stale < sa_stale, f'thuas_stale={thuas_stale}, sa_stale={sa_stale}')

                conn.execute('reset role')
                hist = conn.execute(
                    "select count(*), count(*) filter (where valid_to is null) from nl_content.fact where fact_key = 'cak_fine_eur'"
                ).fetchone()
                check('009 on_fact_insert auto-closes prior version (2 total, 1 active)',
                      hist[0] == 2 and hist[1] == 1, str(hist))

                audit_cnt = conn.execute("select count(*) from nl_content.staff_change").fetchone()[0]
                check('009 staff_change logged all 5 valid mutations', audit_cnt >= 5, f'audit_cnt={audit_cnt}')

                conn.execute('savepoint sp_audit_immut')
                immut_blk = False
                try:
                    conn.execute("delete from nl_content.staff_change")
                except psycopg.errors.InsufficientPrivilege:
                    immut_blk = True
                conn.execute('rollback to savepoint sp_audit_immut')
                check('009 staff_change is append-only (DELETE blocked with 42501)', immut_blk)

                conn.execute('rollback;')
            except Exception as exc:
                try:
                    conn.execute('rollback;')
                except Exception:
                    pass
                check('live Content Editor PostgreSQL suite', False, str(exc))

            # 6. Multi-connection concurrent stress test (accumulate, publish_snapshot & editor_upsert_service)
            try:
                reset_data(conn)
                conn.execute('truncate nl_content.staff_change restart identity')

                def worker_ingest(idx):
                    batch = (
                        [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'} for _ in range(25)]
                        + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(25)]
                        + [{'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'} for _ in range(15)]
                    )
                    with psycopg.connect(uri, autocommit=True) as wconn:
                        return wconn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(batch),)).fetchone()[0]

                def worker_accumulate():
                    with psycopg.connect(uri, autocommit=True) as wconn:
                        return wconn.execute('select nl.accumulate()').fetchone()[0]

                with ThreadPoolExecutor(max_workers=4) as pool:
                    futs = [
                        pool.submit(worker_ingest, 0),
                        pool.submit(worker_accumulate),
                        pool.submit(worker_ingest, 1),
                        pool.submit(worker_accumulate),
                    ]
                    for f in futs:
                        f.result()

                conn.execute('select nl.accumulate()')
                tot_contrib = conn.execute("select contributors from nl.t1_cohort where institution='thuas' and intake='2026-sep'").fetchone()[0]
                cell_nh = conn.execute("select num, denom from nl.accumulated_cell where table_id='t1_inst_category' and row_key='thuas:housing' and col_key='2026-sep'").fetchone()
                check('concurrency: parallel ingest + accumulate conserves exact counts (50 contrib, 30/50 cell)',
                      tot_contrib == 50 and cell_nh == (30, 50), f'contrib={tot_contrib}, cell={cell_nh}')

                def worker_publish(i):
                    with psycopg.connect(uri, autocommit=True) as wconn:
                        return wconn.execute('select nl.publish_snapshot(%s)', (f'concurrent-pub-{i}',)).fetchone()[0]

                with ThreadPoolExecutor(max_workers=4) as pool:
                    snaps = [f.result() for f in [pool.submit(worker_publish, i) for i in range(4)]]
                check('concurrency: 4 simultaneous publish_snapshot() calls serialize cleanly without 23505',
                      len(set(snaps)) == 4, str(snaps))

                def worker_editor(i):
                    with psycopg.connect(uri, autocommit=True) as wconn:
                        wconn.execute('begin;')
                        wconn.execute('set local role authenticated')
                        wconn.execute("select set_config('request.jwt.claims', %s, true)",
                                      (json.dumps({'sub': f'thuas-worker-{i}', 'app_metadata': {'role': 'editor', 'institution_id': 'thuas'}}),))
                        res = wconn.execute(
                            'select nl_content.editor_upsert_service(%s::jsonb, %s)',
                            (json.dumps({
                                'service_id': f'thuas_conc_{i}', 'name': f'THUAS Desk {i}',
                                'service_type': 'support', 'city_id': 'the-hague', 'municipality_id': 'the-hague',
                                'for_institution_id': 'thuas', 'description': f'Concurrent worker {i} desk.',
                                'url': 'https://www.thuas.com/study-choice/international-office'
                            }), f'Concurrent upsert {i}')
                        ).fetchone()[0]
                        wconn.execute('commit;')
                        return res['service_id']

                with ThreadPoolExecutor(max_workers=4) as pool:
                    svcs = [f.result() for f in [pool.submit(worker_editor, i) for i in range(4)]]
                conc_logs = conn.execute("select count(*) from nl_content.staff_change where entity_key like 'thuas_conc_%'").fetchone()[0]
                conn.execute("delete from nl_content.service where service_id like 'thuas_conc_%'")
                check('concurrency: 4 simultaneous editor_upsert_service() calls commit & log 4 staff_change rows',
                      len(set(svcs)) == 4 and conc_logs == 4, f'svcs={svcs}, logs={conc_logs}')
            except Exception as exc:
                check('multi-connection concurrency suite', False, str(exc))

            # 7. Review-fix regressions (ingest strictness, gateway secret, scoping, editor city_id, https)
            try:
                def rejects(sql, params, err=psycopg.errors.InvalidParameterValue):
                    try:
                        conn.execute('savepoint sp_rf')
                        conn.execute(sql, params)
                        conn.execute('rollback to savepoint sp_rf')
                        return False
                    except err:
                        conn.execute('rollback to savepoint sp_rf')
                        return True

                conn.execute('begin;')
                base1 = {'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'}
                check('fix: tier-1 rejects the unused n field',
                      rejects('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(dict(base1, n=3)),)))
                check('fix: tier-2 rejects high_risk on non-scam events',
                      rejects('select nl.ingest_t2_rpc(%s::jsonb)', (json.dumps({'institution': 'thuas', 'region': 'eu_eea', 'intake': '2026-sep', 'event': 'joined', 'high_risk': True}),)))
                conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(base1),))
                hr = conn.execute("select received_at = date_trunc('hour', received_at) from nl.raw_t1 order by id desc limit 1").fetchone()[0]
                check('fix: raw received_at is stored hour-truncated', hr is True)

                # gateway secret: enforced once configured
                conn.execute("insert into nl.ingest_gateway (secret_sha256) values (encode(sha256(convert_to('s3cret', 'UTF8')), 'hex'))")
                conn.execute("select set_config('request.headers', '{}', true)")
                check('fix: ingest without gateway header is refused once configured',
                      rejects('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(base1),), psycopg.errors.InsufficientPrivilege))
                conn.execute("select set_config('request.headers', %s, true)", (json.dumps({'x-nl-ingest-secret': 's3cret'}),))
                check('fix: ingest with correct gateway header is accepted',
                      conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(base1),)).fetchone()[0] == 1)
                # rotation: a second hash may be active; a third is refused; deleting the old one retires it
                conn.execute("insert into nl.ingest_gateway (secret_sha256) values (encode(sha256(convert_to('n3w', 'UTF8')), 'hex'))")
                conn.execute("select set_config('request.headers', %s, true)", (json.dumps({'x-nl-ingest-secret': 'n3w'}),))
                new_ok = conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(base1),)).fetchone()[0] == 1
                conn.execute("select set_config('request.headers', %s, true)", (json.dumps({'x-nl-ingest-secret': 's3cret'}),))
                old_ok = conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(base1),)).fetchone()[0] == 1
                check('fix: secret rotation - old and new gateway secrets both work while two hashes are active', new_ok and old_ok)
                check('fix: secret rotation - a third active gateway hash is refused (23514)',
                      rejects("insert into nl.ingest_gateway (secret_sha256) values (encode(sha256(convert_to('x3', 'UTF8')), 'hex'))",
                              None, psycopg.errors.CheckViolation))
                conn.execute("delete from nl.ingest_gateway where secret_sha256 = encode(sha256(convert_to('s3cret', 'UTF8')), 'hex')")
                check('fix: secret rotation - the deleted old secret is refused afterwards',
                      rejects('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(base1),), psycopg.errors.InsufficientPrivilege))
                conn.execute('rollback;')

                # scoped reader cannot request an older snapshot
                conn.execute('select nl.publish_snapshot(%s)', ('rf-a',))
                conn.execute('select nl.publish_snapshot(%s)', ('rf-b',))
                old_snap = conn.execute('select min(snapshot_id) from nl.snapshot where published').fetchone()[0]
                conn.execute('begin;')
                conn.execute('set local role authenticated')
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'role': 'authenticated', 'app_metadata': {'role': 'reader', 'institution_id': 'thuas'}}),))
                check('fix: scoped reader blocked from historic snapshot (42501)',
                      rejects('select nl.release_json_for_institution(%s, %s)', ('thuas', old_snap), psycopg.errors.InsufficientPrivilege))
                latest_ok = conn.execute('select nl.release_json_for_institution(%s, null)', ('thuas',)).fetchone()[0]
                check('fix: scoped reader withheld cells carry no size bucket',
                      all(h.get('bucket') is None for t in latest_ok['tables'] for h in t['withheld']))

                # editor: municipal card cannot be filed under a shared city via an editable municipality
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'rf', 'role': 'authenticated', 'app_metadata': {'role': 'editor', 'institution_id': 'thuas'}}),))
                svc = {'service_id': 'rf_probe', 'name': 'Probe GP', 'service_type': 'gp', 'city_id': 'the-hague',
                       'municipality_id': 'zoetermeer', 'description': 'Probe card.', 'url': 'https://example.org/'}
                check('fix: editor blocked from shared city_id with editable municipality (42501)',
                      rejects('select nl_content.editor_upsert_service(%s::jsonb, %s)', (json.dumps(svc), 'probe'), psycopg.errors.InsufficientPrivilege))
                svc_http = dict(svc, city_id='zoetermeer', url='http://example.org/')
                check('fix: http:// service URL rejected (https only)',
                      rejects('select nl_content.editor_upsert_service(%s::jsonb, %s)', (json.dumps(svc_http), 'probe')))
                conn.execute('rollback;')
            except Exception as exc:
                check('review-fix regression suite', False, str(exc))

            # 8. Privilege-surface invariants (allowlist; any new callable function or open table fails)
            try:
                schemas = "('nl', 'nl_content', 'public')"
                callable_rows = conn.execute(f"""
                    select r.rolname, n.nspname || '.' || p.proname
                      from pg_proc p
                      join pg_namespace n on n.oid = p.pronamespace
                      cross join (select rolname from pg_roles where rolname in ('anon', 'authenticated')) r
                     where n.nspname in {schemas}
                       and has_schema_privilege(r.rolname, n.oid, 'USAGE')
                       and has_function_privilege(r.rolname, p.oid, 'EXECUTE')""").fetchall()
                got = {}
                for role, fn in callable_rows:
                    got.setdefault(role, set()).add(fn)
                allow = {
                    'anon': {'nl.ingest_t1_rpc', 'nl.ingest_t2_rpc'},
                    'authenticated': {'nl.ingest_t1_rpc', 'nl.ingest_t2_rpc', 'nl.release_json_for_institution',
                                      'nl_content.editor_list', 'nl_content.editor_upsert_service',
                                      'nl_content.editor_upsert_step_local', 'nl_content.editor_publish_fact',
                                      'nl_content.editor_mark_verified', 'public.can_edit_city'},
                }
                for role in ('anon', 'authenticated'):
                    extra = sorted(got.get(role, set()) - allow[role])
                    check(f'surface: {role} can call only allowlisted functions (Supabase default ACLs applied)', not extra, str(extra))
                no_rls = conn.execute(f"""
                    select n.nspname || '.' || c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where c.relkind in ('r', 'p') and n.nspname in {schemas} and not c.relrowsecurity""").fetchall()
                check('surface: every table in nl / nl_content / public has RLS enabled', not no_rls, str(no_rls))
                grants = conn.execute(f"""
                    select grantee, table_schema || '.' || table_name, privilege_type
                      from information_schema.role_table_grants
                     where grantee in ('anon', 'authenticated', 'PUBLIC') and table_schema in {schemas}""").fetchall()
                check('surface: anon/authenticated/PUBLIC hold no table or view privileges', not grants, str(grants[:5]))
                policies = conn.execute(f"select schemaname || '.' || tablename from pg_policies where schemaname in {schemas}").fetchall()
                check('surface: no RLS policies exist (all access goes through SECURITY DEFINER RPCs)', not policies, str(policies))
                bad_definer = conn.execute(f"""
                    select n.nspname || '.' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname in {schemas} and p.prosecdef
                       and not exists (select 1 from unnest(coalesce(p.proconfig, '{{}}')) x where x like 'search_path=%')""").fetchall()
                check('surface: every SECURITY DEFINER function pins search_path', not bad_definer, str(bad_definer))

                conn.execute('begin;')
                conn.execute('set local role anon')
                check('surface: anon cannot rewrite public.institution_campuses (shared-city escalation)',
                      rejects("delete from public.institution_campuses where city_id = 'the-hague'", None,
                              psycopg.errors.InsufficientPrivilege))
                conn.execute('rollback;')
            except Exception as exc:
                check('privilege-surface invariant suite', False, str(exc))

            # 9. Cell-key perturbation: defence against n-1 flooding (tools/pentest/n1_flooding.py)
            try:
                conn.execute('alter table nl.raw_t1 alter column rkey set default nl.new_record_key()')
                conn.execute('alter table nl.raw_t2 alter column rkey set default nl.new_record_key()')
                reset_data(conn)
                ev = lambda **k: dict({'institution': 'thuas', 'intake': '2027-feb', 'app_version': 'abcd1234'}, **k)
                conn.execute('begin;')
                check('cell-key: client cannot supply its own record key (22023)',
                      rejects('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(ev(event='cohort_joined', rkey=0)),)))
                conn.execute('rollback;')
                noise_ok = conn.execute(
                    'select min(nl.cell_noise(k)) = -4 and max(nl.cell_noise(k)) = 4 and nl.cell_noise(0) = 0 '
                    'and count(distinct nl.cell_noise(k)) = 9 from generate_series(0, 251) k').fetchone()[0]
                check('cell-key: noise is -4..+4, all 9 values reachable, key 0 means no noise', noise_ok is True)

                def n1_trial(real_completed):
                    reset_data(conn)
                    fakes = ([ev(event='cohort_joined')] * 14 + [ev(event='step_applies', category='housing')] * 19
                             + [ev(event='step_completed', category='housing')] * 12)
                    real = [ev(event='cohort_joined'), ev(event='step_applies', category='housing')]
                    if real_completed:
                        real.append(ev(event='step_completed', category='housing'))
                    conn.execute('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(fakes + real),))
                    conn.execute('select nl.accumulate()')
                    snap = conn.execute("select nl.publish_snapshot('n1')").fetchone()[0]
                    row = conn.execute("select num, denom from nl.published_cell where snapshot_id = %s and "
                                       "table_id = 't1_inst_category' and row_key = 'thuas:housing'", (snap,)).fetchone()
                    return row, snap

                trials = 150
                dist = {True: {}, False: {}}
                for real_completed in (True, False):
                    for _ in range(trials):
                        row, _snap = n1_trial(real_completed)
                        dist[real_completed][row] = dist[real_completed].get(row, 0) + 1
                outcomes = set(dist[True]) | set(dist[False])
                tvd = sum(abs(dist[True].get(o, 0) - dist[False].get(o, 0)) for o in outcomes) / (2 * trials)
                accuracy = 0.5 + tvd / 2
                check('cell-key: n-1 flooding attacker accuracy <= 0.66 (was 1.00 before cell keys; theory ~0.56)',
                      accuracy <= 0.66, f'accuracy={accuracy:.3f}, outcomes={len(outcomes)}')

                # consistency: an unchanged cell republishes identically (no averaging across snapshots)
                _row, s1 = n1_trial(True)
                s2 = conn.execute("select nl.publish_snapshot('n1-repeat')").fetchone()[0]
                same = conn.execute(
                    'select count(*) = 0 from (select table_id, row_key, col_key, num, denom from nl.published_cell where snapshot_id = %s '
                    'except select table_id, row_key, col_key, num, denom from nl.published_cell where snapshot_id = %s) d',
                    (s1, s2)).fetchone()[0]
                check('cell-key: unchanged cells republish with identical noise', same is True)
                bounded = conn.execute(
                    'select bool_and(abs(p.num - a.num) <= 6 and abs(p.denom - greatest(a.denom, 15)) <= 6) '
                    'from nl.published_cell p join nl.accumulated_cell a using (table_id, row_key, col_key) '
                    'where p.snapshot_id = %s', (s2,)).fetchone()[0]
                check('cell-key: published counts stay within 6 of the true counts (noise 4 + rounding 2)', bounded is True)
                conn.execute('alter table nl.raw_t1 alter column rkey set default 0')
                conn.execute('alter table nl.raw_t2 alter column rkey set default 0')
            except Exception as exc:
                check('cell-key perturbation suite', False, str(exc))

            # 10. Benchmark (pooled) cells: >= 3 institutions and no dominant institution (P3)
            try:
                def pooled_state(counts):
                    reset_data(conn)
                    b = []
                    for inst, n in counts.items():
                        b += [{'institution': inst, 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': 'abcd1234'}] * 20
                        b += [{'institution': inst, 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': 'abcd1234'}] * n
                        b += [{'institution': inst, 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': 'abcd1234'}] * (n // 2)
                    ingest_t1_chunked(conn, b)
                    conn.execute('select nl.accumulate()')
                    snap = conn.execute("select nl.publish_snapshot('pooled')").fetchone()[0]
                    pub = conn.execute("select count(*) from nl.published_cell where snapshot_id = %s and table_id = 't1_category_totals' "
                                       "and row_key = 'housing'", (snap,)).fetchone()[0]
                    return pub == 1
                check('benchmark: a pooled cell with only 2 institutions is withheld (no subtraction of the other school)',
                      not pooled_state({'thuas': 40, 'uva': 40}))
                check('benchmark: a pooled cell with 3 balanced institutions is published',
                      pooled_state({'thuas': 40, 'uva': 40, 'leiden': 40}))
                check('benchmark: a pooled cell where one institution dominates the rest is withheld',
                      not pooled_state({'thuas': 200, 'uva': 40, 'leiden': 20}))
            except Exception as exc:
                check('benchmark publication rule suite', False, str(exc))

            # 11. Mutation-gap tests: each kills a mutation that survived tools/mutation_check.py
            try:
                T = {'institution': 'thuas', 'intake': '2026-sep', 'app_version': 'abcd1234'}
                t1e = lambda **k: dict(T, **k)

                # identity fields (privacy policy section 16); tier 1 and tier 2, any case
                conn.execute('begin;')
                bad_t1 = [k for k in ('sid', 'SID', 'session_id', 'user_id', 'email', 'ip', 'device_id', 'installation_id')
                          if not rejects('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps(t1e(event='cohort_joined', **{k: 'x'})),))]
                bad_t2 = [k for k in ('sid', 'Session_Id', 'uid', 'ip_address', 'deviceid', 'install_id')
                          if not rejects('select nl.ingest_t2_rpc(%s::jsonb)', (json.dumps({'institution': 'thuas', 'region': 'eu_eea',
                                         'intake': '2026-sep', 'event': 'joined', k: 'x'}),))]
                check('gap: identity fields are rejected by both tiers in any letter case (22023)', not bad_t1 and not bad_t2,
                      f't1={bad_t1}, t2={bad_t2}')
                # batch cap (M04)
                check('gap: a batch of 101 events is rejected (22023)',
                      rejects('select nl.ingest_t1_rpc(%s::jsonb)', (json.dumps([t1e(event='cohort_joined')] * 101),)))
                conn.execute('rollback;')

                # rate limiter counts events (M14)
                reset_data(conn)
                before = conn.execute("select coalesce(sum(req_count), 0) from nl.ingest_rate_limits where tier = 1 "
                                      "and bucket_hour = date_trunc('hour', now())").fetchone()[0]
                ingest_t1_chunked(conn, [t1e(event='cohort_joined')] * 50)
                after = conn.execute("select coalesce(sum(req_count), 0) from nl.ingest_rate_limits where tier = 1 "
                                     "and bucket_hour = date_trunc('hour', now())").fetchone()[0]
                check('gap: one 50-event request counts 50 towards the rate limit (events, not requests)', after - before == 50,
                      f'delta={after - before}')

                # secondary suppression of a lone withheld cell (M09) + no buckets for scoped readers (M16)
                reset_data(conn)
                ingest_t1_chunked(conn, [t1e(event='cohort_joined')] * 20
                                  + [t1e(event='step_applies', category='housing')] * 40
                                  + [t1e(event='step_applies', category='money')] * 40
                                  + [t1e(event='step_applies', category='health')] * 40
                                  + [t1e(event='step_applies', category='work')] * 6)
                conn.execute('select nl.accumulate()')
                snap = conn.execute("select nl.publish_snapshot('secondary')").fetchone()[0]
                withheld = dict(conn.execute("select row_key, reason::text from nl.suppressed_cell where snapshot_id = %s "
                                             "and table_id = 't1_inst_category'", (snap,)).fetchall())
                check('gap: a lone floor-withheld category also withholds its smallest sibling (secondary suppression, 4 categories)',
                      withheld.get('thuas:work') == 'floor' and len(withheld) == 2
                      and sorted(withheld.values()) == ['complementary', 'floor'], str(withheld))
                conn.execute('begin;')
                conn.execute('set local role authenticated')
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'role': 'authenticated', 'app_metadata': {'role': 'reader', 'institution_id': 'thuas'}}),))
                rdoc = conn.execute("select nl.release_json_for_institution('thuas', null)").fetchone()[0]
                conn.execute('rollback;')
                held = [h for t in rdoc['tables'] for h in t['withheld']]
                pdoc = conn.execute('select nl.release_json(null)').fetchone()[0]
                pooled_held = [h for t in pdoc['tables'] for h in t['withheld']]
                check('gap: scoped readers get withheld cells without size buckets (privileged view still has them)',
                      len(held) >= 2 and all(h.get('bucket') is None for h in held)
                      and any(h.get('bucket') is not None for h in pooled_held), f'held={len(held)}')

                # benchmark dominance on one count only (M12)
                def pooled_published(spec):
                    reset_data(conn)
                    b = []
                    for inst, (applies, completes) in spec.items():
                        tpl = dict(T, institution=inst)
                        b += [dict(tpl, event='cohort_joined')] * 20
                        b += [dict(tpl, event='step_applies', category='housing')] * applies
                        b += [dict(tpl, event='step_completed', category='housing')] * completes
                    ingest_t1_chunked(conn, b)
                    conn.execute('select nl.accumulate()')
                    sn = conn.execute("select nl.publish_snapshot('dominance')").fetchone()[0]
                    return conn.execute("select count(*) from nl.published_cell where snapshot_id = %s and table_id = 't1_category_totals' "
                                        "and row_key = 'housing'", (sn,)).fetchone()[0] == 1
                check('gap: benchmark withheld when only the denominator is dominated',
                      not pooled_published({'thuas': (200, 20), 'uva': (40, 20), 'leiden': (40, 20)}))
                check('gap: benchmark withheld when only the numerator is dominated',
                      not pooled_published({'thuas': (40, 38), 'uva': (40, 2), 'leiden': (40, 2)}))

                # retention reporting (M24) and health (M25)
                reset_data(conn)
                conn.execute("insert into nl.raw_t1 (institution, intake, event, app_version, received_at) "
                             "values ('thuas', '2026-sep', 'cohort_joined', 'abcd1234', now() - interval '4 hours')")
                h = conn.execute('select nl.health()').fetchone()[0]
                check('gap: health flags a stalled fold (unprocessed row older than 3 h)', h.get('fold_stalled') is True and h.get('ok') is False, str(h))
                conn.execute("insert into nl.raw_t1 (institution, intake, event, app_version, received_at) "
                             "values ('thuas', '2026-sep', 'cohort_joined', 'abcd1234', now() - interval '26 hours')")
                lost = dict(conn.execute('select store, removed from nl.purge_raw()').fetchall())
                check('gap: purge_raw reports raw rows that expired unprocessed', lost.get('raw_unfolded_expired') == 1, str(lost))
                reset_data(conn)

                # editor: https-only links and safe labels (M22)
                conn.execute('begin;')
                conn.execute('set local role authenticated')
                conn.execute("select set_config('request.jwt.claims', %s, true)",
                             (json.dumps({'sub': 'gap', 'role': 'authenticated', 'app_metadata': {'role': 'editor', 'institution_id': 'thuas'}}),))
                step = {'step_id': 'register_gp', 'municipality_id': 'zoetermeer', 'for_institution_id': 'thuas', 'body': 'Local GP guidance.'}
                check('gap: step links must be https (22023)',
                      rejects('select nl_content.editor_upsert_step_local(%s::jsonb, %s)',
                              (json.dumps(dict(step, links=[{'url': 'http://example.org/', 'label': 'GP list'}])), 'gap test')))
                for bad_date in ('44318707', '2026-13-45', '2026-02-30', '+1000-01-01'):
                    ok_date = rejects('select nl_content.editor_upsert_step_local(%s::jsonb, %s)',
                                      (json.dumps(dict(step, last_verified=bad_date)), 'gap test'))
                    if not ok_date:
                        break
                check('gap: malformed or impossible dates give a clear 22023 validation error (not 22007/22008)', ok_date, f'last={bad_date}')
                check('gap: link labels with markup are rejected (22023)',
                      rejects('select nl_content.editor_upsert_step_local(%s::jsonb, %s)',
                              (json.dumps(dict(step, links=[{'url': 'https://example.org/', 'label': '<img src=x onerror=alert(1)>'}])), 'gap test')))
                conn.execute('rollback;')

                # editor: the ownership check holds a per-service lock until commit (M23)
                with psycopg.connect(uri, autocommit=True) as conn_a, psycopg.connect(uri, autocommit=True) as conn_b:
                    conn_a.execute('begin;')
                    conn_a.execute('set local role authenticated')
                    conn_a.execute("select set_config('request.jwt.claims', %s, true)",
                                   (json.dumps({'sub': 'gap', 'role': 'authenticated', 'app_metadata': {'role': 'editor', 'institution_id': 'thuas'}}),))
                    conn_a.execute('select nl_content.editor_upsert_service(%s::jsonb, %s)',
                                   (json.dumps({'service_id': 'gap_lock_probe', 'name': 'Lock probe', 'service_type': 'support',
                                                'city_id': 'the-hague', 'municipality_id': 'the-hague', 'for_institution_id': 'thuas',
                                                'description': 'Lock probe card.', 'url': 'https://example.org/'}), 'gap test'))
                    got = conn_b.execute("select pg_try_advisory_xact_lock(hashtext('nl_content.service:gap_lock_probe'))").fetchone()[0]
                    conn_a.execute('rollback;')
                check('gap: a concurrent writer cannot take the service lock while an upsert is open (no check-then-write race)',
                      got is False)
            except Exception as exc:
                check('mutation-gap suite', False, str(exc))

    finally:
        if pg is not None:
            try:
                pg.cleanup()
            except Exception:
                pass
        shutil.rmtree(pgdata, ignore_errors=True)

    failed = 0
    for ok, name, detail in RESULTS:
        if ok:
            print(f'PASS  {name}')
        else:
            failed += 1
            print(f'FAIL  {name}' + (f'  [{detail}]' if detail else ''))

    print(f'\n{len(RESULTS)} checks, {len(RESULTS) - failed} passed, {failed} failed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
