# Release checklist (v2.1 consolidated)

- [ ] **Execute & test SQL on live PostgreSQL 15+:** Run `db/001_schema.sql` through `db/004_retention.sql` (and `db/005_content_editor_security_fix.sql` on the content DB), verify `pg_cron` schedules, and run smoke + negative tests (`22023`, `42501`, `23514`).
- [ ] **Add per-institution tenant scoping / RLS:** Restrict `nl.release_json()` and university dashboard credentials so each institution reads only its own published rows (never pooled raw counters or other schools' snapshots).
- [ ] **Verify client queue & browser compatibility:** Run `tools/test_suppression.py` (62/62 pass), test `netherlanded-app.html` weekly batching/migration without dropping old `nl-basic`/`nl-stats` queued items, and test browsers with and without `navigator.locks` and `crypto.randomUUID`.
- [ ] **Edge hardening & IP stripping:** Strip client IP addresses at the edge gateway before logging, cap technical logs at ≤ 24h, and enable API rate limiting on ingest endpoints.
- [ ] **Legal & governance sign-offs:**
  - [ ] Settle controller model (`DISCLOSURE_CONTROL.md` §8 vs. `LEGAL_DELTA.md` §1) and replace `[bracketed]` placeholders in `TERMS_AND_PRIVACY.md` + `netherlanded-app.html`.
  - [ ] Confirm Tier 1 (*Telecommunicatiewet* art. 11.7a + GDPR Art. 6(1)(f)) with THUAS privacy officer (FG), sign `LEGITIMATE_INTEREST_ASSESSMENT.md`, and complete DPIA + Art. 30 record.
  - [ ] Sign Supabase EU Art. 28 DPA, verify static-host transfer mechanism, sign university data-sharing & use-restriction agreements, and issue the separate staff privacy notice.
