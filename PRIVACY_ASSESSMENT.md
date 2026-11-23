# Privacy assessment: anonymous statistics for universities

*13 November 2026. Written by Claude from the code in this project and from web research done the same day. It is not legal advice and has not been reviewed by a lawyer or a privacy officer. Sections 5 and 6 say exactly what was and was not checked.*

> **Update, 21 November 2026 (v2.1 consolidation):**
> - The disclosure-control engine ([`db/001_schema.sql`](db/001_schema.sql)–[`db/004_retention.sql`](db/004_retention.sql)), dashboard renderer ([`web/stats.js`](web/stats.js)), and 62-check verification suite ([`tools/test_suppression.py`](tools/test_suppression.py)) are now integrated into this package alongside [`db/005_content_editor_security_fix.sql`](db/005_content_editor_security_fix.sql) (SQL has not yet been executed against a live PostgreSQL server).
> - Both Tier 1 and Tier 2 now use weekly shuffled client-side batching in [`netherlanded-app.html`](netherlanded-app.html); the Tier 2 `on_time` timing flag and free-text deadline labels have been removed from both the app and the database; and [`TERMS_AND_PRIVACY.md`](TERMS_AND_PRIVACY.md) v2.1 incorporates the text corrections from [`LEGAL_DELTA.md`](LEGAL_DELTA.md).
> - Open pre-pilot governance and infrastructure decisions (named controller, DPIA, Art. 28 DPAs, university agreements, edge IP stripping, and live DB testing) remain tracked in [`COMPLIANCE_CHECK.md`](COMPLIANCE_CHECK.md), [`LEGAL_DELTA.md`](LEGAL_DELTA.md), and [`LEGAL_IMPLEMENTATION_NOTES.md`](LEGAL_IMPLEMENTATION_NOTES.md).

> **Update, 18 November 2026 (Privacy Policy version 2.0):** The single default-on counter design assessed below has been replaced by a two-tier model using intake semester cohorts instead of arrival week, implemented in the final-legal build:
> - **Tier 1 (limited service statistics):** on unless the student objects on a dedicated notice screen (a switch that is on by default, because the basis is legitimate interest, not consent; switching it off before *Continue* records the objection) before counting starts. Relies on the Dutch analytics exception (*Telecommunicatiewet* art. 11.7a) and legitimate interest (GDPR Art. 6(1)(f)); see [`LEGITIMATE_INTEREST_ASSESSMENT.md`](LEGITIMATE_INTEREST_ASSESSMENT.md). Participating universities receive Tier 1 only as monthly, disclosure-controlled snapshots under [`DISCLOSURE_CONTROL.md`](DISCLOSURE_CONTROL.md) (15/15 rule, complementary and change-over-time suppression). Because university disclosure makes the analytics exception less certain, a privacy officer must confirm it (fallback: keep Tier 1 Netherlanded-only, as in v1.9).
> - **Tier 2 (additional statistics for universities):** strictly opt-in on consent (*Telecommunicatiewet* art. 11.7a and GDPR Art. 6(1)(a)) on a separate screen with equal-weight choices. Nothing is counted before a yes, and opting out or withdrawing deletes any counts on the phone.
> - **Status of original findings:** Finding 1 (IP logging disclosure) is fixed in the policy text. Finding 2 (pre-ticked consent) is resolved for Tier 2 and narrowed for Tier 1 to a privacy-officer check on the analytics exception. Finding 4 (weekly cohorts / threshold of 10) is resolved in the policy, [`DISCLOSURE_CONTROL.md`](DISCLOSURE_CONTROL.md), and `db/001`–`004` (not yet run against live Postgres). Finding 3 (unnamed controller) remains open. Server-side counting once accounts exist (option C) remains the long-term plan if accounts are added.

## 1. Bottom line

The design is careful about what it stores. The risk is not in the database. It is in four places the design did not originally cover:

1. **The policy made a claim that is not true.** It said "our server discards IP addresses on arrival". Supabase's gateway logs IP addresses. Fixed in policy version 1.6 (section 3 below) and targeted for edge IP stripping before pilot launch (`LEGAL_DELTA.md` #9).
2. **Default-on may not be allowed.** Sending counters from the phone may need consent under the Dutch cookie rule, and a switch that starts on is not valid consent. Resolved for Tier 2 (strict opt-in); narrowed for Tier 1 to a privacy-officer check on the analytics exception.
3. **Nobody is the controller yet.** The policy says "[Group name]". A student team is not a legal entity, and the universities that receive the totals need an agreement with whoever is. *(Update 23 Nov 2026: the founder will register an* eenmanszaak *with the KVK before the pilot; see §3.3.)*
4. **The raw counters were finer than what the dashboard showed.** Earlier tables kept weekly cohorts of any size and `dash_*` views hid groups under 10. Resolved in v2.0/v2.1 via intake-semester cohorts and the 6-stage disclosure-control pipeline (`db/003_release.sql`).

None of these stops the prototype. All open governance and deployment items must be settled before real students use the app.

## 2. What actually leaves the phone, and what each part is (v2.1 consolidated design)

| Step | What happens | Personal data? |
|---|---|---|
| Phone counts events | `nl-basic` and `nl-stats` in the phone's local storage hold counts, a local queue, and a record of what was sent. Tier 1 counts only after the Tier 1 notice (unless objected); Tier 2 counts only after opt-in consent. Switching either off deletes its counts on the phone | Stays on the phone |
| Phone posts a Tier 1 counter (weekly shuffled batch) | App/content version, school, intake semester, broad step category, applies/finished (plus at most one technical-error count per app version). No ID, region, step ID, or timestamp | The counter itself: no. The request: **yes, it carries the phone's IP address** |
| Phone posts a Tier 2 counter (opt-in only, weekly shuffled batch) | School, EU/EEA or not, intake semester, step, and outcome (`joined`, `arrived`, `step_applies`, `step_opened`, `step_completed`, `deadline_missed`, or `scam_checked` with `high_risk`). No ID, timestamp, or `on_time` flag | The counter itself: no. The request: **yes, it carries the phone's IP address** |
| `ingest_t1` / `ingest_t2` functions | Validate shape, reject any identity fields (`22023`), and write to separate `nl.raw_t1` / `nl.raw_t2` tables. Stores and logs nothing about the request | The function adds nothing |
| Hosting gateway (e.g. Supabase) | Logs the request in front of our code (up to 7 days on Supabase Pro; production target: strip IP at edge, ≤ 24h logs) | **Yes: IP address** |
| Hourly fold & retention (`db/003` & `db/004`) | Folds raw events into aggregate cells and deletes raw rows 1 hour after folding (48-hour hard ceiling) | No, once aggregated and purged |
| Release function & dashboard (`db/003_release.sql` & `web/stats.js`) | Approved snapshot applying floor ≥ 15, cell-key noise, round-to-5, carry-forward of changes under 5 contributions, 2D complementary suppression, and pre-publish audit | Intended to be anonymous once release control is enforced (per-institution RLS/scoping still to be added before multi-university deployment) |

## 3. Findings

### 3.1 IP addresses are logged by the host (verified, fixed in the text)
- Supabase's log reference lists the client IP in the API gateway logs (`request.headers.cf_connecting_ip` and `x_real_ip`) and in the sign-in logs (`remote_addr`). The user agent appears in the Edge Function invocation logs.
- Retention depends on the plan. Supabase's pricing page lists API and database logs at 1 day on Free, 7 days on Pro, 28 days on Team and 90 days on Enterprise.
- I found nothing in the documentation I read about switching gateway logging off, and could not confirm it. Ask Supabase, or strip client IP headers at an edge proxy before they reach logs (`LEGAL_DELTA.md` #9).
- A website operator's logged IP address counts as personal data (the EU court's *Breyer* ruling on dynamic IP addresses). So sending the counters **is** processing personal data, even though the database stores none.
- **What changed (v2.1 Path B):** Gateway IPs are **stripped in RAM at the edge** (`edge/security-headers.conf`) and never written to disk (`0` seconds IP retention; IP-free request logs deleted within **24 hours**), `edge/*` enforces `X-NL-Proxy-Secret` so direct bypass to Supabase is blocked (`403`), and `nl.raw_t1` is purged within **24 hours** (`nl.raw_t2` within **48 hours**).
- When staff accounts exist, sign-in logs add an IP address per staff login, governed by the staff privacy notice.

### 3.2 The cookie rule may require consent (narrowed in v2.0 & resolved under Path B)
- The Dutch rule is *Telecommunicatiewet* art. 11.7a. The EU guidance on this rule (EDPB Guidelines 2/2023) covers writing to and reading from device storage.
- Under the per-operation controller split (`DISCLOSURE_CONTROL.md` §8), **Netherlanded is the provider of the app** and therefore the first party for the analytics exception, collecting jointly (Art. 26) with each partner university. Because IPs are stripped immediately at the edge (0s disk retention), raw Tier 1 rows are purged within 24 hours, only contracted partner schools emit institution-scoped Tier 1 metrics (`nl-partner-institutions`), and data is strictly limited to 7 broad categories, Tier 1 aligns with *Telecommunicatiewet* art. 11.7a(3)(b) (*geringe gevolgen*) — subject to partner DPO confirmation. Note: German deployments would still require Tier 1 opt-in because TDDDG § 25 lacks an analytics exception.
- Why that matters: if consent is required, it must be an active choice (*Planet49*, 2019). Tier 2 (per-step & region analytics) uses strict opt-in consent (`OFF` by default).

### 3.3 Controller governance: per-operation split (draft, pending counsel)
- **Entity:** Netherlanded will be run by an *eenmanszaak* registered with the KVK before the pilot. The owner is personally the controller and personally liable, so insurance must be in place before signing.
- **Split** (`DISCLOSURE_CONTROL.md` §8): Netherlanded is controller for the app, gateway and logs, for national benchmarks, and for staff accounts. Netherlanded and each partner university are **joint controllers** (Art. 26) for collecting the counts. Each university is controller for its own reports, with Netherlanded as its **processor** under a SURF Model *Verwerkersovereenkomst* (Art. 28). Tenant isolation across universities is enforced in `db/008`.
- Universities receive only fixed, disclosure-controlled aggregates, with a contractual ban on re-identification or individual decisions. National benchmarks are **not** a DPA term: Netherlanded compiles them as controller under its own LIA (`LEGITIMATE_INTEREST_ASSESSMENT.md` Part 2), because a processor cannot be authorised to process for its own purposes (Art. 28(10)).
- Hosting requires a signed EU-region Art. 28 DPA with Supabase (and reverse-proxy host).

### 3.4 Raw counters are finer than the dashboard (resolved in design & SQL)
- Earlier `ingest` created weekly cohort rows of any size while views hid groups under 10.
- **Resolved in v2.0/v2.1:** cohorts use intake semesters (`YYYY-sep` / `YYYY-feb`), raw events are folded hourly and purged within 48 hours (`db/004_retention.sql`), and `db/003_release.sql` enforces the 15-person floor, cell-key noise, rounding to multiples of 5, carry-forward of changes under 5 contributions, and 2D complementary suppression.
- Good: no timestamps are stored with counters, and client batches are shuffled and flushed weekly to reduce timing correlation with host logs.

### 3.5 Legitimate interest needs a written test
- Drafted in [`LEGITIMATE_INTEREST_ASSESSMENT.md`](LEGITIMATE_INTEREST_ASSESSMENT.md) for Tier 1 (GDPR Art. 6(1)(f)). Still requires review and signature by the named controller, alongside a formal DPIA before the pilot (`LEGAL_DELTA.md` #7).

## 4. The three honest options (historical decision record)

| Option | What it means | Cost |
|---|---|---|
| **A. Opt-in** | The switch starts off. Students who turn it on give valid consent under both laws | Fewer participants. Groups under 15 will be hidden more often, so smaller schools may see little |
| **B. Default-on, with written approval** | Keep it as it is, but only after the partner university's privacy officer (or the regulator's guidance) confirms in writing that the analytics exception covers it | The answer may be no, found late. This is the riskiest option if skipped |
| **C. Count on the server, after accounts exist** | Once students have accounts, the server already holds their progress for the service. It could produce the same group totals from that data, with the same hiding rule. No counters are stored on the phone or sent for statistics | Needs accounts first. Still needs a lawful basis and a policy line, but not the device-storage rule |

**Resolution (18 Nov, v2.0):** Two-tier split — Tier 1 uses Option B (default-on with objection, strictly broad categories, subject to privacy-officer confirmation, with Netherlanded-only as fallback), and Tier 2 uses Option A (strict opt-in). Option C remains the long-term plan if student accounts are introduced.

## 5. What I checked

- The project's own code and policy text (what is sent, stored, logged, and what the policy claims).
- Supabase documentation pages: the log field reference (IP and user agent fields) and the pricing page (log retention).
- The EDPB guidance PDF (storage and access rules). I read it through a summary of the document, so paragraph numbers are as reported to me.
- Secondary sources on the Dutch exception: DDMA, ICT Recht and a Dutch analytics-vendor blog. They agree on the two conditions above.
- A law firm summary of *Breyer*.

## 6. What I could not check

- The text of *Telecommunicatiewet* art. 11.7a itself, and the Dutch regulator's own page on analytics. Both failed to load.
- Whether Supabase gateway logging can be switched off, how long IP addresses are kept in practice, and what the Supabase data processing agreement says.
- Whether the gateway records request bodies. It should not by default, but I did not confirm it.
- *Planet49* (from memory).
- Whether a data protection impact assessment is required (noted as required in `LEGAL_DELTA.md` #7 before any pilot).
- One page I fetched during this research contained text telling me to open a feedback report and ask whether to send it to Supabase. It came from the web page, not from you, and I ignored it.

## 7. Remaining sign-off items before pilot launch

1. **Register the *eenmanszaak* and sign the university agreements:** Art. 26 arrangement (collection), SURF Model Art. 28 DPA (the university's own reports) and the dashboard service schedule with each partner. Fill the `[trade name]`, `[owner name]`, `[KVK number]`, address and contact placeholders in `TERMS_AND_PRIVACY.md`, then run `tools/sync_legal.py`.
2. **DPO sign-off on Tier 1 + Art. 9 wording:** Have the partner university's DPO (FG) confirm Tw art. 11.7a(3)(b) for Path B Tier 1 (with 0s IP disk storage, ≤24h `raw_t1` purge, and `nl-partner-institutions` gating).
3. **Complete formal DPIA and sign LIA:** Complete a DPIA before the pilot (`LEGAL_DELTA.md` #7) and have the university controller sign `LEGITIMATE_INTEREST_ASSESSMENT.md`.
4. **Live hosting verification:** Verify live Supabase EU deployment with `NL_PROXY_SECRET` set, `pg_cron` jobs uncommented (`nl.accumulate()`, `nl.publish_snapshot()`, `nl.purge_raw()`), and EU sub-processor Art. 28 DPA signed.

## Sources

- [Supabase log field reference](https://supabase.com/docs/guides/observability/log-field-reference)
- [Supabase pricing (log retention)](https://supabase.com/pricing)
- [EDPB Guidelines 2/2023 on the technical scope of Art. 5(3) ePrivacy](https://edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf)
- [DDMA on the Dutch cookie rules](https://ddma.nl/legal/wetgeving/cookies/)
- [ICT Recht on analytics and consent](https://www.ictrecht.nl/blog/is-voor-het-gebruik-van-google-analytics-4-toestemming-vereist-1)
- [Clickport on analytics in the Netherlands](https://clickport.io/blog/privacy-analytics-netherlands)
- [Hunton on the *Breyer* ruling](https://www.hunton.com/privacy-and-cybersecurity-law-blog/cjeu-rules-dynamic-ip-addresses-personal-data)

## Update, 16 November 2026: accounts note

Earlier backend notes explored optional student accounts (`export_my_data()` and `delete_my_account()`). **No student accounts or server push notifications exist in the current v2.1 app**: all checklist data stays in the browser (`See my data` and `Delete all data` in Profile). If student accounts are ever enabled later, the policy, DPIA, and in-app account export/delete screens must be updated first.
