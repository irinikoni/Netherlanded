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
check('app has meta config tags for ingest URLs & partner gating', 'meta name="nl-basic-url"' in app_txt and 'meta name="nl-ingest-url"' in app_txt and 'meta name="nl-partner-institutions"' in app_txt)

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
            'statsFlush', 'maybeAskConsent', 'localQueueId', 'shuffleArr', 'nextBatchTs',
            'promoteDailyBatch', 'journeyCompleteNow',
            'parentInstitutionId', 'fetchWithTimeout', 'withLock', 'flushQueue',
            'maybePromptCalendar', 'googleCalUrl', 'downloadIcs', 'setRemindersEnabled',
            'checkLocalReminders', 'syncAppInert']:
    check(f'JS defines {sym}', sym in defs)

for forbidden in ['fromISO', 'deadlines(', 'p.school', 'on_time', 'nlReceipt', 'Push reminders', 'E-mail reminders']:
    check(f'JS/HTML excludes {forbidden}', forbidden not in app_txt)

check("telemetry uses flushQueue with mode:'cors', credentials:'omit', referrerPolicy:'no-referrer'",
      "mode:'cors'" in js_all and "credentials:'omit'" in js_all and "referrerPolicy:'no-referrer'" in js_all)
check('telemetry uses batched array POSTs up to 100', 'BATCH_MAX = 100' in js_all and 'batch.map(e=>e.payload)' in js_all)
check('Tier 1 rolls up campus_of, gates non-partner schools, and emits cohort_joined', 'parentInstitutionId(' in js_all and 'isPartnerInstitution(' in js_all and "event:'cohort_joined'" in js_all)
check('Profile includes Local reminders & Anonymous statistics switches', 'Local reminders' in js_all and 'id="pf-stats-sec"' in js_all)
check('Tier 1 notice: legitimate-interest switch on by default, one Continue button, Continue honours the switch',
      'id="bgSwitch" role="switch" checked' in js_all and 'id="bgObject"' not in js_all
      and "closeBasicGate(document.getElementById('bgSwitch')?.checked!==false)" in js_all)
check('Tier 2 consent names both purposes and offers an explicit choice',
      'National comparisons combine at least 3 institutions' in js_all and 'id="cgYes"' in js_all and 'id="cgNo"' in js_all)
check('addDays uses calendar Date(y, m, d+n) (DST-safe)', 'new Date(d.getFullYear(),d.getMonth(),d.getDate()+n)' in js_all)
check('telemetry uses daily cadence (24h + ≤6h jitter) and a checklist-completion milestone send',
      'BATCH_DAY_MS' in js_all and 'BATCH_JITTER_MS' in js_all and 'journeyCompleteNow()' in js_all and 'WEEKLY_MS' not in js_all)
check('whatIncludedSheet surfaces next batch waiting count', 'Waiting for next batch' in js_all)
check('See my data includes _telemetry_queues', '_telemetry_queues' in js_all)
check('app registers root ./sw.js', "register('./sw.js')" in js_all)
check('app calendar prompt, stable ICS UID, real local reminders & JSON backup present',
      'UID:${d.step.id}@netherlanded' in js_all and 'TRIGGER:-P1D' in js_all and 'Notification.requestPermission' in js_all and 'id="exportBackup"' in js_all and 'id="importBackup"' in js_all and 'netherlanded-backup' in js_all)
check('app accessibility uses aria-current="page" nav, unique scam labels, Tab modal trap & AA contrast tokens',
      '<nav class="tabs" aria-label="Sections">' in app_txt and 'aria-current="page"' in app_txt and 'aria-labelledby="sq-' in js_all and "document.getElementById('termsGate')?.querySelector('.tg-card')" in js_all and '--red:#c4382f' in app_txt and '--label3:#637069' in app_txt)

for old_http in [
    'http://studenthousingvenlo.nl/',
    'http://www.campushuisarts.nl',
    'http://www.hollandexpatcenter.com/',
    'http://www.huisarts31.nl/erasmus',
    'http://www.huisdoc.com/',
]:
    check(f'upgraded verified HTTPS URL ({old_http})', old_http not in content_raw and old_http.replace('http://', 'https://') in content_raw)

# 3. Verify db/001..008 & test_sql.sql
sql1 = read_text('db/001_schema.sql')
sql3 = read_text('db/003_release.sql')
sql4 = read_text('db/004_retention.sql')
sql5 = read_text('db/005_content_editor_security_fix.sql')
sql6 = read_text('db/006_security_rls_and_scoping.sql')
sql7 = read_text('db/007_seed_vocab.sql')
sql8 = read_text('db/008_scoped_insights.sql')
sqlt = read_text('db/test_sql.sql')

check('001 defines fold_run partial indexes and published_cell_history_idx',
      'raw_t1_fold_run_idx' in sql1 and 'raw_t2_fold_run_idx' in sql1 and 'published_cell_history_idx' in sql1)

check("003 carry-forward replaces delta/sticky (no sticky livelock; small changes republish the previous value)",
      "carried = true" in sql3 and "between 1 and 4" in sql3 and "set reason = 'sticky'" not in sql3 and "set reason = 'delta'" not in sql3)
check('003 enforces 15-student contributor floor via t1_cohort & t2_base', 'nl.t1_cohort' in sql3 and 'nl.t2_base' in sql3)
check('003 tracks both v_hit_row and v_hit_col in complementary loop', 'v_hit_row' in sql3 and 'v_hit_col' in sql3)
check('004 checks raw_t1 (24h) & raw_t2 (48h) in nl.health() and schedules monthly release', "interval '24 hours'" in sql4 and "interval '48 hours'" in sql4 and 'nl.raw_t2' in sql4 and 'monthly' in sql4)
check('005 uses public, pg_temp search_path & revokes PUBLIC', 'set search_path = public, pg_temp' in sql5 and 'revoke execute on function public.can_edit_city(text) from public' in sql5)
check('006 uses nl, pg_temp search_path & enables RLS on nl tables', 'set search_path = nl, pg_temp' in sql6 and sql6.count('enable row level security') >= 15)
check('006 uses dynamic secret salt & pg_catalog.sha256 without pgcrypto', 'nl.rate_limit_secret' in sql6 and 'pg_catalog.sha256' in sql6 and 'pgcrypto' not in sql6.lower())
check('006 sets global circuit-breaker limit (60000)', '60000' in sql6)
check('006 ingest gateway fails closed when unconfigured (dev opt-in via nl.allow_direct_dev only)',
      "raise exception 'ingest_gateway_not_configured' using errcode = '42501'" in sql6
      and "coalesce(current_setting('nl.allow_direct_dev', true), '') = '1'" in sql6
      and 'return;  -- not configured' not in sql6)
check('008 uses split_part (no LIKE wildcard) & fail-closed role check', 'split_part(row_key' in sql8 and "like p_institution" not in sql8 and "v_app_role not in ('super_admin', 'reader', 'editor')" in sql8)
check('008 redacts rate and band on tail-capped cells for non-pooled readers', 'or rate <= 0.10 or rate >= 0.90 then null' in sql8 and 'or rate <= 0.10 or rate >= 0.90 or denom < 50 then null' in sql8)

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
check('dashboard.html loads ./stats.js & links to ./editor.html', 'src="./stats.js"' in dash_html and 'href="./editor.html"' in dash_html)
check('dashboard.html has demo preview, intake filter, CSV export & bottlenecks panel',
      'nl-demo-btn' in dash_html and 'nl-intake-filter' in dash_html and 'nl-export-csv' in dash_html and 'nl-bottlenecks' in dash_html)
check('stats.js uses Object.create(null) & renders withheld rows/buckets', 'Object.create(null)' in stats_js and 'cells.concat(withheld)' in stats_js and 'h.bucket' in stats_js)
check('stats.js implements tail capping, Demo Mode, CSV injection guard & avoids innerHTML/document.write',
      "'<= 10.0%'" in stats_js and "'>= 90.0%'" in stats_js and 'DEMO_SNAPSHOT' in stats_js and 'exportCsv' in stats_js and 'innerHTML' not in stats_js and 'document.write' not in stats_js)
check('manifest.webmanifest has scope, theme_color, and icons', manifest_obj.get('name') == 'Netherlanded' and manifest_obj.get('scope') == '../' and len(manifest_obj.get('icons', [])) >= 1)
check('web/icon.svg exists', os.path.isfile(os.path.join(ROOT, 'web', 'icon.svg')))
check('root sw.js exists, skips /api/, returns Response.error(), and checks origin on notificationclick',
      "url.pathname.startsWith('/api/')" in sw_js and 'Response.error()' in sw_js and 'parsed.origin !== self.location.origin' in sw_js)
check('old web/sw.js removed', not os.path.exists(os.path.join(ROOT, 'web', 'sw.js')))

# 4b. Verify web/editor.html, web/editor.js & db/009_content_editor.sql
ed_html = read_text('web/editor.html')
ed_js = read_text('web/editor.js')
sql9 = read_text('db/009_content_editor.sql')

check('editor.html has copyright header, strict CSP, no Google Fonts, & links to dashboard.html',
      'Copyright (c) 2026 Eirini Konidari' in ed_html and 'http-equiv="Content-Security-Policy"' in ed_html and 'fonts.googleapis' not in ed_html and 'href="./dashboard.html"' in ed_html)
check('editor.html has staff auth form, role simulator, & ./editor.js script',
      'nl-editor-auth-form' in ed_html and 'nl-role-sim' in ed_html and 'src="./editor.js"' in ed_html)
check('dashboard.html & editor.html include WCAG overflow/focus/1rem fixes & region filter wrapper',
      'overflow-x: auto' in dash_html and 'font: 600 1rem var(--sans)' in dash_html and 'id="nl-region-filter-wrap"' in dash_html and 'outline: 3px solid var(--polder-text)' in dash_html and 'outline: 3px solid var(--polder-text)' in ed_html and 'font: 400 1rem var(--sans)' in ed_html)
check('editor.js uses Object.create(null), /api/editor, Demo can_edit_city, & avoids innerHTML/document.write',
      'Copyright (c) 2026 Eirini Konidari' in ed_js and 'Object.create(null)' in ed_js and '/api/editor' in ed_js and 'canEditCityDemo' in ed_js and 'innerHTML' not in ed_js and 'document.write' not in ed_js)
check('editor.js wires liveData tables, dynamic shared cities, community/government types, accepting_students & alert banner',
      'SHARED_CITIES.heerlen' not in ed_js and "'https://www.thuas.com/'" not in ed_js and 'E.liveData.services' in ed_js and 'E.liveData.step_local' in ed_js and 'E.liveData.facts' in ed_js and "'community'" in ed_js and "'government'" in ed_js and 'accepting_students: accStr' in ed_js and "setAttribute('role', 'alert')" in ed_js)
check('009_content_editor.sql has copyright, nl_content schema, RLS, search_path, future-date guard & immutable audit trigger',
      'Copyright (c) 2026 Eirini Konidari' in sql9 and 'create schema if not exists nl_content' in sql9 and sql9.count('enable row level security') >= 4 and 'set search_path = nl_content, public, pg_temp' in sql9 and sql9.count('v_verified > current_date') >= 3 and 'guard_staff_change_immutable' in sql9 and 'on_fact_insert' in sql9)
check('009_content_editor.sql seeds canonical tud/zuyd campuses, expands service_type, tightens URLs & returns campus_cities',
      "'community'" in sql9 and "'government'" in sql9 and "('tud', 'delft')" in sql9 and "('zuyd', 'heerlen')" in sql9 and "('tudelft', 'delft')" not in sql9 and "('wur', 'wageningen')" not in sql9 and "^https://[^\\s\"''<>\\\\]+$" in sql9 and "'campus_cities'" in sql9)

def csp_directives(html):
    m = re.search(r'<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]+)"', html, re.I)
    out = {}
    for part in (m.group(1) if m else '').split(';'):
        words = part.split()
        if words:
            out[words[0].lower()] = words[1:]
    return out


index_html = read_text('index.html')
for label, page in (('index.html', index_html), ('netherlanded-app.html', app_txt), ('dashboard.html', dash_html), ('editor.html', ed_html)):
    check(f'{label} sets no-referrer meta', '<meta name="referrer" content="no-referrer">' in page)

for label, page in (('netherlanded-app.html', app_txt), ('dashboard.html', dash_html), ('editor.html', ed_html)):
    d = csp_directives(page)
    check(f"{label} CSP limits connect-src to 'self' (no scheme-wide https: wildcard)", d.get('connect-src') == ["'self'"], str(d.get('connect-src')))

check('netherlanded-app.html escapes fact() in viewDeadlines',
      "esc(fact('cak_response_months'))" in app_txt and "esc(fact('cak_fine_eur'))" in app_txt)
check('editor.js allow-lists live subpaths', 'ALLOWED_SUBPATHS' in ed_js)

# 5. Verify edge/ adapters & security headers
edge_ingest = read_text('edge/ingest/index.ts')
edge_stats = read_text('edge/stats/index.ts')
edge_editor = read_text('edge/editor/index.ts')
edge_conf = read_text('edge/security-headers.conf')

check('edge/ingest uses streaming body cap, fail-closed CORS, proxy secret, and P0001 JSON match',
      'readBodyLimited' in edge_ingest and 'ALLOWED_ORIGINS.includes(origin)' in edge_ingest and 'NL_PROXY_SECRET' in edge_ingest and 'errJson?.code === "P0001"' in edge_ingest)
check('edge/stats pads base64url JWT with TextDecoder, checks proxy secret, forwards ingest secret, and fails closed on CORS',
      'TextDecoder' in edge_stats and 'ALLOWED_ORIGINS.includes(origin)' in edge_stats and 'NL_PROXY_SECRET' in edge_stats and 'NL_INGEST_SECRET' in edge_stats and 'release_json_for_institution' in edge_stats)
check('edge/editor uses readBodyLimited, fail-closed CORS, proxy secret, ingest secret, Bearer auth, and editor_list/service/step-local/fact/verify RPCs',
      'Copyright (c) 2026 Eirini Konidari' in edge_editor and 'readBodyLimited' in edge_editor and 'ALLOWED_ORIGINS.includes(origin)' in edge_editor and 'NL_PROXY_SECRET' in edge_editor and 'NL_INGEST_SECRET' in edge_editor and 'editor_list' in edge_editor and 'editor_publish_fact' in edge_editor)
check('edge/security-headers.conf has rate limit, SNI, proxy secret header, /api/stats, /api/editor, and /sw.js scope header',
      'limit_req_zone' in edge_conf and 'proxy_ssl_server_name on' in edge_conf and 'X-NL-Proxy-Secret' in edge_conf and 'location = /api/stats' in edge_conf and 'location ~ ^/api/editor' in edge_conf and 'Service-Worker-Allowed' in edge_conf)
check('edge/security-headers.conf verifies the upstream certificate (proxy_ssl_verify on, trusted CA, depth)',
      re.search(r'^\s*proxy_ssl_verify on;', edge_conf, re.M) is not None
      and re.search(r'^\s*proxy_ssl_trusted_certificate \S+;', edge_conf, re.M) is not None
      and re.search(r'^\s*proxy_ssl_verify_depth \d+;', edge_conf, re.M) is not None
      and re.search(r'^\s*proxy_ssl_verify off;', edge_conf, re.M) is None)
for ftxt in (edge_ingest, edge_stats, edge_editor, edge_conf):
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
