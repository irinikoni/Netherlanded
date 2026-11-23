# Disclosure control: how statistics reach universities

*Updated 21 November 2026 (v2.1 consolidation) for Privacy Policy version 2.1. The 6-rule SQL release engine is now implemented in [`db/001_schema.sql`](db/001_schema.sql)–[`db/004_retention.sql`](db/004_retention.sql), mirrored and tested by [`tools/suppress_reference.py`](tools/suppress_reference.py) and [`tools/test_suppression.py`](tools/test_suppression.py) (62/62 checks pass), and rendered safely by [`web/stats.js`](web/stats.js). Remaining pre-pilot tasks: executing the SQL on live PostgreSQL, adding per-institution tenant scoping/RLS to `nl.release_json()`, and adding edge rate limiting. Not legal advice.*

## 1. Principle

Universities never get database access. They get a **fixed, predefined snapshot** made by a server-side release function after every check below has passed. If the output is effectively anonymous for the university, its receipt falls outside the GDPR. Netherlanded's collection, temporary handling and aggregation stay inside the GDPR until anonymisation is complete.

```
Raw "+1" counter increments (never stored as rows)
        ↓
Aggregation per institution × intake semester × metric
        ↓
Cohort and denominator checks (≥ 15)
        ↓
Complementary suppression
        ↓
Change-over-time check
        ↓
Re-identification review (people, before each new report type)
        ↓
Approved snapshot → university dashboard (read-only)
```

## 2. What may go into each tier's reports

| Tier 1: limited service statistics (legitimate interest, objection) | Tier 2: additional statistics (consent) |
|---|---|
| Participating students per institution and intake semester | EU/EEA versus non-EU/EEA comparisons |
| Broad step-category applicability and completion rates | Missed immigration, CAK, insurance, financial or municipal deadlines |
| Technical error counts per app version | Housing-scam check outcomes |
| Missing or unclear content counts (not built yet) | Step opening and completion (timing flags such as `on_time` removed per `LEGAL_DELTA.md` #10) |
| Trends between sufficiently large semesters | Campus, programme or municipality-level results |
| | Any metric meant to find groups for intervention, or that suggests a group may be non-compliant |

When a new metric cannot clearly be called low-impact, general service improvement, it goes to Tier 2.

## 3. Publication rule

A result is shown only when **all** of these hold, checked on the **final combination** of every dimension in the report, not on each dimension separately:

```
cohort contributors          >= 15
AND metric denominator       >= 15   -- students the metric applies to
AND every comparison group   >= 15
AND complementary check passes
AND change-over-time check passes
```

Otherwise the cell shows **"Insufficient group size"**. Never zero, "<15", a percentage, or a chart position from which the value could be inferred.

**Example that may be released:** *THUAS, September 2026 intake: 68% of 74 contributing students completed a registration step.*
**Example that must be suppressed:** *THUAS, September 2026, non-EU/EEA students living in Zoetermeer: 4 of 6 completed municipality registration.*

## 4. Complementary suppression

If a total and one side of a split are shown, the other side can be worked out by subtraction. "20 eligible, 17 completed" reveals that 3 did not.

**Rule chosen for the pilot (the strict rule):** a completion result is shown only if both `completed >= 15` and `not_completed >= 15`. Also suppress any other cell whose value could be worked out from cells that are shown, including row and column totals.

This will suppress many pilot results. **Documented alternative**, only after a written disclosure-risk assessment signed by the controller: publish percentages rounded to the nearest 5 or 10 points, without exact denominators, when the denominator is at least 15 but one side is below 15.

## 5. Change over time

- No live dashboards. Snapshots are made **monthly**. Fortnightly is acceptable only for cohorts above 50.
- No daily or weekly history. Compare only whole intake semesters with each other.
- Suppress an updated value if it rests on **fewer than 5** new contributions since the previous snapshot. Show the previous value instead.
- Round percentages to whole points; for denominators under 50, round to the nearest 5.

### Known limitation: contributor counts are self-reported

The system holds no identifiers by design, so it cannot de-duplicate devices. The 15-contributor floor counts `cohort_joined` events, and Tier 2 denominators count events. A reinstall, a repeated send, or deliberately fabricated events can inflate a count past the floor or skew a rate. Mitigations: gateway-only ingest (`nl.check_ingest_gateway()`), per-IP limits at Nginx, the per-tier event circuit breaker, and the human people-check before each release. The DPIA must state this residual risk.

## 6. Background knowledge

A group of 15 is not automatically anonymous if the university already knows who is in it: who contacted the International Office, who received a CAK letter, who lives in a certain municipality, who has a certain immigration requirement. This is why Tier 1 reports carry no region, municipality, campus or deadline dimensions, and why those stay in Tier 2.

## 7. What the university gets, and what it doesn't

| Gets | Does not get |
|---|---|
| A read-only dashboard of approved snapshots for its own institution | Access to the counter database, the ingest function, logs, accounts or raw increments |
| Predefined reports listed in the pilot specification | Filters, custom cuts, SQL, or ad-hoc requests that bypass suppression |
| Exports of the same snapshots, with the same suppression | Exports of anything not on the dashboard |

**Use restriction**, written into the university agreement: no decisions or interventions concerning individual students; no attempt to re-identify students; no combining with its own records to single out students.

## 8. Controller model (Path B — Multi-Tenant Controller / Art. 28 Processor)

**Adopted architecture (Path B, SURF Model DPA):**
- **Each contracted participating university is the independent GDPR controller** for its own incoming students' onboarding analytics under a signed **SURF Model Data Processing Agreement (*Verwerkersovereenkomst*, Art. 28 GDPR)**. Netherlanded operates strictly as the multi-tenant **Data Processor** (`edge/*` + EU Supabase PostgreSQL) on behalf of each contracting institution.
- **No cross-university joint controllership:** Each university receives only its own institution's disclosure-controlled snapshots (`db/008_scoped_insights.sql`); universities never see other institutions' data or raw counters, and per-institution complementary suppression is strictly isolated.
- **Non-partner exclusion:** Students whose selected institution is not flagged as a contracted partner (`nl-partner-institutions`) do not emit institution-scoped Tier 1 metrics.
- **National benchmark clause:** Each SURF Model DPA authorizes Netherlanded to compile irreversible, disclosure-controlled national benchmarks (GDPR Recital 26: floor >= 15, rounded to 5, zero personal data).
- **Use restriction:** Written into every university agreement — zero decisions or interventions concerning individual students, zero attempts to re-identify students, and zero combining with internal university records to single out individuals.

*(This resolves the governance question raised in `LEGAL_DELTA.md` §1 cleanly across 2, 10, or 50 Dutch universities.)*

## 9. Build list

- [x] `nl.accumulate()`, `nl.build_stage()`, `nl.assert_release_safe()`, `nl.publish_snapshot()`, and `nl.release_json()` implemented in [`db/003_release.sql`](db/003_release.sql) (15-person floor, unbiased rounding to the **nearest** 5, delta suppression below `max(5pp, 5/denominator)` so a change resting on fewer than ~5 people is never published, 2-release sticky suppression, 2D complementary suppression plus secondary suppression of a lone withheld cell in an institution-scoped column, and withheld bucket reporting for pooled readers only).
- [x] Separate Tier 1 (`nl.ingest_t1` / `nl.raw_t1`) and Tier 2 (`nl.ingest_t2` / `nl.raw_t2`) endpoints and tables in [`db/001_schema.sql`](db/001_schema.sql) and [`db/002_ingest.sql`](db/002_ingest.sql).
- [x] Per-institution tenant scoping, RLS, tail redaction, and `split_part` isolation implemented in [`db/006_security_rls_and_scoping.sql`](db/006_security_rls_and_scoping.sql) and [`db/008_scoped_insights.sql`](db/008_scoped_insights.sql).
- [x] Edge IP/UA stripping in RAM, ≤ 24h IP-free logs, per-IP `30r/m` rate limiting, and `X-NL-Proxy-Secret` bypass protection configured in [`edge/security-headers.conf`](edge/security-headers.conf) and [`edge/*`](edge/ingest/index.ts); Tier 1 raw purge tightened to **24h** in [`db/004_retention.sql`](db/004_retention.sql).
- [x] Safe read-only dashboard renderer [`web/stats.js`](web/stats.js) (zero `innerHTML`, `credentials: 'omit'`, capped tails `<= 10.0%` / `>= 90.0%`).
- [x] Reference specification and live PostgreSQL 16.2 verification suite in [`tools/test_suppression.py`](tools/test_suppression.py), [`tools/verify_build.py`](tools/verify_build.py), and [`tools/run_pg_tests.py`](tools/run_pg_tests.py).
- [x] Shared-city content editor privilege fix and audited CMS RPCs in [`db/005_content_editor_security_fix.sql`](db/005_content_editor_security_fix.sql) and [`db/009_content_editor.sql`](db/009_content_editor.sql).
- [ ] Verify hosted Supabase deployment (`pg_cron` jobs uncommented, `NL_PROXY_SECRET` set) and run a human people-check before adding any new report dimension.
