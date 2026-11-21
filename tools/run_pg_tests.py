#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Run all Netherlanded SQL migrations, live role tests, and adversarial SDC regressions
against an embedded PostgreSQL server (`pgserver` + `psycopg[binary]`).
"""

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
        'nl.snapshot, nl.unmapped_value, nl.accumulation_run restart identity cascade'
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

                # Check tail-capped num redaction and suppressed reason redaction for non-super_admin
                cat_tbl = [t for t in doc['tables'] if t['table_id'] == 't1_inst_category'][0]
                money_cell = [c for c in cat_tbl['cells'] if c['row'] == 'thuas:money'][0]
                check('authenticated reader gets null num and <= 10.0% on tail-capped cell',
                      money_cell['num'] is None and money_cell['rate_display'] == '<= 10.0%', str(money_cell))

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

                # R2: Sticky suppression expires after 2 releases (no infinite sticky loop)
                # Move housing +6pp (10/15=66.7% -> 14/18=77.8%)? First suppress by <5pp delta (11/16=68.8% -> 'delta' on R3),
                # then move >=5pp from R2's 66.7% (to 15/18=83.3%) before R4 -> R4 & R5 stay 'sticky' (2 releases), and R6 recovers!
                ingest_t1_chunked(conn, [
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                ])
                conn.execute('select nl.accumulate()')
                s3 = conn.execute("select nl.publish_snapshot('delta-r3')").fetchone()[0]
                r3 = conn.execute("select reason::text from nl.suppressed_cell where snapshot_id=%s and table_id='t1_inst_category' and row_key='thuas:housing'", (s3,)).fetchone()
                ingest_t1_chunked(conn, [
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'cohort_joined', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_applies', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                    {'institution': 'thuas', 'intake': '2026-sep', 'event': 'step_completed', 'category': 'housing', 'app_version': '3b32b5914fb6bdfc'},
                ])
                conn.execute('select nl.accumulate()')
                s4 = conn.execute("select nl.publish_snapshot('sticky-r4')").fetchone()[0]
                r4 = conn.execute("select reason::text from nl.suppressed_cell where snapshot_id=%s and table_id='t1_inst_category' and row_key='thuas:housing'", (s4,)).fetchone()
                s5 = conn.execute("select nl.publish_snapshot('sticky-r5')").fetchone()[0]
                r5 = conn.execute("select reason::text from nl.suppressed_cell where snapshot_id=%s and table_id='t1_inst_category' and row_key='thuas:housing'", (s5,)).fetchone()
                s6 = conn.execute("select nl.publish_snapshot('recover-r6')").fetchone()[0]
                r6_pub = conn.execute("select count(*) from nl.published_cell where snapshot_id=%s and table_id='t1_inst_category' and row_key='thuas:housing'", (s6,)).fetchone()[0]
                check('regression: sticky suppression lasts 2 releases and recovers (no infinite loop)',
                      r3 == ('delta',) and r4 == ('sticky',) and r5 == ('sticky',) and r6_pub == 1,
                      f'r3={r3}, r4={r4}, r5={r5}, r6_pub={r6_pub}')

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

                conn.execute("insert into nl.raw_t2 (institution, region, intake, event, received_at) values ('thuas', 'eu_eea', '2026-sep', 'joined', now() - interval '50 hours')")
                h = conn.execute('select nl.health()').fetchone()[0]
                check('regression: nl.health() detects >48h raw_t2 breach (ok=false)', h['ok'] is False and float(h['raw_oldest_hours']) >= 48.0, str(h))
            except Exception as exc:
                check('adversarial SQL regression suite', False, str(exc))

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
