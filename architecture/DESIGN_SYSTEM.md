# Netherlanded design system

*Current version: v4.4 · 28 October 2026 · live on the shared link and the preview. The full brand (logo, tokens, voice) is the [Netherlanded design system artifact](https://claude.ai/artifact/8k1r41XngDGGKvEcQAdFzp); the change history is the [build timeline](https://claude.ai/artifact/2XdRrsowrGNitVuFDN3AwH). Sections from "v2.0" down are history.*

## v3–v4 · The horizon brand, calm redesign (28 October 2026)

Idea: the Netherlands is flat; arriving is the moment you land on the horizon. Native iPhone patterns stay (they tested best); the brand sits on top.

| Area | Rule |
|---|---|
| Logo | Horizon disc: low-sun yellow `#f3c623` over polder green, split by a thin line. Before arrival the sun is lifted; from arrival day it rests on the line. In the green header the lower half is white at 60%. Home-screen icon: the sun setting onto a pale horizon over two greens |
| Type | Newsreader Semibold for the countdown, sheet and page titles, stage names, group labels and the wordmark; Manrope 400/600/700 for everything people read and tap. Both embedded (works offline, about +90 KB) |
| Colour | Page `#eef3f0` with a warm mist (`#f6efe0`) under the header; cards `#fbfdfb`; text `#17302a` / secondary `#4a5a53`; separators `#d3dfd8`. Dark: night green `#0d1714`, cards `#16211d`, text `#e6efea`. City colour tints the header and accents. Muted status colours: red `#d9534a`, orange `#e39a3b`, green `#4f9a6e` (lighter in dark). Local help tiles muted to match |
| Header | Dawn-sky gradient from a light green at the top to the city colour; drifting clouds (light) or slow twinkling stars (dark); a large sun at the bottom right sits on the header's edge and rises with overall progress (`--p`). Before arrival: "Netherlanding in x days"; after: "Welkom in (city)" with "Day n in (city). You're Netherlanded." Greeting: "Hoi (first name)" |
| Route strip | One numbered box per required step under the progress bar: finished = white with a fading diagonal strike, next = yellow with a soft glow, upcoming = translucent |
| Cards | 18px radius, soft wide shadow, no borders. "Up next" has a soft tint halo and a faint morning-light gradient |
| Deadline tags | Must (legal, red), Fee (costs money, orange), Tip (outlined); full wording for screen readers |
| Drawings | Line art on a horizon line, city colour, 2.2px stroke: plane and cloud (Before you travel), the city skyline with 2–3 landmarks for each of the 10 cities (Your first weeks, Local help), Sprinter train under an overhead wire with a bike and tree (Settling in), calendar (Deadlines), house and magnifier (Scam check). Each has a sun clipped at the horizon that rises with that stage's progress and has one radial, breathing glow. Lines never cross: a background-coloured knockout sits behind moving parts (Leiden's sails) |
| Tab bar | Steps, Deadlines, [profile], Scam check, Local help. The profile is a 54px avatar circle with a yellow ring, raised in a bump that rises out of the bar, with the first name underneath. Active tab: city colour with a soft pill |
| Toasts | Deep polder green, 20px radius, a tiny rising sun before the text |
| Motion | Slow, no bounce (`--spring` cubic-bezier(.22,.8,.26,1)). Plays once per launch: sun rising from under the horizon (2.6s), progress fill, route boxes popping in, train sliding in. Ongoing and subtle: sun glow breathing (5s), clouds (about 1 min), stars, windmill sails. On interaction: tab content rises in, tick swells with a fading sunlight ring, a "Done" stamp settles. All off under Reduce Motion |
| Sound | Made on the phone with Web Audio, never before a tap, switchable in Profile. Soft low sine bells through a low-pass filter: step done C5→F5; stage done and reminder chime "Horizon" F4–C5–F5; arrival D4–A4–D5–A5; untick A4. Opening a category or step: a short breath of pink-noise wind (about 0.7s, S-curve fade-in, starts on touch, fades out if the touch becomes a scroll). Files for real notifications in `sounds/` |
| Notifications | Examples for iPhone (lock screen) and Android (shade, with "Open step" / "Remind me tomorrow"); Profile → Sound → Preview a reminder shows either style with the student's next deadline |
| Removed | Buddy programme (tab, profile section, "Meet your buddy" step) |

Checks: `tests/ux_test.py`, `ux2_test.py`, `motion_test.py` (tick animation `tickCalm` accepted), `landing_test.py` (expects "Welkom in …"), `iphone_audit.py` (profile opened via `#tabMe`); all pass on v4.4.

## v2.0 · Native iPhone look (preview, 20 October 2026)

Feedback was that the app "looks vibe-coded". v2.0 replaces the v1.x visual layer with standard iOS patterns. The sections further down describe v1.8, which is still on the shared link until v2.0 is approved.

| Area | v2.0 rule |
|---|---|
| Type | The phone's own font (`-apple-system`, San Francisco on iPhone; Segoe UI / Roboto elsewhere). iOS sizes: large title 34, title 28, section 20 semibold, body 17, subheadline 15, footnote 13, tab label 10. No code font, no capitals labels, sentence case everywhere. The embedded fonts are gone (page 40% lighter) |
| Colour | Standard iOS system greys for background, cells, text and separators (light and dark). The city sets only the header colour and the tint: buttons, ticks, progress, links, selected tab |
| Lists | Full-width grouped lists on the grey background, hairline separators inset to the text, chevrons on rows that open something, sentence-case section titles |
| Steps | Reminders-style rows: a tick circle you can tap to complete a step (fills in the city tint, with Undo), a lock for locked steps, one meta line (Up next · due date · After … · Optional) instead of tags |
| Header | City-coloured with an iOS large title: "Netherlanding in 23 days" / "Netherlanded" on Steps, the tab name on other tabs; a thin progress line "3 of 12 steps done". The compact bar is a centred iOS navigation title |
| Controls | iOS segmented control for Yes/No and the Local help filter, iOS switches, checkmark option rows and value rows in the setup questions, Settings-style coloured icon tiles in Local help |
| Sheets and screens | iOS page sheets with grabber and a Close button; the main action pinned in a frosted bar. Profile and Terms push in from the right with a "‹ Back" button |
| Motion | Only what iOS does: sheet up/down, screen push, tick fill, category fold, progress change, toast, and the one-time Netherlanding → Netherlanded switch. Removed: intro sequence, counting numbers, scroll reveal, tab slide, staggered lists |
| Removed tells | Numbered blocks (01/02/03), coloured side stripes, monospace labels, uppercase eyebrows, big-number stats strip, tags on every row |

Checks: iPhone audit (no field under 16px, every target at least 44pt including hit-area extensions, safe areas), `tests/motion_test.py` (rewritten for the native set, and nothing moves under reduced motion), plus the UI, city, UX and landing suites.

**v2.2 (A/B tested, 20 Oct 2026):** separate cards for steps and services; quiet emphasis on Up next (larger title, 1.5px city-tint outline, no filled button); finished steps collapse to one flat line; secondary text #3f3f45 light / #c6c6ce dark at 14–16px; Yes/No selected = tint plus 2px outline (amber for Yes, green for No) with the hint "'Yes' means a warning sign"; flat tinted "Sample plan" banner; bold due dates; tab labels 11px, active bold. Full log in AB_TESTING.md.

---

*Version 1.8 · 19 October 2026 · v1.4 is the version shared with classmates; v1.5–1.8 are on the preview link until approved*

## Layout principle: colour bands, not cards

Since v1.2 the app has no floating cards ("bubbles"). Every section is a full-width band, told apart by colour. Since v1.3 the bands sit on the tinted ground (`--bg`) with a steady gap (`--gap`, 12–16px depending on screen width) between sections, so each one reads as its own segment. A label band and the band it introduces stay joined, and the stats strip stays attached to the header (on every tab, so the header never changes height):

| Band | Colour |
|---|---|
| Header | City bar colour (`--bar`), flat bottom edge, optional flag stripe |
| Stats strip (Steps tab) | Bottom segment of the header: one shade darker on coloured bars, a light ink tint on white bars (`--strip`) |
| Page heads (Deadlines, Scam check, Local help, Buddy) | `--tone-1` |
| Next up, city note | `--green-soft` (city soft colour); city note has a 4px primary stripe |
| Phase headers | `--tone-1` / `--tone-2` / `--tone-3`: a three-step tint of the city colour, one per phase, with a solid primary number block (01, 02, 03; a tick when complete). Progress runs along the band's bottom edge |
| Section labels | `--surface-2` grey band; Deadlines uses `--crit-bg` for Overdue and `--warn-bg` for Next 14 days |
| Bodies (steps, rows, forms) | `--surface` (white / dark surface) with hairline separators |
| Sheets | Tinted head band in the step's phase tone; body on surface |

Shapes: tags 3px (`--r-tag`), buttons and inputs 6px or less (`--r-ctl`), bands and blocks square. Circles are kept only for the profile avatar and the city flag badge. Step markers on the route are small squares.

## Tokens

| Group | Tokens | Notes |
|---|---|---|
| Colour (theme) | `--bar`, `--bar-ink`, `--bar-tint`, `--stripe`, `--green` (primary), `--green-ink`, `--green-soft`, `--yellow` (accent), `--yellow-ink`, `--avatar`, `--avatar-ink` | Set per city from its flag (10 cities), light and dark values |
| Colour (base) | `--bg`, `--surface`, `--surface-2`, `--ink`, `--ink-2`, `--line` | Neutral, tinted with the city's primary colour |
| Colour (bands) | `--tone-1`, `--tone-2`, `--tone-3`, `--strip` | Computed per city with `color-mix` (light: 6/11/17% primary into white; dark: 9/14/20% into the dark surface) |
| Colour (meaning) | `--ok`, `--warn`, `--crit`, `--info` + `-bg` variants | Done / costs money / legal risk / advice. Never used as brand colour |
| Type | `--fs-2xs` 11 · `--fs-xs` 12 · `--fs-sm` 13.5 · `--fs-base` 15 · `--fs-md` 16 · `--fs-lg` 20 · `--fs-xl` 23 · `--fs-2xl` 26 · `--fs-3xl` 29 · `--fs-4xl` 32 | Replaced 24 ad-hoc sizes |
| Fonts | `--f-display` Newsreader (headings) · `--f-body` Manrope (text, UI) · `--f-mono` Source Code Pro (dates, tags) | Self-hosted, no Google requests |
| Radius | `--r-tag` 3 (tags, inputs, toggles) · `--r-ctl` 6 (buttons) · 14px sheet top · bands 0 | v1.2 dropped the card and pill radii |
| Elevation | `--e2` toasts only | Bands are separated by colour and hairlines, not shadows |
| Spacing | `--s1` 4 · `--s2` 8 · `--s3` 12 · `--s4` 16 · `--s5` 20 · `--s6` 24 · `--s7` 32 · `--gap` clamp(12px, 3.6vw, 16px) | Every inner padding and margin uses this scale. Band heads 24/20, bodies 16–20, rows 14, label bands 12/10 |
| Motion | `--ease` cubic-bezier(.2,.8,.2,1) · `--ease-in` · `--spring` · `--d1` 120ms · `--d2` 220ms · `--d3` 420ms | All motion off under `prefers-reduced-motion` |

## Motion

| Moment | Behaviour |
|---|---|
| First load, and after changing your answers | Header lines, then the stats strip, then the first bands settle in one after another (about 1 second in total, once) |
| Changing city | Header, stats strip, tab bar and bars crossfade to the new city's colours, also live while you pick a city in the questions |
| Stats strip | Numbers tick from their old value to the new one (from 0 on first load); nothing moves if they did not change |
| Scrolling | Bands and labels fade and rise in (no scaling, so band edges stay flush) when they enter the screen (staggered; rows inside a card follow one by one) and settle back down when they leave. Anything on screen at rest is always visible |
| Big header leaves the screen | Compact bar with city flag, app name and avatar slides down from the top |
| Tab change | The tinted tab cell slides to the new tab; content glides in from the side you moved towards |
| Progress bars | Grow from their previous value (from empty on first load), so ticking a step visibly extends the bar |
| Collapsing a category | Body folds smoothly (grid-row animation), chevron springs round, subtitle switches to the next open step; opening it again brings the steps in one by one |
| Next up | When it changes after ticking a step, the new text eases in |
| Ticking a step | Marker pops, row flashes in the theme's soft colour |
| Sheets | Spring up on open, drop and fade on close; their contents follow in a short stagger |
| Scam check | The verdict band eases in when the risk level changes (not on every answer); the explanation of a "yes" fades in under the question |
| Local help filter | The filtered list fades up into place |
| Profile and Terms screens | Slide in from the right, slide out on back |
| Toasts | Spring up, fade down |
| Buttons, rows, tabs | Hover tint (mouse only), press shrinks to 97%; tab icons dip slightly on press; the phase number block dips when its header is pressed |

Rules: nothing loops or plays on its own after the first load, distances are 6–22px, durations 120–560ms, and everything is switched off under `prefers-reduced-motion` (checked by `tests/motion_test.py`).

## Components

| Component | Variants / states |
|---|---|
| Button `.btn` | primary · ghost · danger · small; hover, pressed, disabled, focus ring |
| Band `.seg-card` | plain · next-up · verdict (low/med/high) · profile identity (`.id-card`, tone-1); header stats strip `.hstats` |
| Label band `.group-label` | grey · `.crit` · `.warn` |
| Page head `.page-head` | title + lead on tone-1 |
| Phase band `.phase` | expanded · collapsed (shows next step) · complete (tick in the number block, green progress edge, collapses by default); "x of y done" ("done" hidden under 360px; optional-only phases say "all optional"); choice remembered per phase; `aria-expanded` on the header button |
| Step row `.stop` | to do · done · locked · optional · just-done |
| List row `.rowi` | static · link (chevron) · danger; inset separators |
| Tag `.chip` | legal · financial · advice · good · lock ("After: first blocker +n more") · optional |
| Filter strip `.filters` | segmented, square, active segment filled with primary; scrolls sideways on narrow screens |
| Local block `.local` | soft band with primary stripe; links as stacked rows |
| Tab bar | flat; one soft-tinted cell with a 3px primary bar on top slides to the active tab; square badge for deadlines in 14 days |
| Switch `.switch` | on/off, spring thumb, keyboard focus ring |
| City flag badge `.flag` | round; circle-specific artwork for Amsterdam, Leiden, Maastricht, Eindhoven |

## Accessibility

- Visible focus ring on every control; switches and toggles work with the keyboard.
- New colour pairs checked against WCAG AA (4.5:1 for text) in all 10 city themes, light and dark; `--warn` darkened to #865400 for this.
- Status is never shown by colour alone (labels such as "Legal / permit risk", "Locked").
- Reduced-motion users get no animation; the reveal effect is skipped entirely.
- Escape closes sheets and screens.

## iPhone (v1.4)

| Topic | Rule |
|---|---|
| Focus zoom | Every text field, date field, select and textarea is at least 16px; iOS Safari zooms the page into anything smaller |
| Touch targets | At least 44pt. Small visuals (toggle switch, compact avatar) get an invisible larger hit area |
| Safe areas | Header, compact bar, tab bar, sheets and full screens add `env(safe-area-inset-*)`; checked with a 59px notch and 34px home bar |
| Status bar | A fixed band behind it in the city colour (`--status`); white-header cities use their flag stripe so white status text stays readable. `theme-color` follows the city |
| Taps | No grey tap flash; a passive `touchstart` listener so `:active` press states work on iOS; `touch-action: manipulation` on controls |
| Scrolling | Open sheets and screens lock the page behind them; sheets use `overscroll-behavior: contain` |
| Native fields | Date fields keep a 48px height and left-aligned value on iOS |
| Older iOS | Theme colours are mixed to hex in JS, with CSS fallbacks where `color-mix()` is used, so iOS below 16.2 gets the same colours |
| Home-screen version | `tools/build_iphone.py` builds `dist/iphone/` (manifest, icons, offline service worker, Apple web-app tags) |

## Interaction patterns (v1.5–v1.7, preview)

| Pattern | Behaviour |
|---|---|
| Pinned sheet actions | Step sheets and the setup questions keep their main button pinned to the bottom edge |
| Swipe to close | Pull a sheet down from its head or from the top of its scroll: closes past 110px (or a quick flick), springs back otherwise |
| Undo | Ticking a step off shows "Done · Undo" for about 5 seconds |
| Category complete | The number block becomes a tick, the band flashes green, a message names the category, then it folds away (unless the student kept it open) |
| Locked step | The main button reads "First: [blocking step]" and opens it, instead of a disabled button |
| Next marker | The next step to do carries a green "Next" tag in the list |
| Due date in sheet head | Shown as a tag next to the status, e.g. "Due 28 Oct 2026 · in 9 days" |
| Header on other tabs | Greeting and countdown fold away on Deadlines, Scam check, Local help and Buddy; the stats strip stays |
| Setup questions | "x of 6 answered" with a bar; submitting with gaps marks each missing question with a red stripe and a plain message, scrolls to the first, and clears each message once answered |
| Scam check | "x of 8 answered" line; the verdict band appears with the first answer |
| Local help filters | Stick under the compact top bar while the list scrolls |
| Focus | Tab stays inside an open sheet or screen; closing returns focus to whatever opened it |
| Small phones | Greeting, page and sheet titles scale with `clamp()` so an iPhone SE shows more content |

Tests: `tests/ux_test.py` (15 checks) and `tests/ux2_test.py` (9 checks) cover these, alongside `tests/iphone_audit.py`, `tests/motion_test.py`, `tests/ui_test.py` and `tests/city_local_test.py`.

## Arrival state (v1.8, preview)

The name and logo always read **Netherlanded**. Only the yellow arrival chip under the greeting changes, based on the arrival date the student entered (never on location):

| When | Chip |
|---|---|
| More than a day before arrival | "Netherlanding in 23 days" |
| The day before | "Netherlanding tomorrow" |
| Arrival day and after | "Netherlanded · day 1 in The Hague", "… day 4 …" |

- The first time the chip switches, "-ing" drops out and "-ed" drops in while the chip touches down (about 1.5 s, once; not under reduced motion). After that the word is plain text again.
- In the last 7 days before arrival an "I've arrived" button sits next to the chip. It sets the arrival date to today, plays the switch, and offers Undo.
- Moving the arrival date back into the future resets the state, so the switch plays again on the new date.
- Screen readers get the full sentence via `aria-label` ("Netherlanding in 23 days", "Netherlanded. Day 4 in Leiden"). Covered by `tests/landing_test.py` (13 checks).
