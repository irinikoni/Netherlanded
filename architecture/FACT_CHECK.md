# Fact-check log – 19 October 2026

The desk research (28 Sep 2026) was checked against official sources before its figures went into the app. Every corrected value is now stored in the database with its source and a `last_verified` date of 2026-10-19.

## Corrected or made more precise

| Topic | Desk research said | Now in the app | Source |
|---|---|---|---|
| CAK fine for being uninsured (2026) | €529.72 (via Study in NL) | **€529.74** (3 × €176.58: average monthly premium €157.00 + expected deductible €19.58). A second fine follows if you are still uninsured three months later. | [CAK – Received a fine](https://www.hetcak.nl/en/uninsured/received-fine/) |
| Municipal registration deadline | "Register if staying longer than four months" | Register **in person within 5 days of arrival** if you stay longer than 4 months | [NetherlandsWorldwide](https://www.netherlandsworldwide.nl/personal-records-database-brp/when-register) |
| Collecting the residence permit | "Must travel to Utrecht" | At a **central IND collection day at the Jaarbeurs in Utrecht**. The university invites you to book once the IND approves. Some students give biometrics first. | [THUAS – Arrival services](https://www.thuas.com/study-choice/international-office/arrival-services) |
| Student finance (DUO) for EU/EEA students | "More than 56 hours per month" | DUO lowered the standard work requirement (from Sep 2023) to **at least 32 hours a month** (or an average of at least 24 hours a month over 6+ months, or earning ≥ 50% of the social minimum norm). | [DUO – Student finance for EU/EEA citizens](https://duo.nl/particulier/student-finance/eligibility.jsp) |
| THUAS registration route | "Fast track with The Hague International Centre" | THUAS and the International Centre offer a fast, simplified registration. Booking instructions arrive by email over the summer. | [THUAS – Arrival services](https://www.thuas.com/study-choice/international-office/arrival-services) |
| Student GPs | Four practice names, no contact details | The Student Doctors (Nieuwe Uitleg 29, online registration) and Praktijk Shams (two practices near Hollands Spoor) now have verified websites | [Study in The Hague – Student GP](https://www.studyinthehague.com/student-gp) |

## Added (missing from the desk research)

- **TB test:** depending on nationality, non-EU students need a TB check at the GGD after arrival as part of their residence permit (chest X-ray, €60, by invitation). Added as an optional non-EU step. Source: [THUAS – Arrival services](https://www.thuas.com/study-choice/international-office/arrival-services).
- **Biometrics:** some non-EU students must give fingerprints and a photo at the IND first. Added to the residence permit step.

## Added after the independent review

- **Student GP details** (Study in The Hague): The Student Doctors offers consults by phone, video, app or in person; Praktijk Shams says about 40% of its patients are students, about 80% of them international; practices ask for personal details, Dutch health insurance and a BSN when you register.
- **Scam check:** questions 1, 3, 6 and 8 rest on research findings (deposit scams, Facebook scams, the BSN dependency, discrimination figures). Questions 2, 4, 5 and 7 are common-sense app guidance and are stored without a source so they are not mistaken for research.
- **Permit deadline** is now marked as advice, not a legal deadline, and the "May to July peak" is attributed to the commercial guide it came from (StudyPath), as the research asks.
- **Loneliness figure** now quoted exactly: about a third often or always felt lonely *or bored* (Nuffic, 2021–22).
- **CAK letter** is now a step for every student, because study-only students can also receive a letter (sometimes in error) and must still act within three months.

## Not re-verified (kept from the desk research, still marked 28 Sep 2026)

- Bank BSN deadline of 90–120 days (sources: EUR, UvA). The app tells students to check their own bank.
- More than 75% of GP practices in The Hague not accepting new patients (Klein et al., 2026, preprint).
- THUAS Housing Service helps about half of incoming students; furnished apartments from about €950 a month.
- Biking Doctors and Huisartspraktijk M. Lachman (Leiden University list). No website found yet.
- HousingAnywhere holding rent until 48 hours after move-in (not used in app content).

These items show up in the database view `v_stale_content` once they are older than 180 days, so they get re-checked.

## Lesson for the project

Even the source the desk research treated as official (Study in NL) was two cents off the CAK's own figure. That is exactly the "outdated information" problem the research describes, and it is why the backbone stores every figure with its source, a validity period and a last-checked date.
