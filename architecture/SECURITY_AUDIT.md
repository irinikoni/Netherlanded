# Security audit: app, editor, dashboard, content and database

*Pass 1: 14 November 2026, run in the default session. The app labelled the model Sonnet 5.5 at the start and the serving model changed during the session, so I cannot certify that it was a single model. Pass 2: 14 November 2026, run with Opus 5.5 (results at the end; they correct pass 1). This is a code read plus automated tests. It is not a penetration test and not an outside review.*

## Scope

Where could text that a person typed, or text from the content, end up as running code or a harmful link?

- **App** (`src/js`, `src/site`): 23 uses of `innerHTML`, `outerHTML` or `insertAdjacentHTML`, and about 260 values placed inside HTML templates.
- **Editor panel** (`editor/index.html`) and **dashboard** (`dashboard/index.html`): 3 and 4 uses of `innerHTML`.
- **Service worker** (`src/site/sw.js`): what a push message can make the app open.

Method: list every place HTML is built, list every value placed in it, and for each value decide whether it can come from a person or from content and whether it is escaped.

## Result

**Pass 2 corrected this:** pass 1 said no exploitable injection was found. That was wrong for content: the build placed content into the page without escaping it, so content containing `</script>` ran as code for every student (pass 2, finding P1). The rest of this paragraph stands. Every place where a typed value (first name, municipality, dates) reaches a page was already escaped or set as plain text. A few places were safe only by luck, or relied on the content being trusted. Those are fixed in pass 1.

| # | Finding | Risk | Status |
|---|---|---|---|
| 1 | Addresses from content were put in `href` after escaping, but with no check of the scheme. A `javascript:` address would run when tapped. Every address in the content today starts with `https://` or `http://`. | Medium once editors can type addresses | **Fixed.** `safeUrl()` allows only `http://` and `https://` addresses; used at all five link sites. The editor and the database accept only `https://` for new entries. |
| 2 | `esc()` did not escape a single quote. Safe today because every attribute is double-quoted, but one single-quoted attribute later would break it. | Low (fragile) | **Fixed.** `esc()` now escapes `'`. |
| 3 | The saved photo was placed in an `<img src>` unchecked. Only the person's own browser storage can set it, but a bad value would break out of the attribute. | Low (self only) | **Fixed.** `safePhoto()` accepts only a `data:image/png`, `jpeg` or `webp` string. |
| 4 | Dates were placed in `value="…"` without escaping (4 places). The browser's date field only produces `yyyy-mm-dd`, but stored data could hold anything. | Low (self only) | **Fixed.** `safeDay()`. |
| 5 | A push message could carry any address, and tapping the notification would open it. Only our server can send pushes, but there was no check. | Low | **Fixed.** The service worker opens only addresses on its own site. |
| 6 | Saved setup progress was copied wholesale into the setup state (`Object.assign`). | Low (self only) | **Fixed.** Only known fields with plain values are taken. |
| 7 | Editor: three `data-…="${s.id}"` attributes were not escaped. Ids come from us today. | Low | **Fixed.** |
| 8 | The page's Content-Security-Policy allows `'unsafe-inline'` scripts, so it would not stop an injected inline script. A single-file app needs inline scripts. | Medium (defence in depth) | **Fixed in pass 2** (P2). |
| 9 | A `<meta>` Content-Security-Policy cannot set `frame-ancestors`, so the page can be framed. | Low | **Open.** Needs response headers from the host. GitHub Pages cannot set them. |

Because the editor will later let staff type content that students see, finding 1 is the one that matters most. The database already refuses new addresses that do not start with `https://` (`editor_save_service`, links), so a check now exists at three layers: the editor, the database, and the app when it shows a link.

**Content follow-up:** 15 addresses in the content still start with `http://` (GP practices, housing and expat sites in Delft, Eindhoven, Enschede, Venlo, Maastricht and Rotterdam). They work, but they are not encrypted, and an editor who opens one of those entries cannot save it again until the address is `https://`. Check each site and switch it where the site supports it.

## Tests added

`tests/test_hardening.py`:
- Hostile text in the name, the municipality, the photo and both date fields does not run. The page is visited in every tab, the profile and 12 step sheets.
- The helper functions refuse `javascript:` and `data:` addresses, quote-breaking addresses, an SVG photo and non-date text.
- Every link in every step sheet is a web address or `#`.

I checked that the first test fails when the old unsafe photo handling is put back, so it does detect the problem. The full suite passes.

## Not covered by pass 1

- **Dashboard** (`dashboard/index.html`): read, nothing found, but its data is currently built in. Re-read when it is connected to the live `dash_*` views, because then its values come from a database.
- ~~Content loader, service worker caching, build, SQL~~: covered in pass 2.
- **Edge Functions:** read while writing, not re-read as an attacker.
- **Live Supabase:** nothing in this audit touches a live project. Row-level security is untested there.
- **Real browsers:** all tests run in desktop Chrome. Not tried on iPhone Safari or Android.

## Pass 2 brief (for Opus, later)

Read this file and the code, then try to break it rather than confirm it. Focus on:
1. Whether finding 8 can be fixed with script hashes, and what else breaks. Propose the change and test it.
2. The content loader and cache: a hostile or stale content file, a half-downloaded file, a rollback to older content.
3. The three editor-to-database paths and the dynamic SQL: can a staff member of one school reach another school's data or run anything beyond the intended function?
4. Anything this pass missed. Treat the "No exploitable injection was found" line as a claim to test, not a fact.
5. The row-level security policies, as written in `database/`: write the attack list to run on a live project.

Add the findings to a new section below, with date and model, and keep the table format.

## Pass 2 results

*14 November 2026, run with Opus 5.5. Method: tried to break each area, proved each finding with a working attack before fixing it, then checked that each new test fails when the fix is removed.*

### Bottom line

Pass 1's main claim was wrong in one important place. **Content could run code in every student's app** (P1). Anyone who can change content, which includes editors once the editor panel is live, could have used it. That is fixed and tested. Pass 2 also found that **a student could make the reminder server send requests to any website** (P3). The database access rules held up against every attack tried.

| # | Finding | Risk | Status |
|---|---|---|---|
| P1 | **The build placed content inside `<script type="application/json">` without escaping it.** A step title containing `</script><script>…` ended the data block and ran as code in the built app, for every student. Proved with a working attack. A title containing `{{js}}` also broke the whole app, because the template was filled in several passes and content was scanned again. | **High** (anyone who can change content) | **Fixed.** Every `<` in embedded JSON becomes `<`, which is the same JSON value. The template is filled in one pass. The build refuses invalid JSON, and refuses our own scripts if they contain `</script`, `<script` or `<!--`. |
| P2 | Pass 1 finding 8: the security policy allowed any inline script. | Medium (defence in depth) | **Fixed.** The hosted site and the single file now allow only their own scripts, by hash, computed at build time. Injected scripts and `onerror=` handlers are blocked (tested). The single file also allows no network access at all. Styles still allow inline, which is lower risk. |
| P3 | **A signed-in student could store any `https://` address as a push address**, and the reminder server would send requests to it. That is server-side request forgery. A student could also store unlimited addresses, multiplying every reminder. | **Medium** | **Fixed.** The database accepts only real push services (Google, Mozilla, Apple, Microsoft) and at most 5 devices per student. The sender also refuses unknown addresses, never contacts them, and deletes them (covers rows stored before the change). |
| P4 | **The content loader never checked a downloaded file against its fingerprint.** A half-downloaded file, a cache serving an old file next to a new manifest, or a file changed after publishing would be saved and used. A file with the wrong shape could break the app until new content arrived. | Medium (reliability, integrity) | **Fixed.** Each file must match the first 16 hex characters of its SHA-256 fingerprint. The shape is checked before saving, and nothing is saved if any check fails. The app checks the saved copy's shape again on start, and falls back to the content built into the page. |
| P5 | Content text had no size limits, and link addresses only had to start with `https://` (spaces and quotes allowed). One editor could make every phone download megabytes. | Low to medium | **Fixed.** Checked whenever content changes, by any route: local text 5,000 characters, 10 links, labels 120 characters, service names 120 and descriptions 1,500. Addresses must be `https://` with no spaces or quotes. Unchanged older rows are left alone. |
| P6 | Ids and keys (steps, cities, schools, sources, figures) go into HTML attributes unescaped, and had no format rule. | Low (project team only) | **Fixed.** Lower-case letters, digits, `-` and `_` only (all current ids comply). The loader checks step ids too. |
| P7 | Two trigger functions running with the owner's rights did not list `pg_temp` last in their search path. | Low (students cannot run raw SQL) | **Fixed.** A test now fails if any such function lacks it. |
| P8 | Student text (name, own municipality, step note) had no size limits. | Low | **Fixed.** 60, 80 and 2,000 characters. |
| P9 | One school's editor can change local text and services in a city that another school shares (for example Amsterdam). | Design choice | **Open.** Every change is logged with who made it. Decide whether shared cities need one owner or an admin's approval. |
| P10 | The editor panel and dashboard pages load Google Fonts and have no security policy. They will hold staff sign-ins, the most valuable sessions. | Medium once live | **Open.** Give them the same hash-based policy when they are connected, and self-host the fonts. |
| P11 | Pass 1 finding 9 (framing) still needs response headers from the host. | Low | **Open.** Choose a host that can set `frame-ancestors 'none'` and `X-Content-Type-Options: nosniff`, or accept it. |

Checked and found sound:
- **Editor functions:** each write checks the editor's cities before acting. A service cannot be moved to another city. National content and figures need an admin. An editor sees only their own change log.
- **Who the database thinks you are** (`app_uid()`): it reads only the verified sign-in token. Students cannot set it through the API.
- **Dynamic SQL:** every built statement uses `format('%I')`, `%L` or parameters on fixed names from the code. No user text reaches it.
- **Server functions:** still callable only by their narrow roles.
- **The buddy tables** that pass 2 first flagged were already removed by `13_cleanup.sql`, so that finding was dropped.

### Tests added in pass 2

- `database/24_security_tests.sql` grants Supabase's default table rights first, so it tests what a live project would do. Then it attacks as student A against student B, as an anonymous caller, and as an editor for one school against another school's cities. It also fails if any table lacks row-level security, if any view runs with the owner's rights, if any owner-rights function has an unsafe search path, or if a signed-in user can call anything outside a fixed list. I broke six things on purpose (removed the push check, switched off row-level security, removed the text check, widened a policy, granted a server function, widened an editor's cities), and each was caught by the right check.
- `tests/test_hardening.py`: hostile content in the build (five attack strings), the build refusing broken JSON, and the policy blocking injected scripts on the hosted site and in the single file. I checked that the content test fails when escaping is removed.
- `tests/test_hosted_settings.py`: scripts are allowed by hash only, bad settings are refused, a file that does not match its fingerprint is not used, content with the wrong shape is not used, and a broken saved copy falls back to the built content.
- `infra/tests/send.test.ts`: an address that is not a push service is never contacted, and is removed.

### Attack list for the live project

Run these on the real Supabase project once accounts exist. Use two student accounts (A and B), one editor and the anonymous key, calling the REST API directly (for example with `curl`), not through the app.

1. As anonymous: read `app_user`, `user_step`, `push_subscription`, `notification`, `staff_account`, `staff_change`. Expect empty results or errors, never rows.
2. As A: the same reads. Expect only A's own rows, and nothing from the staff tables.
3. As A: `PATCH` and `DELETE` on B's rows in each table, with `id=eq.<B>` filters. Expect 0 rows changed.
4. As A: `POST` a `user_step` and a `push_subscription` with `user_id` set to B. Expect a refusal.
5. As A: `POST` a push address of `https://example.org/x`, and a sixth device. Expect refusals.
6. As A: call `/rpc/user_email`, `/rpc/claim_due_notifications`, `/rpc/content_files` and `/rpc/editor_save_local`. Expect "permission denied" or "not allowed".
7. As A: `PATCH` `step`, `service`, `fact` and `staff_account`. Expect 0 rows changed, or a refusal.
8. As the editor: change local text and a service in a city of another school, add a national service, add a figure. Expect "not allowed" each time. Then change something in their own city, and check it appears in `staff_change`.
9. As anyone: `POST` to `ingest` 700 times quickly from one machine. Expect `429` after about 600 (the limit is per function instance, so it can be higher if Supabase runs several).
10. Check that the Supabase dashboard shows row-level security on for every table in `public`, which matches what test X1 checks locally.

### Still not covered

- Live Supabase (the list above), real phones, and an outside reviewer.
- The editor panel and dashboard once connected (P10).
- The Edge Functions' own Supabase settings (JWT verification off by design; check that only the three intended functions exist).

## Pass 3: accounts functions (16 November 2026)

`database/26_accounts.sql` adds four functions a signed-in student can call: `sync_progress()`, `my_state()`, `export_my_data()` and `delete_my_account()`. `database/27_accounts_tests.sql` attacks them locally.

| Check | Result |
|---|---|
| Who may call (C1 to C3) | Only `authenticated`. Revoked from `anon` and PUBLIC. A signed-out caller is refused |
| One student reaching another's rows (B1, B2) | Each function reads and writes only the caller's own rows. A second student's data is untouched by sync, export and delete |
| Size limits | 60,000 characters, 200 steps, 50 events per call. Larger payloads are refused |
| Wrong clocks | A change time or completion date in the future is clamped, so a phone cannot win every later merge |
| Staff accounts | `delete_my_account()` refuses them |
| Allow-list of callable functions (X4 in `24_security_tests.sql`) | Updated with the four new functions |

Each rule was checked by breaking it on purpose (removing the latest-change guard, the sign-in delete, the change-time trigger and the sync switch reset); the matching test failed each time.

**Open:** (1) `delete_my_account()` removes the row in `auth.users`. Locally that table is a stand-in; check on real Supabase that the function's owner may do this. (2) The sync has size limits but no speed limit like the counter door has. (3) The app does not call any of this yet, so none of it has been exercised through the real REST API.
