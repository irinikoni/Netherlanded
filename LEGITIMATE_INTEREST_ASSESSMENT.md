# Legitimate interest assessment: limited service statistics (Tier 1 — Path B Multi-Tenant Controller Model)

*Draft, updated 22 November 2026 (v2.1 Path B hardening) for Privacy Policy version 2.1. Written for each contracting university controller to review and sign under its SURF Model DPA. It is not legal advice and has not been reviewed by a lawyer or a privacy officer.*

**Scope.** This assessment covers **Tier 1, limited service statistics** for **contracted participating universities** (`nl-partner-institutions`): counted after the student has seen a notice of its own, with a toggle and "Object to limited statistics" button there and a switch in Profile. **Tier 2**, the additional statistics for universities, is opt-in and rests on consent (Art. 6(1)(a)); it is not covered here.

**Purpose & Path B Governance.** Each **contracted university is the independent first-party GDPR controller** for its incoming students under a signed **SURF Model Data Processing Agreement (Art. 28 GDPR)**, and Netherlanded operates strictly as its multi-tenant **Data Processor**. The university uses limited service statistics to measure onboarding quality and technical reliability, and receives disclosure-controlled aggregate reports for its own students. Non-partner universities are excluded from institution-scoped Tier 1 metrics. The statistics are never used to monitor individual students, make decisions about them, or identify students who need intervention.

**Processing assessed.** Once per student and step, a "+1" holding only: app or content version, school (rolled up to parent institution, never campus), intake semester (for example `2026-sep`), and either a one-time `cohort_joined` marker or a broad step category (`admin`, `housing`, `money`, `health`, `work`, `social`, `wellbeing`) with `step_applies` / `step_completed`; plus at most one `technical_error` count per app version. **No `step_id` is ever included in Tier 1.** Counts are queued on the phone and sent in **weekly shuffled batches** through our EU reverse proxy, which **strips all IP and User-Agent headers in RAM (0 seconds IP disk storage)** and enforces `X-NL-Proxy-Secret` so direct Supabase bypass is rejected (`403`). Raw Tier 1 events (`nl.raw_t1`) are folded hourly into aggregates and deleted within 1 hour of folding (**24-hour hard ceiling**, `db/004_retention.sql`). Universities receive only their own institution's approved snapshots (`db/008_scoped_insights.sql` + `db/003_release.sql`): every result based on at least 15 students, counts rounded to multiples of 5, extreme tails (`<= 10.0%` / `>= 90.0%`) redacted (`num`/`rate`/`band` nulled), `< 5`pp delta suppression, 2-release sticky suppression, 2D complementary suppression, and pre-publish audit (`nl.assert_release_safe()`).

**Not included:** account, device, installation or session IDs; IP address on disk (`0` seconds); name, e-mail or student number; EU/EEA status or nationality; exact dates or timestamps; step ids, opening histories or page sequences; notes or form contents; scam-check answers; missed deadlines; anything linking counts over time or across devices.

**Legal basis claimed:** GDPR Article 6(1)(f) on behalf of each contracting university controller, alongside the Dutch first-party analytics exception in *Telecommunicatiewet* art. 11.7a(3)(b) (supported by immediate edge IP stripping, 24h raw purge, partner-only gating, and strict category granularity).

**Personal data involved:** Transient IP address during TLS termination at the edge proxy (rate-limited in RAM and stripped before upstream forwarding — **0 seconds stored on disk**; technical logs are IP-free and rotated ≤ 24h), and raw Tier 1 counters prior to hourly folding and ≤ 24h deletion. Approved snapshots meet Recital 26 anonymity thresholds.

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
| Could the IP address be avoided? | Handled at the edge proxy: `edge/security-headers.conf` enforces in-RAM rate limiting (`30r/m`), strips all client IP and User-Agent headers in RAM (0 seconds on disk), enforces `X-NL-Proxy-Secret`, and rotates IP-free logs within 24 hours. |

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
| The IP address is linked to counts | Negligible | Stripped in RAM at edge proxy (0s stored on disk), `X-NL-Proxy-Secret` blocks bypass, IP-free logs ≤ 24h |
| Reports are used to target students for intervention | Low | Purpose limitation in the notice, policy and university agreement; no group dimensions that would allow it |
| Tier 1 grows into university-driven analytics | Medium | Metrics fixed in the pilot specification; new metrics go to Tier 2 unless clearly low-impact; university cannot define fields (otherwise it may become a joint controller) |

### 3.5 Vulnerability and power imbalance
- New international students depend on their university, and some are 16 or 17. This weighs **against** the processing. It is countered by the absence of identifiers, the disclosure controls, the use restriction, and an objection that costs the student nothing.

### 3.6 Safeguards
- Notice before counting; objection on the notice and in Profile; objecting stops counting and deletes the counts on the phone.
- Client-side weekly shuffled batching (`credentials: 'omit'`, `referrerPolicy: 'no-referrer'`) to prevent network-timing correlation.
- Separate Tier 1 (`nl.raw_t1`) and Tier 2 (`nl.raw_t2`) stores, hard identity-field rejection (`nl.reject_identity()`), hourly folding, and enforced deletion (`nl.purge_raw()`, 1h after fold; **24-hour hard ceiling** for `nl.raw_t1`, 48h for `nl.raw_t2`), monitored by `nl.health()`.
- 6-rule SQL disclosure-control pipeline (`db/003_release.sql` + `db/008_scoped_insights.sql` + `nl.assert_release_safe()`): ≥ 15 floor, rounding to multiples of 5, `< 5`pp delta suppression, 2-release sticky suppression, 2D complementary suppression, tail redaction (`<= 10.0%` / `>= 90.0%` nulls `num`/`rate`/`band`), and withheld bucket reporting.
- Multi-tenant Path B controller governance (`DISCLOSURE_CONTROL.md` §8): each contracted university acts as independent GDPR controller under a SURF Model DPA (`nl-partner-institutions` gating), receiving only its own institution's snapshots.
- Concrete retention periods (`db/004_retention.sql`): Tier 1 raw events ≤ 24h, Tier 2 raw events ≤ 48h, staging cells 90 days, published snapshots 3 years (1,095 days), unmapped dictionary 400 days, gateway technical logs IP-stripped in RAM (0s IP storage) and rotated ≤ 24h.

**Result:** with immediate IP stripping, 24-hour `raw_t1` deletion, and Path B multi-tenant controller isolation, students' interests do not override the contracting university's legitimate interests. Adding dimensions or step-level detail stays restricted to opt-in Tier 2.

---

## 4. Conclusion

Article 6(1)(f) is an appropriate basis for Tier 1 under **Path B**, alongside the first-party analytics exception in *Telecommunicatiewet* art. 11.7a(3)(b).

**Before launch:**
- [ ] Partner university DPO confirms Path B Tier 1 setup (with 0s IP disk storage, ≤ 24h `raw_t1` purge, and `nl-partner-institutions` gating).
- [ ] Complete the formal DPIA before the pilot (`LEGAL_DELTA.md` #7).
- [ ] Execute SURF Model Art. 28 DPA with each participating university (predefined reports, ban on individual decisions/re-identification, Recital 26 benchmark authorization) and EU hosting DPAs.
- [ ] Verify `pg_cron` jobs and `NL_PROXY_SECRET` in hosted production deployment (`db/004_retention.sql`, `edge/*`).
- [ ] The university controller reviews and signs this assessment annually or upon schema changes.

Signed: ______________________ (controller)   Date: ____________
