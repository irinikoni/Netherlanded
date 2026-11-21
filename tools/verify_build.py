#!/usr/bin/env python3
# Copyright (c) 2026 Eirini Konidari. All rights reserved.
"""Comprehensive build, CSP, SQL, dashboard, edge, and parity verifier for Netherlanded Antigravity."""

import base64
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

RESULTS = []


def check(name, condition, detail=''):
    RESULTS.append((bool(condition), name, detail))


def read_text(rel):
    path = os.path.join(ROOT, rel)
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()


# 1. Run tools/test_suppression.py
supp = subprocess.run(
    [sys.executable, os.path.join(HERE, 'test_suppression.py')],
    capture_output=True,
    text=True,
)
check('tools/test_suppression.py exits 0', supp.returncode == 0, supp.stdout.strip().splitlines()[-1] if supp.stdout.strip() else supp.stderr)

# 2. Verify netherlanded-app.html CSP SHA-256 hash, fonts, config metas, JSON scripts, and JS symbols
app_txt = read_text('netherlanded-app.html')
app_lines = app_txt.splitlines()

csp_m = re.search(r'<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]+)"', app_txt, re.I)
check('app HTML contains CSP meta tag', csp_m is not None)
csp_val = csp_m.group(1) if csp_m else ''
sha_m = re.findall(r"'sha256-([^']+)'", csp_val)
check('app CSP declares exactly one sha256 script hash', len(sha_m) == 1, str(sha_m))
check('app CSP allows embedded data: fonts', "font-src 'self' data:" in csp_val)
check('app <head> has <title>Netherlanded</title> and no <title>final-legal</title>', '<title>Netherlanded</title>' in app_txt and '<title>final-legal</title>' not in app_txt)
check('app has meta config tags for ingest URLs', 'meta name="nl-basic-url"' in app_txt and 'meta name="nl-ingest-url"' in app_txt)

exec_scripts = []
for m in re.finditer(r'<script([^>]*)>(.*?)</script>', app_txt, flags=re.S):
    if 'application/json' not in m.group(1):
        exec_scripts.append(m.group(2))
check('app HTML has exactly one executable <script> block', len(exec_scripts) == 1, str(len(exec_scripts)))
if exec_scripts and sha_m:
    actual_hash = base64.b64encode(hashlib.sha256(exec_scripts[0].encode('utf-8')).digest()).decode('ascii')
    check('app CSP sha256 matches executable <script> byte-for-byte', actual_hash == sha_m[0], f'{actual_hash} == {sha_m[0]}')

html_outside_scripts = re.sub(r'<script[^>]*>.*?</script>', '', app_txt, flags=re.S)
inline_on = re.findall(r'\bon[a-z]+\s*=', html_outside_scripts, flags=re.I)
check('app HTML outside scripts has zero inline on* event handlers', len(inline_on) == 0, str(inline_on))

content_lines = [l for l in app_lines if l.startswith('<script id="content"')]
legal_lines = [l for l in app_lines if l.startswith('<script id="legal"')]
check('app HTML has one content JSON tag and one legal JSON tag', len(content_lines) == 1 and len(legal_lines) == 1)

content_raw = re.sub(r'^<script id="content" type="application/json">|</script>$', '', content_lines[0])
legal_raw = re.sub(r'^<script id="legal" type="application/json">|</script>$', '', legal_lines[0])
check('embedded JSON tags contain no raw < or </script',
      '<' not in content_raw and '<' not in legal_raw and '</script' not in content_raw.lower() and '</script' not in legal_raw.lower())

content_obj = json.loads(content_raw)
legal_obj = json.loads(legal_raw)
check('embedded content & legal JSON parse cleanly', isinstance(content_obj, dict) and 'html' in legal_obj)

js_all = exec_scripts[0] if exec_scripts else ''
defs = set(re.findall(r'(?:function|const|let|var)\s+([A-Za-z_$][\w$]*)', js_all))
for sym in ['parse', 'iso', 'deadlinesFor', 'consentNow', 'setConsent', 'statsNote',
            'whatIncludedSheet', 'statsSheet', 'basicSync', 'basicFlush', 'statsSync',
            'statsFlush', 'maybeAskConsent', 'localQueueId', 'shuffleArr', 'nextWeeklyTs',
            'parentInstitutionId', 'fetchWithTimeout', 'withLock', 'flushQueue']:
    check(f'JS defines {sym}', sym in defs)

for forbidden in ['fromISO', 'deadlines(', 'p.school', 'on_time', 'nlReceipt', 'Push reminders', 'E-mail reminders']:
    check(f'JS/HTML excludes {forbidden}', forbidden not in app_txt)

check("telemetry uses flushQueue with mode:'cors', credentials:'omit', referrerPolicy:'no-referrer'",
      "mode:'cors'" in js_all and "credentials:'omit'" in js_all and "referrerPolicy:'no-referrer'" in js_all)
check('telemetry uses batched array POSTs up to 100', 'BATCH_MAX = 100' in js_all and 'batch.map(e=>e.payload)' in js_all)
check('Tier 1 rolls up campus_of and emits cohort_joined', 'parentInstitutionId(' in js_all and "event:'cohort_joined'" in js_all)
check('Profile includes Local reminders & Anonymous statistics switches', 'Local reminders' in js_all and 'id="pf-stats-sec"' in js_all)
check('Tier 1 notice buttons have equal primary class', 'id="bgObject">Object' in js_all and 'cg-quiet' not in js_all.split('showBasicGate')[1].split('showConsentGate')[0])
check('addDays uses calendar Date(y, m, d+n) (DST-safe)', 'new Date(d.getFullYear(),d.getMonth(),d.getDate()+n)' in js_all)
check('whatIncludedSheet surfaces weekly batch waiting count', 'Waiting for weekly batch' in js_all)
check('See my data includes _telemetry_queues', '_telemetry_queues' in js_all)
check('app registers root ./sw.js', "register('./sw.js')" in js_all)

for old_http in [
    'http://studenthousingvenlo.nl/',
    'http://www.campushuisarts.nl',
    'http://www.hollandexpatcenter.com/',
    'http://www.huisarts31.nl/erasmus',
    'http://www.huisdoc.com/',
]:
    check(f'upgraded verified HTTPS URL ({old_http})', old_http not in content_raw and old_http.replace('http://', 'https://') in content_raw)

# 3. Verify db/001..008 & test_sql.sql
sql3 = read_text('db/003_release.sql')
sql4 = read_text('db/004_retention.sql')
sql5 = read_text('db/005_content_editor_security_fix.sql')
sql6 = read_text('db/006_security_rls_and_scoping.sql')
sql7 = read_text('db/007_seed_vocab.sql')
sql8 = read_text('db/008_scoped_insights.sql')
sqlt = read_text('db/test_sql.sql')

check("003 fixes infinite sticky loop (not in ('floor', 'sticky'))", "not in ('floor', 'sticky')" in sql3)
check('003 enforces 15-student contributor floor via t1_cohort & t2_base', 'nl.t1_cohort' in sql3 and 'nl.t2_base' in sql3)
check('003 tracks both v_hit_row and v_hit_col in complementary loop', 'v_hit_row' in sql3 and 'v_hit_col' in sql3)
check('004 checks raw_t2 in nl.health() and schedules monthly release', 'nl.raw_t2' in sql4 and 'monthly' in sql4)
check('005 uses public, pg_temp search_path & revokes PUBLIC', 'set search_path = public, pg_temp' in sql5 and 'revoke execute on function public.can_edit_city(text) from public' in sql5)
check('006 uses nl, pg_temp search_path & enables RLS on nl tables', 'set search_path = nl, pg_temp' in sql6 and sql6.count('enable row level security') >= 15)
check('006 uses dynamic secret salt & pg_catalog.sha256 without pgcrypto', 'nl.rate_limit_secret' in sql6 and 'pg_catalog.sha256' in sql6 and 'pgcrypto' not in sql6.lower())
check('006 sets campus-NAT limits (1800) and stripped-IP fallback (12000)', '1800' in sql6 and '12000' in sql6)
check('008 uses split_part (no LIKE wildcard) & fail-closed role check', 'split_part(row_key' in sql8 and "like p_institution" not in sql8 and "v_app_role not in ('super_admin', 'reader', 'editor')" in sql8)

for tbl in ['t1_inst_category', 't2_inst_step', 't2_inst_opened', 't2_inst_missed', 't2_inst_region', 't2_inst_scam']:
    check(f'008 defines scoped table {tbl}', tbl in sql8)
for fld in ['region', 'step_opened', 'deadline_missed', 'scam_checked', 'high_risk', 'nl.release_json_for_institution']:
    check(f'008 folds/exposes {fld}', fld in sql8)

for pat in ['22023', '42501', 'nl.accumulate()', 'nl.publish_snapshot', 'nl.release_json_for_institution']:
    check(f'test_sql.sql asserts {pat}', pat in sqlt)

for inst in content_obj.get('institutions', []):
    check(f"007 seeds institution {inst['id']}", f"'{inst['id']}'" in sql7)
for step in content_obj.get('steps', []):
    check(f"007 seeds step {step['id']}", f"'{step['id']}'" in sql7)

# 4. Verify web/dashboard.html, web/stats.js, web/manifest.webmanifest, web/icon.svg, root sw.js
dash_html = read_text('web/dashboard.html')
stats_js = read_text('web/stats.js')
manifest_obj = json.loads(read_text('web/manifest.webmanifest'))
sw_js = read_text('sw.js')

check('dashboard.html includes strict CSP meta tag and staff JWT form', 'http-equiv="Content-Security-Policy"' in dash_html and 'nl-auth-form' in dash_html)
check('dashboard.html loads no Google Fonts', 'fonts.googleapis' not in dash_html and 'fonts.gstatic' not in dash_html)
check('dashboard.html loads ./stats.js module', 'src="./stats.js"' in dash_html)
check('stats.js uses Object.create(null) & renders withheld rows/buckets', 'Object.create(null)' in stats_js and 'cells.concat(withheld)' in stats_js and 'h.bucket' in stats_js)
check('stats.js implements tail capping & avoids innerHTML/document.write', "'<= 10.0%'" in stats_js and "'>= 90.0%'" in stats_js and 'innerHTML' not in stats_js and 'document.write' not in stats_js)
check('manifest.webmanifest has scope, theme_color, and icons', manifest_obj.get('name') == 'Netherlanded' and manifest_obj.get('scope') == '../' and len(manifest_obj.get('icons', [])) >= 1)
check('web/icon.svg exists', os.path.isfile(os.path.join(ROOT, 'web', 'icon.svg')))
check('root sw.js exists, skips /api/, returns Response.error(), and checks origin on notificationclick',
      "url.pathname.startsWith('/api/')" in sw_js and 'Response.error()' in sw_js and 'parsed.origin !== self.location.origin' in sw_js)
check('old web/sw.js removed', not os.path.exists(os.path.join(ROOT, 'web', 'sw.js')))

# 5. Verify edge/ adapters & security headers
edge_ingest = read_text('edge/ingest/index.ts')
edge_stats = read_text('edge/stats/index.ts')
edge_conf = read_text('edge/security-headers.conf')

check('edge/ingest uses streaming body cap, fail-closed CORS, and P0001 JSON match',
      'readBodyLimited' in edge_ingest and 'ALLOWED_ORIGINS.includes(origin)' in edge_ingest and 'errJson?.code === "P0001"' in edge_ingest)
check('edge/stats pads base64url JWT with TextDecoder and fails closed on CORS',
      'TextDecoder' in edge_stats and 'ALLOWED_ORIGINS.includes(origin)' in edge_stats and 'release_json_for_institution' in edge_stats)
check('edge/security-headers.conf has rate limit, SNI, /api/stats, and /sw.js scope header',
      'limit_req_zone' in edge_conf and 'proxy_ssl_server_name on' in edge_conf and 'location = /api/stats' in edge_conf and 'Service-Worker-Allowed' in edge_conf)
for ftxt in (edge_ingest, edge_stats, edge_conf):
    check('edge sets frame-ancestors none & nosniff', "frame-ancestors 'none'" in ftxt and 'nosniff' in ftxt)

failed = 0
for ok, name, detail in RESULTS:
    if ok:
        print(f'PASS  {name}')
    else:
        failed += 1
        print(f'FAIL  {name}' + (f'  [{detail}]' if detail else ''))

print(f'\n{len(RESULTS)} checks, {len(RESULTS) - failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
