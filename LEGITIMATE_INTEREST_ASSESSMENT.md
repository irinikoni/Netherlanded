# Legitimate interest assessment: limited service statistics (Tier 1)

*Draft, updated 21 November 2026 (v2.1 consolidation) for Privacy Policy version 2.1. Written by Claude for the controller to review and sign. It is not legal advice and has not been reviewed by a lawyer or a privacy officer.*

**Scope.** This assessment covers **Tier 1, limited service statistics**: counted after the student has seen a notice of its own, with an "Object to limited statistics" button there and a switch in Profile. **Tier 2**, the additional statistics for universities, is opt-in and rests on consent (Art. 6(1)(a)); it is not covered here.

**Purpose, as stated to students.** Netherlanded processes limited service statistics to find technical problems and guidance that may be unclear or not working, and to give participating institutions disclosure-controlled aggregate information that helps them improve general onboarding guidance. The statistics are not used to monitor individual students, to make decisions about them, or to identify students who need intervention.

**Processing assessed.** Once per student and step, a "+1" holding only: app or content version, school, intake semester (for example `2026-sep`), a broad step category (`admin`, `housing`, `money`, `health`, `work`, `social`, `wellbeing`), and whether a step in that category applies or was finished; plus at most one `technical_error` count per app version. **No `step_id` is ever included in Tier 1.** Counts are queued on the phone and sent in **weekly shuffled batches**; raw events are folded hourly into aggregates and deleted within 1 hour of folding (48-hour hard ceiling, `db/004_retention.sql`). Universities receive only approved snapshots under `DISCLOSURE_CONTROL.md` and `db/003_release.sql`: every result based on at least 15 students, counts floored to multiples of 5, `< 5`pp delta suppression, 2-release sticky suppression, 2D complementary suppression, and pre-publish audit (`nl.assert_release_safe()`), with no filters or system access.

**Not included:** account, device, installation or session IDs; IP address in the payload; name, e-mail or student number; EU/EEA status or nationality; exact dates or timestamps; step ids, opening histories or page sequences; notes or form contents; scam-check answers; missed deadlines; anything linking counts over time or across devices.

**Legal basis claimed:** GDPR Article 6(1)(f), alongside the Dutch analytics exception in Telecommunicatiewet art. 11.7a for storing and sending counts on the phone. University disclosure raises the privacy impact and makes that exception **less certain**; a privacy officer should confirm it.

**Personal data involved:** the IP address reaching the hosting provider with each request (logs kept up to 7 days), and the counts while they are being aggregated. The approved snapshots are intended to be anonymous.

---

## 1. Purpose test: is there a legitimate interest?

| Interest | Whose | Lawful, specific, current? |
|---|---|---|
| Finding technical problems and guidance that is unclear or not working | Netherlanded, and students who rely on its legal and financial deadlines | Yes. Rules change every year (FACT_CHECK.md); without a signal the team cannot see broken or ignored content |
| Improving general onboarding guidance for international students | The participating universities, and their future students | Yes. The research behind the app found information provision for international students "not yet in order" (ARCHITECTURE.md, appendix) |

Both are stated to students before counting starts. **Result:** legitimate interests exist.

## 2. Necessity test

| Question | Answer |
|---|---|
| Does the processing help? | Yes. Category-level applicability and completion per school and intake show where guidance works and where students stall; the error count shows broken releases |
| Less intrusive alternatives? | Surveys: sparse, late, memory-based. Server-side counting from accounts (option C): avoids device storage, but no accounts exist yet; it remains the long-term plan. Consent for everything: possible, but leaves both purposes with too little data for most schools; the sensitive metrics are kept in consent-based Tier 2 instead |
| Data minimised? | Yes. Five fields; no identifiers, dates, region or step ids; aggregated on arrival; university output further reduced by disclosure control |
| Could the IP address be avoided? | No. Exposure is limited to the provider's logs, up to 7 days, used only to run and secure the service |

**Result:** necessary and kept to the minimum.

## 3. Balancing test

### 3.1 Nature of the data
- Not sensitive. No special categories (Art. 9). "Health" means a step about insurance or a GP applies or was done, not anything about a student's health.

### 3.2 Reasonable expectations
- A screen of its own, before anything is counted, says what is counted, that universities may get aggregate statistics, the 15-student rule, the ban on individual decisions, and how to object. Objecting is one button, equal to Continue.
- Service statistics are an expected part of an app; university reporting is less expected, which is why it is stated up front and not only in the policy.

### 3.3 The universities' background knowledge
Universities already hold enrolment and support records: who is in an intake, who contacted the International Office, who lives where, who has immigration requirements. That raises the risk of inference from small groups. It is countered by: no region, campus, municipality or deadline dimensions in Tier 1; the 15/15 rule applied to the final combination of dimensions; complementary and change-over-time suppression; no filters or custom cuts; and a contractual ban on re-identification and individual use.

### 3.4 Risks
| Risk | Likelihood | Mitigation |
|---|---|---|
| A university infers something about a student from a report | Low | `DISCLOSURE_CONTROL.md` sections 3–7 |
| A student is singled out by comparing reports over time | Low | Monthly snapshots at most; updates resting on fewer than 5 new contributions suppressed |
| The IP address is linked to counts | Low | Not stored with counts, no timestamps, logs 7 days and used for nothing else |
| Reports are used to target students for intervention | Low | Purpose limitation in the notice, policy and university agreement; no group dimensions that would allow it |
| Tier 1 grows into university-driven analytics | Medium | Metrics fixed in the pilot specification; new metrics go to Tier 2 unless clearly low-impact; university cannot define fields (otherwise it may become a joint controller) |

### 3.5 Vulnerability and power imbalance
- New international students depend on their university, and some are 16 or 17. This weighs **against** the processing. It is countered by the absence of identifiers, the disclosure controls, the use restriction, and an objection that costs the student nothing.

### 3.6 Safeguards
- Notice before counting; objection on the notice and in Profile; objecting stops counting and deletes the counts on the phone.
- Client-side weekly shuffled batching (`credentials: 'omit'`, `referrerPolicy: 'no-referrer'`) to prevent network-timing correlation.
- Separate Tier 1 (`nl.raw_t1`) and Tier 2 (`nl.raw_t2`) stores, hard identity-field rejection (`nl.reject_identity()`), hourly folding, and enforced deletion (`nl.purge_raw()`, 1h after fold / 48h hard ceiling).
- 6-rule SQL disclosure-control pipeline (`db/003_release.sql` + `nl.assert_release_safe()`): ≥ 15 floor, rounding to multiples of 5, `< 5`pp delta suppression, 2-release sticky suppression, 2D complementary suppression, and withheld bucket reporting.
- Controller governance locked before launch (`DISCLOSURE_CONTROL.md` §8 / `LEGAL_DELTA.md` §1); universities receive disclosure-controlled snapshots only.
- Concrete retention periods (`db/004_retention.sql`): raw events ≤ 48h, staging cells 90 days, published snapshots 3 years (1,095 days), unmapped dictionary 400 days, gateway logs up to 7 days on Supabase Pro (target: edge IP-stripped and ≤ 24h).

**Result:** with these safeguards, students' interests do not override the two legitimate interests. The balance depends on Tier 1 staying strictly at broad category level (no `step_id`) and the release controls working. Adding dimensions, recipients or step-level detail means redoing this assessment, and probably moving that metric to Tier 2.

---

## 4. Conclusion

Article 6(1)(f) is an appropriate basis for Tier 1, alongside the analytics exception in *Telecommunicatiewet* art. 11.7a, provided the university receives only disclosure-controlled output.

**Before launch:**
- [ ] A privacy officer confirms that Tier 1, with university reports, still fits the analytics exception (fallback: keep Tier 1 Netherlanded-only, v1.9).
- [ ] Complete the Data Protection Impact Assessment (DPIA) before the pilot (`LEGAL_DELTA.md` #7).
- [ ] Test `db/001`–`db/005` on live PostgreSQL 15+, add per-institution tenant scoping/RLS to `nl.release_json()`, and enable edge IP stripping / rate limiting.
- [ ] Agreement with each university: predefined reports, contractual ban on individual decisions and re-identification (`LEGAL_DELTA.md` #4), and clear controller/processor terms.
- [ ] The controller reviews and signs this assessment.
- [ ] Review if the counts, recipients, age limit or hosting provider change, and at least once a year.

Signed: ______________________ (controller)   Date: ____________
