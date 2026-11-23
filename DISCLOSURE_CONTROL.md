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

### 3a. Cell-key perturbation (defence against flooding)

Floors and rounding alone cannot stop an **n-1 flooding attack**. Ingest is anonymous, so an insider who knows the one real student in a small intake can submit fake contributors to pass the floor, and choose the fake count so that the real student's single event straddles a rounding boundary. Before this rule, the published cell revealed that student's status with certainty (`tools/pentest/n1_flooding.py`).

**Rule:** every raw event receives a secret, server-assigned record key (0–251). Each cell carries the sum of its contributors' keys (mod 252), and that cell key selects a fixed perturbation of −4…+4, added to the count before rounding to 5 (`nl.new_record_key()`, `nl.cell_noise()`, `nl.build_stage()`). Clients can neither choose nor see keys.

- **Effect on the attack:** the attacker's best guess about the real student drops from certainty to **55.6 %**, against 50 % for a coin flip (measured over 1,000 trials per case; the theoretical value is 0.5 + 1/18).
- **Consistency:** an unchanged cell always gets the same noise, so republishing it cannot be averaged away.
- **Accuracy cost:** published counts stay within 6 of the truth (noise 4 + rounding 2). Rates on denominators of 100 or more move by a few points at most. Small cells were already shown only as bands or ranges.
- **Residual risk:** an attacker who keeps changing the cell (adding new fake events before each monthly snapshot) gets a fresh noise draw each time and can, in principle, average over many releases. The monthly cadence, the delta and sticky rules (a change of fewer than ~5 people is withheld for three releases), gateway-only ingest and per-IP limits make this slow and visible. The DPIA must state it.

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

## 8. Controller model (Path B, per-operation split)

*Draft for review by external privacy counsel and the partner university's data protection officer (FG). Roles are assigned per processing operation (EDPB Guidelines 07/2020): one party can be a controller for one operation and a processor for another.*

**Netherlanded's legal entity:** an *eenmanszaak* (sole proprietorship) registered with the KVK before the pilot. An *eenmanszaak* has no separate legal personality, so the owner is personally the controller and personally liable. This makes professional indemnity and cyber insurance a precondition for signing, and a BV worth considering once revenue allows.

| # | Processing operation | Controller | Netherlanded | Legal basis | Instrument |
|---|---|---|---|---|---|
| A | Serving the app; gateway security; IP-free technical logs; rate limiting | Netherlanded | Controller | Art. 6(1)(f): secure, reliable service | Privacy policy §11, §13 |
| B | Collecting Tier 1 / Tier 2 counts and holding raw events (≤ 24 h / ≤ 48 h) until folded | Netherlanded **and** the partner university, jointly (Art. 26). Netherlanded alone for non-partner students (technical error counts only) | Joint controller | Tier 1: Art. 6(1)(f) + *Tw* 11.7a(3)(b) (Netherlanded is the service provider). Tier 2: consent, Art. 6(1)(a) | **Art. 26 arrangement** in the university agreement |
| C | Producing the university's own scoped reports and dashboard (`db/008_scoped_insights.sql`) | The partner university | Processor | The university's Art. 6(1)(f) (Tier 1) / consent (Tier 2) | **SURF Model DPA** (*Verwerkersovereenkomst*, Art. 28) |
| D | National benchmarks across all partner universities (`t1_category_totals`, `t2_step_totals`) | Netherlanded | Controller | Art. 6(1)(f): improving guidance for all students; sector findings | Netherlanded's own LIA (`LEGITIMATE_INTEREST_ASSESSMENT.md` Part 2); disclosed in policy §11, §13 |
| E | Staff accounts and the content-editor audit log (`nl_content.staff_change`) | Netherlanded | Controller | Art. 6(1)(f): content integrity and accountability | Separate staff privacy notice |

**Why benchmarks are not in the DPA.** A processor may only process for its client's purposes (Art. 28(10)). A cross-university benchmark serves Netherlanded's purpose, so it cannot be "authorised" by each university's DPA. Netherlanded takes it on as controller (operation D) instead. Its output passes the same disclosure-control pipeline and contains no personal data, but compiling it from raw counts is still processing.

**Art. 26 arrangement (operation B): essence to publish.**
- Netherlanded decides what is counted, the event schema, retention, and the security and disclosure-control measures. The university decides that its cohort is measured for its reports.
- Netherlanded provides the Art. 13 notice (the in-app policy), is the contact point for data-subject requests, and forwards requests about reports to the university.
- Data subjects may exercise their rights against either party (Art. 26(3)).
- Each party reports personal-data breaches affecting operation B to the other within 24 hours. Netherlanded notifies the AP for its own operations A, B, D and E.

**What stays as before:**
- **No cross-university access.** Each university sees only its own institution's snapshots. Benchmarks are published only as pooled, disclosure-controlled totals.
- **Non-partner exclusion.** Students of non-partner institutions (`nl-partner-institutions`) emit no institution-level Tier 1 metrics.
- **Use restriction**, written into every university agreement: no decisions or interventions concerning individual students, no attempts to re-identify students, and no combining with internal records to single out individuals.

**Contractual dashboard entitlement (university agreement, service schedule).** The university's access is a contractual right, not a courtesy:
- read-only Insights Dashboard access for named staff seats (Standard: up to [10] seats; Enterprise: [unlimited]);
- a disclosure-controlled snapshot published at least **monthly** during each intake window;
- CSV export of every published snapshot;
- published snapshots kept available for **3 years** (matching `nl.purge_raw()`) for intake-on-intake comparison;
- Content Editor access for the university's own services and single-institution cities;
- target availability of [99.5]% per month outside announced maintenance, with service credits if missed.

The schedule must also state plainly that **cells failing the disclosure-control rules are withheld**: access to the dashboard is guaranteed, specific numbers are not.

*(Supersedes the earlier "pure processor plus DPA-authorised benchmark" wording. Settles `LEGAL_DELTA.md` §1 subject to counsel review.)*

## 9. Build list

- [x] `nl.accumulate()`, `nl.build_stage()`, `nl.assert_release_safe()`, `nl.publish_snapshot()`, and `nl.release_json()` implemented in [`db/003_release.sql`](db/003_release.sql) (15-person floor, secret cell-key perturbation of −4…+4 (§3a), unbiased rounding to the **nearest** 5, delta suppression below `max(5pp, 5/denominator)` so a change resting on fewer than ~5 people is never published, 2-release sticky suppression, 2D complementary suppression plus secondary suppression of a lone withheld cell in an institution-scoped column, and withheld bucket reporting for pooled readers only).
- [x] Separate Tier 1 (`nl.ingest_t1` / `nl.raw_t1`) and Tier 2 (`nl.ingest_t2` / `nl.raw_t2`) endpoints and tables in [`db/001_schema.sql`](db/001_schema.sql) and [`db/002_ingest.sql`](db/002_ingest.sql).
- [x] Per-institution tenant scoping, RLS, tail redaction, and `split_part` isolation implemented in [`db/006_security_rls_and_scoping.sql`](db/006_security_rls_and_scoping.sql) and [`db/008_scoped_insights.sql`](db/008_scoped_insights.sql).
- [x] Edge IP/UA stripping in RAM, ≤ 24h IP-free logs, per-IP `30r/m` rate limiting, and `X-NL-Proxy-Secret` bypass protection configured in [`edge/security-headers.conf`](edge/security-headers.conf) and [`edge/*`](edge/ingest/index.ts); Tier 1 raw purge tightened to **24h** in [`db/004_retention.sql`](db/004_retention.sql).
- [x] Safe read-only dashboard renderer [`web/stats.js`](web/stats.js) (zero `innerHTML`, `credentials: 'omit'`, capped tails `<= 10.0%` / `>= 90.0%`).
- [x] Reference specification and live PostgreSQL 16.2 verification suite in [`tools/test_suppression.py`](tools/test_suppression.py), [`tools/verify_build.py`](tools/verify_build.py), and [`tools/run_pg_tests.py`](tools/run_pg_tests.py).
- [x] Shared-city content editor privilege fix and audited CMS RPCs in [`db/005_content_editor_security_fix.sql`](db/005_content_editor_security_fix.sql) and [`db/009_content_editor.sql`](db/009_content_editor.sql).
- [ ] Verify hosted Supabase deployment (`pg_cron` jobs uncommented, `NL_PROXY_SECRET` set) and run a human people-check before adding any new report dimension.
