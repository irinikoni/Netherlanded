# Release checklist (v2.1 consolidated)

- [ ] **Execute & test SQL on live PostgreSQL 15+:** Run `db/001_schema.sql` through `db/004_retention.sql` (and `db/005_content_editor_security_fix.sql` on the content DB), verify `pg_cron` schedules, and run smoke + negative tests (`22023`, `42501`, `23514`).
- [ ] **Add per-institution tenant scoping / RLS:** Restrict `nl.release_json()` and university dashboard credentials so each institution reads only its own published rows (never pooled raw counters or other schools' snapshots).
- [ ] **Verify client queue & browser compatibility:** Run `tools/test_suppression.py` (62/62 pass), test `netherlanded-app.html` weekly batching/migration without dropping old `nl-basic`/`nl-stats` queued items, and test browsers with and without `navigator.locks` and `crypto.randomUUID`.
- [ ] **Gateway-only ingest:** Set `NL_PROXY_SECRET` and `NL_INGEST_SECRET` on every edge function (they now fail closed without `NL_PROXY_SECRET`; never set `NL_ALLOW_DIRECT_DEV=1` outside local dev) and store the ingest secret's hash in the database: `insert into nl.ingest_gateway (secret_sha256) values (encode(sha256(convert_to('<NL_INGEST_SECRET>', 'UTF8')), 'hex'));`. Until that row exists, the public anon key can call the ingest RPCs directly, around Nginx's per-IP limits.
- [ ] **Backup window matches the privacy policy:** set the hosting provider's backup / point-in-time-recovery retention to at most the number of days stated in `TERMS_AND_PRIVACY.md` §14 (placeholder **[7]**), and update that placeholder to the real value.
- [ ] **Rotate the ingest secret without an outage:** insert the new hash into `nl.ingest_gateway` (up to two may be active), deploy the new `NL_INGEST_SECRET`, then delete the old hash.
- [ ] **Monitor `nl.health()`:** alert when `ok` is false or `fold_stalled` is true (unfolded raw rows older than 3h); `nl.purge_raw()` also reports `raw_unfolded_expired`.
- [ ] **Edge hardening & IP stripping:** Strip client IP addresses at the edge gateway before logging, cap technical logs at ≤ 24h, and enable API rate limiting on ingest endpoints.
- [ ] **Legal & governance sign-offs:**
  - [ ] Settle controller model (`DISCLOSURE_CONTROL.md` §8 vs. `LEGAL_DELTA.md` §1) and replace `[bracketed]` placeholders in `TERMS_AND_PRIVACY.md` + `netherlanded-app.html`.
  - [ ] Confirm Tier 1 (*Telecommunicatiewet* art. 11.7a + GDPR Art. 6(1)(f)) with THUAS privacy officer (FG), sign `LEGITIMATE_INTEREST_ASSESSMENT.md`, and complete DPIA + Art. 30 record.
  - [ ] Sign Supabase EU Art. 28 DPA, verify static-host transfer mechanism, sign university data-sharing & use-restriction agreements, and issue the separate staff privacy notice.
