# Legal delta

Corrections owed to the documents already published for this project. Each item is a
statement in an existing document that is wrong, incomplete or now out of date, with
the correction that replaces it.

## 1. There is no named controller

The privacy statement describes obligations without naming who owes them. Under
Article 4(7) GDPR a controller has to be identified. The university is the controller
for this processing, not the app author, and the app author is a processor.

Action: name the university, its address and its data protection officer, and add an
Article 28 processing agreement between the university and the app author.

## 2. Supabase is a processor without a contract

The insights database sits on Supabase in an EU region. That is a transfer of personal
data to a processor. No Article 28 agreement is in place.

Action: sign the Supabase data processing addendum, record the region, and add the
processor to the Article 30 record.

## 3. Recipients are not listed

Article 13(1)(e) requires the recipients of personal data to be named. The current text
names nobody.

Action: list the university as recipient of the aggregate statistics, and state that no
other party receives data.

## 4. Universities must not reuse rates for individual decisions

Aggregate completion rates are published to the university. Nothing in the current
documents stops those rates being used in admissions, selection or disciplinary
decisions.

Action: add an explicit contractual restriction that released statistics must not be
used to take a decision about an identified or identifiable person.

## 5. The claim that the app never stores health information is wrong

The journey covers health, money and housing, and the seven categories include health.
Category level counts are stored and, where a group is large enough, published.

Action: replace the absolute claim with an accurate one: the app stores the category of
a step, never its content, and health category counts are published only in groups of
fifteen or more.

## 6. Obsolete account and push notification sections

The documents describe user accounts and push notifications. The app has no student
accounts. Staff may have accounts for the dashboard; students never do.

Action: delete the account and push sections, and describe the staff-only dashboard
access separately.

## 7. No DPIA

The processing is systematic, involves a vulnerable group and includes a special
category. No data protection impact assessment exists.

Action: complete a DPIA before the pilot, covering the suppression thresholds, the
re-identification risk of small cells, and the effect of repeated releases.

## 8. No retention period for published snapshots

Retention was described as a principle, not a period.

Action: state it: raw events have a 48 hour ceiling and are normally removed within an
hour of the fold that captured them; published snapshots are kept for three years;
aggregates are kept indefinitely.

## 9. Gateway logs keep IP addresses

The edge logs the client address for up to seven days, which is longer than the analytics
purpose needs and contradicts the claim that no address is collected.

Action: strip the address at the edge before it is written, and reduce the log retention
to twenty-four hours.

## 10. Corrections already made in the code

These no longer need a text change but are listed so the documents match the build:

- No session identifier, installation identifier or address is stored or accepted. The
  ingest functions reject those fields outright with error 22023.
- Tier 1 and Tier 2 are separate stores and are never joined.
- The step timing flag is not stored, so it cannot be published.
- Withheld cells are reported as a bucket, never as a count.
- The university is not told which individuals are missing from a cohort.

---

## Consolidation status (21 November 2026)

| Item | Status in consolidated v2.1 package | Where addressed / remaining action |
|---|---|---|
| 1. Named controller & Art. 28 agreement | **Open (governance decision)** | Settle controller choice (`DISCLOSURE_CONTROL.md` §8 vs. item 1 above) with THUAS FG and fill `TERMS_AND_PRIVACY.md` §11 |
| 2. Supabase Art. 28 DPA & Art. 30 record | **Open (pre-launch ops)** | Sign Supabase EU DPA and complete Art. 30 record; documented in `TERMS_AND_PRIVACY.md` §13 & `COMPLIANCE_CHECK.md` |
| 3. Recipients listed (Art. 13(1)(e)) | **Partly resolved** | `TERMS_AND_PRIVACY.md` §13 names participating universities (aggregate snapshots only), hosting processor, and states no other party receives data; final entity names still to be filled |
| 4. Contractual ban on individual decisions | **Open (legal agreement)** | Stated in `TERMS_AND_PRIVACY.md` §13 & `DISCLOSURE_CONTROL.md` §7; still requires signed university agreements |
| 5. Accurate `health` category claim | **Resolved in v2.1** | Updated in `TERMS_AND_PRIVACY.md` §12 and embedded app legal text |
| 6. Obsolete account & push sections | **Resolved in v2.1** | Clarified in `TERMS_AND_PRIVACY.md` §12 (no student accounts or server push; staff dashboard accounts covered by separate staff notice) |
| 7. DPIA before pilot | **Open (pre-pilot legal)** | Listed as mandatory pre-launch gate in `LEGITIMATE_INTEREST_ASSESSMENT.md` §4 & `PRIVACY_ASSESSMENT.md` §7 |
| 8. Concrete retention periods | **Resolved in v2.1** | `TERMS_AND_PRIVACY.md` §14 now states 48h ceiling (1h post-fold) for raw events, 90d staging, 3y snapshots, 400d dictionary, indefinite aggregates |
| 9. Gateway edge IP stripping & 24h logs | **Open (pre-launch infra)** | Disclosed honestly in `TERMS_AND_PRIVACY.md` §13 (7d on Supabase Pro; 24h IP-stripped target); must be configured at edge before launch |
| 10. Code invariants (no IDs, separated T1/T2, no `on_time`, bucketed suppression) | **Resolved in v2.1** | Aligned in `netherlanded-app.html` and `db/001`–`004` (verified by `tools/test_suppression.py`, 62/62 pass; live Postgres execution still pending) |
