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

## 6. Background knowledge

A group of 15 is not automatically anonymous if the university already knows who is in it: who contacted the International Office, who received a CAK letter, who lives in a certain municipality, who has a certain immigration requirement. This is why Tier 1 reports carry no region, municipality, campus or deadline dimensions, and why those stay in Tier 2.

## 7. What the university gets, and what it doesn't

| Gets | Does not get |
|---|---|
| A read-only dashboard of approved snapshots for its own institution | Access to the counter database, the ingest function, logs, accounts or raw increments |
| Predefined reports listed in the pilot specification | Filters, custom cuts, SQL, or ad-hoc requests that bypass suppression |
| Exports of the same snapshots, with the same suppression | Exports of anything not on the dashboard |

**Use restriction**, written into the university agreement: no decisions or interventions concerning individual students; no attempt to re-identify students; no combining with its own records to single out students.

## 8. Controller model

**Preferred, for the pilot:** Netherlanded is the controller for collection and aggregation; Supabase and the e-mail provider are processors; the university receives only anonymous output and cannot influence which fields are collected. THUAS may review the pilot specification for usefulness and safety, but Tier 1 metrics stay fixed in that specification.

**Higher-risk, avoid:** if the university decides which behaviours are measured, which student groups are compared, how long records are kept, or which reports are made, it may become an independent or joint controller for part of the processing, whether or not the output is called aggregate.

> **Open governance decision (`LEGAL_DELTA.md` §1 vs. §8 above):** `LEGAL_DELTA.md` §1 alternatively models the university as GDPR controller and the app author as processor under an Article 28 processing agreement. Settle which controller model applies with the THUAS privacy officer (FG) before pilot launch, and update `TERMS_AND_PRIVACY.md` §11 accordingly.

## 9. Build list

- [x] `nl.accumulate()`, `nl.build_stage()`, `nl.assert_release_safe()`, `nl.publish_snapshot()`, and `nl.release_json()` implemented in [`db/003_release.sql`](db/003_release.sql) (15-person floor, rounding to 5, `< 5`pp delta, 2-release sticky suppression, 2D complementary suppression, and withheld bucket reporting).
- [x] Separate Tier 1 (`nl.ingest_t1` / `nl.raw_t1`) and Tier 2 (`nl.ingest_t2` / `nl.raw_t2`) endpoints and tables in [`db/001_schema.sql`](db/001_schema.sql) and [`db/002_ingest.sql`](db/002_ingest.sql).
- [x] Safe read-only dashboard renderer [`web/stats.js`](web/stats.js) (zero `innerHTML`, `credentials: 'omit'`, withheld cells rendered as bucket counts, never zeros).
- [x] Reference specification and 62-check verification suite in [`tools/test_suppression.py`](tools/test_suppression.py) (passes 62/62).
- [x] Shared-city content editor privilege fix in [`db/005_content_editor_security_fix.sql`](db/005_content_editor_security_fix.sql).
- [ ] Execute `db/001`–`db/005` against a live PostgreSQL 15+ instance and verify `pg_cron` jobs for hourly fold/purge and monthly release.
- [ ] Add per-institution tenant scoping / RLS so `nl.release_json()` and staff credentials expose only their own institution's rows (currently `release_json(null)` returns all institutions and pooled category/step tables).
- [ ] Configure edge/API rate limiting and edge IP stripping before pilot traffic.
- [ ] A people check before every new report type: could this be combined with what the university knows?
