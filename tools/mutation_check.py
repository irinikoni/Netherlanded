#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Mutation check: do the tests actually catch each protection being removed?

Each mutation deliberately breaks one security or privacy property in the source, runs
the suites that should notice, and restores the file. A mutation is KILLED when at least
one suite fails, and SURVIVED when every suite still passes, which means a test is missing.

Usage: python3 tools/mutation_check.py [mutation-id ...]   (default: all; takes several minutes)
Needs everything the individual suites need (pgserver, psycopg, scipy, deno).
Exit 1 if any mutation survives or cannot be applied.
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
SUITES = {
    'pg': [PY, 'tools/run_pg_tests.py'],
    'sdc': [PY, 'tools/pentest/sdc_attacks.py', '3'],
    'ref': [PY, 'tools/test_suppression.py'],
    'build': [PY, 'tools/verify_build.py'],
    'deno': ['deno', 'test', '--allow-env', '--allow-read', 'edge/tests/edge.test.ts'],
}

# Mutants proven equivalent (behaviour unchanged, so no test can kill them); reported, not failed.
EQUIVALENT = {
    'M01': 'tier 1 also has a strict field allowlist, which rejects every identity field on its own',
    'M11': 'the dominance rule always fails for 1 or 2 institutions, so ">= 3 institutions" is implied',
}

# (id, file, old, new, replace_all, suites, property protected)
MUTATIONS = [
    ('M01', 'db/002_ingest.sql', "    perform nl.reject_identity(e);\n", "", False, ['pg'],
     'tier 1 rejects identity fields (sid, user_id, ip, ...)'),
    ('M02', 'db/002_ingest.sql', "'category', 'app_version')", "'category', 'app_version', 'n')", False, ['pg'],
     'unused n field is rejected'),
    ('M03', 'db/002_ingest.sql', "if v_event <> 'scam_checked' then", "if false then", False, ['pg'],
     'high_risk only on scam_checked'),
    ('M04', 'db/002_ingest.sql', "if v_len < 1 or v_len > 100 then", "if v_len < 1 or v_len > 100000 then", False, ['pg'],
     'batch size capped at 100 events'),
    ('M05', 'db/001_schema.sql', "default date_trunc('hour', now())", "default now()", True, ['pg'],
     'raw arrival times hour-truncated'),
    ('M06', 'db/001_schema.sql', "select (((coalesce(p_key, 0) % 252) % 9 + 4) % 9 - 4)::integer;", "select 0;", False, ['pg', 'sdc'],
     'cell-key noise (n-1 flooding defence)'),
    ('M07', 'db/003_release.sql', "update nl.stage_cell set reason = 'floor' where denom_true < 15;",
     "update nl.stage_cell set reason = 'floor' where denom_true < 10;", False, ['pg', 'sdc'], '15-contribution cell floor'),
    ('M08', 'db/003_release.sql', "between 1 and 4;", "between 1 and 0;", False, ['pg', 'sdc'],
     'carry-forward of changes under 5 contributions'),
    ('M09', 'db/003_release.sql', "s3.reason is not null) = 1", "s3.reason is not null) = -1", False, ['pg', 'sdc'],
     'secondary suppression of a lone withheld cell'),
    ('M10', 'db/003_release.sql', "       and g.npub = 1;", "       and g.npub = -1;", False, ['pg', 'sdc'],
     'complementary suppression (row rule)'),
    ('M11', 'db/003_release.sql', "or sh.n_inst < 3", "or sh.n_inst < 2", True, ['pg', 'sdc'],
     'benchmark cells need >= 3 institutions'),
    ('M12', 'db/003_release.sql', "or sh.d1 > 0.7 * (sh.t_d - sh.d2)", "or sh.d1 > 99 * (sh.t_d - sh.d2)", True, ['pg', 'sdc'],
     'benchmark dominance rule'),
    ('M13', 'db/006_security_rls_and_scoping.sql', "  if not exists (select 1 from nl.ingest_gateway) then\n    return;",
     "  if true then\n    return;", False, ['pg'], 'gateway secret enforced once configured'),
    ('M14', 'db/006_security_rls_and_scoping.sql', "nl.payload_event_count(p)) then", "1) then", True, ['pg'],
     'rate limiter counts events, not requests'),
    ('M15', 'db/008_scoped_insights.sql', "  if p_snapshot is not null and not v_allow_pooled",
     "  if false and p_snapshot is not null and not v_allow_pooled", False, ['pg'], 'scoped readers see the latest snapshot only'),
    ('M16', 'db/008_scoped_insights.sql', "'bucket', case when v_allow_pooled then bucket else null end)", "'bucket', bucket)", False, ['pg'],
     'no size buckets for scoped readers'),
    ('M17', 'db/008_scoped_insights.sql', "and split_part(row_key, ':', 1) = p_institution)", "and true)", True, ['pg'],
     'tenant isolation of institution-scoped rows'),
    ('M18', 'db/008_scoped_insights.sql',
     "when num <= 5 or (denom - num) <= 5 or rate <= 0.10 or rate >= 0.90 or denom < 50 then null\n                         else num end",
     "when false then null\n                         else num end", False, ['pg'], 'tail and small-denominator redaction of num'),
    ('M19', 'db/008_scoped_insights.sql', "    if v_app_role not in ('super_admin', 'reader', 'editor')",
     "    if false and v_app_role not in ('super_admin', 'reader', 'editor')", False, ['pg'], 'reader role required'),
    ('M20', 'db/009_content_editor.sql', "and public.can_edit_city(v_muni) and public.can_edit_city(v_city))",
     "and public.can_edit_city(v_muni))", False, ['pg'], 'municipal cards need an editable city_id'),
    ('M21', 'db/009_content_editor.sql', "    execute 'revoke all on table public.institution_campuses from anon';",
     "    execute 'select 1';", False, ['pg'], 'anon cannot rewrite institution_campuses'),
    ('M22', 'db/009_content_editor.sql', "  if v_url !~ '^https://", "  if v_url !~ '^https?://", False, ['pg'],
     'https-only service URLs'),
    ('M23', 'db/009_content_editor.sql', "  perform pg_advisory_xact_lock(hashtext('nl_content.service:' || v_service_id));\n", "", False, ['pg'],
     'service upsert ownership check is race-free'),
    ('M24', 'db/004_retention.sql', "  store := 'raw_unfolded_expired'; removed := v_lost1 + v_lost2; return next;\n", "", False, ['pg'],
     'purge reports rows that expired unprocessed'),
    ('M25', 'db/004_retention.sql',
     "    'fold_stalled', exists (select 1 from nl.raw_t1 where fold_run is null and received_at < now() - interval '3 hours')",
     "    'fold_stalled', false and exists (select 1 from nl.raw_t1 where fold_run is null and received_at < now() - interval '3 hours')",
     False, ['pg'], 'health flags a stalled fold'),
    ('M26', 'edge/ingest/index.ts', "if (!PROXY_SECRET) return ALLOW_DIRECT_DEV;", "if (!PROXY_SECRET) return true;", False, ['deno'],
     'ingest fails closed without NL_PROXY_SECRET'),
    ('M27', 'edge/ingest/index.ts', "const MAX_BYTES = 64 * 1024;", "const MAX_BYTES = 64 * 1024 * 1024;", False, ['deno'],
     '64 KB ingest body cap'),
    ('M28', 'edge/ingest/index.ts', 'if (!ctype.includes("application/json")) {', "if (false) {", False, ['deno'],
     'JSON media type required (blocks simple-request CORS)'),
    ('M29', 'edge/stats/index.ts', "!/^[a-z0-9_-]{2,32}$/.test(inst)", "!/^.+$/.test(inst)", False, ['deno'],
     'institution parameter validated'),
    ('M30', 'edge/editor/index.ts', 'detail: ownMessage ?? "invalid_payload"', 'detail: errJson?.message ?? "invalid_payload"', False, ['deno'],
     'editor echoes only our own error messages'),
    ('M31', 'edge/editor/index.ts', "if (!PROXY_SECRET) return ALLOW_DIRECT_DEV;", "if (!PROXY_SECRET) return true;", False, ['deno'],
     'editor fails closed without NL_PROXY_SECRET'),
    ('M32', 'tools/suppress_reference.py', "    return (k + NOISE_HALF_WIDTH) % (2 * NOISE_HALF_WIDTH + 1) - NOISE_HALF_WIDTH",
     "    return 0", False, ['ref'], 'reference model mirrors cell-key noise'),
]


def run_suite(name):
    try:
        r = subprocess.run(SUITES[name], cwd=ROOT, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return False, 'timeout'
    tail = [line for line in (r.stdout + r.stderr).splitlines() if line.startswith('FAIL') or 'FAILED' in line]
    return r.returncode == 0, (tail[0][:110] if tail else f'exit {r.returncode}')


def main():
    wanted = set(sys.argv[1:])
    todo = [m for m in MUTATIONS if not wanted or m[0] in wanted]
    print('baseline (unmutated):')
    for name in sorted({s for m in todo for s in m[5]}):
        ok, info = run_suite(name)
        print(f'   {name:5} {"pass" if ok else "FAIL " + info}')
        if not ok:
            sys.exit('baseline must pass before mutating')
    results = []
    for mid, path, old, new, replace_all, suites, prop in todo:
        full = os.path.join(ROOT, path)
        with open(full, encoding='utf-8') as fh:
            original = fh.read()
        if old not in original:
            results.append((mid, 'NOT APPLIED', prop, 'pattern not found'))
            print(f'{mid} NOT APPLIED   {prop}')
            continue
        mutated = original.replace(old, new) if replace_all else original.replace(old, new, 1)
        start = time.time()
        try:
            with open(full, 'w', encoding='utf-8') as fh:
                fh.write(mutated)
            killer = None
            for name in suites:
                ok, info = run_suite(name)
                if not ok:
                    killer = f'{name}: {info}'
                    break
        finally:
            with open(full, 'w', encoding='utf-8') as fh:
                fh.write(original)
        status = 'KILLED' if killer else ('EQUIVALENT' if mid in EQUIVALENT else 'SURVIVED')
        if status == 'EQUIVALENT':
            killer = EQUIVALENT[mid]
        results.append((mid, status, prop, killer or 'no suite failed'))
        print(f'{mid} {status:11} {prop}  [{killer or "-"}] ({time.time() - start:.0f}s)')
    bad = [r for r in results if r[1] not in ('KILLED', 'EQUIVALENT')]
    equivalent = sum(1 for r in results if r[1] == 'EQUIVALENT')
    print(f'\n{len(results) - len(bad) - equivalent}/{len(results)} mutations killed, {equivalent} equivalent, {len(bad)} survived')
    for mid, status, prop, info in bad:
        print(f'   {mid} {status}: {prop} ({info})')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
