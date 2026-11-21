# Netherlanded: source

The app as source files, with a build, a content export from the database, and automated tests.
Before 13 November 2026 the app existed only as one 500 KB page; this folder is that page taken apart.

## Layout

| Folder | What is in it |
|---|---|
| `src/index.html` | The page shell. `{{css:…}}`, `{{js}}`, `{{content}}` and `{{legal}}` mark where the build puts things |
| `src/css/` | 30 style files, in the order they apply. `05-fonts.css` is the two embedded fonts |
| `src/js/` | The script in 18 parts, joined in name order into one function. `00-core.js` opens it, `99-end.js` closes it |
| `src/site/` | Only for the hosted site: page head, service worker, content loader, web app manifest, icons |
| `content/` | Generated from the database. Do not edit by hand |
| `database/` | The SQL files, 01 to 27. 17, 19 and 26 are what the server needs |
| `infra/` | Server functions, Supabase settings and setup steps. Start with `infra/README.md` |
| `.github/workflows/` | `ci.yml` (all checks), `deploy-backend.yml`, `deploy-site.yml` |
| `dashboard/` | University dashboard prototype: the page, and `data.json` with the fictional intake |
| `editor/` | Editor panel prototype |
| `tools/` | `build.py`, `export_content.py`, `build_pages.py` (dashboard and editor), `demo_intake.py` (fictional data), `make_migrations.py` (database files → Supabase migrations) |
| `tests/` | Browser tests (pytest + Playwright) and `run_sql.sh` for the database checks |
| `dist/` | Build output |

## Commands

```
python3 tools/export_content.py      # database -> content/*.json   (needs psql; set DATABASE_URL)
python3 tools/build.py               # src + content -> dist/
python3 tools/build_pages.py         # dashboard + editor -> dist/dashboard.html, dist/editor.html
python3 tools/demo_intake.py         # FICTIONAL intake through insights.ingest() -> dashboard/data.json
python3 -m pytest tests -q           # 55 browser tests, about two minutes
python3 tools/make_migrations.py --check   # a clean live database exports the committed content
deno test -A infra/tests/            # the three server functions (needs Deno and the test databases)
tests/run_sql.sh                     # rebuild both databases and run every SQL check
```

Needs Python 3.10+, `pip install pytest playwright`, `python -m playwright install chromium`, and PostgreSQL 16 for the database parts.

## What the build makes

- **`dist/site/`**: the hosted web app. Put this folder on any static host. It has the service worker (opens offline), the web app manifest (installs to the home screen) and `content/` next to `index.html`.
- **`dist/netherlanded.html`**: one self-contained file with no network needs, for sending or opening from disk.
- **`python3 tools/build.py --fragment "Netherlanded Demo" out.html`**: the page without `<html>` and `<head>`, for publishing as a claude.ai artifact. The Demo and Preview links are made this way.

## How content reaches a phone

1. An editor changes a step, figure or service in the database.
2. `export_content.py` rewrites only the content files that changed, and `manifest.json` with a fingerprint per file.
3. Those files go to the host. No new build of the app is needed.
4. On its next open the app reads `content/manifest.json`, downloads only the files whose fingerprint changed, and keeps them on the phone.
5. The open after that shows the new content. A toast tells the student it is ready.

The page always carries a full copy of the content from build time, so a first open, an offline open or a broken download still shows a complete app. Downloaded content is thrown away when a newer build is installed, because that build's own copy is at least as new.

## The three prototypes around the app

| Prototype | Where | What is real | What is a stand-in |
|---|---|---|---|
| Anonymous counters | `src/js/15-anonymous-totals.js`; in the app under Profile → Terms & Privacy → "See exactly what is shared" | The counters have the exact shape `insights.ingest()` accepts. A test posts them and the real function accepts every one | No server address is set, so nothing leaves the phone |
| University dashboard | `dashboard/` → `dist/dashboard.html` | The figures are what the insights database returned after the weekly snapshot, including the hidden small groups | The intake is fictional (`tools/demo_intake.py`). The sign-in is a dropdown |
| Editor panel | `editor/` → `dist/editor.html` | Loaded with the real content export. It names the content files each change would rewrite, by the same rule as the export | Changes stay in the browser. Nothing is written to the database. The sign-in is a dropdown |

The counters are made and sent only if the student said yes to sharing, the terms are agreed, the plan is not the sample plan, and the school is a listed one. Each counter is produced once per phone and is never taken back. (Since the final-legal build of 18 Nov, counters carry the intake semester; the counter test against `ingest()` needs `ingest()` updated to match.)

To run the counter test against the real function, set `INSIGHTS_DATABASE_URL` before `pytest`; without it that one test is skipped.

## Rules that keep this working

- **Content is edited in the database, never in `content/`.** CI fails if `content/` differs from a fresh export.
- **A new script part goes in `src/js/` with a number** that puts it where it belongs. Everything shares one function scope, as before; nothing is a module.
- **Database files run in this order:** 01, 02, 03, 05, 04, 08, 12, 13, 15, 17 on the app database; 06, the reference rows, 09, 19 on the insights database. `tests/run_sql.sh` is the reference. A live database skips 04 (fictional students); `tools/make_migrations.py` holds that list.
- **The database writes the content files' text.** `content_files()` returns each file byte for byte, so the build script and the server's publish function cannot drift apart.

## The hosted site's settings

`tools/build.py` reads two optional environment variables for the hosted site:

| Variable | Effect |
|---|---|
| `NL_INGEST_URL` | Where counters are sent. Unset: they stay on the phone |
| `NL_CONTENT_BASE` | Where content files are fetched from (the content bucket). Unset: the site's own `content/` folder |

The hosted page also carries a Content-Security-Policy: it may only talk to its own address and these two.
A reminder's link ends in `#step-<id>`; opening it opens that step.

## Not done yet

- **Nothing is deployed.** The server code in `infra/` is tested here against PostgreSQL, never on Supabase. `infra/README.md` lists what is unverified.
- **No student accounts.** Progress lives on the phone. Reminders by push or e-mail need accounts first.
- **The editor panel and dashboard are not connected** to the database functions written for them (`editor_*`, `dash_*`).
- **Counter flooding is limited, not prevented.** `ingest` has a per-source limit (memory only) and database limits per minute and per school (`database/21`). They cap the damage; they cannot tell a fake counter from a real one.
- New content applies on the next open, not immediately.
- The app shows a city theme for 11 cities. The export covers 18 study cities; the other 7 work but use the default colours and skyline.
- The older test suites in the team's own `tests/` folder were not available here and are not part of this folder.
