# ADspace Digital Portal — design system, architecture and laws

Imported by `CLAUDE.md`. Every screen, every push and every screenshot is
checked against this file. Rules only; the reasoning and history behind each
line is in `docs/DESIGN-NOTES.md` (this file as it stood on 2026-09-26) and
`docs/DECISIONS.md`. Search there before changing a rule.

## 1. Register
- Apple / Cloudflare: clarity, deference, depth by layering, not shadow. Flat,
  quiet, one accent, corporate, warm neutrals.
- Never "AI SaaS": no rainbow gradients, no decorative shadows, no walls of
  tinted pills, no explanatory blurbs, no highlighter colours. A status is a
  dot and its word in ink (App Store Connect), never a coloured box.
- At a desk the console is v3: one white sheet (`.console-main`, 12px in, 18px
  corner, a `--card-edge` hairline) on the grey `--frame`, the rail flat on
  the frame (its chosen row white with the same hairline). The sheet's head
  names the section at 22/600 in Slate (`--font-head`, as every heading) over one line (`.console-sub`, the same Slate at 13.6px, the title over φ): the rail's
  group, then what the section holds as figures and words
  (`ADspaceAdmin.counts`: 14 open · 2 late · 6 due this week; a late part
  in red words), drawn by the section itself; the head is every bar's height, `--head-h` (64, 56 on a phone), its words centred in it and its sides at the body's 32px, every sticky offset reading it. A card on the sheet is white
  with a `--card-edge` hairline drawn as an outline just inside it (never
  an inset shadow, which the rows' white ground covers), never a shadow; a card inside a
  card is one surface; cards take the large corner (`--radius-lg`). The
  rail's Dashboard row counts what waits on the reader (`.nav-n`). Inside an
  open record (a client, a campaign, a supplier, a colleague, a creator)
  the record stays on the white sheet and is hairline cards: the head, each part of a pane (`.rec-part`: its head inside
  the card at 15/600 with its count as a `.tab-n`, its list the card's
  rows) and each rail block, each edged by `--part-edge` (a register (`.bookreg`) the card, its rows lines in it; ink at 11%; light
  ink at 12% in dark), 16px apart, the grouping carried by the space; a
  part's add act is a shaded `.btn-sm` with its glyph (`.btn-quiet`) unless
  it is the record's next step, then blue; a rail fact's pen and ⋯ show on hover and
  focus at a desk, always under a finger. Phones
  keep their solid head and one-line title. What holds words over other
  words (a menu, a popover, the finder, a sheet, a question) is solid
  `--raised`. Client pages keep their white.
- A page's surface is one attribute, `data-layout` on `<html>`: `v3` on
  the console (the grey frame, one white sheet) and on every client page
  (plain white to the edge, each part a white card edged by the
  `--part-edge` hairline); `shaded` on the front door alone; every section
  card family reads the section tokens (`--ground`, `--section-bg`,
  `-edge`, `-radius`, `-pad`, `-gap`) through one base rule and keeps only
  its arrangement (`docs/rules/components.md`, Surface).
- Marks stay light: a ring or outline beside words is a hairline (1 to 2px), a list row's name reads at 500 and a figure at 500; 600 is for headings.
- Tuned for a long working session: few visible lines, light boundaries,
  generous space, full text contrast. Calm comes from the boundaries, never
  from dimming text.

## 2. Tokens (`css/portal.css` `:root`; nothing outside these)

### Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `--ink` | `#1a1a1a` | `#f0f0f0` | Text (the brand's monochrome, neutral in both themes) |
| `--ink-soft` | `#515151` | `#c9c9c9` | Secondary text, default button text |
| `--ink-mute` | `#666666` | `#a9a9a9` | Labels, hints, quiet buttons (4.5:1 on every ground) |
| `--line` | `#e0e0e0` | `#3c3c3c` | Card borders, table rules |
| `--line-soft` | `#ececec` | `#2e2e2e` | Row dividers, the selected fill, a hover on `--sunk` |
| `--line-ctl` | `#8e8e8e` | `#858585` | A control's drawn edge (a radio, a tick's ring): the lightest neutral that holds 3:1 on every ground |
| `--field` | `#f0f0f0` | `#323232` | A box typed into: filled, no outline; white with the blue edge and ring while typed in; on a grey card (`--sunk`) it takes the white ground and the control's edge (`--line-ctl`, 3:1) through `--field` / `--select-ground` / `--field-edge`, set on the one list of grey cards in `css/portal.css`; a placeholder is `--ink-mute` at full strength |
| `--page` | `#f5f5f5` | `#171717` | The ground (the brand's own off white; never "corrected") |
| `--card` | `#ffffff` | `#1f1f1f` | Panels, tables, rows |
| `--sunk` | `#f9f9f9` | `#272727` | Inset areas, table sub-headings, hover |
| `--card-line` | transparent | transparent | Every card's edge, on every page (console and client pages alike), and every row that opens something (`.railnext`); nothing else draws a card outline. A box inside a card is shaded (`--sunk`), never outlined. Buttons and fields are filled, never outlined; the contact chip, menus, sheets, file tiles, and the floating tab bar and More keep their edges. `uxaudit` `outline` |
| `--fill` / `--on-fill` | `#1a1a1a` / `#fff` | `#f0f0f0` / `#1a1a1a` | The ink surface: a selected `.acttab`, progress, the bell's unread count. Never a button but Use passkey (`.btn-ink`), never the Undo bar |
| `--tonal`, `--tonal-hover`, `--tonal-press` | ink at 6.5% | light ink at 9% | Every secondary button and bar mark |
| `--action` / `--on-action` | `#0071e3` / `#fff` | `#0071e3` / `#fff` | **Blue: the one primary action of a view** (Add, Create and Save as much as Publish, Release, Submit and Approve), as apple.com draws every primary; never a status. White on it 4.70:1 |
| `--action-hover` / `--action-pressed` | `#0068d1` / `#005bb8` | the same | Its steps, each darker so the label keeps AA (Apple's lighter hover is 4.32:1). `#007AFF` (4.02:1) is refused |
| `--action-ink` | `#0066cc` | `#2997ff` | Blue as words or a glyph (5.57:1 on white, 5.47:1 on the dark card) |
| `--dot-ok` / `--dot-wait` / `--dot-late` / `--dot-off` | `#34c759` / `#ff9f0a` / `#ff3b30` / `#aeaeb2` | `#30d158` / `#ff9f0a` / `#ff453a` / `#636366` | A status's 8px dot before its word in ink, Apple's system colours: green done or live, amber waiting on somebody or still running, red needs acting on now, grey not started, paused or closed. The word carries the meaning; the dot is never alone |
| `--action-ring` | `#8ab4f8` | `#8ab4f8` | The focus ring everywhere |
| `--accent` = `--ok`, `--ok-bg` | `#1f7a4d`, `#ecf5f0` | `#4aa876`, `#17281f` | **Green words: success only** (`.msg.ok`, a ring done); a live or done state is its dot |
| `--ok-solid` / `--on-ok` | `#1f7a4d` / `#fff` | `#4aa876` / `#07150e` | A green fill and its text |
| `--warn` / `-bg` / `-line` | `#a94d0c` / `#fdf1e7` / `#f1d3b8` | `#cf9350` / `#2a2217` / `#4a3520` | A mark drawn over a guidance figure (a capacity bar, a chart bar or key); a waiting state is its amber dot, a caution a neutral box led by it (the upgrade line, an Important announcement, `.msg.warn`), never a tinted slab |
| `--warn-solid` / `--on-warn` | `#9c5c16` / `#fff` | `#cf9350` / `#1d1408` | A warn fill |
| `--err` / `-bg` / `-line` / `-hi` | `#b3261e` / `#fdeceb` / `#e9b9b5` / `#8c1d18` | `#e8837a` / `#2e1d1b` / `#6a3a35` / `#f2a9a2` | **Red: destroys, refuses, or is late** (danger items, the billing gate, blocked; a date already passed: overdue, late, Urgent, Urgent delivery, a lead over its follow-up time) |
| `--pub` / `--pub-bg` | `#2a5793` / `#e6effb` | `#a7c6ed` / `#1d2735` | The post date on the My Work calendar, nowhere else: a pastel blue of Pantone 2717 C, greyer than the action blue |
| `--health` / `--health-bg` | `#ce0f69` / `#fcebf3` | `#f57eb6` / `#2e1a24` | Health's own pink (Pantone 214 C): its heart glyph and the answer chosen in a check-in, nothing else; never red, which refuses |
| `--vic` / `--vic-ink` / `--vic-bg` | `#b08a32` / `#7a5a0e` / `#f7f0dc` | `#c9a24c` / `#e3c272` / `#2b2517` | A Very Important Client's antique gold: the VIC tag (`--vic-ink` on `--vic-bg`, 6.4:1 light, 9.6:1 dark), its crown and the ring round the client's logo, nothing else; browner than Medium's yellow, cooler than the amber dot |
| `--sec-{home,work,clients,review,scripts,campaigns,reports,messages,int}` / `-bg` | `#2f62d6` / `#e8effc` (My Work) … | `#8ab0f5` / `#1d2a44` … | A section's mark (palette B): its glyph in its colour on a soft tint of it, the Work sections a hue each, the Dashboard and Analytics graphite, Internal graphite; drawn wherever the rail's glyph is copied (`svg.sec`, the rail, the tab bar, search's groups, Waiting for you, Engagements, the bell, Arrange sections, a figure tile, Needs attention). Never a status, a button or a word |
| `--dot-soon` / `--soon-bg` | `#ffcc00` / `#fdf6d8` | `#ffd60a` / `#2b2614` | Medium priority's yellow (Apple's system yellow): its strip and its deadline tag's ground, nothing else |
| `--focus` | `rgba(0,113,227,.22)` | `rgba(138,180,248,.34)` | Legacy focus halo |
| `--chrome` / `--chrome-solid` | `rgba(255,255,255,.72)` / `#fff` | `rgba(23,23,23,.72)` / `#171717` | Sticky bars, Apple's glass over `saturate(180%) blur(20px)` / the same, opaque under a finger (the console's head; a client page's bar keeps its glass over a white root) and as `theme-color` |
| `--trace-ink` / `--trace-strength` | `#1a1a1a` / .06 | `#f0f0f0` / .07 | The viewer's trace over a screen of personal data (`js/trace.js`), nothing else |
| `--veil` | `rgba(255,255,255,.88)` | `rgba(23,23,23,.88)` | A label or a question laid over a thumbnail (`.filecard-name`, `.filearm`), kept legible over any picture |
| `--scrim` | `rgba(0,0,0,.42)` | `rgba(0,0,0,.62)` | Behind a sheet |
| `--raised` / `--line-lift` | `#ffffff` / ink at 16% | `#272727` / white at 14% | What floats over the page (a ⋯ menu, a popover card, the finder): its own ground and a crisper edge than a card's rule, under `--shadow-lift`, so it never melts into the card beneath |
| `--shadow` / `--shadow-lift` | panels / menus | | Nothing else casts a shadow |
| `--z-trace`, `--z-sticky` … `--z-picker` | 10 the viewer's trace over its screen, 20 sticky bar, 30 console head, 39 notice cover, 40 top and confirm bars, 43 to 45 the tab bar, 50 menus and cards, 55 and 60 the drawer, 70 pull mark, 85 side sheet, 90 sheets, 92 and 93 a card over a sheet, 95 the question and canvas, 96 the finder | | Every page-level layer is one of these; a component's own stacking keeps a small figure. A new layer joins the scale, never a literal |

**How colour is used:**
- Every colour is a token; a literal cannot follow the theme.
- A document (every PDF) pairs its ground and words as the user's palette
  does: the
  white page carries `#515151`, the ADspace wordmark too, a shaded
  `#f5f5f5` box `#1a1a1a`; titles `#1a1a1a`; the head's and the foot's
  marks and fine print `#a1a1a1`; hairlines `#cfd0d4` (Print, §2
  Typography).
- An email's palette: `docs/rules/messages.md`.
- `color-scheme: light dark` is set on `:root`, and `color: inherit` on
  `button`.
- A fill and its text are always a pair (`--action` / `--on-action`, never
  `var(--ink)` / `#fff`). A hover is the token's own step (`--action-hover`)
  or `filter: brightness()` on the same token.
- One colour, one meaning, and the screen stays about nine-tenths neutral: blue is
  the action, green done or live, amber waiting or still running, red needs
  acting on now or destroys, grey not started or closed. A fact (High,
  Goodwill, White label, You) is a grey tag, never a status colour. Health's
  pink, the calendar's pastel blue and a VIC's gold keep their one place.
  - Every primary is blue: Add, Create and Save as much as Publish, Release
    and Approve.
  - Copy link, Preview, Edit, Cancel, row actions and every caution (Unpublish,
    Withdraw, Stop, Revert, Reopen) are the neutral tonal button.
  - One blue action per view, two at most (`uxaudit` `accent`).
- The accent marks the exception, not the norm. A state true of nearly every
  row carries no colour: the row says nothing, and the exception is a neutral
  chip beside the name with the row faded (Inactive, Paused). Green marks a
  milestone only a minority have reached.
- Grounds, ink and borders are neutral greys on the brand's monochrome
  (`#f5f5f5`, `#ffffff`, `#515151`, `#a1a1a1`, `#1a1a1a`); `#a1a1a1` is never words (2.6:1), only
  the contact chip's edge and an email's fine print.
  - Never set a filled surface to `--page`.
  - A new dark value keeps the luminance of the one it replaces.

### Shape, size, motion

| Token | Value | Use |
|---|---|---|
| `--radius-lg` / `--radius` / `--radius-sm` / `--radius-ctl-sm` / chip | 18 / 14 / 10 / 8 / 5px | The corner follows the size, about a quarter of a control's height: a sheet / a card or bounded section / a 34 or 36px control / a 30 or 32px control / a chip. Aliases `--radius-panel`, `--radius-ctl`. A nested corner is concentric: inner = outer − inset, written as the subtraction (a ⋯ menu's rows `calc(var(--radius) - 6px)`, a sliding thumb the track's less 2). Where the browser draws `corner-shape` (Chrome, Safari), every rounded box takes the squircle on the same radii by one rule at no specificity (`:where(*), ::before, ::after`), never a list of classes; a round shape opts out where its radius is set, every `border-radius` of 50%, 999px or half its box carrying `corner-shape: round` in the same block, and a variant taking a pill back to a corner says `squircle` beside it; the review mockups stay round; never some round and some squircle beside each other (`tests/corners.js` reads both sheets and measures every box on the client pages and console routes) |
| `--head-h` | 64px (56 phone) | Every bar, one height: every client page's bar (the wordmark and the portal's name), the console's signed-out pages and the console's own head; no page sets its own; never wraps; the kicker hides below 640 before anything clips |
| `--ctl-h` | 34px (36 coarse) | Every button, field, select, icon button, menu row, at Apple's sizes; under a finger a `.btn` still takes a 44px press (its `::after`) |
| `--ctl-h-sm` | 30px (32 coarse) | `.btn-sm`, `.input-sm`, `.select-sm`, status selects, segments, bar marks |
| `--tap` | 44px | The press a finger needs: a `.btn`'s invisible press area and an icon button's box under a coarse pointer |
| `--box-h` / `--box-h-sm` | 84 / 72px | A box of lines' floor; a short note's the smaller |

A height is a token, never a figure in a rule. A button, a field and every base element keep their own design wherever they stand: a section places them and never resizes or restyles them to fit its view, by a token or by a rule (the user, 2026-11-27: the design system is stabilised, Global > parent > child). Where a size does not fit, the section picks the element's own variant (`.btn` or `.btn-sm`), never a change to it (`cssguard`). Standing before this rule and changed only by the user: `--ctl-h-sm: var(--ctl-h)` on `.team-act`, `.cmdbar-views` (three places), `.pushpop-acts`, `.guide-acts` and `.rp-idspop-acts`; `--box-h: var(--box-h-sm)` on `.draft-body`, `.changebox` and `.saved.is-editing`; `--ctl-corner` on `.cmdbar`, `--btn-ground` on `.combinebar` and `--field-ring` on `.cmdbar-find`. None is added.
| `--state-w` | 124px | Status select or chip column (My Work's stage track 170px) |
| `--ctl-text` / `--field-text` | 13 / 14px (14 / 15 coarse) | Control label / field text |
| Button min width | 116px | |
| Icon | 15px glyph, stroke 1.8; icon box `--ctl-h` (44 coarse, drawn only on hover) | Same glyph for the same action; never mix outline and filled |
| Ring | 18px, stroke 2 | `.ring`; complete is `.ring-done`, a filled green disc with a white tick |
| `--t-fast` / `--t` / `--t-slow` | .12s / .2s / .34s | Colour or press / state change / size, position, surface |
| `--ease` / `--ease-out` | `cubic-bezier(.32,.72,0,1)` / `(.22,.61,.36,1)` | A move / an arrival |

**How shape and motion are used:**
- Every control presses to `scale(.97)` at `--t-fast`. A full-width phone slab
  dims to `.72` instead.
- A surface arrives from what opened it:
  - a menu from its button;
  - a sheet lifts, or rises from the floor to stand above the tab bar on a phone;
  - a fold runs `grid-template-rows` 0fr→1fr with opacity;
  - the Undo bar slides down.
- One `prefers-reduced-motion` block zeroes every duration and press.

### Typography
System stack (`--font`: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto,
Helvetica, Arial). Chinese adds PingFang SC and Microsoft YaHei under
`lang="zh"`.

| Level | Size / weight / tracking | Where |
|---|---|---|
| Display | 24/600/-.02em (21 phone); 26 review hero; 20 batch title | `.cover-panel h2`, `.batch-title` |
| Section heading | 19/600/-.02em | `.viewhead h2` (a record's pane heads take the panel title's 15/600), record name (the creator portal's `h1` too) |
| Sub-heading | 16/600/-.01em | `.viewhead h3`, a card's own title (`.qnext-title`, `.lockcard-title`) |
| Panel and group title | 15/600/-.01em | a record's `.viewhead h2`, `.panel h3`, `.crm-group-head h3`, `.kcard-name`, `.ovsec-head h3`, `.railtitle` |
| Body | 14px console; **16px client pages** (`:root[data-face="client"]`); line-height 1.55 | Only what inherits moves |
| Money in a row | 13.5px tabular, its figure at 500 (never the browser's bold) | `.svc-rate`, `.svc-amt b` |
| A row on a client page | 14px: a line, a figure, a total, a script's words, never the 16px reading size (uxaudit `figsize`) | `.qs-quote`, `.cp-line`, `.vs-text` |
| Control, small | 13 / 12.5px | |
| Label | 12/600, sentence case, mute, **no tracking, never uppercase** (but the PDFs' uppercase marks: uppercase by the stylesheet alone) | Every table header, band, fact label, step title, sidebar kicker |
| Chip | A fact's tag 11.5/600, radius 5, padding 2px 8px, sentence case (`.chip`, `.tone`); a status 12.5/500 in ink after its 8px dot, no ground (`.chip-state`, a chip with a tone), the dot an inline box on the word's baseline and 6px before it, never a flex item (a word holding a part of its own stays one phrase) | `.state-select` 12.5/500, its dot 8px inside the box (`--sdot`) and the word 6px after it; in a column it keeps the column's width (My Work's longest stage whole at 170px), standing alone (a record head) it is as wide as its longest option, never less than `--state-w` |
| Numbers in cells | 17/600/-.02em | `.tally-cell b`; the selection page's results summary under its lead figure (`.cx-figs dd`, 17/600, kept for emphasis) |
| Floor | 11px | Nothing smaller (the review mockups are exempt) |
| Mono | `ui-monospace, SFMono-Regular, Menlo` 12.5px | Slugs, tokens, codes only |

- Slate Regular (`/css/fonts/bold.woff2`, preloaded, `font-display: optional`)
  through `--font-head` on the display and section headings, and on the front
  door's names (`.lp-way-name`, the days) and tagline (`.lp-tagline`,
  19/400, 16 phone). Optima (`--font-mark`, `css/fonts/mark.ttf`) sets the front door's name (`.lp-title`, 48/400,
  36 phone) and otherwise stays on the letterhead. A face's file is the install's
  (`css/fonts/`, the agency profile's `font_*`) and its family is a token's
  (`Agency Head`, `Agency Mark`): no rule, head or script types the face's own name.
- The front door's hierarchy: headings in the body face 17/600 (16 phone); the
  names under them in Slate Regular 400, 15 (14 phone); links 13.5 (13);
  address and lead 14.
- Print (every PDF: the Word templates, the head and the foot, a sealed copy's Record page, a quotation's layout) and letter tables: `docs/rules/print.md`, read whole before drawing or changing a PDF.

### Spacing
The scale for gaps between blocks is 4, 8, 12, 16, 24, 32, and it stops there.

| Where | Value |
|---|---|
| Section head `.viewhead` | 24 above, 12 below, at every width |
| Blocks stacked in a section | 12 between every pair, whatever the block (`uxaudit` `stack`) |
| The front door (`body.lp`) | Editorial: one centred column (`--lp-col` 980, 560 at 900 and under; `--lp-gut` 24) for the name, the ticks and the hours (the bar and the foot keep every page's edges); the photograph edge to edge; section steps 32 to 56 |
| Sections in a list `.crm-group` | 24 |
| Panel padding | 18px 20px (14 phone) |
| Fold head `.disclosure` | 16px 22px (12px 14px phone) |
| Table row | 10px 15px (12px 15px phone); header row `12px 15px 8px` on the header itself, whatever its row's own pad |
| Field row gap `.row` | 12 across; **16 down between fields in a sheet** (`.sheet-body :where(.row)`), never a per-row style; a row inside a box that lays its own gap (`.qb-morebox`, `.perf-plan`) takes no step of its own, the gap being the step |
| Side-sheet cards | 16 apart, padded 18/20 |
| `.facts` / `.tally` gap | 14px 24px / 14px |
| Label beside value (`.ovfacts`, `.tfacts`, `.raildates`, `.railmoney`) | 8 between rows; the label 13px `--ink-mute` |
| A title over its block (`.railtitle`, `.qcard-title`) | 8 below; a read group's `.fsec-h` 12, as in the sheet |
| `.cards` / `.kcard` gap | 14 / 10 |
| `.svc-cat` | 14px 15px 6px |
| Tab strip to pane | 12, owned by the strip |

## 3. Themes
- A dark value hangs off `:root[data-theme="dark"]` alone, never a
  `prefers-color-scheme` query: the head script sets the attribute for Auto,
  so a query also fires on a device in dark whose colleague chose Light.
- Client pages (`/client/`, `/creators/`, `/creator/`, `/review/`, `/verify/`,
  `/quote/`, `/details/`, the covers) are **light only** and never carry `data-theme`.
- The console follows the device until somebody chooses.
  - The choice is Theme in the account menu (`#themePick`, a small segment:
    Auto, Light, Dark), kept in `localStorage` `adspace-theme` and winning from then on.
  - Auto clears the choice; a `matchMedia` listener follows the device while
    nothing is stored.
  - The head script applies it before first paint.
  - The palette hangs off `:root[data-theme="dark"]`.
  - No theme control sits in the console bar.
- The post mockups and the client's logo disc stay light in both themes.
- uxaudit walks the console in both themes.

## 4. Components (a new screen is built from these)

Moved to `docs/rules/components.md` (the components table), printed on the first edit of a screen's files: read it whole before building or changing a screen.

## 5. Laws (each broke once; the reasons are in the archive)

Moved to `docs/rules/laws.md` (Layout and alignment, Records, Forms, sheets, buttons, Menus and action groups, Colour, state, hover, Responsive and phone, with the phone checklist), printed on the first edit of a screen's files: read it whole before building or changing a screen.

## 6. Copy
Moved to `docs/rules/copy.md` (Copy and How copy is drafted), printed on the first edit of a screen's files or `supabase/`: read it whole before writing any word a person reads.

## 7. Architecture
- The Dashboard sits alone above the three groups, with no label, drawn for
  every colleague (its Me tab; `CLAUDE.md`).
- Analytics follows it, above the groups, drawn where any of its charts is readable (each at its section's access).
- The rail runs in three groups, each under its label (12/600 mute, the desk
  rail alone), the same sequence everywhere:
  - **Work**: My Work, Content Review, Video Scripts, Reports, Messages
    (Messages last; its WhatsApp and Email tabs).
  - **Partners**: Clients, Creators, Suppliers.
  - **Company**: Documents, Services, Short Links, Team (Hiring is Team's
    tab).
  - A colleague may arrange their own order within each group (Arrange
    sections), which the tab bar follows; everything else keeps this one.
  - The desk rail never scrolls for a full admin from 720px high (the user,
    2026-11-22): rows 40px and touching (36px under 760px tall, a mouse's
    rail; a finger's keeps 40), groups 8px apart, a label one 16px line 4px
    over its rows (`tests/rail.js`).
  - The Handbook is a mark at the rail's foot before Settings'.
  - The Activity record is a mark at the rail's foot, last of the row
    Arrange sections', the Handbook's and Settings' marks make, the build
    under them at a desk's 212px rail (`.sidebar-foot`, each a `.railrow`,
    not a section).
  - A group whose every route is withheld hides its label.
- Five layers, each with one job (the user, 2026-11-28; `docs/MAP.md`):
  every new table, column, function, screen or document is placed in one
  before it is built, and the PR's Test plan names it.
  1. Identity: a record links to another by its uuid with a foreign key and
     a stated `on delete`; a name, email, code or number is display only,
     never a key. A person is found by their account (`auth.uid()`), a
     colleague by `team_members.id`; a "by whom" field keeps the id beside
     the name it shows.
  2. Agency: every agency value (name, legal details, domains, mailboxes,
     numbering, tax, country) is read from the agency profile through its
     one read path, never typed.
  3. Content: agency wording a person reads (letters, terms, emails,
     WhatsApp, HR documents, consent lines, guides, AI prompts; English and
     中文) is a template, never a literal in code.
  4. Business chain: a section states what feeds it and what it feeds
     (`docs/MAP.md` §B), linked by id, never by a copied value or a date
     match.
  5. Presentation: tokens and components only (global > parent > child).
- Everything hangs off a client. Only active clients appear in Content Review,
  campaigns and reports.
- The sale:
  - The lead is keyed in.
  - The first call or visit moves it to Contacted.
  - Billing and brand follow as the deal firms, then service lines.
  - The Letter of Offer goes out (Proposal sent). The client signs it; the
    quotation and invoice are issued outside the portal.
  - Billing complete, then Active, then engagements.
- The client signs in by email to `/client/` and sees one client, through
  security-definer functions only.
- Content Review and creator selection keep their token links (`?k=`), which
  read no other parameter. A readable address (a slug) never carries access.
- The client portal and the Clients list share one record shape. The console
  carries the complexity; client pages do not (Tesler).
- PDPA 2010 (MY) and 2012 (SG): collect what the page needs, show a client only
  its own data, soft remove before hard delete.
- Removed is not deleted:
  - Remove hides and keeps history.
  - Delete permanently (Manage) is for data that should not exist. A contact's
    foreign keys are `on delete set null`.
- Numbering (every number and reference, and the house scheme a new one follows): `docs/rules/numbering.md`.
- Row ⋯ menus are placed on the viewport. A faded row fades its content, never
  its ⋯. The global click handler spares `.kcard-head`, `.kmenu` and
  `.team-act`. A modal that filters keeps one height.

## 8. Theories applied on every change (at 1280 and 390)
- **Fitts**: 34px desk controls, 36px under a finger with a 44px press; the primary nearest the hand.
- **Hick**: one primary action per view; rare acts in the ⋯; a select for more
  than four choices.
- **Miller**: groups of three to five; six or more fold or become a table.
- **Gestalt**: a control sits with what it changes; the same data looks the
  same; a border groups and whitespace separates; one grid.
- **Jakob**: table, disclosure, ⋯, sheet, chip, select; nothing invented.
- **Von Restorff**: one accent per promise.
- **Doherty**: feedback under 400ms; a saving state on the button; never a
  reload.
- **Progressive disclosure**: a step appears when its stage is reached. What
  cannot apply yet is hidden, not disabled, and leaves again when reverted,
  with one exception: an act switched off in Settings,
  or past its daily limit, is drawn disabled with its reason (`data-gate`,
  `#gateWhy`); one the person is not permitted is hidden; what the portal
  would send by itself, switched off, is one `.msg.warn` line where the step
  that relies on it is taken, never a disabled act. What a client may not see is withheld by the
  function.
- **Serial position**: it governs the rail's two ends, not a pair of buttons
  (that is motor memory: one order, one anchor).
- **Visual weight**: the name, then the money, then the meta. The ⋯ is the
  lightest. One bold amount per document.
- **WCAG 2.2 AA**:
  - 4.5:1 text and 3:1 boundaries;
  - visible focus;
  - a label on every field and icon button;
  - never information by colour alone;
  - zoom to 200% works.
- **Golden ratio** where it serves (pane to rail 1.618, name 19 to meta 12).
  Never on controls or dense tables.
