# Data Protection Impact Assessment (DPIA) — Netherlanded

*Skeleton v0.1 — 23 November 2026. Built from the legal research session of 23 Nov 2026
(AVG/UAVG, Telecommunicatiewet, GDPR, WP248rev.01, AP mandatory-DPIA list) and the project's
own documents. **Not legal advice.** Before any pilot this document must be completed,
reviewed by Dutch counsel, and signed by the named controller and the partner university's
privacy officer (FG) — open gate `LEGAL_DELTA.md` #7, `COMPLIANCE_CHECK.md` #13,
`RELEASE_CHECKLIST.md`.*

> **Status: SKELETON.** Everything marked `[TODO]` still has to be filled in, decided, or
> signed. Sections pre-filled with facts are drawn from `netherlanded-app.html` (TERMS_V 2.2),
> `db/001–009`, `web/`, `DISCLOSURE_CONTROL.md`, `PRIVACY_ASSESSMENT.md`,
> `LEGITIMATE_INTEREST_ASSESSMENT.md`, and the research notes of 23 Nov 2026.

---

## 0. Administrative details

| Field | Value |
|---|---|
| Controller | `[TODO: legal name of the eenmanszaak + KVK number + contact address — placeholders still open in TERMS_AND_PRIVACY.md; Art. 13(1)(a)]` |
| Processor(s) | Supabase (EU region) — DPA drafted, **not signed**; GitHub (Pages hosting) — DPA + DPF/SCCs to document |
| Recipients / joint controllers | Participating universities — Art. 26/28 arrangement drafted, **not signed** (`COMPLIANCE_CHECK.md` #15) |
| FG / DPO | `[TODO: assess Art. 37(1)(b) "regular and systematic monitoring on a large scale" at pilot scale; WP243; THUAS FG to confirm university data-sharing]` |
| Date / version | 23 November 2026 — skeleton v0.1 |
| Systems in scope | PWA `netherlanded-app.html` v2.2, `sw.js`, Nginx edge gateway, Supabase Postgres (`db/`), dashboards (`web/`), release pipeline |

## 1. Why a DPIA is required (Art. 35(1), 35(3); WP248rev.01; AP list BWBR0042812)

Art. 35(1) requires a DPIA where processing is likely to result in a high risk, in
particular when using new technologies. WP248rev.01: generally **two or more** of the nine
criteria below trigger a DPIA.

| # | WP248 criterion | Applies to Netherlanded? | Evidence |
|---|---|---|---|
| 1 | Evaluation or scoring of data subjects | No | No profiling of individuals; aggregates only |
| 2 | Automated decisions with legal/significant effect (Art. 35(3)(a)) | No | Art. 22 not engaged; no automated decisions about students |
| 3 | **Systematic monitoring** | **Yes** | Tier 1/Tier 2 telemetry events on every app use |
| 4 | Sensitive / highly personal data | Partially | No Art. 9 data by design, but see risk R4 (inference) |
| 5 | Large-scale monitoring of public areas (Art. 35(3)(c)) | Not literally | Not a public area; large-scale assessed below |
| 6 | **Matching / combining datasets** | **Yes** | Telemetry events × institution × intake-semester cohort attributes |
| 7 | **Vulnerable data subjects** | **Yes** | Students; minimum age 16 (UAVG art. 5), so under-18 minors may use the app |
| 8 | **Innovative use / new technology** | **Yes** | Custom aggregation + 6-rule disclosure-control pipeline |
| 9 | Processing preventing exercise of a right/service | No | App fully usable with both tiers off |

Large-scale factors (WP248): number of data subjects across institutions, volume of events,
duration/permanence of processing, geographic extent — `[TODO: fill in pilot numbers]`.

**AP mandatory list** (Besluit lijst verplichte DPIA, BWBR0042812): check the current list —
the AP treats education-sector learning analytics as high-risk; large-scale processing and
systematic monitoring are on the list. Education-sector sectorbeeld Onderwijs applies.

**Conclusion:** a DPIA is very likely **mandatory** (criteria 3, 6, 7, 8 + large scale).
It must be completed **before** any processing with real students starts (Art. 35(1);
EDPB position). If residual risk remains high after measures, **Art. 36 prior consultation
with the AP** is required (see §7).

## 2. Systematic description of the processing (Art. 35(7)(a))

### 2.1 What the app does
- Single-file PWA, no accounts, no cookies, no third-party requests; strict CSP
  (script-src hash only); service worker caches only the app shell; checklist data stays
  in the user's own `localStorage`.
- Device storage/access (localStorage queues, SW cache) is covered by the
  technique-neutral **Telecommunicatiewet art. 11.7a** "cookie rule".

### 2.2 Data flows and categories

| Flow | Data | Where | Retention |
|---|---|---|---|
| Checklist (user's own content) | Steps, notes, deadlines | Device `localStorage` only | Until user deletes |
| Tier 1 `nl-basic` queue (default-on notice screen; objection recorded) | App/content version, institution (rolled up, never campus), intake semester, one `cohort_joined` or broad category × `step_applies\|step_completed`, ≤1 `technical_error`/version | Device queue → edge → `nl.raw_t1` → hourly fold → aggregate | Raw purged 1h after fold, hard ceiling 24h |
| Tier 2 `nl-stats` queue (strict opt-in consent, withdrawable) | + EU/EEA region, `step_id`, events (`joined/arrived/step_applies/step_opened/step_completed/deadline_missed/scam_checked+high_risk`); no timestamps, no `on_time` | Device queue → edge → `nl.raw_t2` → hourly fold | Raw ceiling 48h; staging 90d; snapshots 3y; aggregates indefinite |
| Edge gateway | Strips IP/UA in RAM (0s IP on disk); IP-free logs ≤24h target; per-IP 30 r/m; gateway secret re-checked in DB (`nl.check_ingest_gateway`), fail-closed; ingest rejects identity fields with SQLSTATE `22023` | Nginx edge | Logs ≤24h (7d gateway logs) |
| Published university snapshots | Aggregates under 6-rule disclosure control (floor ≥15, secret cell-key noise ±4, round-to-5, carry-forward <5, 2D complementary suppression, tail redaction) | Dashboard (`web/`) | Snapshots 3 years |
| Staff (university editors/dashboard users) | E-mail, sign-in logs, change log | Supabase auth / dashboard | `[TODO: state period; staff notice needed — Art. 13]` |

### 2.3 Recipients and transfers (Ch. V)
- Supabase: EU region pin; DPA/SCCs + TIA — `[TODO: execute DPA, write TIA]`
- GitHub Pages (hosting): US request-metadata logs; GitHub LLC is EU-US DPF-certified +
  SCCs — `[TODO: TIA; keep personal data out of URLs/repo; `frame-ancestors` cannot be set
  via meta on Pages — open audit finding]`
- Universities: receive only disclosure-controlled anonymous snapshots —
  `[TODO: sign Art. 26/28 agreements]`

## 3. Purposes and legal bases (Art. 35(7)(b))

| Purpose | Legal basis | Status |
|---|---|---|
| Strictly necessary device storage (app shell, user's own checklist) | Tw 11.7a(3)(a) (strictly necessary) | OK |
| Tier 1 "limited service statistics" | Tw 11.7a(3)(b) low-impact analytics exception + GDPR Art. 6(1)(f) (LIA in `LEGITIMATE_INTEREST_ASSESSMENT.md`) | ⚠️ **Contested once Tier 1 feeds university reports** — AP reads 11.7a(3)(b) as limited to the provider's *own* service; default-on then invalid (*Planet49*; EDPB 1/2024: legitimate interest cannot substitute for consent). `[TODO: FG written confirmation, else fallback: Tier 1 Netherlanded-only or opt-in]` |
| Tier 2 "additional statistics" | Tw 11.7a + GDPR Art. 6(1)(a) consent (separate screen, equal choices, easy withdrawal via Profile) | Design valid per EDPB 05/2020; `[TODO: consent records per Art. 7(1)]` |
| Service operation / security | Art. 6(1)(f) / 6(1)(c) as applicable | `[TODO: spell out per purpose]` |

## 4. Necessity and proportionality (Art. 35(7)(b))

- No identifiers are collected or stored by design — T1/T2 queues never contain names,
  e-mails, student numbers, IPs, device IDs, or local queue IDs (never sent).
- Data minimisation verified: identity fields hard-rejected at ingest (`22023`);
  T1/T2 never joined in one table; no timestamps or `on_time` flags; hour-truncated
  arrival; shuffled daily batches (plus one send when the checklist is finished), with
  `credentials:'omit'`, `referrerPolicy:'no-referrer'`, and on-device queue retention
  capped at ~30 hours by the same schedule.
- `[TODO: proportionality argument per purpose — why less intrusive means (e.g. no
  telemetry at all, on-device only) were rejected]`

## 5. Risk register — risks to the rights and freedoms of data subjects (Art. 35(7)(c))

| ID | Risk | Source | Likelihood | Impact | Rights affected |
|---|---|---|---|---|---|
| R1 | **Small-cell re-identification** in published snapshots | `DISCLOSURE_CONTROL.md` § residual; WP216 singling-out/linkability | `[TODO]` | High | Art. 8 GDPR / privacy |
| R2 | **Repeated-release noise averaging**: attacker changes cell content before each monthly snapshot, averages fresh noise draws over many releases | `DISCLOSURE_CONTROL.md` — "the DPIA must state it" | Medium (slow, visible) | High | Re-identification |
| R3 | **Count inflation / no de-duplication**: no identifiers → reinstall, repeat send, or fabricated events can push a cell past the floor or skew a rate | `DISCLOSURE_CONTROL.md` — "the DPIA must state this residual risk" | Medium | Medium | Accuracy of statistics; indirect identification |
| R4 | **Art. 9 inference** from Tier 2 step-level events (e.g. health-category step patterns could reveal health status) | *OT v VTEK* C-184/20; *Lindenapotheke* C-21/23 | Low (no identifiers + 48h purge) | High | Art. 9 special categories |
| R5 | **Tier 1 default-on unlawful** if Tw 11.7a(3)(b) exception does not cover university-facing reports → no valid basis, no valid consent (*Planet49*) | AP enforcement (Kruidvat €600k; systematic cookie scans since Apr 2025) | Medium | High | Art. 6/7 validity; Tw 11.7a |
| R6 | **Breach of raw telemetry** in the 24h/48h window before purge | Art. 33; WP250 | Low (RLS, fail-closed, IP stripping) | High | Confidentiality |
| R7 | **Staff personal data** (editors/dashboard users) insufficiently protected/noticed | `COMPLIANCE_CHECK.md` #14 | Medium | Medium | Staff privacy |
| R8 | **Third-country transfer** exposure: GitHub Pages US logs; Supabase sub-processors | Ch. V; *Schrems II*; Recs 01/2020 | Low | Medium | Transfer safeguards |
| R9 | **Background-knowledge re-identification** by universities (enrolment data) of cohort aggregates | Recital 26; EDPS v SRB C-413/23 | `[TODO]` | Medium | Anonymity of reports |
| R10 | `[TODO: add risks found in review]` | | | | |

## 6. Measures to address the risks (Art. 35(7)(d))

| Risk | Existing measures (verified) | Open actions before pilot |
|---|---|---|
| R1 | 6-rule disclosure-control pipeline, pre-publish audit, human people-check; pentest: n-1 flooding 1.00 → 0.556, snapshot-diffing 20/20 → 0/40 | Run SQL suites on live Postgres (`tools/run_pg_tests.py`, 106/106) |
| R2 | Monthly cadence, carry-forward <5, gateway-only ingest, per-IP limits | State explicitly in DPIA final; monitor release logs |
| R3 | Gateway-only ingest, `22023` identity rejection, per-tier circuit breaker, human check | Document residual in final DPIA |
| R4 | No identifiers; 48h purge; broad categories only at Tier 1 | Address inference scenario in final DPIA (research session flag) |
| R5 | Tier 2 valid consent design; Tier 1 objection recorded | **Decide Tier 1**: FG written confirmation of 11.7a(3)(b), else Netherlanded-only or opt-in; sign LIA |
| R6 | RLS + explicit revokes, fail-closed gateway, DB-side secret re-check, IP stripped in RAM, pentest 46/46 | Breach runbook + register (Art. 33/34, 72h meldloket) — `[TODO]` |
| R7 | — | Staff Art. 13 notice; state retention for staff logs — `[TODO]` |
| R8 | Supabase EU region; GitHub DPF-certified | Execute DPAs; write TIAs (Supabase, Pages); resolve `frame-ancestors` |
| R9 | Region/municipality-level only rolled-up institution; floor 15 | `[TODO: assess with FG]` |
| All | Art. 32 security measures; strict CSP; no cookies/trackers | Keep pentest cadence on db/edge changes; revoke legacy HS256 secret (P13) |

## 7. Residual risk and Art. 36 decision

- `[TODO: after §6 measures, assess residual risk per risk R1–R10.]`
- If residual risk remains **high** → **prior consultation with the AP (Art. 36)** before
  processing starts. `[TODO: decision + rationale, recorded here.]`
- Note: the AP can also require a DPIA case-by-case (Art. 35(4)); ICS was fined partly for
  missing DPIA.

## 8. Review, accountability and sign-off

- **Review duty (Art. 24(1))**: review this DPIA when the risk profile changes — new tier,
  new data field, new recipient, accounts added, scale-up, new transfer, incident.
  `[TODO: assign owner + review date]`
- Accountability records to keep alongside (Art. 5(2)): ROPA (Art. 30 — the <250-employee
  exemption does **not** apply), LIA, consent records, Art. 28 DPAs, TIAs, breach register,
  DSR log.

| Role | Name | Signature | Date |
|---|---|---|---|
| Controller (eenmanszaak, `[TODO]`) | | | |
| Dutch counsel | `[TODO]` | | |
| University FG (THUAS) | `[TODO]` | | |
| DPO (if appointed per Art. 37) | `[TODO]` | | |

## 9. References

- GDPR Art. 35/36: https://eur-lex.europa.eu/eli/reg/2016/679/oj · UAVG: https://wetten.overheid.nl/BWBR0040940 · Telecommunicatiewet art. 11.7a: https://wetten.overheid.nl/BWBR0009950
- WP248rev.01 (DPIA): https://ec.europa.eu/newsroom/article29/items/611236/en · WP216 (anonymisation), WP250 (breaches), WP243 (DPOs), WP217 (LIA)
- AP mandatory-DPIA list (BWBR0042812): https://www.autoriteitpersoonsgegevens.nl/documenten/lijst-verplichte-dpia · AP DPIA page: https://www.autoriteitpersoonsgegevens.nl/themas/basis-avg/praktisch-avg/data-protection-impact-assessment-dpia · ICS fine (Art. 35 violation)
- EDPB 05/2020 consent · 1/2024 Art. 6(1)(f) · 2/2023 ePrivacy 5(3) · Recs 01/2020 TIAs
- CJEU: *Planet49* C-673/17 · *Fashion ID* C-311/18 · *OT v VTEK* C-184/20 · *Lindenapotheke* C-21/23 · EDPS v SRB C-413/23 · *Schrems II* C-364/19
- EU-US DPF: Decision (EU) 2023/1795 + https://www.dataprivacyframework.gov/list · SCCs: Decision (EU) 2021/914
- Internal: `PRIVACY_ASSESSMENT.md` · `LEGITIMATE_INTEREST_ASSESSMENT.md` · `DISCLOSURE_CONTROL.md` · `COMPLIANCE_CHECK.md` · `LEGAL_DELTA.md` #7 · `TERMS_AND_PRIVACY.md` v2.2 · research notes (legal research session, 23 Nov 2026)

*Skeleton prepared for planning purposes only — not legal advice. Complete, review and sign
before any pilot with real students.*
