# Compliance check: Terms of Service and Privacy Policy

*18 November 2026. Written by Claude. It compares the Terms and Privacy Policy with what the code and database actually do. It is not legal advice and has not been reviewed by a lawyer or a privacy officer.*

> **Update, version 2.1 consolidation (21 November 2026):** `TERMS_AND_PRIVACY.md` v2.1, `netherlanded-app.html`, `db/001`–`005`, `web/stats.js`, and `tools/test_suppression.py` resolve the technical/text gaps below: concrete retention periods (48h raw ceiling, 90d staging, 3y snapshots), Art. 13(2)(e) & (f) notices, accurate `health`-category wording (fixing `LEGAL_DELTA.md` #5), 30-day change notice, university content attribution, removal of `on_time` flags and obsolete student-account/push claims, weekly shuffled client batching, and the 6-rule SQL disclosure-control engine (passing 62/62 Python/static checks; live Postgres run and per-institution tenant scoping remain open). The governance blockers (#1 controller, #3/#4/#5 DPAs & transfers, #13 DPIA & Art. 30 records, #14 staff notice, #15 university agreements, and edge IP stripping) remain open before pilot launch.
>
> **Update, version 2.0 (same day):** Tier 1 may now reach universities, but only as approved snapshots under `DISCLOSURE_CONTROL.md` (15/15 rule, complementary and change suppression, monthly, no filters or access). A notice screen of its own, with an equal "Object" button, comes before any Tier 1 counting. The assessment now weighs both Netherlanded's and the universities' interests. University disclosure makes the analytics exception less certain.
>
> **Update, version 1.9: two tiers.** Tier 1, basic app statistics, is on by default under the Dutch analytics exception (Telecommunicatiewet 11.7a) and GDPR Art. 6(1)(f), with an objection switch; it is used only by Netherlanded and never reaches universities. Tier 2, additional statistics for universities, is opt-in on consent (Art. 6(1)(a)). The legitimate interest assessment now covers Tier 1. Whether Tier 1 fits the analytics exception is a judgment, not a certainty: confirm it with a privacy officer.
>
> **Update, version 1.8:** the GDPR legal basis for statistics is now legitimate interest (Art. 6(1)(f)), backed by the written assessment in `LEGITIMATE_INTEREST_ASSESSMENT.md`. The opt-in screen stays, as the permission the Dutch cookie rule (Telecommunicatiewet 11.7a) requires before anything is stored on the phone or sent.
>
> **Update, version 1.7:** this check was written for version 1.6. Version 1.7 resolves items 6 and 7 (statistics are now opt-in on consent, asked separately after the Terms, and nothing is counted before the student says yes), replaces weekly groups with intake-semester groups, and fixes Terms clause 10. These rows are marked **Fixed in 1.7** below. Everything else still applies.

## Summary

- **Prototype demo (browser storage only, nothing sent):** proceed, once the placeholders are filled.
- **Real students, with accounts, reminders or statistics:** **requires further review.** The policy was written for the prototype. The system that now exists collects more than the policy lists, uses providers the policy does not name, and promises in-app buttons that do not exist. There is no written agreement with universities yet.

## Applicable regulations

| Regulation | Relevance | Key requirements |
|---|---|---|
| GDPR / AVG + UAVG | Students' profile, progress, e-mail, IP addresses, push addresses | Lawful basis per purpose, full Art. 13 notice, processor agreements (Art. 28), records of processing (Art. 30), rights handled within one month |
| UAVG art. 5 | Digital consent age in NL is 16 | Terms already set minimum age 16. Aligned |
| Telecommunicatiewet art. 11.7a (cookie rule) | Phone stores counters and sends them | Consent needed for the statistics. **Fixed in 1.7:** opt-in, separate from the Terms, equal Yes and No buttons |
| BW 6:231–6:237 (general terms, consumer black and grey lists) | The Terms are general terms toward consumers | Unfair clauses can be voided; terms must be available to save before agreeing |
| BW 7:50aa ff. (digital content, from EU Directive 2019/770) | A free app paid for with personal data can count as digital content supplied to a consumer | Conformity and update duties; the "as is" clause cannot remove them. The savings sentence in section 8 helps |
| Brussels I bis art. 18–19, Rome I art. 6 | Students from other EU countries | Consumers can sue at home and keep mandatory protection of their home law |

## Requirements

| # | Requirement | Status | Action needed |
|---|---|---|---|
| 1 | Controller named with contact details (Art. 13(1)(a)) | **Drafted** | Per-operation split in `TERMS_AND_PRIVACY.md` §11. Fill in the *eenmanszaak* trade name, owner, KVK number, address and a working e-mail address that will be answered for the life of the app |
| 2 | Every category of data listed | **Not met** (full app) | Missing from section 12 for the full app: e-mail address (sign-in and reminders), country, study city and home municipality, step notes (free text up to 2,000 characters), push addresses per device, queued reminder texts, IP addresses in sign-in logs |
| 3 | Recipients and processors named (Art. 13(1)(e)) | **Not met** | Name them: Supabase (database, sign-in, EU region), Brevo (e-mail), GitHub Pages (serves the app; receives visitors' IP addresses), the browser push services of Google, Apple, Mozilla and Microsoft, and the universities (anonymous totals only) |
| 4 | Transfers outside the EU (Art. 13(1)(f)) | **Unknown** | GitHub and the push services are US companies; Supabase is a US company hosting in the EU. State the transfer basis per provider after checking each provider's DPA |
| 5 | Processor agreements (Art. 28) | **Not met** | Sign or accept the DPAs of Supabase and Brevo before launch. Check GitHub's terms for Pages |
| 6 | Lawful basis per purpose | **Fixed in 1.8** | Statistics: legitimate interest (Art. 6(1)(f)) with a written balancing test, plus device permission under Tw 11.7a through the opt-in screen. Reminders and name/photo on consent; checklist on performance of the service. The assessment still needs the controller's signature |
| 7 | Statistics default | **Fixed in 1.7** | Off until the student says yes. Asked once after the Terms, with Yes, No and Decide later; a second "later" counts as no. Switching off deletes the counts on the phone |
| 8 | Rights can be exercised as described | **Met for local app** | Section 15 now accurately points to *Profile → See my data* (including local telemetry queues), *Delete all data*, and the two statistics switches. Student accounts do not exist in v2.1 (see §12) |
| 9 | Retention stated | **Fixed in 2.1** | Concrete periods now match `db/004_retention.sql`: raw events folded hourly and purged ≤ 48h, staging 90d, snapshots 3 years, unmapped dictionary 400d, aggregates indefinite; gateway logs 7d (target ≤ 24h IP-stripped) |
| 10 | Statutory/contractual requirement and consequences of not providing data (Art. 13(2)(e)) | **Fixed in 2.1** | Added to section 12 of `TERMS_AND_PRIVACY.md` v2.1 |
| 11 | Automated decisions (Art. 13(2)(f)) | **Fixed in 2.1** | Added to section 12 of `TERMS_AND_PRIVACY.md` v2.1 |
| 12 | "We never store health information" is true | **Fixed in 2.1** | Replaced absolute claim in section 12 (`LEGAL_DELTA.md` #5): states accurately that `health` category counts (e.g. insurance/GP steps) are processed and published only in groups ≥ 15, never personal health details |
| 13 | Records of processing (Art. 30) and DPIA screening | **Not met** | One page each |
| 14 | Staff (university editors and dashboard users) informed | **Not met** | Their e-mail, sign-in logs and change log are personal data. They need their own short notice |
| 15 | Agreement with universities | **Drafted (not signed)** | Three parts per `DISCLOSURE_CONTROL.md` §8: Art. 26 arrangement (joint collection), SURF Model DPA (own reports), and the dashboard service schedule (seats, monthly snapshots, export, 3-year history, availability). Plus no re-identification, staff accounts and published content |
| 16 | Terms available to save before agreeing (BW 6:234) | Unknown | Make sure the agreement screen links to a version the student can download or keep |

## Terms of Service: clause review

| Clause | Verdict | Change |
|---|---|---|
| 1 Not an official service | **Fixed in 2.1** | Section 1 now states that content marked as from a university is that university's responsibility |
| 3 Information, not advice | Good | None |
| 4 Minimum age 16 | Good (matches UAVG) | None |
| 8 Liability "as is" | Acceptable with the savings sentence | Exclusions are on the grey list (BW 6:237 f) and the conformity duties of BW 7:50aa ff. still apply |
| 9 Changes | **Fixed in 2.1** | Section 9 & 18 now specify at least 30 days' advance notice for important changes |
| 10 Court | **Fixed in 1.7** | Was a fixed court in The Hague, black-listed under BW 6:236 sub n. Now: the Dutch court competent by law, with home-country protection for EU students |

## Risk areas

| Risk | Severity | Mitigation |
|---|---|---|
| Policy describes a system smaller than the one built | High | Rewrite sections 12, 13 and 16 for the full app before any account is created |
| No controller, no DPAs, no university agreement | High | Decide the controller first; everything else is signed by them |
| Default-on statistics without valid consent | ~~High~~ **Fixed in 1.7** | Opt-in |
| Promised in-app rights buttons missing | Medium | Build export and delete screens with accounts |
| Small groups in raw counters | Low (was Medium) | **Fixed in 1.7** in the app: intake semester instead of arrival week. The server's `ingest()` still needs the matching change |
| Notes field collecting sensitive data | Low | Hint text in the field |

## Recommended next actions

1. **Name the controller** and a real contact address.
2. **Rewrite Part B for the full app** when accounts are added: complete data table, named processors, transfers, retention, the two missing Art. 13 sentences, staff notice.
3. **Sign the DPAs** (Supabase, Brevo) and a data-sharing agreement with each university.
4. **Build export and delete buttons** with accounts.
5. Write the one-page records of processing and the DPIA screening.

## Approvals needed

| Approver | Why | Status |
|---|---|---|
| Controller (to be named) | Signs everything below | Pending |
| THUAS privacy officer (FG) | University data-sharing, DPIA screening | Pending |
| Course supervisor | Whether a student may be controller for a service offered to THUAS students (moot once the *eenmanszaak* is registered; still confirm there is no conflict with student status) | Pending |
| Supabase, Brevo | Data processing agreements | Pending |
