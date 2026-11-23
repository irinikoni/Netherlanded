# Terms of Service and Privacy Policy

*Version 2.2 · 23 November 2026 · Netherlanded prototype*

> Template text written for a student project (Creative Business Solutions, THUAS). It is not legal advice. Have it checked before the app is offered to real users, and fill in the parts in [square brackets].

## Part A – Terms of Service

### 1. Who we are
Netherlanded ("the app", "we") is a guide for first-year international students who are moving to the Netherlands. It is made and run by [trade name], a sole proprietorship (*eenmanszaak*) of [owner name], registered with the KVK under number [KVK number] (details in section 11). Contact: [contact e-mail].

The app is **not an official service** of THUAS, the Municipality of The Hague, the IND, DUO, the CAK or the Dutch government. Content explicitly marked as provided by a participating university is that university's responsibility.

### 2. What the app does
The app shows a personal checklist of arrival steps, works out deadlines, offers a housing scam check, lists local services, can show local browser reminders for your deadlines, uses limited service statistics to find problems and unclear guidance, shared with universities only as disclosure-controlled aggregate reports (section 13a), and, only if you say yes, shares additional statistics with your university (section 13b).

### 3. Information, not advice
We collect information from official and other sources and show where each piece comes from and when we last checked it. Rules, amounts and deadlines change. **Always confirm with the official organisation before you act.** The app does not give legal, financial, immigration or medical advice.

The scam check gives an indication only. A low score does not mean an offer is safe, and a high score does not prove fraud.

### 4. Who can use the app
You must be at least 16 years old. You are responsible for the information you enter and for keeping your device secure.

### 5. Staying safe
**Never send money, ID documents, your BSN or bank details to anyone who contacts you about housing or paperwork** unless you have checked who they are through an official channel. The app will never ask you for these.

### 6. Acceptable use
Do not misuse the app: no false information about other people, no attempts to access other users' data, no automated scraping.

### 7. Links to other services
The app links to websites of government bodies, universities, housing providers and GP practices. We are not responsible for their content or services.

### 8. Liability
We work carefully, but the app is provided "as is". As far as the law allows, we are not liable for damage caused by relying on its content, including missed deadlines, fines or housing losses. Nothing in these terms limits rights you have under mandatory Dutch or EU consumer law.

### 9. Changes and ending
We may update the app and these terms. If a change is important, we tell you in the app at least 30 days before it takes effect. You can stop using the app and delete your data at any time (see Part B).

### 10. Law
Dutch law applies. Disputes go to the Dutch court that is competent by law. If you live in another EU country, you keep the protection of the mandatory rules of that country and can also go to a court there.

## Part B – Privacy Policy

### 11. Who is responsible for your data
**Netherlanded** is run by **[trade name]**, a sole proprietorship (*eenmanszaak*) of **[owner name]**, registered with the Dutch Chamber of Commerce (KVK) under number **[KVK number]**, **[business or correspondence address]**, **[contact e-mail]**. Who is responsible depends on what is being done with the data:

| Processing | Who is responsible (controller) | Netherlanded's role |
|---|---|---|
| Delivering the app, keeping it secure, and the gateway's technical logs | Netherlanded | Controller |
| Collecting the statistics counts and holding them briefly before they are folded into totals (sections 13a and 13b) | Netherlanded **together with** your university, if it is a participating partner (joint controllers, Art. 26 GDPR). Netherlanded alone for students of other institutions | Joint controller |
| Producing your university's own statistics reports | Your university (participating partners only) | Processor, under a SURF Model Data Processing Agreement (Art. 28 GDPR) |
| National benchmarks: anonymous totals across all participating universities, used to improve the app's guidance for everyone and to publish sector-level findings | Netherlanded | Controller |

**The joint-controller arrangement in short.** Netherlanded decides what is counted and how it is protected; your university decides that its own cohort is measured for its reports. Netherlanded gives you this notice, handles your requests and questions, and runs the security and disclosure-control measures. You can still exercise your rights with either party (Art. 26(3) GDPR), and each will pass your request on to the other where needed. The essence of the arrangement is available on request.

Universities without an active agreement receive nothing: for their students, Netherlanded collects only technical error counts, as sole controller.

### 12. What we collect, why, and on what basis

The current app has **no student accounts and no server push notifications**: your checklist answers, progress, and local reminders stay in your browser on your device. (University staff who access the aggregate statistics dashboard or content editor have separate staff accounts governed by a separate staff privacy notice.)

| Data | Why | Legal basis |
|---|---|---|
| Answers to the start questions: EU/EEA or not, institution, city/campus, arrival date, plans to work | To show the steps and deadlines that apply to you | Performance of our service (Art. 6(1)(b) GDPR) |
| Your progress, and dates you enter (first working day, CAK letter) | To track your steps and calculate deadlines | Performance of our service |
| First name and profile photo (optional, stored on device only) | To personalise the app | Consent (Art. 6(1)(a)) |
| App settings: appearance, sounds | To remember how you like the app | Performance of our service |
| Local reminder preferences | To show browser/local deadline reminders on your device if you turn them on | Consent (Art. 6(1)(a)) |
| Scam check answers | To give you an indication on your device. Not stored on a server | Performance of our service |
| Limited service statistics (on unless you object, see section 13a) | To find technical problems and guidance that may be unclear or not working, to give participating universities disclosure-controlled aggregate statistics for improving general onboarding guidance, and to compile anonymous national benchmarks | Legitimate interest (Art. 6(1)(f)). You can object at any time on the notice screen or with the switch in Profile |
| Additional statistics for your university (only if you say yes, see section 13b) | To show universities where new students get stuck, so they can improve support | Consent (Art. 6(1)(a)). Off unless you turn it on. You can withdraw it at any time in Profile |

**Health and sensitive data.** We never ask for or store your BSN, passport or permit number, bank details, medical records, or diagnoses. The checklist includes a broad step category named `health` (general arrival tasks such as Dutch health insurance and finding a GP); only category-level applicability and completion counts are processed, never your personal health details or notes, and `health` category counts are published only in groups of at least 15.

**Whether providing data is required.** No data is required by law or contract. Without the start questions, the app cannot personalise your checklist or deadlines.

**Automated processing.** Deadline calculations and the housing scam check run automatically on your device as general guidance only; they do not produce legal or similarly significant decisions (Art. 22 GDPR).

### 13. Where your data is kept, recipients, and processors
- **Prototype (current version):** your answers, progress, and local telemetry queues are saved in your browser on your device. The prototype does not send statistics to a server unless a server address is configured.
- **Hosted deployment:** aggregate statistics are stored with a hosting provider inside the EU (for example Supabase, EU region) under a signed GDPR Article 28 Data Processing Addendum (DPA), and the static app is served from a web host (such as GitHub Pages, with transfer safeguards verified before launch).
- **Recipients & multi-tenant isolation:** **Participating universities** receive **only** fixed, disclosure-controlled statistics for **their own institution** (never personal profiles, accounts, raw counts, or another school's results). Their agreement forbids any attempt to re-identify students and any use of the statistics for admissions, selection, disciplinary, or other decisions about an individual. **National benchmarks** are compiled by Netherlanded as controller (section 11) from the same counts, pass the same disclosure-control rules, and contain no personal data. Students at institutions without an active agreement generate no institution-level statistics. No other third party receives your data. We never sell your data or use it for advertising.
- **Technical logs (immediate edge IP stripping):** As with any web request, your IP address reaches our EU reverse proxy, which enforces in-RAM rate limits (`30r/m`), **strips all client IP and User-Agent headers before forwarding requests upstream**, and uses internal gateway secrets, checked again inside the database, so the database cannot be reached around the gateway. It writes **zero IP addresses to disk** (technical logs are IP-free and deleted within **24 hours**).

### 13a. Limited service statistics (on unless you object)
**Purpose.** Netherlanded counts limited service statistics to measure the quality and effectiveness of the app, find technical errors or unclear guidance, and compile anonymous national benchmarks. For participating partner universities, the same counts are also used to produce that university's own disclosure-controlled reports, so it can improve its onboarding support (see section 11 for who is responsible for what). Non-partner institutions are excluded from institution-level Tier 1 statistics. The statistics are never used to monitor individual students, make decisions about them, or identify students who need intervention.

- Your phone queues individual aggregate contributions locally and sends them in **weekly shuffled batches** (with no cookies, credentials, or referrer). Each count holds only: the app or content version, your school (rolled up to its parent institution, never campus), your intake semester (for example `2026-sep`), and either a one-time `cohort_joined` marker or a broad step category (`admin`, `housing`, `money`, `health`, `work`, `social`, or `wellbeing`) with `step_applies` / `step_completed`. There is also at most one `technical_error` count per app version.
- **Never included:** name, account, device, installation or session ID, EU/EEA status, `step_id`, exact dates or times, notes, scam-check answers, or missed deadlines. Raw Tier 1 counters are stored with an arrival time rounded to the hour, folded hourly into aggregate cells, and deleted within **24 hours** (`nl.raw_t1`); Tier 1 and Tier 2 are kept in separate database stores and are never joined.
- We tell you about this on its own screen before anything is counted, and counting starts only after that.

**What universities receive.** Only fixed, predefined monthly reports for their own institution and intake semester, checked by a server-side disclosure-control pipeline before release: every result must be based on **at least 15 students**; published counts are **rounded to the nearest multiple of 5**; a change between releases that rests on fewer than about 5 students (under 5 percentage points, or under 5 students' worth on small groups) is withheld and stays withheld for two further releases; very small or very large counts are shown only as a range (for example "fewer than 8 of 20"), and extreme shares (`<= 10.0%` / `>= 90.0%`) have counts, exact rates, and bands redacted; results that could be worked out by subtraction (**complementary suppression**) are withheld; and withheld results are shown to universities only as "withheld", never as counts, sizes, or zeros. Universities get no filters, no ad-hoc queries, and no access to raw counters or logs.

**Legal basis.** Dutch law allows the provider of an online service to measure its quality and effectiveness without prior opt-in consent when the privacy impact is minimal (*Telecommunicatiewet* art. 11.7a(3)(b)); Netherlanded is that provider. Processing rests on legitimate interests (GDPR Art. 6(1)(f)): Netherlanded's interest in a reliable, accurate app and in national benchmarks that improve guidance for all students, and, for participating partners, the university's interest in measuring and improving its onboarding guidance. We have weighed these against your interests in written assessments, available on request. **You can object at any time**, on the notice screen or with the toggle switch in Profile. Objecting stops all counting and deletes the counts on your phone; the app works normally.

### 13b. Additional statistics for your university (only if you say yes)
To help your university improve support for future students, you can choose to share additional statistics. This is **off unless you turn it on**. We ask you once, after you agree to these terms; you can choose yes, no, or decide later, and the app works the same whichever you choose. You can change your choice at any time in Profile, or with the switch **at the end of this Privacy Policy**.

- Nothing extra is counted or kept until you say yes. If you say no, or switch it off later, the app deletes these counts from your phone.
- Like Tier 1, counts are queued locally and sent in **weekly shuffled batches** with no cookies, credentials, or referrer. Each count holds your school, EU/EEA or not, your intake semester, the step, and what happened: joined, arrived, step applies, step opened, step completed, deadline passed (`deadline_missed`), or a scam check done (`high_risk` true or false). **No exact timestamps and no on-time/late timing flags are sent or stored.**
- Tier 2 is stored separately from Tier 1, never joined to it, and passes through the exact same disclosure-control rules in section 13a before any report is published to a university dashboard. Universities cannot see, request, or receive data about individual students or your profile.
- Your internet address reaches the hosting provider only in transient technical logs as described in section 13.

**Legal basis.** Your consent, given to Netherlanded and (if it is a participating partner) your university as joint controllers, both for storing these counts on your phone (*Telecommunicatiewet* art. 11.7a) and for processing them (GDPR Art. 6(1)(a)). Tier 2 counts are included in national benchmarks only as anonymous totals after the same disclosure-control rules. You can withdraw it at any time; this does not affect totals already sent, which cannot be linked to you.

Because stored aggregate outputs meet the disclosure-control thresholds and cannot be linked back to you, published reports are anonymous. (Transient IP addresses in gateway logs and raw events prior to folding and deletion are treated as personal data until deleted.)

### 14. How long we keep it
- **On-device checklist, preferences, and local telemetry queues:** kept in your browser until you clear them (*Profile → Delete all data*), or until a queued batch is sent or you object/withdraw consent.
- **Raw Tier 1 incoming counter events (`nl.raw_t1`):** folded hourly into aggregate cells, deleted 1 hour after folding, and **never kept past 24 hours**.
- **Raw Tier 2 incoming counter events (`nl.raw_t2`):** folded hourly into aggregate cells, deleted 1 hour after folding, and **never kept past 48 hours**.
- **Release staging cells (`stage_cell`):** kept for up to **90 days** for debugging.
- **Published disclosure-controlled snapshots (`snapshot`):** kept for **3 years** (1,095 days) to compare intakes.
- **Unmapped step-key dictionary (`unmapped_value`):** kept for **400 days**.
- **Anonymised aggregate totals (`accumulated_cell`):** retained indefinitely for multi-intake comparison (contains no personal data).
- **Reverse-proxy gateway technical logs:** client IP addresses and User-Agent headers are stripped in RAM before upstream forwarding (0 seconds stored on disk); IP-free request logs are deleted within **24 hours**.

### 15. Your rights
You can view or copy everything stored on your device (*Profile → See my data*, including your local telemetry queues), delete all local data (*Profile → Delete all data*), object to Tier 1 statistics, and withdraw Tier 2 consent at any time (*Profile → Privacy & legal*). For anything else, e-mail Netherlanded at [contact e-mail]; this is also the contact point for requests about your university's reports, which we pass on where needed (section 11). We reply within one month.

If you are unhappy with how we handle your data, you can complain to the Dutch Data Protection Authority (*Autoriteit Persoonsgegevens*).

### 16. Security
We collect as little as possible, reject any identity fields (`session_id`, `user_id`, `device_id`, `ip`, etc.) at ingest, and use encrypted connections and access control in the hosted deployment. On your device, anyone with access to your device and browser could see what you entered.

### 17. Cookies and tracking
The app uses no advertising or tracking cookies and loads no third-party fonts or third-party analytics. The app uses your browser's local storage only to remember your own answers and settings, and—unless you objected (Tier 1) or declined (Tier 2)—to hold the local statistics queues prior to weekly batch upload, along with your choices.

### 18. Changes
If we change this policy, we update the date at the top and tell you in the app (at least 30 days in advance for important changes).
