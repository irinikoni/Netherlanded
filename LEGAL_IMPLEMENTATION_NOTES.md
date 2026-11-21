# Legal implementation notes (v2.1 consolidated)

This package implements a technical and legal direction. It is not legal clearance.

- **Two-tier split & client batching (`netherlanded-app.html`):**
  - **Tier 1 (`nl-basic`, default-on with immediate objection):** Strictly broad category level (`admin`, `housing`, `money`, `health`, `work`, `social`, `wellbeing`) plus `institution`, `intake` (`YYYY-sep`/`YYYY-feb`), `app_version`, and at most one `technical_error` per app version. **No `step_id`**. Relies on *Telecommunicatiewet* Art. 11.7a(3)(b) and GDPR Art. 6(1)(f), backed by [`LEGITIMATE_INTEREST_ASSESSMENT.md`](LEGITIMATE_INTEREST_ASSESSMENT.md) and subject to THUAS privacy-officer confirmation (fallback: keep Tier 1 Netherlanded-only).
  - **Tier 2 (`nl-stats`, strict opt-in consent):** Records `institution`, `region` (EU/EEA or not), `intake`, `step`, and `event` (`joined`, `arrived`, `step_applies`, `step_opened`, `step_completed`, `deadline_missed`, `scam_checked` + `high_risk`). Step timing (`on_time`) and free-text deadline labels are never sent or stored.
  - Both tiers queue entries locally with local-only queue IDs (never sent over HTTP), shuffle and flush weekly via `navigator.locks` with `credentials: 'omit'`, `referrerPolicy: 'no-referrer'`, and a 10s timeout.

- **Server-side disclosure control & retention (`db/001_schema.sql`–`db/005_content_editor_security_fix.sql`):**
  - Separate `nl.raw_t1` and `nl.raw_t2` stores with hard rejection of any identity fields (`22023`).
  - Hourly fold (`nl.accumulate()`), 6-rule suppression (`nl.build_stage()`: floor ≥ 15, round-to-5, `< 5`pp delta, 2-release sticky, 2D complementary suppression, over-suppression sweep), and transactional pre-publish safety audit (`nl.assert_release_safe()`).
  - Enforced retention (`db/004_retention.sql`): raw rows purged 1 hour after fold (48-hour hard ceiling), staging 90 days, published snapshots 3 years, unmapped dictionary 400 days.
  - Shared-city content editor privilege fix (`db/005_content_editor_security_fix.sql`).

- **Required before production (open blockers):**
  1. Settle and name the GDPR controller (`DISCLOSURE_CONTROL.md` §8 vs. `LEGAL_DELTA.md` §1) and fill `[group name]` / `[contact e-mail]` placeholders in `TERMS_AND_PRIVACY.md` (and rebuild `netherlanded-app.html` `<script id="legal">`).
  2. Complete the DPIA (`LEGAL_DELTA.md` #7), Art. 30 records, signed LIA, and privacy-officer sign-off on Tier 1.
  3. Sign Art. 28 DPAs (Supabase EU region, etc.) and university agreements (use restriction banning individual decisions and re-identification).
  4. Execute `db/001`–`005` on live PostgreSQL 15+, add per-institution RLS/scoping to `nl.release_json()`, configure edge IP stripping (≤ 24h logs) and edge rate limiting, and publish the separate staff privacy notice.
