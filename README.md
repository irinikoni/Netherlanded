# Netherlanded – Consolidated Legal, App & Analytics Package (v2.1)

Netherlanded is a checklist and arrival-guidance web application for first-year international students arriving in the Netherlands (International Business project, THUAS). This repository consolidates the working student app, the harmonised legal documentation (v2.1), the PostgreSQL statistical disclosure-control & content-editor backends, the University Insights Dashboard, the Content Editor Panel, the business case deliverables, and the automated verification suite.

## What's in this repository

| Path | What it is |
|---|---|
| `LICENSE` | Proprietary copyright notice (`Copyright (c) 2026 Eirini Konidari. All rights reserved.`). |
| `netherlanded-app.html` | Working student prototype (`TERMS_V = '2.1'`) with embedded Terms & Privacy Policy v2.1, separate Tier 1 notice/objection & Tier 2 opt-in consent flows, weekly shuffled client batching, and local telemetry inspection in *See my data*. |
| `TERMS_AND_PRIVACY.md` | Terms of Service and Privacy Policy, version 2.1 (21 November 2026), harmonised with `LEGAL_DELTA.md` and `COMPLIANCE_CHECK.md`. The exact same text is embedded inside `netherlanded-app.html`. |
| `LEGITIMATE_INTEREST_ASSESSMENT.md` | Written balancing test for Tier 1 limited service statistics (GDPR Art. 6(1)(f)), covering both Netherlanded's and participating universities' interests. |
| `DISCLOSURE_CONTROL.md` | How statistics reach universities: 6-rule disclosure-control pipeline, 15-student floor, cell-key noise, rounding to 5, carry-forward and complementary suppression, controller model, and use restrictions. |
| `COMPLIANCE_CHECK.md` | Compliance review against GDPR/AVG, *Telecommunicatiewet* art. 11.7a, and Dutch consumer law, updated with v2.1 resolution status and remaining pre-pilot blockers. |
| `PRIVACY_ASSESSMENT.md` | Deep privacy assessment (host IP logging, Dutch cookie rule, cohorts, governance decisions). |
| `LEGAL_DELTA.md` | Audit of 10 legal-text and implementation corrections owed before production, with v2.1 consolidation status. |
| `LEGAL_IMPLEMENTATION_NOTES.md` | Concise legal-engineering handover notes and remaining production conditions. |
| `RELEASE_CHECKLIST.md` | Pre-production deployment, privacy, and testing checklist. |
| `db/001_schema.sql`–`db/008_scoped_insights.sql` | PostgreSQL 15+ analytics schema, Tier 1/2 ingest RPCs, hourly fold (`nl.accumulate()`), 6-rule suppression (`nl.build_stage()`), retention (`48 hours` raw ceiling), RLS, campus-NAT rate limiting, vocabulary seeds (29 institutions, 19 steps), and tenant-scoped release exporter (`nl.release_json_for_institution`). |
| `db/005_content_editor_security_fix.sql` & `db/009_content_editor.sql` | Shared-city editor privilege fix (`public.can_edit_city`) and isolated `nl_content` schema (`service`, `step_local`, versioned `fact` with `on_fact_insert` auto-closing trigger, append-only `staff_change` audit log, and 5 fail-closed `SECURITY DEFINER` RPCs). |
| `db/test_sql.sql` | Transactional (`BEGIN ... ROLLBACK`) PostgreSQL verification suite exercising ingest, batching, `22023`/`42501` guards, folding, snapshot safety, cross-institution isolation, purge, and health. |
| `edge/` | Stateless Deno/Supabase Edge adapters (`ingest/index.ts`, `stats/index.ts`, `editor/index.ts`) and reverse-proxy hardening (`security-headers.conf` for IP-free logs, `/api/t1`, `/api/t2`, `/api/stats`, `/api/editor`, `frame-ancestors 'none'`, `nosniff`). |
| `web/dashboard.html` & `web/stats.js` | Strict-CSP, zero-`innerHTML` University Dashboard with Polder/Horizon light & dark UI, v2.1-compliant Demo Preview (`floor >= 15`, rounded to 5, tail-capped `<= 10.0%` / `>= 90.0%`), formula-safe CSV export, and live `/api/stats` Staff JWT mode. |
| `web/editor.html` & `web/editor.js` | Strict-CSP, zero-`innerHTML` 6-tab Content Editor Panel (`To check`, `Local texts`, `Services`, `Figures`, `Steps`, `Changes`) enforcing `can_edit_city()` shared-city locks, THUAS override workflow, URL validation, change reasons, JSON export, and live `/api/editor` sync. |
| `sw.js`, `web/manifest.webmanifest` & `web/icon.svg` | Root-scoped HTTPS Service Worker (skipping `/api/` and `no-store` responses, same-origin notification URL validation) and PWA manifest/icon. |
| `tools/` | `suppress_reference.py` (Python reference engine), `test_suppression.py` (62 checks), `verify_build.py` (162 checks), and `run_pg_tests.py` (live PostgreSQL 16.2 test & multi-connection concurrency runner). |
| `business/` | IB business deliverables: `COMPETITOR_ANALYSIS.md`, `BUSINESS_MODEL_AND_ROI.md`, `STAKEHOLDER_ANALYSIS.md`, `CHECKLIST_BENCHMARK_AUDIT.md`, `INTERNATIONAL_EXPANSION_OUTLOOK.md` (CAGE framework), and `REPORT_HYGIENE_AND_REFLECTION.md`. |
| `architecture/` | System architecture (`ARCHITECTURE.md`), `INFRASTRUCTURE.md`, `SECURITY_AUDIT.md`, `PENTEST_PLAN.md` (pentest simulation options, attack scripts in `tools/pentest/`), `CHECKLISTS.md`, `SOURCE_AND_BUILD.md`, research (`FACT_CHECK.md`, `CITY_RESEARCH.md`), and design history. |
| `.github/workflows/` | GitHub Actions workflows: `ci.yml` (runs all 3 verification suites on push/PR) and `pages.yml` (publishes `index.html`, `netherlanded-app.html`, `sw.js`, and `web/` to GitHub Pages). |
| `index.html` | Static GitHub Pages landing portal linking directly to `netherlanded-app.html`, `web/dashboard.html`, and `web/editor.html` in Demo Mode. |

## How to preview the app, dashboard, and editor

1. **Student App (`netherlanded-app.html`):** Open in a browser (ideally mobile viewport). Complete profile setup, review **Before you start** (Terms & Privacy v2.1), then review the separate **Limited service statistics** (Tier 1) and **Contribute to university support insights** (Tier 2) screens.
2. **University Dashboard (`web/dashboard.html`):** Open directly in a browser to explore the v2.1-hardened Demo Preview across `THUAS International Office`, `Leiden University`, and `THUAS Zoetermeer (<15 suppression state)`, or paste a Staff Bearer JWT to query `/api/stats`.
3. **Content Editor (`web/editor.html`):** Open in a browser to test the 6-tab editorial workflow and switch between `THUAS International Office` (shared cities locked, institution overrides and Zoetermeer unlocked) and `Project team (all content)`, or connect to `/api/editor` with a Staff JWT.

## Running the verification suites

Requirements: Python 3.10+ (and `pgserver` + `psycopg[binary]` for embedded PostgreSQL 16 testing, or `docker` and `psql` for a containerised instance).

```bash
python3 tools/test_suppression.py
python3 tools/verify_build.py
python3 tools/run_pg_tests.py
```

To apply the SQL migrations manually on a throwaway PostgreSQL container via `docker` and `psql`:

```bash
docker run --name nl-pg -e POSTGRES_PASSWORD=dev -p 5432:5432 -d postgres:16
export PGPASSWORD=dev
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/001_schema.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/002_ingest.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/003_release.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/004_retention.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/006_security_rls_and_scoping.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/007_seed_vocab.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/008_scoped_insights.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/009_content_editor.sql
psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/test_sql.sql
```

## Verification status

- `tools/test_suppression.py` (**62/62 checks**) and `tools/verify_build.py` (**162/162 checks**) pass across the suppression engine, CSP SHA-256 hash, dashboard, content editor, SQL invariants, edge adapters, PWA files, and vocabulary seeds.
- `tools/run_pg_tests.py` (**63/63 checks**) executes `db/001`–`db/009`, `db/test_sql.sql`, live `anon`/`authenticated` role-isolation checks, shared-city editor privilege boundaries, and multi-connection concurrency stress tests against an embedded PostgreSQL 16.2 server.
- **Total automated checks: 287 / 287 passing.**
- **Production deployment has not been run yet.** Live hosted `pg_cron` jobs, Edge Functions (`edge/ingest`, `edge/stats`, `edge/editor`), and gateway IP stripping still need to be tested against the target EU Supabase/Postgres host.
- Four external links in `netherlanded-app.html` (`http://international.zuyd.nl/`, `http://www.huisartsenpostdelft.nl/english/`, `http://www.lebecitycampus.nl/en/`, `http://www.stichtingveste.nl/index.php/nieuw-in-venlo/`) remain on `http://` because their TLS certificates failed verification during checking (5 other verified links were upgraded to `https://`).
- Before a live production rollout with real students, complete the external governance items in `COMPLIANCE_CHECK.md` and `RELEASE_CHECKLIST.md` (lawyer/DPO sign-off, signed Art. 28 DPAs, and live EU Supabase deployment). The documents in this repository are not formal legal advice.
