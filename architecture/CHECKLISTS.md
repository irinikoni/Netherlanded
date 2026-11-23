# Netherlanded: what still needs to be done

*Written 14 November 2026, statistics decisions updated 18 November 2026. Tick a box when it is truly done. Every box is something that is not finished today.*
*Tags: **[blocks launch]** must be done before real students use the app. **[you]** only a person on the team can do it. **[Claude]** can be built or drafted on request.*

**Where things stand:** the app runs as a prototype in the browser with the checklist, deadlines, scam check, city themes and opt-in anonymous statistics. The server code is written and tested on a local PostgreSQL. Nothing is deployed, there are no student accounts, and no outside person has reviewed the security or the legal text.

---

## 1. Decisions only people can make **[blocks launch]** **[you]**

- [ ] **Who is the controller?** Plan so far: one named person. Get a short written message from each group mate saying they hand the project over.
- [ ] Check whether the course or THUAS has rules on who owns the project and on using it outside the course.
- [ ] Decide whether to register a sole proprietorship (eenmanszaak) at the KVK for a legal identity and business address.
- [x] **Default for anonymous statistics:** decided 18 Nov: **opt-in** (A), asked on a separate screen after the Terms. Policy 1.7. Option C (count on the server) to be revisited when accounts exist.
- [x] **Cohort size:** decided 18 Nov: **intake semester** instead of arrival week. Done in both the app and `db/001`–`db/008` (`intake` format `YYYY-sep` / `YYYY-feb`).
- [ ] Choose the contact address to publish in the policy. Do not use a private address unless you want it public.
- [x] Decide how many years anonymous totals are kept: **3 years (`1095` days)** for published snapshots, **48 hours** maximum ceiling for raw events (`db/004_retention.sql`).
- [ ] Decide which universities are the first pilot partners (target viability city: The Hague / THUAS).

## 2. Legal and privacy **[blocks launch]**

- [ ] Fill the placeholders in the policy: group name, contact e-mail, years totals are kept. (The 7-day log retention is filled in for Supabase Pro.)
- [x] Write the one-page legitimate-interest test: drafted 18 Nov (`LEGITIMATE_INTEREST_ASSESSMENT.md`, policy 2.1).
- [x] **Build the Tier 1 endpoint** (`NL_BASIC_URL`): built in `db/001_schema.sql`, `db/002_ingest.sql`, and `edge/ingest/index.ts` (`/api/t1` → `nl.ingest_t1_rpc`).
- [x] **Build the release function** (`DISCLOSURE_CONTROL.md` section 9): built in `db/003_release.sql` and `db/008_scoped_insights.sql` with the 15-student floor, rounding to 5, tail capping (`<= 10.0%` / `>= 90.0%`), cell-key noise, carry-forward, and 2D complementary suppression, and tenant-scoped `nl.release_json_for_institution()`.
- [ ] Get a privacy officer's view on whether Tier 1, including the university reports, fits the Telecommunicatiewet 11.7a analytics exception.
- [ ] **Have the controller sign the legitimate-interest test**, and review it again if the counters, the recipients or the age limit change.
- [ ] Write a short data protection impact assessment screening note, even if the answer is "not required".
- [ ] Sign the data processing agreement with Supabase. Ask support whether it is available on Pro. The pricing page does not mention one.
- [ ] Sign a data processing agreement with the e-mail provider that sends reminders.
- [ ] Agree in writing with each partner university what it receives and who decides what is measured.
- [ ] Ask Supabase whether gateway logging can be switched off, and how long sign-in (auth) logs are kept. The policy's "7 days" covers only API and database logs.
- [ ] Read the actual text of Telecommunicatiewet art. 11.7a and the Dutch regulator's page on analytics. Both failed to load during research.
- [ ] Look up *Planet49* and confirm the pre-ticked-box point (it was cited from memory).
- [ ] Have a lawyer or privacy officer review the Terms and Privacy Policy.
- [ ] Work through the open items in `legal/COMPLIANCE_CHECK.md` (data list, named processors, transfers, Art. 13 sentences, staff notice).
- [ ] When accounts exist: add the sign-in IP address line to section 12 and update section 13 (full app).
- [ ] Review how names and photos of 16 and 17 year olds are handled, and write it down.
- [ ] Remember that changing the policy after launch means raising the version number, which asks every student to agree again.

## 3. Deploy the backend **[blocks launch]**

- [ ] Create two Supabase projects in an EU region: **app** and **insights**. Choose Pro. Keep the spend cap on. (About $35 a month with the second project; check the exact price.)
- [ ] Run the generated migrations in order (`python3 tools/make_migrations.py`). Enable the extensions `pg_cron`, `pg_net`, `supabase_vault` first.
- [ ] Change `ingest()` and the dashboard views to the intake semester (`intake`, e.g. `2026-sep`) instead of the arrival week.
- [ ] Add the Vault secrets `project_url` and `cron_secret` in both projects.
- [ ] Generate the push keys (`infra/tools/vapid.ts`) and set them as function secrets.
- [ ] Create the e-mail provider account, verify the sending domain, set the API key.
- [ ] Deploy the three Edge Functions `ingest`, `stats` and `editor` (the earlier names `send-notifications` / `publish-content` no longer exist). Deploy **`ingest` with `--no-verify-jwt`** (students have no token; nginx sends none), and keep JWT verification **on** for `stats` and `editor`, whose callers always send a staff token. Set `ALLOWED_ORIGINS`, `NL_PROXY_SECRET` and `NL_INGEST_SECRET` on all three.
- [ ] Add the GitHub secrets the deploy workflows need and run both workflows once.
- [ ] Check the scheduled jobs exist and run each one by hand once.
- [ ] **Verify on Supabase** that the `postgres` role may switch to `nl_sender`, `nl_publisher` and `insights_ingest`. This is untested; the local test only proves it on plain PostgreSQL.
- [ ] Host the site (GitHub Pages or similar) with `NL_INGEST_URL` and `NL_CONTENT_BASE` set. Check the Content-Security-Policy does not block the app on the real host.
- [ ] Confirm daily backups are running. Decide whether point-in-time recovery ($100 a month) is worth it.
- [ ] Publish the content once and check the phone loads it.

## 4. Security **[blocks launch]**

- [ ] **Test row-level security on the live app project:** sign in as student A and try to read and change student B's rows. Repeat for staff of another school.
- [ ] Have someone outside the team try to break it, such as a classmate with a security background. My own local tests are not a security review.
- [x] Pass 1 of the `innerHTML` audit is done (`SECURITY_AUDIT.md`): no exploitable injection found, 7 hardening fixes made, tests added.
- [x] Pass 2 of the audit (Opus): found and fixed content that could run code in every student's app, push addresses that let a student aim the server at any website, and unchecked content downloads. See `SECURITY_AUDIT.md`.
- [ ] Run the **attack list for the live project** in `SECURITY_AUDIT.md` once accounts exist (10 checks with two student accounts, an editor and the anonymous key).
- [x] Decide who may change content in cities that several schools share (audit P9): resolved in `db/005_content_editor_security_fix.sql` and `db/009_content_editor.sql` (`public.can_edit_city` locks shared municipal rows to `super_admin` while allowing institution-scoped overrides).
- [x] Give the editor panel and dashboard the same strict Content-Security-Policy and remove third-party Google Fonts (audit P10): done in `web/dashboard.html` and `web/editor.html`.
- [x] Configure reverse-proxy security headers (`frame-ancestors 'none'`, `nosniff`, HSTS, IP-free access logs) (audit P11): done in `edge/security-headers.conf`, `edge/ingest/index.ts`, `edge/stats/index.ts`, and `edge/editor/index.ts`.
- [x] Switch the content addresses that still start with `http://` to `https://` where the site supports it: 5 verified links upgraded to `https://`; 4 sites with broken TLS certificates kept on `http://` and documented in `README.md`.
- [ ] Before pushing the code anywhere: scan for real keys, passwords and personal e-mail addresses.
- [ ] Write a plan for rotating the cron secret, the push keys and the e-mail key.
- [ ] Set up Supabase Auth properly when accounts are added: confirmed e-mail, strong sign-in method, rate limits, and no custom password code.
- [ ] Staff accounts: invite flow, and two-step sign-in for editors and university staff.
- [ ] **Rate limiting is in place but only caps the damage.** After the first real traffic, check the limits (600 per source per 10 minutes, 2000 per minute overall, 20000 per hour per school) and adjust them in `insights.ingest_limit`.
- [ ] Decide what to do about fake counters inside the limits, which can still lift a small group over the hide-under-10 line. Options: raise the threshold, or use option C (count on the server once accounts exist). Semester cohorts already make groups larger.
- [ ] Set up a way to see function errors without logging personal data.

## 5. App features

- [x] Accounts, database side (`database/26_accounts.sql`): one sync call with a merge rule, data export, account deletion that also removes the sign-in. Tested locally, including two students side by side.
- [x] Opt-in screen for anonymous statistics after the Terms, with equal Yes and No buttons and "Decide later" (final-legal build, 18 Nov).
- [ ] **Student accounts, app side** **[blocks launch for reminders]:** sign-up and sign-in screens, sign out, the app recording when each step, event and the profile was changed, calling `sync_progress()` and applying what comes back. **[Claude]** can build this; it needs a live Supabase project to test against.
- [ ] Decide the sign-in method (e-mail link, or e-mail and password) and set up Supabase Auth: confirmed e-mail, rate limits.
- [ ] **Data export, app side:** a button in Profile that calls `export_my_data()` and saves the file.
- [ ] "Delete all my data" must call `delete_my_account()` when signed in, then clear the phone.
- [ ] Check on Supabase that `delete_my_account()` and the monthly purge may delete from `auth.users`.
- [ ] The phone's rule for which steps apply ignores a step limited to one city, and a campus of a school a step is limited to. No step uses either today, so nothing is wrong yet; `tests/test_parity.py` will fail the day one does. Bring the phone's rule in line before adding such a step.
- [ ] Reminders: the permission flow, the e-mail opt-in, and a real test of push on iPhone (web push there may need the app added to the home screen; check).
- [x] Connect the **editor panel** to the `editor_*` database functions (`web/editor.html`, `web/editor.js`, `edge/editor/index.ts`, `db/009_content_editor.sql`), with interactive Demo Mode fallback.
- [x] Connect the **university dashboard** to `nl.release_json_for_institution()` (`web/dashboard.html`, `web/stats.js`, `edge/stats/index.ts`, `db/008_scoped_insights.sql`), with v2.1-hardened Demo Preview fallback.
- [ ] Make new content apply immediately instead of on the next open, if that matters.
- [x] The 7 cities added on 14 Nov (Tilburg, Venlo, Leeuwarden, Apeldoorn, Deventer, Heerlen, Sittard-Geleen) have colours, skylines, and researched arrival/BRP/GGD-TB/housing details embedded in `netherlanded-app.html` and `web/editor.html` (Apeldoorn, Heerlen, Sittard-Geleen, and Deventer individual BRP fallback completed on 22 Nov 2026; see `architecture/CITY_RESEARCH.md`). **Remaining visual polish:** confirm and draw custom municipality flag SVGs for the 7 cities (currently using lettered colour badges).
- [ ] A proper accessibility check (contrast, screen reader, keyboard, text size). Only partial checks have been done.
- [ ] Tab bar labels now follow the text size (rem). Check the bar still fits at 200% on a real phone.
- [ ] Most text is sized in px, so it does not follow a larger text setting. Move sizes to rem and recheck every screen at 200%.
- [ ] The open tab is not remembered after a reload. Decide whether it should be.
- [ ] The design review found a red "Choose where you will live" error before anything was tapped; it could not be reproduced. Watch for it in user tests.
- [ ] Decide whether the app needs Dutch or other languages.

## 6. Content

- [ ] Re-check every date, amount and rule against its official source before launch. Name one owner. `architecture/FACT_CHECK.md` shows how it was checked.
- [ ] Review the content for all 18 cities and the campus lists.
- [ ] Amsterdam's local registration text still gives the July to September 2026 dates, which have passed. Check the municipality site and update it.
- [ ] Several figures are still written into step texts instead of using the fact placeholders (bank 90 to 120 days, 5 days to register, 32 hours, TB test €60). Switch them to `{fact_key}` so a changed figure updates everywhere.
- [ ] Test every link in the app still works.
- [ ] Calibrate the scam check against real examples. It gives an indication only, and the wording says so.
- [ ] Set a schedule for re-checking content (rules change), and say who does it.

## 7. Testing and quality

- [ ] Run the tests in GitHub Actions for the first time and fix what differs from the local setup.
- [ ] The team's older test suites in its own `tests/` folder are not part of this folder. Add them back.
- [ ] Test on real phones: iPhone Safari, Android Chrome, small screens, slow connection, offline.
- [ ] Usability test with about five real first-year students. Your friend's copy is the first step. Ask what confused them first.
- [ ] Test the counter door under load.
- [ ] Test the full flow end to end on the live setup: sign up, complete a step, counter arrives, snapshot publishes, dashboard shows it, reminder arrives.

## 8. Team and handover

- [x] Put the source in the team's repository. Keep it private. Added `LICENSE` (`Copyright (c) 2026 Eirini Konidari. All rights reserved.`), `.gitignore`, `.gitattributes`, and `.github/workflows/ci.yml`.
- [ ] Agree who owns what after the course ends: Supabase, the domain, the keys, the content.
- [x] Pitch, business model, competitor analysis, stakeholder analysis (kept in a private repository), and technical suites updated to the 21 November 2026 v2.1 state (263 automated checks passing).
- [ ] Give group mates the handover note (section 1) and the privacy assessment to read.
- [ ] Decide what happens to the data and the accounts when the project ends.

---

## Already done (for reference)

- Database schema, logic, seed, cities and campuses, content export with fingerprints
- Server functions with narrow roles, reminder queue, scheduled jobs, staff roles and change log
- Edge Functions for counters, reminders and publishing, with tests
- Build and deploy workflows, written but not run
- Policy version 1.7: statistics opt-in on consent, intake-semester groups, court clause fixed (18 Nov). Version 1.6 corrected the IP address statement and filled in the 7-day log retention
- Privacy assessment (`legal/PRIVACY_ASSESSMENT.md`) and compliance check (`legal/COMPLIANCE_CHECK.md`)
- Rate limiting on the counter door: per source, per minute and per school, with tests
- Security audit pass 1 and hardening of links, photo, dates, setup progress, push links and the editor
- Security audit pass 2: content escaped in the build, scripts allowed by hash only, push addresses limited to real push services, content downloads checked against their fingerprints, size limits on text, and a database test that attacks as two students and an editor
- App prototype: onboarding, checklist, deadlines, scam check, city themes, opt-in anonymous statistics
- Accounts, database side: `sync_progress()`, `export_my_data()`, `delete_my_account()`, the purge removing sign-ins, and a test that runs the same students through the phone and the database and compares the result (16 Nov)
- Design review and first tester round (14 Nov): header shows progress as the rising sun over a country scene plus one line of text (numbered boxes and bars removed); every count uses the same rule; quieter finished cards, readable locked cards, no glow; neutral inner-page bars; every costly or legal deadline says what happens if missed, with live figures (`database/25_content_updates.sql`); "Up next" puts urgent legal or costly deadlines first; finished phases always fold away; plain tags (By law, Costly, Tip); screen-reader labels and announcements for ticking; long municipality texts folded
