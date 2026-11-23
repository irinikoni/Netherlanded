# Netherlanded infrastructure

Everything needed to run Netherlanded as a service instead of a prototype. **None of it has been
deployed.** The database files and the three server functions are tested here against PostgreSQL 16;
the Supabase and GitHub settings have never run against a real project (see "Not verified").

## What runs where

| Piece | Where | Code |
|---|---|---|
| The web app (installable, works offline) | Static hosting: GitHub Pages | `src/`, built by `tools/build.py` |
| App database: content, accounts, progress, reminder queue | Supabase project "app" (EU region) | `database/01` to `26` |
| Content files phones download | Public Storage bucket `content` in the app project | written by `publish-content` |
| `publish-content`: uploads changed content files | Edge Function, app project | `infra/app/supabase/functions/publish-content` |
| `send-notifications`: push and e-mail reminders | Edge Function, app project | `infra/app/supabase/functions/send-notifications` |
| Insights database: anonymous counters, weekly snapshot | Supabase project "insights" (EU region), separate on purpose | `database/06`, `09`, `19` |
| `ingest`: the only way counters get in | Edge Function, insights project | `infra/insights/supabase/functions/ingest` |
| Scheduled jobs | pg_cron inside each database | `server_jobs()` in `17` and `19` |
| Push delivery | The browsers' own push services (Web Push) | no account needed, only a key pair |
| E-mail delivery | Brevo's HTTP API (any provider with a similar API works) | `send-notifications/handler.ts` |

Two Supabase projects, one static host, one e-mail provider. Nothing else.

## How the pieces talk

**Content, editor to phone.** An editor saves through an `editor_*` database function. A trigger calls
`publish-content`, which asks the database for every content file's exact text and fingerprint, uploads
only the files that differ from the published manifest, and uploads the manifest last. Phones read the
manifest on each open and download only changed files. A job repeats the call every ten minutes in case
one was missed.

**Counters, phone to university.** The app posts each "+1" to `ingest`. The function passes it to
`insights.ingest_checked()` (which counts against a speed limit, then calls `ingest()`) as a database role that can do nothing else, and stores or logs nothing about the
request. Every Monday at 03:00 UTC `publish_snapshot()` rebuilds what universities see. Signed-in staff
read the `dash_*` views, which show only their own school.

**Reminders.** Daily jobs put due reminders in the `notification` table. Every ten minutes
`send-notifications` claims the due ones, sends each by push and/or e-mail according to the student's
switches, and reports back. A message is retried up to five times; a push address that no longer
exists is forgotten.

## Scheduled jobs (UTC)

| Job | When | Does |
|---|---|---|
| `nl-queue-reminders` | daily 04:05 | queues deadline reminders (7 days before, and on the day) |
| `nl-queue-checkins` | daily 04:10 | queues the monthly check-in |
| `nl-send-reminders` | every 10 min | calls `send-notifications` |
| `nl-publish-content` | every 10 min | calls `publish-content` (uploads nothing if nothing changed) |
| `nl-purge-accounts` | 1st of the month 03:30 | deletes accounts 12 months after arrival |
| `nl-insights-snapshot` | Monday 03:00 | rebuilds the university snapshot |
| `nl-insights-purge` | 1st of the month 04:00 | removes totals older than the retention period |

## First-time setup

1. **Create two Supabase projects** in an EU region: "app" and "insights". Note each project's
   reference id and database password.
2. **GitHub secrets and variables.** Add the secrets listed at the top of
   `.github/workflows/deploy-backend.yml`, and the two variables listed in `deploy-site.yml`.
3. **Run "deploy backend"** (GitHub → Actions). It applies the database files, deploys the three
   functions and copies school and step names into the insights database.
4. **Function secrets.** Copy `infra/.env.example`, fill it in, and run the two
   `supabase secrets set` commands written at its top. Make the push key pair with
   `deno run infra/tools/vapid.ts`.
5. **Vault secrets** in the app project (SQL editor), so the database can call the functions:
   ```sql
   select vault.create_secret('https://<app-ref>.supabase.co', 'project_url');
   select vault.create_secret('<the same value as CRON_SECRET>', 'cron_secret');
   ```
6. **First publish.** `select call_server_function('publish-content');` in the app project, then check
   that `https://<app-ref>.supabase.co/storage/v1/object/public/content/manifest.json` opens.
7. **Insights API.** In the insights project's API settings, add `insights` to the exposed schemas.
8. **Run "deploy site"**, after turning on GitHub Pages (Settings → Pages → Source: GitHub Actions).
9. **Staff accounts.** Invite the person in Supabase Auth (Authentication → Users → Invite), then:
   ```sql
   -- app project: an editor for THUAS (cities follow from the school's campuses), or an admin
   insert into staff_account (user_id, role, institution_id) values ('<user id>', 'editor', 'thuas');
   -- insights project: who may see which school's dashboard
   insert into insights.university_member (user_id, institution_id) values ('<user id>', 'thuas');
   ```

## Changing the live database

`tools/make_migrations.py` copies `database/*.sql` into the two migration folders in the right order,
leaving out the tests and the fictional demo students. Supabase applies each file once. So **never edit
a file that has been deployed: add a new numbered file** and list it in `make_migrations.py`.
`make_migrations.py --check` builds a clean database from the migrations and fails if it would export
different content than `content/`.

## Tests

```
tests/run_sql.sh                              # both databases, every check file
python3 tools/make_migrations.py --check      # a clean live build exports the committed content
deno test -A infra/tests/                     # the three server functions, against the test databases
python3 -m pytest tests -q                    # the app in a browser (also runs the Deno tests if Deno is installed)
```

The function tests use the real handlers and a real database. Only the outside world is replaced:
the push service, the e-mail provider and the Storage bucket are stand-ins that record what they
receive. The push test decrypts the message with a browser key pair, as a browser would.

## Accounts (database side, `database/26_accounts.sql`)

The phone stays the working copy, so the app keeps working offline. A signed-in phone sends what it
has and gets the merged state back. Four functions, callable only by a signed-in student and only for
their own account:

| Function | Does |
|---|---|
| `sync_progress(payload)` | Merges profile, steps and events. The first call creates the account and must carry a profile with a region. Returns the merged state, and the ids it did not know (`skipped`) |
| `my_state()` | The account's current state, in the same shape |
| `export_my_data()` | Everything stored about the caller, for the right of access: profile, steps with notes, events, reminders, and devices by push service name |
| `delete_my_account()` | Removes the profile (progress, events, devices and reminders go with it) and the sign-in. Refused for staff accounts |

**Merge rule.** Per item (the profile, each step, each event) the latest change wins. Two "done" marks
keep the earlier completion date. An un-ticked step and a removed event stay as rows, so an older
phone cannot bring them back. A change time in the future counts as now; a completion date in the
future becomes today.

**The lock rule and sync.** A single direct tick of a locked step is still refused. A sync stores what
the phone has, including "later step done, earlier step un-ticked", which the phone allows.

**Payload.**
```
{ "profile": { "display_name": "...", "region": "eu_eea", "institution_id": "thuas", "study_city_id": "the-hague",
               "home_municipality_id": "the-hague", "arrival_date": "2026-12-09", "plans_to_work": true,
               "notify_email": false, "notify_push": false, "at": "2026-11-16T10:00:00Z" },
  "steps":   { "find_housing": { "done": "2026-11-01", "at": "..." }, "open_bank": { "done": null, "at": "..." } },
  "events":  { "first_work_day": { "date": "2026-12-01", "at": "..." } } }
```
Limits: 60,000 characters, 200 steps, 50 events.

The monthly purge now removes the sign-in as well as the account.

## Not verified

- **Nothing has run on Supabase.** `config.toml`, the workflows, `supabase db push`, the pg_cron
  schedule, the pg_net call and the Vault lookups are written from the documentation, not tested.
  Expect small fixes on the first deploy.
- **Storage upload and e-mail requests** are tested against stand-ins, not the real services.
- **Database roles.** The functions connect as the database owner and step down to `nl_sender`,
  `nl_publisher` or `insights_ingest`. Whether Supabase's `postgres` role may do that after the grant
  in `17` and `19` is untested.
- **Deleting a sign-in.** `delete_my_account()` and the monthly purge delete from `auth.users` as the
  function owner. Locally that table is a stand-in. Check on Supabase that the owner may delete there,
  and that Supabase Auth needs nothing else removed.
- **IP addresses.** `ingest` stores and logs nothing, but Supabase's own gateway logs the client IP
  address for its retention period (1 day on Free, 7 on Pro, 28 on Team, per its pricing page).
  The policy says so. Whether those logs can be switched off is unconfirmed. Everything else about
  consent, the controller and small cohorts is in `legal/PRIVACY_ASSESSMENT.md`.

## Not built

- **Student accounts, the app side.** The database side exists (see "Accounts" below). The app has no
  sign-in screen, does not call `sync_progress()`, and does not yet record when each step was changed,
  which the merge needs. Until then progress lives only on the phone and `send-notifications` has
  nobody to send to.
- **The app does not ask for push permission** or store a push address. The service worker can show a
  pushed reminder and open the right step; the sign-up side waits for accounts.
- **Editor panel and dashboard are not connected.** The database functions they need exist and are
  tested (`editor_*`, `staff_me`, `dash_*`). The two pages still run on built-in data with a dropdown
  sign-in.
- **Staff sign-in through SURFconext** is a setting in Supabase Auth (a custom OIDC provider) plus an
  agreement with SURF. Neither is configured here.
- **`ingest()` and the intake semester.** Since policy 1.7 the app groups counters by intake semester
  (`intake`, e.g. `2026-sep`) instead of the Monday of the arrival week. `ingest()` still expects the
  week and must be changed before counters are sent.

## Speed limits on the counter door

The door is public, so anyone can send counters. Limits cap the damage; they cannot tell fake from real.

| Limit | Where | Default | Answer |
|---|---|---|---|
| Per source | `ingest` function, memory only (salted hash of the address, lost on restart) | 600 counters per 10 minutes | 429, `Retry-After: 600` |
| Whole door | `insights.ingest_limit` row `all` | 2000 per minute | 429, `Retry-After: 60` |
| One school | `insights.ingest_limit` row `school` | 20000 per hour | 429, `Retry-After: 60` |

Change the database limits with an `UPDATE` on `insights.ingest_limit`. A phone that gets 429 keeps its counters and tries later. The per-source limit is generous because a campus network can share one address, and it is per function instance, so it slows one source down but does not stop a flood from many sources. Fake counters inside the limits are still counted, and enough of them can lift a group over the hide-under-10 line.

## Push addresses

Students store their own push addresses, so the sender must never contact an arbitrary site. The database
(`database/23_security.sql`) accepts only the push services browsers use: `fcm.googleapis.com`,
`updates.push.services.mozilla.com`, `web.push.apple.com` and `*.notify.windows.com`, with at most 5 devices per
student. `send-notifications` checks the same list before every send and removes any other address. If a browser starts using another push service, add it in both places. (Student-facing server push is not active in the v2.1 local prototype.)

---

## v2.1 Consolidation Note (21 November 2026)

- **Consolidated Analytics & Disclosure-Control SQL:** Any earlier references to weekly `arrival_week` (`2026-W35`) cohorts or threshold-10 `dash_*` views are superseded by `db/001_schema.sql`–`db/004_retention.sql` (`intake` semester `YYYY-sep`/`YYYY-feb`, separate `nl.raw_t1` / `nl.raw_t2` stores, 6-rule disclosure control at floor ≥ 15 with cell-key noise, rounding to 5, carry-forward and complementary suppression, 48h raw event ceiling, and `web/stats.js` safe dashboard renderer).
- **Shared-City Editor Privilege Fix:** `db/005_content_editor_security_fix.sql` addresses `SECURITY_AUDIT.md` Finding P9 (`can_edit_city` with `search_path = public, pg_temp`).
- **Pre-pilot remaining infrastructure work:** Live PostgreSQL execution of `db/001`–`005`, per-institution RLS/tenant scoping on `nl.release_json()`, edge rate limiting, edge IP stripping (target ≤ 24h logs vs. 7 days on Supabase Pro), and signed Art. 28 DPAs.
