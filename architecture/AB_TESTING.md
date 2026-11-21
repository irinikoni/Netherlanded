# Overnight A/B testing log · 20 October 2026

Method: each round compared the current best version against one new variant. Three independent reviewer agents judged blind (labels X/Y, order swapped between rounds) from screenshots of 12 screens on an iPhone 15 Pro-sized display (light and dark): an anxious first-year international student reading English as a second language, a WCAG 2.2 / Apple HIG accessibility specialist, and a senior iOS product designer. Majority vote decided; the winner became the baseline. Principles applied: Norman, Shneiderman's golden rules, Krug, Laws of UX (Von Restorff, Miller, Hick, Fitts, aesthetic-usability), Universal Principles of Design, WCAG 2.2.

| Round | Variant tested | Result | Lesson |
|---|---|---|---|
| 1 | Filled "Open step" button, green pills, darker text | Lost 0–3 | Emphasis through filled blocks reads as busy |
| 2 | Quiet emphasis: bigger Up next title + tint outline, done steps collapse to one line, darker grey, tinted Yes/No | Won 3–0 | Weight and size beat fills |
| 3 | Tick glyphs on Yes/No, chevron on header link, larger text | Lost 0–3 | Extra glyphs add noise |
| 4 | Outline on selected answer (not colour alone), quieter subtitle, school abbreviation first | Won 3–0 | Non-colour state cue wins |
| 5 | School shows only abbreviation, amber Yes, darker grey, consistent "Due in" wording, soft card edges | Won 2–1 | Red read as alarm; amber calmer |
| 6 | Flat done rows, roomier cards, darker tab labels, "'Yes' means a warning sign" hint, "Sample plan" wording | Won 3–0 | Plain-language hints help |
| 7 | Neutral iOS Yes/No, tinted flat banner, bold due dates | Won 2–1 | Banner + bold meta liked; neutral Yes/No disliked |
| 8 | v7 with tinted Yes/No restored | Won 2–1 | Combine winning parts |
| 9 | Neutral "No", hide next step's summary in list | Lost 0–3 | Consistency beats nativeness here |
| 10 | Secondary text one step larger and darker | Won 2–1 (low confidence) | Converged; stopped to save usage |

Recurring reviewer note not acted on (owner's explicit choice): the compact bar says "Netherlanding in …" while the logo says "Netherlanded".
Possible next experiment: give Local help services a different shape from steps (icon-led grouped list) so the two object types differ.

**After the A/B test (20–28 October):** later changes came from the owner's direct feedback, not further A/B rounds: depth, the horizon brand with Newsreader and Manrope, the calm redesign, city skylines, sounds and the profile button. See DESIGN_SYSTEM.md (v3–v4) and the build timeline. No real students have tested the app yet; that is the next evidence to collect.

## Final against Square · 15 November 2026

Same method as October: three reviewer agents judged blind from screenshots (labels X/Y, order swapped for one reviewer), 12 screens at 390 × 844 in light and dark. **Final** is the card design. **Square** is the same build with a styling layer: flat full-width lists with hairlines, heavy rules and larger serif headings, small-capital tags, square structure, 3px corners on controls, and no decoration apart from the header scene.

| Reviewer | Vote | Confidence | Screens (Square / Final / tie) |
|---|---|---|---|
| Anxious first-year student, English as a second language | Square | Medium | 6 / 4 / 2 |
| Accessibility specialist (WCAG 2.2, Apple HIG) | Square | Medium | 3 / 3 / 6 |
| Senior iOS product designer | Square | Medium to high | 8 / 2 / 2 |

**Result: Square won 3–0.** No reviewer was highly confident, and the student said Final feels calmer and kinder.

Why Square won: more content per screen (four scam questions against two and a half), stronger headings, an unmistakable selected "Yes", clear square checkboxes, the "By law" label visible where Final's drawings took the space. The designer called Final the more generic-looking of the two (cards on a tint, gradient header with clouds, repeated plane-and-sun drawing, coloured icon tiles, pill tags).

Where Final was better, by all three reviewers:
- Controls look like controls. In Square the setup search field has no visible edge, "iPhone / Android" are bare words, the appearance setting looks like the Local help filter, and "This is a sample plan" has no container.
- The scam warning. Final's pink box is noticed at once; Square's red left rule is weak, most of all in dark mode.
- "Up next" as an outlined card reads as tappable; Square's left rule less so.

Other Square problems: an empty gap on the welcome screen; heavy rules stop at the margin while row dividers run to the edge; dark mode is near-black with a bright mint button; the small-capital "TIP" is the smallest text in the app.

Problems in both: the round profile button in the tab bar covers list text, including the "By law · Due in…" line; the last row is cut off under the sticky button on the setup question and the step sheet; the grey "Source: … checked" line on Local help measured about 3.5:1 in light mode, under the 4.5:1 minimum.

Limits: the reviewers are AI agents looking at screenshots, not students using the app. They could not judge motion, screen readers or keyboard focus. Treat the result as a reason to fix Square's control affordance, not as proof students prefer it.

**Acted on, same day (Square link):** the setup search field has a border; the appearance and iPhone/Android settings are bordered two- and three-part controls with a filled selection; the sample-plan line sits in a tinted band; the scam verdict is a tinted box with a heavy coloured edge; "Up next" is an outlined box; heavy rules run edge to edge like the row lines; the profile button sits inside the tab bar and no longer covers text; dark mode uses a softer ground and the header green for the main button; tag text is 12px; the "Source … checked" line now passes contrast. Not changed: the empty space on the welcome screen, and rows that scroll under the sticky button.
