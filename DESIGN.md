# ADspace Digital Portal — design system, architecture and laws

Imported by `CLAUDE.md`. Every screen, every push and every screenshot is
checked against this file. Rules only; the reasoning and history behind each
line is in `docs/DESIGN-NOTES.md` (this file as it stood on 2026-09-26) and
`docs/DECISIONS.md`. Search there before changing a rule.

## 1. Register
- Apple / Cloudflare: clarity, deference, depth by layering, not shadow. Flat,
  quiet, one accent, corporate, warm neutrals.
- Never "AI SaaS": no rainbow gradients, no decorative shadows, no coloured
  dots for status, no explanatory blurbs, no highlighter colours.
- Tuned for a long working session: few visible lines, light boundaries,
  generous space, full text contrast. Calm comes from the boundaries, never
  from dimming text.

## 2. Tokens (`css/portal.css` `:root`; nothing outside these)

### Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `--ink` | `#1b1a17` | `#f2efec` | Text |
| `--ink-soft` | `#524e47` | `#cdc8c3` | Secondary text, default button text |
| `--ink-mute` | `#6b6760` | `#ada8a3` | Labels, hints, quiet buttons (4.5:1 on every ground) |
| `--line` | `#e2dfd8` | `#3e3b38` | Card borders, table rules |
| `--line-soft` | `#ececec` | `#2e2e2e` | Row dividers, the selected fill, a hover on `--sunk` |
| `--line-ctl` | `#8e8e8e` | `#858585` | Field and outline borders: the lightest neutral that holds 3:1 on every ground |
| `--page` | `#f5f5f5` | `#171717` | The ground (the brand's own off white; never "corrected") |
| `--card` | `#ffffff` | `#1f1f1f` | Panels, tables, rows |
| `--sunk` | `#f9f9f9` | `#272727` | Inset areas, table sub-headings, hover |
| `--card-line` | transparent | transparent | Every card's edge, on every page (console and client pages alike), and every row that opens something (`.railnext`); nothing else draws a card outline. A box inside a card is shaded (`--sunk`), never outlined. Fields, buttons, the contact chip, menus, sheets and file tiles keep their edges. `uxaudit` `outline` |
| `--fill` / `--on-fill` | `#1b1a17` / `#fff` | `#f2efec` / `#1c1a19` | The ink surface: the primary for your own progress, a selected `.acttab`, progress. Never the Undo bar |
| `--tonal`, `--tonal-hover`, `--tonal-press` | ink at 6.5% | light ink at 9% | Every secondary button and bar mark |
| `--action` / `--on-action` | `#0b57d0` / `#fff` | `#a8c7fa` / `#062e6f` | **Blue: moves work to somebody else** (Publish, Release, Submit, Approve, a hand-off) |
| `--action-hover` / `--action-pressed` | `#0847ae` / `#063989` | `#c2dafc` / `#d3e3fd` | Its steps |
| `--action-ring` | `#8ab4f8` | `#8ab4f8` | The focus ring everywhere |
| `--accent` = `--ok`, `--ok-bg` | `#1f7a4d`, `#ecf5f0` | `#4aa876`, `#17281f` | **Green: live state and success only** |
| `--ok-solid` / `--on-ok` | `#1f7a4d` / `#fff` | `#4aa876` / `#07150e` | A green fill and its text |
| `--warn` / `-bg` / `-line` | `#a94d0c` / `#fdf1e7` / `#f1d3b8` | `#cf9350` / `#2a2217` / `#4a3520` | Caution, pending, reviewing, overdue |
| `--warn-solid` / `--on-warn` | `#9c5c16` / `#fff` | `#cf9350` / `#1d1408` | A warn fill |
| `--err` / `-bg` / `-line` / `-hi` | `#b3261e` / `#fdeceb` / `#e9b9b5` / `#8c1d18` | `#e8837a` / `#2e1d1b` / `#6a3a35` / `#f2a9a2` | **Red: destroys or refuses** (danger items, the billing gate, blocked) |
| `--pub` / `--pub-bg` | `#6a3fb5` / `#f2edfa` | `#c4a8f4` / `#251d33` | The publish date on the My Work calendar, nowhere else |
| `--focus` | `rgba(31,122,77,.18)` | `rgba(74,168,118,.30)` | Legacy focus halo |
| `--chrome` / `--chrome-solid` | `rgba(255,255,255,.72)` / `#fff` | `rgba(23,23,23,.72)` / `#171717` | Sticky bars, Apple's glass over `saturate(180%) blur(20px)` / the same, opaque under a finger and as `theme-color` |
| `--veil` | `rgba(255,255,255,.88)` | `rgba(23,23,23,.88)` | A label or a question laid over a thumbnail (`.filecard-name`, `.filearm`), kept legible over any picture |
| `--scrim` | `rgba(0,0,0,.42)` | `rgba(0,0,0,.62)` | Behind a sheet |
| `--shadow` / `--shadow-lift` | panels / menus | | Nothing else casts a shadow |

**How colour is used:**
- Every colour is a token; a literal cannot follow the theme.
- `color-scheme: light dark` is set on `:root`, and `color: inherit` on
  `button`.
- A fill and its text are always a pair (`--fill` / `--on-fill`, never
  `var(--ink)` / `#fff`). A hover is `filter: brightness()` on the same token.
- One colour per promise, and the screen stays about nine-tenths neutral.
  - Add, Create and Save are ink operations.
  - Copy link, Preview, Edit, Cancel and row actions are neutral.
  - One blue action per view, two at most (`uxaudit` `accent`).
- The accent marks the exception, not the norm. A state true of nearly every
  row carries no colour: the row says nothing, and the exception is a neutral
  chip beside the name with the row faded (Inactive, Paused). Green marks a
  milestone only a minority have reached.
- Grounds are neutral and the warmth is in the marks. Dark keeps its ink and
  borders on light's own hue axis.
  - Never set a filled surface to `--page`.
  - A new dark value keeps the luminance of the one it replaces.

### Shape, size, motion

| Token | Value | Use |
|---|---|---|
| `--radius-lg` / `--radius` / `--radius-sm` / `--radius-ctl-sm` / chip | 18 / 14 / 10 / 8 / 5px | The corner follows the size, about a quarter of a control's height: a sheet / a card or bounded section / a 38 or 44px control / a 32px control (10 under a finger, where it is 38) / a chip. Aliases `--radius-panel`, `--radius-ctl`. A nested corner is concentric: inner = outer − inset, written as the subtraction (a ⋯ menu's rows `calc(var(--radius) - 6px)`, a sliding thumb the track's less 2) |
| `--head-h` | 64px (56 phone) | The top bar on every page; never wraps; the kicker hides below 640 before anything clips |
| `--ctl-h` | 38px (44 coarse) | Every button, field, select, icon button, menu row |
| `--ctl-h-sm` | 32px (38 coarse) | `.btn-sm`, `.input-sm`, `.select-sm`, status selects, segments, bar marks |
| `--state-w` | 124px | Status select or chip column (My Work's stage track 160px) |
| `--ctl-text` / `--field-text` | 13 / 14px (14 / 15 coarse) | Control label / field text |
| Button min width | 116px | |
| Icon | 15px glyph, stroke 1.8; icon box 38 (44 coarse) | Same glyph for the same action; never mix outline and filled |
| Ring | 18px, stroke 2.6 | `.ring`; complete is `.ring-done`, a filled green disc with a white tick |
| `--t-fast` / `--t` / `--t-slow` | .12s / .2s / .34s | Colour or press / state change / size, position, surface |
| `--ease` / `--ease-out` | `cubic-bezier(.32,.72,0,1)` / `(.22,.61,.36,1)` | A move / an arrival |

**How shape and motion are used:**
- Every control presses to `scale(.97)` at `--t-fast`. A full-width phone slab
  dims to `.72` instead.
- A surface arrives from what opened it:
  - a menu from its button;
  - a sheet lifts, or comes from the floor on a phone;
  - a fold runs `grid-template-rows` 0fr→1fr with opacity;
  - the Undo bar slides down.
- One `prefers-reduced-motion` block zeroes every duration and press.

### Typography
System stack (`--font`: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto,
Helvetica, Arial). Chinese adds PingFang SC and Microsoft YaHei under
`lang="zh"`.

| Level | Size / weight / tracking | Where |
|---|---|---|
| Display | 24/600/-.02em (21 phone); 26 review hero; 20 batch title | `.cover-panel h2`, `.camphead h1`, `.batch-title` |
| Section heading | 19/600/-.02em | `.viewhead h2`, record name (the creator portal's `h1` too) |
| Sub-heading | 16/600/-.01em | `.viewhead h3`, a card's own title (`.tnext-title`, `.qnext-title`, `.lockcard-title`) |
| Panel and group title | 15/600/-.01em | `.panel h3`, `.crm-group-head h3`, `.kcard-name`, `.ovsec-head h3`, `.railtitle` |
| Body | 14px console; **16px client pages** (`:root[data-face="client"]`); line-height 1.55 | Only what inherits moves |
| Money in a row | 13.5px tabular | `.svc-rate` |
| Control, small | 13 / 12.5px | |
| Label | 12/600, sentence case, mute, **no tracking, never uppercase** | Every table header, band, fact label, step title, sidebar kicker |
| Chip | 11.5/600, radius 5, padding 2px 8px, sentence case | `.tone`, `.chip`, `.chip-state`; `.state-select` 12.5/600 |
| Numbers in cells | 17/600/-.02em | `.tally-cell b` |
| Floor | 11px | Nothing smaller (the review mockups are exempt) |
| Mono | `ui-monospace, SFMono-Regular, Menlo` 12.5px | Slugs, tokens, codes only |

- Slate Regular (`/css/SlateRg.woff2`, preloaded, `font-display: optional`)
  through `--font-head` on the display and section headings, and on the front
  door's names (`.lp-way-name`, the days) and tagline (`.lp-tagline`,
  19/400, 16 phone). Optima sets the front door's name (`.lp-title`, 48/400,
  36 phone) and otherwise stays on the letterhead.
- The front door's hierarchy: headings in the body face 17/600 (16 phone); the
  names under them in Slate Regular 400, 15 (14 phone); links 13.5 (13);
  address and lead 14.
- Print (the letterhead):
  - wordmark in Optima 14pt (`fontMark`);
  - body in Slate Book 11/14.5pt, 14pt between paragraphs (`font`);
  - heavier lines in Slate Regular (`fontBold`), headings in Slate Medium
    (`fontMed`);
  - registration 9pt, table 10pt, notes 8.5pt, page count 7.5pt;
  - margins 54pt;
  - the monogram 21pt, top right of the letterhead only.
  - Config holds file paths, never font names.
- Letter tables: Description, Rate, Amount only. Quantity rides in the rate
  cell. The term sits mute under the Amount. Inclusions go under the name, then
  one mute line of basis, period and note. TERMS holds at most three sentences.

### Spacing
The scale for gaps between blocks is 4, 8, 12, 16, 24, 32, and it stops there.

| Where | Value |
|---|---|
| Section head `.viewhead` | 24 above, 12 below (22/12 phone) |
| Blocks stacked in a section | 12 between every pair, whatever the block (`uxaudit` `stack`) |
| The front door (`body.lp`) | Editorial: one centred column (`--lp-col` 980, 560 at 900 and under; `--lp-gut` 24) for the name, the ticks and the hours (the bar and the foot keep every page's edges); the photograph edge to edge; section steps 32 to 56 |
| Sections in a list `.crm-group` | 24 |
| Panel padding | 18px 20px (14 phone) |
| Fold head `.disclosure` | 16px 22px (12px 14px phone) |
| Table row | 10px 15px (12px 15px phone); header row `12px 15px 8px` on the header itself, whatever its row's own pad |
| Field row gap `.row` | 12 across; **16 down between fields in a sheet** (`.sheet-body :where(.row)`), never a per-row style |
| Side-sheet cards | 16 apart, padded 18/20 |
| `.facts` / `.tally` gap | 14px 24px / 14px |
| Label beside value (`.ovfacts`, `.tfacts`, `.raildates`, `.railmoney`) | 8 between rows; the label 13px `--ink-mute` |
| A title over its block (`.railtitle`, `.qcard-title`) | 8 below; a read group's `.fsec-h` 12, as in the sheet |
| `.cards` / `.kcard` gap | 14 / 10 |
| `.svc-cat` | 14px 15px 6px |
| Tab strip to pane | 12, owned by the strip |

## 3. Themes
- Client pages (`/client/`, `/creators/`, `/creator/`, `/review/`, `/verify/`,
  the covers) are **light only** and never carry `data-theme`.
- The console follows the device until somebody chooses.
  - The choice is kept in `localStorage` `adspace-theme` and wins from then on.
  - Choosing the register the device already shows clears the choice.
  - A `matchMedia` listener follows the device while nothing is stored.
  - The head script applies it before first paint.
  - The palette hangs off `:root[data-theme="dark"]`.
- The switch is `.themeswitch` in the console bar: an icon naming the register
  it moves to, never an account-menu item.
- The post mockups and the client's logo disc stay light in both themes.
- uxaudit walks the console in both themes.

## 4. Components (a new screen is built from these)

| Need | Component |
|---|---|
| Section head and its one action | `.viewhead` > `.headmark h2` + one `.btn` |
| Search, filters, count, action | `.cmdbar` > `.cmdbar-find` (a mark that grows to 280px) + view selects + the Filters mark (the filters in `#cmdPop` at a desk, `#cmdSheet` on a phone) + `.cmdbar-end` > `.cmdbar-quiet` (count) + `.cmdbar-acts`. Count reads `7 services` whole, `3 of 41` filtered, and is not drawn when empty. Extra acts sit behind one ⋯ |
| What a section is for | `.console-title` button with a 14px info glyph opening `.aboutpop` |
| A small card a control opens (the bell, a section's purpose) | `.popcard` laid by `ADspaceMenu.pop`: from its control with a caret at a desk; docked at the screen's foot on a phone, the action nearest the thumb, a close mark in its head |
| A directory | `ADspaceGroup.section`: `.crm-group` > `.crm-group-head` (15px heading, count, marks, the name as the fold) + `.crm-group-body` > `.crm-table.softpanel` with its own `.crm-head` |
| Rows | `.crm-row` / `.svc-row` and row classes; the header carries the row's classes; state column `var(--state-w)` second last; `.team-act` ⋯ last; each table states its own tracks, hung off its own row class |
| Facts | `dl.facts`, label over value, columns = cells; `.ovfacts` label beside value (150px, 104 narrow) |
| Counts and money | `.tallies` > `.tallygroup` > `.tally` > `.tally-cell` (`is-total`, `is-warn`) |
| Completeness | `.ringline` > `.ring` + "2 of 4" |
| A record | Workspace `.rec` (`minmax(0,1.618fr) minmax(280px,1fr)`, rows `auto 1fr`): `.rec-id` identity, `.rectabs` panes, `.rec-rail` of `.railblock`s |
| A record with no artwork (a task) | `.rec-id-plain`: the number as a token (copy control) heading the record, no mark |
| One record with steps | `.kcard` > `.kcard-head` (name, then summary, then the state beside the ⋯) + `.kstep` |
| Rare or destructive acts | `.kmenu-btn` ⋯ + `.kmenu` > `.kmenu-item` (`is-danger` red on the item itself) |
| An act with a consequence | `ADspaceConfirm` sheet (`.askcard`, 440px) |
| One value | `ADspaceAsk` rename / inline / note |
| Add or edit a record | A sheet: `.sheet` > `.sheet-card.formsheet` (620px; 780 for a picker) with a head and close mark, a scrolling `.sheet-body`, and `.sheet-foot` |
| A form of more than five fields | `section.fsec` > `h4.fsec-h` (13/600 ink), 2 to 5 fields each, divided by a `--line-soft` hairline and a 24px step |
| Fields side by side | `.row.fgrid` (two equal) / `.fgrid-3`, `span-all` / `span-2`; one column under `.is-tight` and below 560. Never a pixel width in a style attribute |
| A choice of two to four | Segment `select[data-seg]`, a pill (five or more stays a select); named by a label beside it where an action shares its row |
| A choice of ten or more | A select; it opens the finder (`.picker`, `js/form.js` §8): a search field over the options, under the field at a desk, the screen's height on a phone |
| Usual defaults | `details.fmore` More details, its line naming what it holds |
| A record pane of facts | Read first (`readGroup`, missing required values in warn); Edit opens the same groups in a sheet |
| Optional detail | `.panel.panel-collapse` > `.disclosure` + `.disclosure-body` |
| Full-page state | `.cover` > `.cover-inner` > `.cover-panel`, `body.is-plain`; the line never restates the title |
| Status | A chip with the word (`.chip`, `.tone`); `select.state-select` (tinted) only for a state that moves as the work |
| Undo | `.undobar` / `.undobar-here`: `--sunk` ground, hairline, ordinary ink, `.btn-sm`, 8 seconds |
| Message | `.msg` (`ok`, `warn`, `err`) as one line under the control, never a card |
| Loading, empty, failed | `ADspaceState` skeleton / `emptyLine` (a line inside its panel, with the way out) / `failLine` (what failed, why, Try again) |
| A queue and one open record | `.queue` > `.qrow`, ordered by what is owed |
| Deciding on one item in a gallery | `.canvas`: the item on a stage, the decision in a rail |
| A figure over time or across things | `ADspaceChart.draw` → `.chartcard`: ink marks, a colour only where the word is a state; the figures folded under it. Only where it answers faster than the table it sits over |
| Reaching a person | `.plink`, the outlined contact chip (1px `--line-chip`, `#a1a1a1` / dark `#5f5f5f`, lighter than a field's edge because its words identify it; no fill, `--sunk` on hover): phone, WhatsApp, email, a meeting or Drive link, a creator's profile, on every page; never an underlined word; equal widths on a phone unless alone |
| A value only read | `.readfield` (the field's height, no box) |
| An instruction | `.hintline` `?` with its line as a `--sunk` callout pointing at the mark, open three times, then retired; a button, never a `title` |
| Who you are (the console's account menu) | `.kmenu.acct-menu`: a head (`.acct-who`, the name over the sign-in email), then groups set off by `.acct-sep`: you (My HR, My namecard), this device (Passkeys, Notifications as a switch, Refresh app), an admin's Upgrade mode as a switch (drawn for an admin alone), Sign out. At a desk it hangs from the control; at 640 and under it docks at the screen's foot through `ADspaceMenu.pop`, rows 48px, with a close mark in its head |
| A word to everyone (an announcement) | `.annbar` under the top bar (`js/announce.js`): the line, then an https link as `.btn-sm` Open with the leaving mark and a close ×; `--tonal` for Info, the warn pair for Important; on the console laid like `.upgradebar`, on a client page edge to edge with the words on the mark's 24px edge (16 on a phone); never a marquee |
| Notifications on a client page | The bar's bell (`.pushbtn`, a second glyph with rays while on) opening `.kmenu.pushpop`, a `.popcard`: title with a close mark, one line, one `.btn-sm` |
| Finding a record in any section | `#searchSheet` (`js/search.js`): a sheet under the head (the floor, full height, on a phone), the field a combobox, answers as `.sgroup` (the rail name in the label face) > `.srow` (name, `.srow-code` in the token face, one mute `.srow-meta`; the match in weight) |

## 5. Laws (each broke once; the reasons are in the archive)

### Layout and alignment
- Two blocks in a section are always the same distance apart.
- A column is a column on every row. Every shared track is fixed and measured
  against its worst case (the clients state chip 120px; the Activity `By`
  150px; the task stage 160px; the schedule shoot 176px). `justify-self:
  stretch` aligns a cell and does not equalise the track.
- On a phone the last column is a right edge: the cell stretches and aligns
  right. An empty action cell gives up its track on a phone only.
- A phone list row is a two-column table, top aligned: who over meta on the
  left, state over age on the right. Two or three lines, never a stack of
  fields. Cells on one line share its baseline: a record beside an outlined
  chip reads on the chip's text (`.cr-record`).
- A phone template names every cell it keeps and hides the rest, including the
  restatement lower in the file.
- An empty grid cell keeps its column on a desk. `display:none` slides the rest
  left.
- A card's state chip sits on its title row at the right edge, before its ⋯
  (a record head, a month, a booking, a task's priority, a set, a post); the
  facts and the amount go on the lines under the name, on a phone as at a
  desk. In a desk table row a chip follows the name, never the far edge of
  a wide cell (a task's Urgent read as the assignee's).
- A padded control on a card's last line gives its padding back with a
  negative block margin (the ⋯, the tick, `.plink-bare`). A control whose
  presence depends on a permission never sizes its row.
- A chip, a ⋯ or a ring on a title line centres on that line, never on its
  own target: the control's cell takes the line's height and the 44px target
  overflows it evenly (the month card, a task row).
- A rule about something inside a pane keys on `is-narrow` / `is-tight`, never
  on a media query. The window is the measure only for a page's own head (the
  client portal).
- Every table states its own tracks. A template hung off `:not(...)` claims the
  wrong header.
- Every tab strip is the view strip: the tonal track, never a rule across the
  column, never bleeding past the page's margins. A report's step strip
  (`.rp-steps`, each step's summary under its name) is one too. A record's strip
  (`.rectabs`, the client portal's too) and a strip inside a card (a set's
  `.poststages`) run the width of that card at every width; a section's switch (`.tabrow`) is its own width at a desk
  and the column's on a phone. Tabs in a full strip share what is spare
  (`flex: 1 0 auto`). It never wraps; it scrolls sideways with the edge that
  has more beyond it faded.
- A tab's count is a small pill (`.tab-n`, 12/600, radius 5): `--tonal`
  with the soft ink, or the tone of the state it counts where it counts any
  (Content Review: Pending warn, Changes requested rose, Approved green, as
  the cards' own chips on both sides; Overview: warn where an item is late).
  It gives back its room on a phone (4px under 640, 3px under 400) before a
  tab's word is cut.
- On a phone a sideways swipe presses the tab beside the chosen one
  (`js/swipe.js`, a region's `data-swipe` naming its strip).
- A component borrowed for its shape carries its old flex and behaviour. Use a
  class of its own (`.railrow`, never `.navitem`).
- A class name belongs to one component. A new component never reuses a name
  already styled elsewhere (grep `css/portal.css` first): Content Review's
  `.cr-rec` split the Creators List's record cell, then named `.cr-rec` too.
- A group that must stay together is one element in the markup, never a hope
  about where a wrap falls.
- Text a person typed (a caption, a brief, a note, a place) breaks anywhere
  (`overflow-wrap: anywhere`), and a grid holding it states
  `minmax(0, 1fr)`, never an `auto` track: one unbroken link otherwise widens
  the card and the page. The walk seeds a 120-character link on both client
  pages. An address that is a row's meta line under its name is one line
  ending in an ellipsis (`.tlink-row`); the whole address is one press away.
- An overlay is positioned against the box it explains (`.sched-field`), never
  its container.
- An image sized by one axis in a box that can clamp the other is squashed. The
  brand mark is `object-fit: contain; object-position: left center`.
- The bar and the foot run to the screen's edges on every page. Content keeps
  its reading width.
- The foot stands on the page's own ground (no band of its own), a `--line`
  rule above it; its bottom pad is the larger of 16px and the home bar's
  inset, never the two added.
- The last "not centred" is usually two type sizes. Measure the ink, the
  borders and the type before calling it even.

### Records
- The head is two parts centred on each other.
  - Left: the mark, the name and the meta.
  - Right: `.rec-ctl`, the state (chip or select, `align-self: center`) and one
    ⋯ holding Edit and Delete. Never Edit standing beside the name.
  - On a phone: `"mark . ctl" / "who who who"`.
- The landing pane is the record itself, built from what is loaded: flat
  sections with one control each; empty ones say so in a line.
- The rail is one block per question, ordered by need. A block with no data
  leaves. A written next action beats a derived one. A missing date's row is
  left out.
- A choice and an action never share a row unseparated: the choice carries
  its label at the left, the action sits at the right edge with its count
  just before it (the draft's language beside Write draft).
- A fact is stated once on a screen. A control that changes it answers
  (`Saved.`), and puts itself back on a refusal.
- A mark holds real artwork (`logo_url`, falling back to initials only while
  none is held). No monogram or avatar placeholders anywhere, no empty dashed
  discs.
- A completion figure is never the whole message: the bar carries its missing
  list.
- A page opens on what it is for, and everything that explains it folds. The
  fold's head carries the summary it is read for.
- A long list needs an axis (Group by) and a bound that never covers open work.
  Off the default axis every card is shut and the heading carries the count
  that matters.
- The commonest act on a row belongs on the row. A control inside a control is
  never nested: the name cell opens the record.
- A forward move is a button at its own width, never full width. Revert beside
  it is neutral, never a second blue.
- The booking register clips its own rows (`.bookreg { overflow: hidden }`).
- A board is the same rows, one workflow at a time. Columns exist only where
  work can go. The drag reaches the same move as the select.
- A card on a board reads in order: what it is, whose it is, when it is owed.

### Forms, sheets, buttons
- Every add or edit form is a sheet over the list, never a panel unfolding at
  the top, never a form replacing the record's head.
- Buttons:
  - `.btn` is tonal (shaded, never outlined; fields keep the ring). The one
    outlined control is the contact chip `.plink`.
  - No bare text links in the portal: a way somewhere is a button, a chip
    or a `.btn-quiet` with a chevron (`.ovgo`), never an underlined word.
    Inside a line of facts it is `.linkbtn` (quiet, chevron, no underline);
    a typed address (a website, a profile, a past link) is a `.plink`.
  - The command bar's controls are 32px and take the small corner
    (`--radius-ctl-sm`).
  - `.btn-primary` is ink.
  - `.btn-go` is blue.
  - `.btn-warn` is warn on its tint (reversible caution).
  - `.btn-danger` is red.
  - `.btn-quiet` is text only.
  - `.btn-sm`.
  - A sheet Cancel is `.btn-quiet`, never a bare `.btn` (`flex: 1` grows it).
    `.sheet-foot > .btn { flex: 0 0 auto }`.
- **Action rows read Cancel / secondary / Save from the left, anchored to the
  right edge** (`flex-direction: row-reverse`; the markup keeps the primary
  first).
  - Applies to `.sheet-foot`, `.row.acts`, `.changebox-actions`,
    `.zone-actions`, `.qform-acts`, `.filearm-acts`.
  - On a phone the two halves are equal, Cancel on the left.
  - A count in the foot sits to the left of the pair (above it on a phone).
- Controls in a row share a width and a height. `.row` aligns to the top, and
  `.row > .btn` to the bottom. A field standing alone fills its container.
- A required field carries a red asterisk from `aria-required`.
- A typed box (`textarea`) runs its row's width and stretches downwards only
  (`resize: vertical`): a sideways drag never widens the page.
- A native field is reskinned to our box:
  - `::file-selector-button` shaded (`--line-soft`), concentric, 13px;
  - a date or time field with `appearance: none`, the value left aligned,
    `min-height: var(--ctl-h)`, and a glyph on the left under a coarse pointer;
  - at a desk a date box reads DD/MM/YYYY with the calendar mark at its right
    edge (`.dmy`, `js/form.js` §7); written dates stay `12 Sept 2026`;
  - the "Not set" hint on the field's wrapper.
- A control that creates a need answers it in place: the tick grows into the
  field (`.pbox`); the name grows out of Approve (`.namebox`). Both ends of a
  width animation are stated.
- One action is not a banner. A head's or bar's lone action keeps its own
  width; `:only-of-type` and `:has(.btn + .btn)` count `:not([hidden])` only.
- A field inside a growing box draws its focus ring inside itself
  (`.cmdbar-find .input:focus`).
- A value only read is not a field.
- A destructive item is red on the item itself.
- A button that acts carries its action's glyph wherever it is drawn: a plus
  to add, a pen to edit, the copy mark, the file mark to download, the leaving
  mark after anything that opens in a new tab (Preview, Open), the chevron
  after a way to another console page. A form's own commit (Save, Cancel, a
  submit, a sheet's foot, a confirm) is words. `uxaudit` `glyph` fails a
  label drawn both ways.
- A border inside a border groups nothing, so the inner one is shaded.
- A word or a value that acts inside a line of text (`.linkbtn`, `.tdate`,
  `.tinline`, `.serial-copy`) keeps its whole target but never shows it: its
  hover fill hugs the line (26px, a `::before`), never a slab the height of
  the target.
- The ⋯ is the lightest control. The account control, the bell and the
  Activity link carry no outline, only a `--line-soft` fill on hover and while
  open.

### Colour, state, hover
- One status vocabulary and one colour set, on console and client pages alike
  (`W.TONE`). Pending and reviewing are warn.
- A stage select is toned by `stage_group`:
  - not started: mute;
  - in hand: none;
  - waiting on a person: warn;
  - cleared: green;
  - blocked: red.
- A lifecycle flag flipped once (Active / Inactive) is a chip plus a ⋯ item,
  never a select on every row.
- Hover is one step lighter than selected (`--sunk` against `--line-soft`),
  never equal. Every hover lives inside `@media (hover: hover)`. A hover is the
  next step of its ground, never `--fill`.
- The chosen one of several is a fill, never a shadow and never a weight:
  every tab, view, segment, nav item and finder option reads at 400, chosen
  or not (the user, 2026-10-04);
  - a nav item: `--line-soft`;
  - a tab, a view and a segment alike: one raised thumb that slides on the
    tonal track (`.rectabs`, `.tabrow`, `.cmdbar-views`, `.seg`);
  - a segment (a value picked) is a pill, track, options and thumb, its
    options 14px either side of the word; a tab or view strip (a screen
    moved to) keeps its corners. Round chooses, rectangular acts. A small
    select (`select-sm`) makes a small segment (`.seg.is-sm`): the small
    control's height and 12.5px type, options as wide as their words, the
    height of the small button it sits with;
  - an `.acttab` outside a strip: the ink fill.
- A ticked row's fill must not cost a control its edge (an untinted select on
  a ticked row takes the mute ink edge).
- The iOS tap highlight is off (`-webkit-tap-highlight-color: transparent`).

### Responsive and phone
- Breakpoints:
  - 640 is the phone line (`.crm-head` hides; facts go two across);
  - 560 and 760 adjust some cards and sheets;
  - 1100 splits the record rail.
- `pointer: coarse` raises controls to 44px.
- Test at 1280 and 390; the matrix adds 320 to 1440 and 200% zoom.
- No horizontal overflow. A 16px side gutter. Never a sideways table (a
  board's columns are not a table).
- The head card ends above the fold. Nothing is clipped under the sticky bar.
  Sheets are measured in `dvh` (falling back to `vh`), are full height on a
  phone, come from the floor, and pad the safe area.
- A line of parts (`client · 10 creators · RM 8,640.00`) wraps between its
  parts, never inside one: a count and an amount hold their spaces.
- A narrow cell keeps its heading's meaning: a bare figure names itself when
  the header hides (`Over by | 4 days`).
- The phone command bar is one row plus the view segment.
- On a phone the bell's panel takes the page gutters
  (`.kmenu.notif-menu`, fixed, 16px each side).
- The My Work view strip scrolls sideways with faded edges
  (`is-more-start`, `is-more-end`). Every view keeps its whole word.
- **Phone checklist, read on every screenshot:**
  - no cell alone on its row;
  - no value wrapping inside a cell;
  - buttons sharing a row share a width;
  - the primary is nearest the thumb;
  - a table row is two or three lines;
  - a lone field fills its container;
  - no pinned `style` width survives the phone line.

## 6. Copy
- No explanatory copy: no hints, blurbs, notices or role descriptions.
  - The heading and the controls are the explanation.
  - Where a line is unavoidable, one neutral corporate sentence; no "we", no
    "you should".
  - Nothing says the same thing twice (a cover line never restates its title;
    a chip never repeats its column).
  - The one exception is the route's one-sentence purpose, which opens from
    its name.
- Buttons:
  - one to three words, sentence case, verb first;
  - no article, and no object the context gives (**Delete**, never
    `Delete client`);
  - a menu item is the action's name only.
- Formal names take title case: documents, agreements, forms, checklists and
  reports (Letter of Offer, Service Agreement, HR Letter, Onboarding Checklist,
  Social Media Accounts Report).
  - Articles and short prepositions stay lower; acronyms keep their capitals;
    Pre-advertising Checklist.
  - Everything else is sentence case.
- Back / Revert / Restore / Reinstate / Undo as in `CLAUDE.md`; never "Return".
- One vocabulary:
  - Creator steps: Confirmed, Pending visit, Pending draft, Submitted,
    Reviewing, Changes requested, Scheduled, Posted, Completed, Withdrawn.
  - Service lines: Enquired, To quote (never Quoted), Confirmed.
  - Client stages: Lead, Contacted, Proposal sent, Active, Paused, Past.
  - Requests: Requested, Reviewing, Approved, Declined, Applied, Withdrawn;
    kinds Upgrade, Downgrade, Cancel, Change of details.
  - On/off: Active / Inactive.
  - Performance: Draft, Shared, Query raised, Query answered, Acknowledged,
    Final; an issue (never breach), notes and a reference (never evidence),
    a query (never dispute) answered Agreed, Partly agreed or Not agreed;
    grades Needs support and Improvement plan; the recovery path.
  - My Work: Assigned to, Content task, Posts, For, Month, Format, Due date,
    Draft due, Post date, Checklists.
- Words are the ones people already use at work, never a legal, police or
  system word (the user, 2026-10-05: "why use evidence. Sounds like some
  criminals"). Only the words change; stored keys never move.
- A state is named for what is true when it is set. A field about a person
  records what we do ("Prefers English", Preferred language). A cover title
  names the outcome (Access denied). A section is named for what it tells you
  (Portal access, Person, Sign-in email).
- A control is named for what it does:
  - Enable backup selection.
  - Add creator.
  - Request extension, when it will only ask.
  - Creators List (never "roster").
  - Assigned to and Created by (never Task Owner, Owner or Manager);
    Reassign; Unassigned.
  - Add another; Create 3 tasks.
  - Import from spreadsheet.
  - Transfer client (a report to the client it belongs to), never Move to
    client.
  - White label (on a client's Brand: its reports carry the client's wide
    logo; on a report: the white-label client and the brand it covers);
    Wide logo; Brand on the report.
- Headings name their content: Task details, Posts, Schedule, Repeat,
  Assignment, Date and time, Meeting channel, Frequency, End of repeat, Call or visit
  details, Contact details, Task settings, Inclusions, Time records, Team
  member.
- Messages:
  - a success is one or two words ("Saved.");
  - a validation names what is required;
  - an empty list is two words ("No entries."), never "yet".
  - A missing value in a table cell is a mute em dash (the one place a dash is
    allowed).
- Count creators, not slots. rednote is lower case; never Xiaohongshu or
  RedNote. Say Post, never Note.
- Placeholders: a value a person would type, from one generic set: John Doe
  (Jane Doe for a creator), email@adspace.me (a colleague's
  email@adspacestudios.com), @adspace.advertising, ADspace Advertising (a
  Facebook page), 012-345 6789, 07-123 4567, https://adspace.me, COMPANY
  NAME SDN BHD, AC001, AD001. A field with no natural example keeps a short
  hint (Optional, One point a line). Never a real client, creator or
  colleague, nor a code one could hold.
- ADspace alone, never "ADspace Studio" (a strict rule).
- Brand names exactly: ADspace, S P Setia, CraftStone, Home Leader, The Mill
  International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim Motorsport,
  Star Living, Niro Granite, Dale & Cecil, Dale.
- Chinese is localised, not translated.
- No dashes in copy where avoidable. Dates `12 Sept 2026`, months `Oct 2026`,
  money `RM 8,490.00`, agreement prose `16 September 2026`.
- Client-page cover words live in `js/words.js`:
  - "Link not recognised / Please contact your ADspace account manager.";
  - "Access code / Enter the access code provided.";
  - "Unable to load / Please refresh…".

## 7. Architecture
- The Overview sits alone above the two chunks, with no label, drawn only for
  a group that manages a section (`CLAUDE.md`).
- The rail runs in two chunks, ordered by frequency, with the same sequence
  everywhere:
  - **Work**: My Work, Clients, Content Review, Creator Campaigns.
  - **Records and setup**: Documents, Reports, Short Links, Services, Team,
    Handbook.
  - The Activity record sits at the rail's foot (`.sidebar-foot`, a `.railrow`,
    not a section).
  - A chunk whose every route is withheld hides its label.
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
- Numbering:
  - Letter of Offer `AQL/{client_code}/{YYMM}{NN}`;
  - campaign invoice `AINV` plus six digits, typed;
  - tasks `#WT00001`;
  - task codes `YYMMW{week}{NN}`;
  - HR `ADHR/…`;
  - client letters `ACL/{client code}/{YYMMDD}{NN}`.
- Row ⋯ menus are placed on the viewport. A faded row fades its content, never
  its ⋯. The global click handler spares `.kcard-head`, `.kmenu` and
  `.team-act`. A modal that filters keeps one height.

## 8. Theories applied on every change (at 1280 and 390)
- **Fitts**: 38px desk and 44px touch targets; the primary nearest the hand.
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
  cannot apply yet is hidden, not disabled, and leaves again when reverted.
  What a client may not see is withheld by the function.
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
