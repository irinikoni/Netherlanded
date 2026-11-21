# Netherlanded design system · v5.0 "blend" and v5.1 first-run setup (11 November 2026)

*Addendum to DESIGN_SYSTEM.md (v4.4). v5.0 is on the preview link; v5.1 is on the separate "Netherlanded Demo" link only. The shared link is still v4.4. Layout, content, brand (horizon, Newsreader + Manrope, city colours) are unchanged. v5.0 is one extra style layer at the end of the page plus a small `refreshView()` helper in the script.*

## v5.1 · First-run profile setup (Demo link only)

Replaces the single "Tell us about you" sheet on first open with one question per screen. The school comes first because a school can have campuses in several cities.

| Order | Screen | Notes |
|---|---|---|
| 0 | Welkom | "Start", or "See an example first" (the sample plan, kept for demos) |
| 1 | Where will you study? | School list with search (also matches abbreviations: TU Delft, HvA, RUG); "Another school" |
| 2 | Which campus? / Which city? | Only the cities that school teaches in. One city: shown already ticked. "Another school": all ten cities |
| 3 | Where will you live? | In the study city, or somewhere else (municipality picker folds open) |
| 4 | Where is your passport from? | |
| 5 | When do you arrive? | Same date limits as before |
| 6 | Will you work next to your studies? | |
| 7 | What should we call you? | Optional first name, plus the deadline-reminder switch |
| end | "(n) steps for you, (name)" | Holds about 2 s, then the Terms agreement, then the app |

- **After setup:** the existing Terms and Privacy agreement, unchanged. Returning users who already agreed go straight in.
- **Later changes:** Profile → "Change these answers" opens the existing sheet. It now follows the same order (school, then that school's cities, where you live, passport, arrival, work), and the profile summary lists them in that order.
- **Resume:** closing the app halfway keeps the answers and the current question on the phone (`nl-setup`); it is cleared on finish or on "See an example first".
- **Motion:** questions slide and fade in the direction of travel, answers stagger in, the tick draws itself on the chosen row and the flow advances after about 0.4 s. The header sun rises one step per question and the progress line fills. Choosing a city crossfades the whole screen to that city's colours and swaps in its skyline. All off under Reduce Motion.
- **Keyboard and screen readers:** focus moves to each new question, Tab stays inside the setup, Escape goes back one question, Enter continues; a missing answer is announced above the button.
- **Data limit:** only Leiden University has two campuses in the app's data (Leiden, The Hague). THUAS Delft and Zoetermeer, Fontys and Saxion outside Eindhoven and Enschede, and similar need checked local content before they can be listed.
- **Also in the Demo:** the compact top bar shows the tab name (Deadlines, Scam check, Local help) instead of "Netherlanding in (city)" on those tabs.

## v5.2 · Audit fixes (Demo link only)

Found by walking through as a new non-EU student arriving in 24 days.

| Area | Before | Now |
|---|---|---|
| Missed recommendations | "Overdue by 66 days" in red, also in a red Overdue group on Deadlines | "Do this as soon as you can"; Deadlines lists them under "Do these now". Overdue (red) is only for missed legal or fee deadlines |
| Due lines on Steps | Red, orange or black text with no explanation | Same Must / Fee / Tip tag as on Deadlines, neutral text |
| Up next | Own card plus the same step directly below it | The card is left out when that step already opens the list; it returns once earlier steps are done |
| Locked steps | "After: Find a room with…" | Full step name, "and 1 more" instead of "+1"; the sheet button "First: (step)" wraps instead of being cut off |
| Tap targets | Segmented controls 40pt, "Website" links 35pt | 44pt |
| Scam check verdict | At the top, off screen while answering | Stays pinned under the top bar while you answer |
| Route boxes in the header | Looked tappable, did nothing | Each opens its step (44pt tall hit area, labelled for screen readers). On a 320px phone with 13 steps they are about 19pt wide |
| E-mail reminders | A switch that could not work | A plain row reading "Full app only" |

## v5.3 · Second round (Demo link only, 12 November 2026)

| Area | Before | Now |
|---|---|---|
| Locked steps | Full card with description | Title plus "After: (step)" on a flatter, quieter card; the description is in the sheet. The Steps list is about 10% shorter |
| Reminders on Deadlines | A row that jumped to Profile | A "Remind me" switch on the tab itself, confirmed with a toast |
| Scam verdict | Pinned, same white as the questions, text showed above it | Pinned flush under the top bar, tinted and outlined by risk level (green, orange, red) |
| Step sheet status line | Coloured due text | Same Must / Fee / Tip tag as Steps and Deadlines |
| Tab labels | "Scam check" wrapped onto two lines on a 320px phone when active | Never wrap; 10px on phones under 360px |

## v5.6 · Small fixes (Demo and Preview, 12 November 2026)

- The "Done" stamp no longer covers the step title. It is smaller and sits on the card's top edge (bottom edge for the first card in a group).
- Setup review on phones under 700px tall: the hint line is hidden and rows are tighter, so about two more answers fit before scrolling.
- Database: `13_cleanup.sql` removes `step.city`, `app_user.city`, `service.city`, the buddy tables and the `meet_buddy` step; `14_cleanup_tests.sql` checks it. Order is now 08, 12, 13, then tests 10 and 14.

## v5.5 · Setup flow, second pass (Demo and Preview, 12 November 2026)

| Area | Before | Now |
|---|---|---|
| Last screen | The name question led to a "Check your answers" screen that crashed (`fmt()` was given a text date), so setup could not be finished in the Demo | Fixed. Each line on the review opens its question; after the change you return to the review |
| Where you are | Only "3 of 7" | A small line above each question shows what is already chosen, for example "THUAS · Zoetermeer" |
| Arrival date | Date field only | Also a "Today" row, and a line under the field that reads the date back ("That is in 23 days.", "That was 5 days ago. Anything already due is shown first.") |
| Final button | "Show my steps" | "Show my 18 steps": the count follows the answers and changes when a line is edited |
| Short phones (under 700px tall) | Drawing pushed the answers down | Drawing hidden, header shorter |

## v5.4 · City colours and THUAS campuses (12 November 2026)

- Page, card, label, separator, tab bar, toast and header haze colours are now mixed from each city's own tint (`--tint-soft`) instead of a fixed green. Checked for all 11 cities in light and dark.
- Zoetermeer added as a city; THUAS lists The Hague, Zoetermeer and Delft as campuses. The local content for both is in the page's data and in `database/12_campuses.sql`.

## v5.0 · What changed visually

| Area | v4.4 | v5.0 |
|---|---|---|
| Buttons | Fully round (999px) | 13px corner (small buttons 10px) |
| Active tab | Tinted capsule behind the icon | Soft radial glow in the city tint, no hard shape |
| Toast | 20px corner | 14px corner |
| Cards / groups / sheet / first-use card | 18 / 12 / 12 / 26px | 16 / 14 / 18 / 20px |
| Up next card | 1.5px outline plus 4px halo ring | 1px tinted edge plus a soft tinted glow |
| Header to page | Flat mist behind the header (hidden on Steps), hard shadow | Warm haze at the horizon, page starts with a faint city tint that fades into the mist, softer tinted shadow |
| Deadline tags | Solid red / orange, capitals | Tinted fills in the palette, sentence case ("Must", "Fee", "Tip") |
| Status text | iOS system red / orange / green | Muted `#b3261e` / `#94560f` / `#2b744a` (dark: `#ff8f85` / `#f0b05e` / `#7fcf9f`), all AA on cards |
| Tab bar and pinned bars | iOS grey material, grey labels | Green-tinted material, labels `#5a6861` (dark `#9aa9a1`) |
| Progress bars | Flat tint | Tint easing toward the sun colour |
| Motion | Slides (sheet, pushed screen), instant re-renders | Everything fades while it moves; sheets and screens travel less; folded categories fade; scam answers, verdict and filter results ease in |

## v5.0 · Fixes

- Scam check and Local help: the drawing at the top no longer disappears after answering a question or changing the filter; keyboard focus stays on the control you pressed.
- Local help: changing the filter while scrolled deep brings you back to the top of the new list.
- Groningen and Enschede (white header): route strip and progress line were white on white; they now use the header ink.
- Step sheet, "Your deadlines": long labels ran off the card; they wrap now.
- Dark mode: the profile initial in the tab bar was greyed out; the deadline badge and status icons had white on a pale colour. Both corrected.
- Focusing any control changed its corner to 12px (the focus rule set a radius); removed.
- Local help: service descriptions were cut off after three lines with no way to read the rest; shown in full.
- Phones under 360px: Yes / No sits under the scam question instead of squeezing it into a narrow column.
- Tab bar: the name under the profile circle lines up with the other labels.
- "Check another room" confirms with a toast and returns to the top.

## Known, not changed

- Preview link only: the compact top bar still shows "Netherlanding in (city)" on every tab, and the sample plan's "Change these answers" opens blank questions. Both are solved in the Demo.
- The test suites in `tests/` were not re-run against v5.0 or v5.1. `motion_test.py` needs the new animation names (`sheetUp`, `pushIn`, `scrimIn`, `obInR`, `obInL`), and any test that expects the Terms card or the sample plan on first open must first pass or skip the setup.
