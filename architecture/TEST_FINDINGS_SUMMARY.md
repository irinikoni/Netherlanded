# Netherlanded: tests, findings and fixes (summary)

*23 November 2026. Branch `ccr-a7d69b39-0qxsiv`. Not legal advice: have counsel confirm the legal points.*

## 1. Test suites (final results)

| Suite | What it checks | Result |
|---|---|---|
| `tools/run_pg_tests.py` | Database: migrations, roles and row-level security, privacy rules, editor scoping, concurrency, plus Supabase's default grants simulated | 106/106 |
| `tools/test_suppression.py` | Python reference model of the privacy rules, plus static checks | 64/64 |
| `tools/verify_build.py` | Build, CSP hash, SQL, dashboard and editor checks | 163/163 |
| `edge/tests/edge.test.ts` | Edge functions (Deno): CORS, secrets that fail closed, body limits, error mapping, which headers are forwarded | 26/26; type-check clean |
| `tools/pentest/sdc_attacks.py` | Privacy attacks: reconstruction by integer programming, snapshot comparison, benchmark subtraction | Pass |
| `tools/pentest/n1_flooding.py` | Fake-student ("n-1") flooding attack, measured over many trials | Attacker accuracy ≈ 0.53–0.56 (a coin flip is 0.50) |
| `tools/pentest/scale_test.py` | Release time at national scale (50 institutions, about 21,000 cells) | 1.4 s (fails above 10 s) |
| `tools/pentest/release_fuzz.py` | Random multi-release scenarios: a release never fails its own audit, floors hold, carry-forward is correct, no school sees another's rows | All properties hold |
| `tools/pentest/rpc_fuzz.py` | Random and near-valid JSON sent to the ingest and editor database functions | 0 unmapped error codes |
| `tools/pentest/gateway_test.py` | End to end: client → Nginx (repo config, TLS) → stand-in Supabase gateway → real edge functions → database | 32/32 |
| `tools/pentest/browser_test.cjs` | Playwright: third-party requests, CSP, HTML injection through stored and API data, corrupted storage, staff tokens, Tier 1 and Tier 2 screens | 29/29 |
| `tools/pentest/plpgsql_lint.py` | `plpgsql_check` static analysis of all database functions | 0 errors |
| `tools/pentest/semgrep_rules.yml` | Project rules: dynamic code, unescaped HTML, credentialed fetch, logging in edge functions | 8 hits, all safe on review |
| detect-secrets + git history scan | Secrets in the current files and in every commit | No real secrets |
| `tools/mutation_check.py` | Breaks 39 protections one at a time to confirm a test notices each | 37 caught, 2 can't change behaviour (no test can catch them), **0 missed** |
| `tools/pentest/supabase_stack_test.py` (GitHub Actions: `pentest-supabase.yml`) | The **real Supabase stack** (Kong, PostgREST, GoTrue, edge runtime) with the intended production settings: API exposure, tokens, logins, edge functions, Schemathesis fuzzing | **46 pass, 0 fail**, 8 info (run 3) |

CI runs everything except the mutation check (it takes about 10 minutes), the browser test (needs Playwright) and `plpgsql_check` (needs the system PostgreSQL extension). The real-Supabase pentest runs in its own workflow whenever `db/`, `edge/` or its test file changes, and can also be started from the Actions tab.

### Real Supabase stack: what it confirmed (run 3, https://github.com/irinikoni/Netherlanded/actions/runs/45175166861)
- **Setup:** PostgreSQL 17.12 and PostgREST 14.1, with our migrations applied as Supabase's real `postgres` role. So Supabase's actual default grants apply.
- **PostgREST:**
  - The anon key's API description for `nl` lists only the two ingest functions.
  - `nl_content` and the system schemas (`auth`, `pg_catalog`, `information_schema`, `extensions`, `storage`) aren't exposed.
  - The anon key can't read any `nl` or `nl_content` table.
  - It can't read, insert into or delete from `institution_campuses`. **P1 holds under the real grants.**
  - Direct ingest is refused without the gateway secret.
  - GET is refused on write functions.
  - Three batches of 100 sent in one request inserted only 100 events.
  - Unexpected parameters are rejected.
- **Supabase logins:**
  - Public signup is off.
  - A real reader sees only their own report, including over GET.
  - A user can change their own `user_metadata`, but the database ignores it. Changing `app_metadata` is refused (403).
  - All of these tokens are rejected: a real ES256 token with a forged `super_admin` payload, an unsigned (`alg none`) token, a wrong-secret token, an expired token, and one claiming the `postgres` role. An HS256 control token was accepted, which proves the last two rejections are real.
  - A leaked service key can't read reports, use the editor or reach the `nl` schema.
- **Edge functions through Kong:**
  - Ingest works without a login token, and is refused without the proxy secret or from a foreign origin.
  - Stats returns only the reader's own report, and requires a token.
- **Schemathesis:** 342 cases as anon (3 operations) and 667 as a reader (5 operations), no server errors. Most generated inputs are rejected at validation, so deep input fuzzing stays with `rpc_fuzz.py`.
- **Getting it running took two fixes:** run 1 exposed our schemas before they existed. Run 2 passed, but two token checks could have passed for the wrong reason, and Schemathesis's coverage couldn't be confirmed. Run 3 added the control test, the forged-payload test and coverage reporting.

## 2. Findings and fixes

### Critical and high
| # | Finding | Fix |
|---|---|---|
| P1 | Supabase grants new `public`-schema tables to the anon role by default. `institution_campuses` had no row-level security, so anyone with the public anon key could give themselves shared-city edit rights. | Row-level security enabled and explicit revokes; privilege tests now run with Supabase's defaults simulated |
| P2 | Fake-student flooding: fake events placed at a rounding boundary revealed one real student's status with certainty. | Cell-key noise (±4, secret, the same every time for unchanged data): attacker accuracy fell from 1.00 to 0.556 |
| P6 | Snapshot comparison: the rate-only change rule leaked changes of 1–4 students (20 of 20 rounds), and withholding a cell also signalled a change. | Carry-forward, as the policy already said: show the previous value until changes add up to 5 (0 of 40 rounds) |
| — | Editor `city_id` bypass: a shared-city card could be filed through an editable municipality. | Both the city and the municipality must be editable |
| — | The edge proxy secret failed open when unset; the anon key could reach the ingest database functions directly. | Fails closed; database-side gateway secret check (`nl.check_ingest_gateway`) |

### Medium
| # | Finding | Fix |
|---|---|---|
| P3 | A benchmark pooled across only two schools let each school subtract its own figures and recover the other's. | At least 3 institutions, plus a dominance rule; checked at release time and again in the pre-publish audit |
| P7 | Sticky livelock: two cells could be stuck hidden forever (an older bug). | Sticky rule retired |
| P8 | Release time grew quadratically: 32 s at national scale. | Rewritten query: 1.4 s |
| P4 | Backups contradicted the policy's "raw data never kept past 24 hours". | Policy §14 now names the backup window ([7] days, placeholder); checklist item to set the real value |
| P12 | Consent didn't mention benchmarks; the in-app IP-address text contradicted the policy. | Option A consent wording and a corrected IP sentence (see §3) |
| — | Rounding down skewed every published rate downward (19/20 was published as 75%). | Round to the nearest 5 |
| — | Overwrite race in the editor's service upsert. | Advisory lock plus `FOR UPDATE` |

### Low
| # | Finding | Fix |
|---|---|---|
| P5 | One gateway hash, so rotating the secret meant an outage. | Up to two active hashes; rotation procedure documented |
| P9 | Nginx disclosed its version, forwarded client cookies and a client-supplied gateway header, and used default TLS settings. | `server_tokens off`, explicit TLS 1.2/1.3, headers stripped |
| P10 | Malformed Unicode in ingest came back as 502; malformed editor dates gave unclear errors. | Every upstream 400 maps to `invalid_payload`; strict date parser (`_parse_date`) |
| P11 | Deployment checklist named edge functions that don't exist and said to turn off login checks on all of them. | Corrected: only `ingest` uses `--no-verify-jwt` |
| P13 | Real Supabase: tokens signed with the old HS256 secret are still accepted alongside the new ES256 keys, so anyone holding that secret could mint valid tokens. | Open (deployment): revoke the legacy JWT secret once everything uses the new keys; in the release checklist |
| — | Also fixed: unused `n` field and `high_risk` misuse now rejected; rate limit counts events, not requests; exact timestamps truncated to the hour; editor echoed raw database errors; `http://` links allowed. | Each fixed and tested |

### Weak or vacuous tests found and fixed
- First mutation run: 11 of 32 protections had no test that noticed when they broke. 12 tests added.
- Three existing tests could never fail: the dominance test was dominated on both counts; the size-bucket test ran on a snapshot with no withheld cells; the https test only covered service URLs.
- The first browser test was vacuous: the attack text was cut off before reaching the page, and one test followed a link and checked the wrong page. It now requires the attack text to be visibly shown as plain text.

## 3. Product and legal changes driven by the tests
- **Tier 1 notice:** a switch that's on by default (legitimate interest) and a single Continue button; switching off records an objection. Placed above Continue so it's visible on a phone (Art. 21(4)).
- **Tier 2 consent (option A):** "Share additional statistics", naming both purposes (your own university, groups of 15+; national comparisons across at least 3 institutions), with an explicit choice.
- **Controller split:** written into the policy (§11) and `DISCLOSURE_CONTROL.md` §8. Netherlanded (eenmanszaak) is controller for the app, logs and benchmarks; joint controller with each partner for collection; processor (SURF Model DPA) for each university's own reports.
- **Sales pitch:** led by "your dashboard is in the contract"; the revenue arithmetic in the business case was corrected.

## 4. Still open
- **Your decision:** limit Tier 1 benchmark use to improving the app (the analytics exception, Tw 11.7a(3)(b)); base public or sector reporting only on Tier 2.
- **Blocked tests** (real PostgREST and Supabase logins are now covered by the GitHub Actions workflow):
  - A hosted staging project: platform logs containing IPs, and the real backup window.
  - Capturing the daily statistics batch in the browser (also fires automatically on checklist completion).
- **Before launch:**
  - Set `NL_PROXY_SECRET` / `NL_INGEST_SECRET` and the `nl.ingest_gateway` row.
  - Match the hosted Supabase project to the tested settings: `nl` and `nl_content` exposed, public signup off, `ingest` without JWT verification, `stats` and `editor` with it. Then revoke the legacy JWT secret (P13).
  - Replace the [7]-day backup placeholder and the KVK placeholders.
  - Counsel review; DPIA; the independent third-party pen test.
