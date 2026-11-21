# Netherlanded – app backbone (CBS project)

*App name: Netherlanded (working name until 19 Oct 2026: Aankomst). File names still use `aankomst`.*

Backbone and prototype of an app that guides first-year international students in 10 Dutch study cities (The Hague and THUAS first) from before they arrive through their first months. Built from the group's desk research (28 Sep 2026), fact-checked on 19 Oct 2026, branded and redesigned up to 28 Oct 2026.

Links: [shared app](https://claude.ai/artifact/AsMX5nY66xXsQ2eCN2Vi2X) · [preview](https://claude.ai/artifact/NRws6P3nr1WReEm4EUGzHn) · [brand](https://claude.ai/artifact/8k1r41XngDGGKvEcQAdFzp) · [documentation](https://claude.ai/artifact/XFAZi2exJmfY3p8EaoZtGF) · [build timeline](https://claude.ai/artifact/2XdRrsowrGNitVuFDN3AwH)

## What's in here

| Folder / file | What it is |
|---|---|
| `db/01_schema.sql` | PostgreSQL tables: steps, dependencies, sources, versioned facts, deadlines, local services, scam check, users, progress, buddies, notifications |
| `db/02_logic.sql` | Views and functions: personalised checklist with lock state, progress, deadlines, stale content, change alerts, reminders, cycle check |
| `db/03_seed.sql` | All content from the research: 20 steps, 14 dependencies, sources, facts, The Hague services, scam questions |
| `db/04_demo_and_tests.sql` | Two fictional demo students and example buddies (buddies are no longer shown in the prototype) |
| `db/05_cities.sql` | City-specific services and settings for the 10 cities |
| `app/aankomst.html` | Clickable prototype (one file, opens in any browser) running on data exported from the database |
| `app/native_head.html` | Design layer: brand fonts (embedded Newsreader + Manrope), colours, drawings' styles, motion |
| `tools/native_build.py` | Assembles `app/template.html` from the design layer and the app logic (steps, deadlines, city drawings, sounds) |
| `app/template.html`, `app/content.json` | Generated prototype source and the exported data |
| `app/wild/` | Six experimental concept versions (metro line, goose game, bulb field, polder, cycle route, printout) |
| `tools/build_iphone.py`, `dist/iphone/` | Installable home-screen version (manifest, horizon icons, offline service worker) |
| `sounds/` | Reminder chime, step-done, arrival and wind sounds (WAV and M4A) for real notifications |
| `docs/DESIGN_SYSTEM.md` | Design rules, current version first (v4.4: the horizon brand) |
| `docs/AB_TESTING.md` | Overnight A/B test log (20 Oct) |
| `docs/ARCHITECTURE.md` | Architecture spec: research → feature traceability, system diagram, data model, logic, screens, roles, roadmap |
| `docs/FACT_CHECK.md` | What was corrected or added after checking official sources |
| `build.sh` | Rebuilds the database, runs checks, exports content and builds the prototype |
| `tests/` | Browser tests (Playwright): UI, UX, motion, arrival, cities, iPhone audit |

## Run it yourself

1. Create a free Supabase project (or install PostgreSQL 15+).
2. In the SQL editor, run the four files in `db/` in order.
3. Try it:
   ```sql
   SELECT step_id, state, blocked_by FROM v_user_checklist
   WHERE user_id = '00000000-0000-0000-0000-000000000002' ORDER BY sort_order;
   SELECT * FROM v_user_deadlines;
   SELECT * FROM v_stale_content;
   ```
4. Open `app/aankomst.html` in a browser to click through the prototype.

## Updating content (e.g. next year's CAK fine)

Insert a new row into `fact` with the new `valid_from` date. The old value closes automatically, the change is logged in `content_change`, and every student the step applies to gets an alert in `notification`.
