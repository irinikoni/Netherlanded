# Netherlanded – Consolidated Legal, App & Analytics Package (v2.1)

Netherlanded is a checklist app for first-year international students arriving in the Netherlands (Creative Business Solutions project, THUAS). This folder consolidates the working prototype, the harmonised legal documentation (v2.1), the PostgreSQL statistical disclosure-control backend, the dashboard renderer, and the verification suite.

## What's in this folder

| Path | What it is |
|---|---|
| `netherlanded-app.html` | Working prototype (`TERMS_V = '2.1'`) with embedded Terms & Privacy Policy v2.1, separate Tier 1 notice/objection & Tier 2 opt-in consent flows, weekly shuffled client batching, and local telemetry inspection in *See my data*. Open in a browser, ideally in phone size. |
| `TERMS_AND_PRIVACY.md` | Terms of Service and Privacy Policy, version 2.1 (21 November 2026), harmonised with `LEGAL_DELTA.md` and `COMPLIANCE_CHECK.md`. The exact same text is embedded inside `netherlanded-app.html`. |
| `LEGITIMATE_INTEREST_ASSESSMENT.md` | Written balancing test for Tier 1 limited service statistics (GDPR Art. 6(1)(f)), covering both Netherlanded's and participating universities' interests. |
| `DISCLOSURE_CONTROL.md` | How statistics reach universities: 6-rule disclosure-control pipeline, 15-student floor, rounding to 5, delta/sticky/complementary suppression, controller model, and use restrictions. |
| `COMPLIANCE_CHECK.md` | Compliance review against GDPR/AVG, *Telecommunicatiewet* art. 11.7a, and Dutch consumer law, updated with v2.1 resolution status and remaining pre-pilot blockers. |
| `PRIVACY_ASSESSMENT.md` | Deep privacy assessment (host IP logging, Dutch cookie rule, cohorts, governance decisions). |
| `LEGAL_DELTA.md` | Audit of 10 legal-text and implementation corrections owed before production, with v2.1 consolidation status. |
| `LEGAL_IMPLEMENTATION_NOTES.md` | Concise legal-engineering handover notes and remaining production conditions. |
| `RELEASE_CHECKLIST.md` | Pre-production deployment, privacy, and testing checklist. |
| `db/001_schema.sql` | PostgreSQL 15+ analytics schema: separate `nl.raw_t1` and `nl.raw_t2` stores, 7 app categories, release/suppression tables. |
| `db/002_ingest.sql` | Tier 1 (`nl.ingest_t1`) and Tier 2 (`nl.ingest_t2`) ingest RPCs with shape validation and identity-field rejection (`22023`). |
| `db/003_release.sql` | Hourly fold (`nl.accumulate()`), 6-rule suppression (`nl.build_stage()`), pre-publish audit (`nl.assert_release_safe()`), snapshot publication, and JSON export (`nl.release_json()`). |
| `db/004_retention.sql` | Retention policy (`48 hours` ceiling on raw events, `90` days staging, `1095` days / 3 years snapshots), `nl.purge_raw()`, delete-guard triggers, and `nl.health()`. |
| `db/005_content_editor_security_fix.sql` | Shared-city editor privilege fix (`can_edit_city`) with safe `search_path = public, pg_temp`. |
| `db/006_security_rls_and_scoping.sql` | Least-privilege schema locks, RLS on all `nl` tables, campus-NAT-friendly `pg_catalog.sha256` hourly rate-limiting RPCs (`nl.ingest_t1_rpc`, `nl.ingest_t2_rpc`), and per-institution scoped release JSON (`nl.release_json_for_institution`). |
| `db/007_seed_vocab.sql` | Idempotent seed script generated from `netherlanded-app.html` for all 29 participating institutions and 19 journey steps. |
| `db/008_scoped_insights.sql` | Institution-scoped category, step, opened, missed-deadline, region, and scam-check release tables folding all collected Tier 1 & Tier 2 fields under the 6-rule disclosure-control pipeline. |
| `db/test_sql.sql` | Transactional (`BEGIN ... ROLLBACK`) PostgreSQL verification suite exercising ingest, batching, `22023`/`42501` guards, folding, snapshot safety, cross-institution isolation, purge, and health. |
| `edge/` | Thin Deno/Supabase Edge adapters (`ingest/index.ts`, `stats/index.ts`) and reverse-proxy hardening (`security-headers.conf` for IP-free logs, `frame-ancestors 'none'`, `nosniff`). |
| `web/dashboard.html` | Strict-CSP, dependency-free university insights page hosting `web/stats.js` and staff JWT authentication input. |
| `web/stats.js` | Dependency-free dashboard renderer (zero `innerHTML`, `credentials: 'omit'`, 10s timeout, tail capping at `<= 10.0%` / `>= 90.0%`, withheld bucket/row display, and cold-start UX). |
| `sw.js`, `web/manifest.webmanifest` & `web/icon.svg` | Root-scoped HTTPS Service Worker (skipping `/api/` and `no-store` responses, same-origin notification URL validation) and PWA manifest/icon. |
| `tools/suppress_reference.py` | Executable Python reference implementation of the 6 suppression rules. |
| `tools/test_suppression.py` | 62-check unit + static verification suite for suppression rules, SQL invariants, dashboard safety, and docs. |
| `tools/verify_build.py` | End-to-end build verifier checking `tools/test_suppression.py`, CSP SHA-256 hash integrity, JSON/JS symbols, SQL security/seeding parity, and dashboard CSP. |
| `tools/run_pg_tests.py` | Embedded PostgreSQL test runner (via `pgserver` + `psycopg[binary]`) executing `db/001`–`db/008`, `db/005`, `db/test_sql.sql`, and live `anon`/`authenticated` role-isolation checks. |
| `architecture/` | System architecture (`ARCHITECTURE.md`), `INFRASTRUCTURE.md`, `SECURITY_AUDIT.md`, `CHECKLISTS.md`, `SOURCE_AND_BUILD.md`, research (`FACT_CHECK.md`, `CITY_RESEARCH.md`), and design history. |

## How to see the legal flow in the app

1. Open `netherlanded-app.html`. Profile setup starts: school, then city or campus, then where you live.
2. After the profile you see **Before you start**: the key terms and a link to the full Terms and Privacy Policy (v2.1). Tap *Agree and continue*.
3. Next comes **Limited service statistics** (Tier 1), a dedicated notice with equal *Continue* and *Object to limited statistics* buttons.
4. Then **Contribute to university support insights**, the separate opt-in for Tier 2. *Continue with sharing* and *Continue without sharing* have equal weight; *Decide later* asks once more after 3 finished steps or 3 weeks; *See exactly what is included* lists both tiers.
5. Both choices can be changed in **Profile → Privacy & legal** (*Anonymous statistics*). Switching either off deletes its counts on the phone. Inspect stored data under *Profile → See my data* and reset with *Profile → Delete all data*.

## Running the analytics database and tests

Requirements: Python 3, and (for the database) PostgreSQL 15+ with `psql`.

Run the verification suites:

    python3 tools/test_suppression.py
    python3 tools/verify_build.py
    python3 tools/run_pg_tests.py   # requires pgserver and psycopg[binary]

To test the SQL migrations on a throwaway PostgreSQL container via `docker` and `psql`:

    docker run --name nl-pg -e POSTGRES_PASSWORD=dev -p 5432:5432 -d postgres:16
    export PGPASSWORD=dev
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/001_schema.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/002_ingest.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/003_release.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/004_retention.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/006_security_rls_and_scoping.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/007_seed_vocab.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/008_scoped_insights.sql
    psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/test_sql.sql

Seed an institution, ingest a smoke test, and fold/release a snapshot:

    insert into nl.institution (institution, display_name) values ('thuas', 'The Hague University of Applied Sciences');
    select nl.ingest_t1('{"institution":"thuas","intake":"2026-sep","event":"step_applies","category":"housing","app_version":"3b32b5914fb6bdfc"}');
    select nl.accumulate();
    select nl.publish_snapshot('first release');
    select jsonb_pretty(nl.release_json(null));

## What has and has not been verified

- `tools/test_suppression.py` (62/62 checks) and `tools/verify_build.py` (126/126 checks) pass across the suppression engine, CSP SHA-256 hash, dashboard, SQL invariants, edge adapters, PWA files, and vocabulary seeds.
- `tools/run_pg_tests.py` (22/22 checks) executed `db/001`–`db/008`, `db/005`, `db/test_sql.sql`, and live `anon`/`authenticated` role-isolation checks against an embedded local PostgreSQL 16.2 server.
- **Production deployment has not been run yet.** Live Supabase/hosted `pg_cron` jobs, Edge Functions (`edge/ingest`, `edge/stats`), and production gateway IP stripping still need to be tested against the target Supabase/Postgres instance.
- Four external links in `netherlanded-app.html` (`http://international.zuyd.nl/`, `http://www.huisartsenpostdelft.nl/english/`, `http://www.lebecitycampus.nl/en/`, `http://www.stichtingveste.nl/index.php/nieuw-in-venlo/`) remain on `http://` because their TLS certificates failed verification during checking (5 other verified links were upgraded to `https://`).
- Before real students use the app, all open governance/legal items in `COMPLIANCE_CHECK.md`, `LEGAL_DELTA.md`, and `RELEASE_CHECKLIST.md` (named controller, DPIA, Art. 28 DPAs, university agreements, per-institution dashboard scoping, edge IP stripping, and privacy-officer sign-off on Tier 1) must be completed. The texts in this package are not legal advice.
