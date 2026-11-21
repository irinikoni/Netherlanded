# Netherlanded design system · v5.8 (14 November 2026)

*Addendum to DESIGN_SYSTEM_v5.md. Built from three AI design reviews and the first real tester (a friend who compared the Preview and Quiet Cards links). Live on the **Quiet Cards** link; the **Netherlanded Final** link has everything here plus the "Final only" items. The Preview and Demo links are unchanged.*

## Progress, header and colour

| Area | Before | Now |
|---|---|---|
| Header progress | Sun, a bar, numbered boxes 1–12 and "3 of 12 done" | The sun rising behind a scene plus one line of text. Boxes and bar removed (they were 26px wide, unexplained, and 12 keyboard stops before the first step) |
| Header scene | City skyline, or nothing | One national scene standing on the header's bottom edge: canal houses, church, windmill, cow, farmhouse, bicycle, tulips, second windmill, lighthouse. Solid, so the sun rises behind it. No water |
| Scene colour | — | Drawn like the phase pictures: outlined in the city tint, filled with the header colour. On a dark bar in light mode the tint is mixed 30% with white so it stays visible. The header's bottom line takes the same colour on Steps, so the scene never stands on a different red |
| Phase bars | A bar, a count and a mini sun per phase | The mini sun and the count; the bar is gone |
| Step counts | "18 steps for you", then "0 of 13" | One rule everywhere: required steps, optional named apart ("13 steps, plus 5 optional") |
| Inner pages (Profile) | Top bar in the city colour (Eindhoven red on every page) | Neutral bar; the city colour stays on the Steps header |
| Bottom bar | Fixed green | Near-neutral with a trace of the city colour |

## Cards and tags

| Area | Before | Now |
|---|---|---|
| Finished steps | Filled pink ticks | Outlined tick, grey title |
| Locked steps | Low-contrast grey card, "After: X and 2 more" | Readable text (9.3:1 light, 11:1 dark), "Do first: X and 2 other steps" |
| Up next | Glowing border (reads as keyboard focus) | One 1.5px edge, no glow |
| Deadline tags | Must / Fee / Tip | By law / Costly / Tip (screen readers hear "Required by law", "Missing it can cost you money", "Recommended") |
| Missed deadlines | The sheet said "Fee" but not what the fee was | Every legal or costly deadline opens its sheet with **If you miss the deadline**, e.g. "Your bank may block your account until you add your BSN. Some banks close it." Live figures: the CAK lines show the current €529.74 |
| Money | "529.74 EUR" in one place, "€529.74" in another | Always €529.74 (and €950/month) |

## Behaviour

- **Up next:** the first available required step, except that a required step with a legal or costly deadline overdue or due within 7 days comes first.
- **Reminder preview:** shows the closest deadline with its consequence; if that is not the step at the top of the list, it adds "Up next on your list: …". The small label reads "Netherlanding · now" before arrival and "Netherlanded · now" after (the tester liked the Netherlanding line).
- **Finished phases** always fold away, even if the student opened or closed them by hand before; un-ticking a step opens the phase again.
- **Advised dates that have passed** say "Do it as soon as you can" instead of showing an old date. After arrival, an unfinished "Before you travel" reads "You have arrived: catch up on these".
- **Scam check:** one serious "yes" shows "Serious warning sign"; "High risk" waits until half the questions are answered.
- **Messages** (toasts) and the reminder preview stay on the screen they belong to: switching tabs, opening Profile or closing it removes them.
- **Long municipality texts** on Local help show four lines with "Read more".
- **Screen readers:** the tick says "Mark as done: …" or "Mark as not done: …"; every message is announced through one polite live region. Tab labels follow the phone's text size.

## Content (database/25_content_updates.sql)

- `deadline_rule.consequence` added and exported; `{fact_key}` placeholders in step texts and consequences are filled from current facts, so a changed figure updates every screen. A test fails if a placeholder has no fact.
- Dutch terms explained where a student first meets them: BSN, DigiD, IND, CAK. Idioms removed ("catch-22"). The buddy line in the monthly check-in and the scam tip removed; the buddy code is gone from the app.

## Final only

- **Seven more cities:** Tilburg, Venlo, Leeuwarden, Apeldoorn, Deventer, Heerlen and Sittard-Geleen get light and dark palettes (contrast-checked), a simple skyline (e.g. Leeuwarden's leaning Oldehove, a Heerlen mine headframe, Het Loo for Apeldoorn) and a lettered badge instead of a flag, because their flags were not confirmed. Their 8 campuses can now be chosen in setup.
- **Calendar file:** Deadlines → "Add these dates to your calendar" makes one .ics file on the phone with every upcoming deadline as an all-day event, a reminder a week before and the consequence in the note. Hidden inside the claude.ai viewer, which blocks downloads and does not accept .ics.
- **Scam check:** if the verdict gets worse while the pinned verdict is out of view, a message says so where the student is.
- Rotterdam's dark tint calmer; the step sheet drawing keeps clear of "Close".

## Known, not changed

- Real flags for the seven new cities; Amsterdam's registration dates (July to September 2026) are past; several figures in local texts are still typed in. All on the checklist.
- Dark headers fall into two families (green and red) across many cities; a stronger split would need new palettes for existing cities.
- The red "Choose where you will live" error seen once before anything was tapped could not be reproduced.

## Netherlanded Final (14 November 2026)

Four testers ran the same scripted checks on the old build (Preview, Demo and the friend copy are identical), Quiet Cards and the newer build with the extra cities and calendar file: function (4 student profiles, tick everything, un-tick, reload, corrupt saved data), accessibility (120 contrast samples per build, tap sizes, keyboard, labels), a blind 12-screen usability comparison, and layout (5 widths, 11 cities in light and dark, load time).

- **No functional regressions** from the old build to the newer one, and no layout differences. the newer build won or tied 11 of 12 screens; the old build won only the scam check, for its line explaining what "Yes" means.
- **Final = that newer build plus:** the scam intro now says "Yes means a warning sign" (the "x of 8 answered" line stays out, by the owner's choice); a message no longer covers a step that is opened; the header's second line is brighter (it was 3.6:1 on Eindhoven's red header in every build); ticks and small buttons have a full 44px hit area; a live region exists from the first screen and decorative drawings are hidden from screen readers; tab labels scale with text size but stop before the bar overflows; "Delete all my data" now clears answers, progress, unsent counters, setup progress and the terms agreement, then returns to the first screen (before, the sample plan showed until a reload).
- **Measured cost of the newer builds:** about 130 ms slower to the first card in a local test (199 ms to 333 ms median, high variance) and 3% larger.
- **Still open, in every build:** most text is sized in px, so it does not follow a larger text setting; the open tab is not remembered after a reload; un-ticking a step does not re-lock the steps that depended on it (by design, but worth testing with students).

## final-legal (18 November 2026)

Final plus the statistics consent screen. After the Terms, "Help next semester's students" asks once whether to share anonymous totals with the student's school. **Yes, I'll help** and **No thanks** are identical in size, colour and weight (the Dutch regulator treats a less visible refuse option as misleading); **Decide later** is a text link that asks once more after 3 finished steps or 3 weeks. The screen names the school, shows an "Example" card of what the school sees with two animated bars, and a "Never shared" line with a lock icon. The buttons stay pinned at the bottom of the card on short phones. The share switch moved out of the Terms card; Profile keeps the switch, now off unless turned on.
