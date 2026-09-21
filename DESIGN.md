# ADspace Digital Portal — design system, architecture and laws

Imported by `CLAUDE.md`. Every screen, every push, every screenshot is
checked against this file.

## 2. Design system

### Register
Apple / Cloudflare: clarity, deference, depth by layering not by
shadow. Flat, quiet, one accent, corporate, warm neutrals. Never "AI
SaaS": no rainbow gradients, no decorative shadows, no coloured dots for
status, no explanatory blurbs, no highlighter colours.

This is a portal a team works in all day, not a page read for forty
seconds, so it is tuned for the long session: few visible lines, light
boundaries, generous space, full text contrast, and a theme that follows
the reader's system.

### Colour tokens (`css/portal.css` `:root`)

Neutrals are **warm**, not cool. A low saturation grey with a blue-green
cast reads clinical, which is the wrong register for somewhere a team
sits all day; a few degrees towards yellow reads considered instead, and
is what the quiet corporate sites this portal takes after actually use.

What is lowered to make a long session comfortable is the **weight of
the boundaries**, never the contrast of the text. Apple's body text is
about 16:1; the calm of those pages comes from few visible lines and
generous space, not from dim type. Every pair below clears WCAG AA and
`uxaudit` measures it on the real page in both themes, so a "softer"
palette can never be bought with legibility.

| Token | Light | Dark | Use |
|---|---|---|---|
| `--ink` | `#1b1a17` | `#eff0ea` | Text |
| `--ink-soft` | `#524e47` | `#c6c8be` | Secondary text, default button text |
| `--ink-mute` | `#6b6760` | `#a6a89e` | Labels, hints, quiet buttons (4.5:1 on every background) |
| `--line` | `#e2dfd8` | `#3a3c36` | Card borders, table rules |
| `--line-soft` | `#ececec` | `#2e2e2e` | Row dividers, the selected fill |
| `--line-ctl` | `#8e8a80` | `#83857c` | Input, select, textarea and outline button borders: 3:1 on every background |
| `--page` | `#f5f5f5` | `#161814` | The ground. ADspace's own off white, the one paired with `#1a1a1a` on the website: a brand value, not a tuned one, and never "corrected" back to a warm grey |
| `--card` | `#ffffff` | `#1e201d` | Panels, tables, rows |
| `--sunk` | `#f9f9f9` | `#272727` | Inset areas, table sub-headings, hover |
| `--fill` / `--on-fill` | `#1b1a17` / `#ffffff` | `#eff0ea` / `#191b17` | The solid ink surface and its text: primary button, selected `.acttab`, progress. **Not the Undo bar**: a full width ink slab a few pixels above an ink Add contact read as one enormous call to action, and the fill is what names the primary action |
| `--action` | `#0b57d0` | `#a8c7fa` | **Blue means forward action.** Publish, Release, Submit and the client's Approve use it; ordinary Add, Create and Save operations use the ink fill. White on `#0b57d0` is 6.39:1 and clears AA for normal text; Apple's own `#007aff` manages 4.02:1 with white on it and is not an option for a button this size. In dark the fill is light, so the pair swaps like every other fill here |
| `--action-hover` / `--action-pressed` | `#0847ae` / `#063989` | `#c2dafc` / `#d3e3fd` | Its hover and its pressed step, both stated, because a button that answers nothing under the pointer reads as furniture |
| `--on-action` | `#ffffff` | `#062e6f` | Its text. 8.5:1 in dark |
| `--action-ring` | `#8ab4f8` | `#8ab4f8` | The focus ring on everything a keyboard reaches. Ours, not the platform's: the console's focus colour used to be whatever the browser drew and differed between two machines looking at the same screen |
| `--accent` = `--ok` | `#1f7a4d` | `#4aa876` | The one green: **live state and success only**. It used to carry the forward button as well, so a screen could not say "press this" and "this is running" in two different voices, and a page of green chips competed with a green button for the one accent. Approved on a review card is green because by then it is a fact and no longer an action |
| `--ok-bg` | `#ecf5f0` | `#17281f` | Its tint |
| `--ok-solid` / `--on-ok` | `#1f7a4d` / `#ffffff` | `#4aa876` / `#07150e` | A green **fill** and its text |
| `--warn` / `--warn-bg` / `--warn-line` | `#a94d0c` / `#fdf1e7` / `#f1d3b8` | `#cf9350` / `#2a2217` / `#4a3520` | Caution, unpublish, pending and reviewing states. **Amber only while it is plainly orange**: the earlier `#9c5c16` had drifted to brown, and a brown chip on a cream tint read as a notice board rather than a warning. 5.05:1 on its own tint. **A refusal is red, not amber**: the billing gate on a client record is `--err`, because the database will not allow Active until the fields are filled, and a caution's colour on a refusal read as an announcement |
| `--warn-solid` / `--on-warn` | `#9c5c16` / `#ffffff` | `#cf9350` / `#1d1408` | A warn fill and its text |
| `--err` / `--err-bg` / `--err-line` / `--err-hi` | `#b3261e` / `#fdeceb` / `#e9b9b5` / `#8c1d18` | `#e8837a` / `#2e1d1b` / `#6a3a35` / `#f2a9a2` | `.msg.err`, danger menu items, the one danger button; `--err-hi` is the pressed step, never a second red |
| `--focus` | `rgba(31,122,77,.18)` | `rgba(74,168,118,.30)` | The focus ring, on every control, never removed |
| `--chrome` | `rgba(255,255,255,.88)` | `rgba(22,24,20,.88)` | The translucent sticky bars (top bar, console head, confirm bar) |
| `--scrim` | `rgba(0,0,0,.42)` | `rgba(0,0,0,.62)` | Behind a sheet |
| `--shadow` | `0 1px 2px rgba(19,24,26,.05)` | `0 1px 2px rgba(0,0,0,.5)` | Panels only |
| `--shadow-lift` | menus only | menus only | Nothing else casts a shadow |

**Every colour is a token.** A colour written into a rule cannot follow
the theme, and that is exactly how a light top bar and black button text
survived into dark: `rgba(255,255,255,.88)` on `.topbar`, and a native
`button` taking the platform's own `buttontext`. Hence `color-scheme:
light dark` on `:root` and `color: inherit` on `button`, so what the
browser draws (select popups, scrollbars, the caret) follows too.

**A fill and its text are always a pair.** In dark the fill is light, so
`color: #fff` on it disappears. Never `background: var(--ink); color:
#fff`; always `var(--fill)` / `var(--on-fill)`, `var(--ok-solid)` /
`var(--on-ok)`. A hover that used to be a darker hex is `filter:
brightness()` on the same token, so one value still drives both themes.

**One colour per promise.** Blue moves work to somebody else, green reports,
amber cautions, red destroys, and everything else is neutral. Add, Create and
Save are ink-primary operations; Publish, Release, Submit and Approve are blue
forward actions. A view carries one prominent blue action, two only where it
genuinely offers two forward decisions; `uxaudit` counts `.btn-go` and
`.btn-approve` per scope and fails at more than two. Copy link, Preview, Edit,
Cancel and every row-level action stay neutral. The screen stays about nine
tenths neutral, which is what makes blue useful rather than decorative.

**A hover state lives inside `@media (hover: hover)`, without exception.**
`.btn:hover` did not, and it outranks `.btn-primary`: a tap on a phone leaves
`:hover` on, so an ink-text hover can land on a filled primary. The same
applies to `.btn-warn`, `.btn-danger` and `.btn-quiet`, whose hover fills would
otherwise stay stuck on the last thing a finger touched.

**The accent marks the exception, not the norm.** Green is the live state, but
a state that is true of nearly every row carries no information, and painting
it green spends the one accent on the ordinary case. Thirty two of the thirty
four rate card lines are Active and so is every colleague: a column of green
Active selects made the default the loudest thing on the screen, louder than
the price beside it, and left the two rows that were **not** active looking
like all the others. Where a state is the default for its list, the row says
nothing while it holds and names the exception when it does not (`Inactive` as
a neutral chip, the row faded). Where a state is a real position in a pipeline
— a client stage, a campaign step, a request — green still marks a milestone
only a minority of rows have reached, and stays. The test is not "is this
live", it is "would marking it tell anybody anything".

**One value per semantic colour where it can do both jobs.** In dark,
`--ok` is legible as text on every surface *and* deep enough to carry
dark text as a fill, so there is still one green. A paler mint passed the
same checks and read as a highlighter pen, which is not this register.

**The grounds are neutral; the warmth is in the marks.** `--page` is the
brand's own `#f5f5f5` and `--card` is white, so the two largest surfaces
agree with each other. **Every filled surface follows them**: `--sunk` and
`--line-soft`, which paint inset areas, hover and the selected nav item,
are neutral greys at the same lightness as the warm ones they replaced, so
the selected item keeps exactly the contrast it had and simply stops being
the one warm patch on a neutral screen. The warmth stays on the marks:
`--line` (borders) and the whole ink ramp.

A filled surface is **not** set to `--page`. `#f5f5f5` is the page's own
value, and the sidebar it would sit on is white: selected would fall from
1.18:1 to 1.09:1 against that white and the gap to hover would collapse
from 1.12 to 1.04, which is the law that hover is never equal to selected.
Same lightness, neutral hue, is the change; the brand value is not a
paint to reach for wherever a grey is needed.

### Themes

**Light is the default everywhere. Dark is the console's, and only ever
by choice.** It is deliberately not taken from `prefers-color-scheme`: a
client who happens to keep their phone in dark mode would be deciding on
a proposal in a register nobody chose for that conversation, and the mood
a decision is made in is not ours to set by accident. So:

- `/client/`, `/creators/` and `/review/` have **no dark at all**. They
  never carry `data-theme`, whatever is in that browser's storage.
- `/admin/` carries a toggle in the sidebar foot, above Sign out, naming
  the theme it switches to the way a light switch does. The choice is
  kept in `localStorage` under `adspace-theme`, per browser, never on the
  account.
- A four-line script in the console's `<head>` applies the stored choice
  before the stylesheet paints, so choosing dark does not flash white on
  every load.
- The palette hangs off `:root[data-theme="dark"]`, never a media query,
  and `color-scheme` follows it so the browser's own chrome (select
  popups, scrollbars, the caret) matches.

Only the colours move; every size, space and shape is the same screen, so
a layout that is right in one theme is right in the other.

Two things deliberately stay light even inside the console:
- **The post mockups** (`.mk-*`, `.fb-*`, `.ig-*`, `.xhs-*` and the
  `.card-stage` they sit on) reproduce each platform's own UI. Instagram's
  feed is white; a dark one would stop being a preview of what the
  client's audience sees. They are outside the audit for the same reason.
- **The client logo disc** (`.bigcard-logo`, `.logopreview`, the mockup
  avatar). The logo is the client's artwork, usually dark on transparent,
  and it is not ours to invert. The ADspace wordmark is one flat colour
  on transparent, so that one *is* inverted rather than shipped twice.

`uxaudit` walks the console in **both themes at both widths**, turning
dark on the way a person does (the stored preference, read by the page's
own head script). The client pages are walked in light only, because they
have no other state; walking them twice would measure the same theme
twice. Contrast is the rule most easily broken by a colour written into a
rule, and a theme nobody audits is a theme that quietly fails AA.

### Shape and size tokens

| Token | Value | Use |
|---|---|---|
| `--radius` / `--radius-sm` | 14px / 10px | A bounded section (panel, card, table, sheet) / anything a finger operates (button, input, select). `--radius-panel` and `--radius-ctl` are aliases of those two, `--radius-lg` is 18px for a sheet. **Two corners and nothing between them**: a contacts table at 10px sitting between two panels at 14 is the mismatch nobody can name and everybody sees, and a third pair of tokens beside the first two is how that happened |
| `--head-h` | 64px (56px on a phone) | The chrome bar, on every page. `.topbar-inner` takes `calc(var(--head-h) - 1px)` because `.topbar` carries the hairline outside its box while `.console-head` carries it inside, and without that the two differ by exactly the border |
| `--ctl-h` | 38px (44px coarse pointer) | Every button, input, select, icon button |
| `--ctl-h-sm` | 32px (44px coarse) | `.btn-sm`, `.input-sm`, `.select-sm`, every status select |
| `--state-w` | 124px | Every status select, on a head as in a row |
| `--ctl-text` / `--field-text` | 13px / 14px (16px coarse, stops iOS zoom) | Control label / field text |
| Button min width | 116px | So a row of buttons does not step |
| Icon glyph | 15px stroke, 1.8 | Same glyph for the same action everywhere; never mix outline and filled |
| Icon button box | 38px (44px coarse) | `.iconbtn`, `.kfold`, `.kmenu-btn`, `.btn-icononly`: the glyph stays 16px, the target never shrinks with it |
| Ring | 18px, stroke 2.6 | `.ring` completeness indicator |

### Motion

**Motion drifts exactly the way colour does, so it is tokens too.** Nineteen
transitions had been written at their point of use, in **nine durations**
(`.14s`, `.15s`, `.16s`, `.18s`, `.2s`, `.22s`, `.25s`, `.28s`, `.32s`) and
three curves (`ease`, `cubic-bezier(.4,0,.2,1)`, and whatever the browser
does by default), so no two things on one screen moved alike and a portal
somebody works in all day felt assembled from parts. Three durations and two
curves now, in `:root`, and nothing outside this table.

| Token | Value | Use |
|---|---|---|
| `--t-fast` | `.12s` | A colour, a border, a press: the pointer has not left yet |
| `--t` | `.2s` | The ordinary state change |
| `--t-slow` | `.34s` | A size, a position, a surface opening |
| `--ease` | `cubic-bezier(.32,.72,0,1)` | A **move**: something changes place or size. Fast away, long settle, which is what reads as unhurried rather than springy |
| `--ease-out` | `cubic-bezier(.22,.61,.36,1)` | Something **arriving**: decelerates, never overshoots |

**A press is felt, not just seen.** Every control takes the same
`transform: scale(.97)` on `:active` at `--t-fast`, so the whole portal
answers alike under a finger: `.btn`, `.iconbtn`, `.kmenu-btn`, `.kmenu-item`,
`.navitem`, `.tab`, `.acttab`, `.crow-tick`, `.crow-backup`, `.langtoggle`,
`.plink`, `.pbox`, `.state-select`. The exception is a control that fills the
width of a phone: a slab that shrinks reads as a wobble, so it dims to `.72`
instead.

**A surface arrives; it does not blink into place.** The ⋯ menu comes from its
button (`translateY(-5px) scale(.97)`, origin top right), the sheet fades its
scrim and lifts its card, and on a phone the card comes up from the floor it
is anchored to. `offsetHeight` is a layout measure and no transform touches
it, so `ADspaceMenu.place()` still reads the same number it always did. The
Undo bar slides down from the row it belongs to.

**Nothing moves for a reader who has asked for stillness.** One
`prefers-reduced-motion` block zeroes every duration and every press
transform. This file had claimed that behaviour for months while the code
carried three scattered rules that only ever quietened two carets.

### Typography (system stack; `--font`: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial; Chinese adds PingFang SC, Microsoft YaHei by `lang="zh"`)

| Level | Size / weight / tracking | Where |
|---|---|---|
| Section heading | 19px / 600 / -.02em | `.viewhead h2`, `.crm-title h2` (record name) |
| Sub-heading | 16px / 600 / -.01em | `.viewhead h3` |
| Panel and group title | 15px / 600 / -.01em | `.panel h3`, `.crm-group-head h3`, `.kcard-name`, `.ovsec-head h3`, `.railtitle` (the rail heads the same kind of block the pane does; as an 11px eyebrow it read as a footnote to the pane rather than its other half) |
| Body | 14px in the console, **16px on the four client facing pages** (`:root[data-face="client"]`, set on the `<html>` of `/creators/`, `/creator/`, `/review/`, `/client/`), line-height 1.55 | `body`, `.facts dd`, `.svc-name b` (600). The console is a dense tool read all day at a desk, which is the departure this portal documents; a client reads one page once, usually on a phone, and is being asked to decide something on it. Only what inherits moves: controls, labels and chips state their own size, so the shapes are identical on both sides |
| Money in a row | 13.5px, tabular | `.svc-rate` |
| Control, small text | 13px / 12.5px | `.btn`, `.btn-sm`, `.svc-calc`, `.backlink` |
| Meta and labels | 12px | `.field-label`, `.svc-name small`, `.crm-lang` |
| Chip and select | 12.5px / 600 and 11.5px / 600 | `.state-select`; `.tone`, `.chip`, `.chip-state` (one chip shape: 11.5px, radius 5px, padding 2px 8px, sentence case, never an uppercase pill) |
| Label | 12px / 600 / sentence case, mute, no tracking | `.facts dt`, `.kstep-title`, `.crm-head`, `.svc-cat`, `.sectionlabel`, `.ovhead`, `.team-head`, the sidebar kicker. **The tracked uppercase eyebrow is retired** (2026-09-22): it was 11px with .06em of tracking on every table header, band and fact label, and the user sent it back as a wide, spaced face that read as decoration. The platform mockups keep their own, because they reproduce another product's UI |
| Numbers in cells | 17px / 600 / -.02em | `.tally-cell b` |
| Brand wordmark fallback | 16px / 700 / -.02em | `.brand-logo` text when the image fails |
| Display | 24px / 600 / -.02em (21px on a phone); 26px on the review hero; 20px batch title | `.cover-panel h2`, `.camphead h1`, `.batch-title` |
| Floor | 11px | Nothing in the portal is set smaller; the audit fails on it (`type`). The review mockups reproduce each platform and are exempt |
Monospace (`ui-monospace, SFMono-Regular, Menlo`) 12.5px for slugs, tokens and code only.

Print (the Letter of Offer) follows the ADspace letterhead: wordmark
"ADspace" in Optima 14pt (`ADSPACE_ORG.fontMark` = `/css/OPTIMA.TTF`), body
in Slate Book 11pt on a 14.5pt line with 14pt between paragraphs
(`ADSPACE_ORG.font` = `/css/SlateBook.TTF`), the heavier lines (PRIVATE &
CONFIDENTIAL, the subject, ADSPACE PLT) in Slate Regular
(`ADSPACE_ORG.fontBold` = `/css/SlateRg.TTF`; no Medium file exists),
registration 9pt, table 10pt, notes 8.5pt, page count 7.5pt. Margins 54pt.
The monogram (`/css/adspace-mark.png`) sits 21pt tall top right and 20pt
bottom centre. No Company Profile QR on a letter. Config holds file
paths, never font names.

**On screen, one brand face, on the display sizes only.** Slate Regular
is already in the repo for the letter, so the portal and the paper it
prints share a voice without a second asset or a webfont service:
`@font-face { font-family: "ADspace Slate" }` served as
`/css/SlateRg.woff2` (38KB against the TTF's 110KB; the TTF stays because
pdf-lib fetches it, and doubles as the fallback), `font-display: optional`
with `<link rel="preload" as="font" crossorigin>` in every page head. Not
`swap`: swap paints the heading in the system face and flips it a moment
later, which is the page correcting itself while somebody is already reading.
Optional gives the face a brief window and, if it misses, leaves that one load
in the fallback rather than swapping under the reader; the preload starts the
fetch with the stylesheet instead of after it, so it almost never misses, and
after the first visit it is cached.
It is applied through `--font-head` to `.viewhead h2`, `.crm-title h2`,
`.cover-panel h2`, `.camphead h1` and `.batch-title` and nowhere else:
body, labels, controls and chips stay on the system stack, where a hinted
system face beats a downloaded one at 12px and needs no download to be
legible at all. Chinese has no Slate, so a `zh` heading falls through the
same stack to the system face at the same size. Optima is the letterhead
wordmark and stays out of the portal.

A service is quoted by the month, never sold by the piece, so the lines
table is **Description, Rate, Amount** and nothing else. Quantity rides
inside the rate cell only where it is not one (`3 × RM 600.00`); a Qty
column that always reads 1, or a Unit price column repeating the Amount,
is a column saying nothing and is removed. The term sits mute under the
Amount it explains (`6 months`), so a figure larger than the rate is
never a surprise. Under the name come the inclusions (`detail`, one per
line), then a 4pt step, then the pricing basis, period and note on one
mute line: what they get, then the terms of it (Gestalt proximity).
Weight carries the reading order, so the name is Slate Regular at 10pt,
the amounts 10pt, everything qualifying them 8.5pt mute; lines under a
name sit 11pt apart and services 10pt further, so each service reads as
one block.

**The term prices the line.** Six months is the minimum a monthly service
is sold on, so it is the baseline and costs nothing. A shorter term carries
the margin a longer one would have earned and a longer commitment earns a
discount, and the two are not the same operation: a short term **divides**
(RM 1,000 over three months is `1,000 / 0.9` = RM 1,111.11 a month, holding
the margin) and a long term **multiplies** (12 months is `rate × 0.95`).
Writing "+10%" and "−5%" in one column hides that difference. The factors
live in `js/money.js` (`TERMS`, `rateFor`, `termWord`) and nowhere else, so
the console, the letter and the client's page read one definition and
cannot drift; a term the rate card does not name costs nothing, because a
rule nobody has written is not one to invent at quoting time.

The adjusted figure is what the **Rate** column shows, because it is what
the client is billed, and the mute line under the name says why it is not
the rate card's figure ("Per month, 6 month minimum · 3 month term, 10%
short term adjustment"): the minimum and the departure from it read as
cause and effect. The rate is rounded to the cent **where it is charged**,
so a total is always the sum of the invoices that make it up
(3 × RM 3,144.44 × 3 months is RM 28,299.96, not the unrounded
RM 28,300.00).

**The client accepts the figure they will be invoiced.** Where every line
runs the same term the letter is priced by the month: every Amount is one
month's, noted `per month`, and the bold line reads **Payable monthly**.
Never head a monthly engagement with the whole contract value, which asks
a client to accept a number they will never be billed. The commitment is
disclosed instead, in the **TERMS** block, in a plain sentence naming the
term and the figure ("The total payable over the 6 month term is
RM 18,338.40 including SST."), so nobody can say the letter showed only a
small monthly sum. A letter of one off or mixed lines has no monthly
figure, so it reads Total as it stands and carries no term sentence.
The closing and the acceptance block are **reserved together** before either
is drawn, because they are one thing: a page carrying nothing but a stamp
box is what the client is being asked to sign, and it has to stay attached
to the words it accepts. Reserving only the closing separated the two the
moment services carried their full inclusions, so the reservation is the
height of both.

**One name for the whole letter.** `To`, the opening paragraph and the
acceptance block each resolved the client's name themselves, and two of them
used the opposite precedence: `legal_name || name` in the header and
`name || legal_name` one paragraph below it. A client whose registered name and
trading name differ was therefore addressed as one in the header and the other
in the sentence beneath. A letter is an agreement, so the name on it is the
legal entity, resolved once (`legalName`) and used everywhere.

**Every line in the letter wraps, because a registered name is longer than the
column.** The reference block and the acceptance heading were drawn with a
single `text()` call, so `PERBADANAN PEMBANGUNAN PERUMAHAN DAN HARTANAH
NUSAJAYA SELATAN BERHAD` and an Attn line carrying a full job title ran off the
right edge and the tail was simply not on the page. Both wrap to the column
they started in. `tests/pdfcases.js` reads the glyph positions back with pdf.js
and fails anything crossing the margins, because a clipped string is clipped by
the media box and not by the stream: it decodes perfectly and is invisible to
every text assertion.

**The closing is reserved alone; the acceptance is its own page.** They used to
be reserved together, on the reasoning that a signature page carrying nothing
but a stamp box has to stay attached to the words it accepts. The effect once
services carried their full inclusions was that both moved, and page two opened
with three orphaned lines of sign-off before anything the client could act on.
The closing is reserved on its own and drawn where it falls, so the letter reads
as finished at the foot of its last page of substance; the acceptance follows as
a separate act. What keeps the two honest is not adjacency but the sentence and
the page count inside the acceptance itself.

**A signature is an area, not a ruled line.** 32mm of blank page labelled
`Authorised signatory and company stamp`, then Name, Designation and Date, each
a full width baseline with 10mm to write on, and the whole block kept on one
page. Every one of the four is also a real AcroForm field
(`acceptance_authorised_signatory`, `acceptance_name`, `acceptance_designation`,
`acceptance_date`), transparent and borderless so the drawn rule and its label
still show on paper — pdf-lib fills a field white and borders it black unless
the key is present, and that white default painted over the label under the
signing area. The appearance font is Helvetica, not the letter's own face: a
subsetted custom font carries only the glyphs the letter drew, so a recipient
typing a character the letter never used would get an appearance stream the
reader cannot build. The fields are widgets on the page and in the AcroForm
tree, so they do not depend on `NeedAppearances`. A typed field is a
convenience, not a certificate backed signature, and nothing in the portal says
otherwise.

**The figures a client accepts are a table, not prose.** `Acceptance of offer`,
one sentence naming the letter and its date, then Monthly fee, Contract term
and Total contract value from the same `priceOf()` object the price table was
drawn from, so the letter cannot quote itself two different totals. Agreement
prose takes a plain date (`16 September 2026`): an ordinal is a letterhead
flourish and this is the operative sentence.

**The initials go where the hand that writes them rests**, which is the side of
the page the signature is on: bottom right on every page but the signed one,
with the reference bottom left, the monogram bottom centre and the page number a
row below the initials, so the only two marks in the right of the foot cannot
collide.

**A letter that is signed on its last page is protected against having its
first one swapped.** The substance is on page one and the signature on page
two, so a signed sheet on its own proves only that somebody signed something.
Three marks, which is what ordinary commercial practice uses: every page foot
carries the **reference**, so a page lifted out still says which letter it came
from; every page but the one that is signed carries an **initials line**; and
the signature page opens with a sentence naming the reference, the date, the
number of pages and the figure ("This acceptance relates to Letter of Offer
AQT/INT/2609001 dated 14th September 2026, comprising 2 pages, at RM 3,396.00
per month over a 3 month term, RM 10,188.00 in total."), so a substituted page
contradicts the page that was signed. That sentence is reserved with the
closing and the acceptance block, because it is part of what is being accepted
and never leaves it. `tests/pdfreal.js` decodes the drawn file and asserts all
three, so step 6 is no longer a person remembering to decompress streams by
hand. Slate folds `ff` and `fi` into one glyph, so extracted text reads "Ofer"
and "Confrmed" while the page displays them correctly; the assertions allow
for it.

`js/documents.js` `priceOf()` works this out once for both the stored
snapshot and the drawing, so the two never drift; the stored
`subtotal`/`tax`/`total` stay the whole commitment, which is what the
record and the pipeline are worth. Conditions go in that one TERMS block
(label 9pt bold mute, the table header's style; body 9.5pt), three short
sentences at most, never a sentence here and a sentence there; the
validity line lives there too.

### Spacing scale and vertical rhythm
Scale for gaps between blocks and sections: 4, 8, 12, 16, 24, 32. Component paddings are the values in the table below and nothing else.

| Where | Value |
|---|---|
| Section head (`.viewhead`) | 24px above, 12px below (phone 22 / 12) |
| Blocks stacked inside a section (a table, a panel, a fold, an empty state, a card, the Undo bar) | 12px between every pair, whatever the block is; `uxaudit` fails a section whose gaps differ (`stack`) |
| Sections in a list (`.crm-group`) | 24px |
| Panel padding | 18px 20px (phone 14px) |
| Fold head (`.disclosure`) | 16px 22px (phone 12px 14px) |
| Row padding in a table | 10px 15px (phone 12px 15px); a header row `0 15px 8px` |
| Field row gap (`.row`) | 12px; a second row 12px above |
| Cell grid gap (`.facts`, `.tally`) | 14px 24px / 14px |
| Card list gap (`.cards`, `.kcard`) | 14px / 10px |
| Table sub-heading (`.svc-cat`) | 14px 15px 6px |

Law of the stack: two blocks that follow each other in one section are
always the same distance apart, no matter which block. A table sitting
against a fold with no gap, or a fold with a larger gap than the table
above it, is a bug. A table with no header carries no header pad; the
first row sits as far from the top as the last does from the bottom.
A header the phone hides is not a header: its pad belongs to the header
row itself (`.crm-head` padding `12px 15px 8px`), never to the table, so
it leaves with the header at whichever breakpoint hides it. `uxaudit`
measures the table whenever its header is not on screen (`padding`).

### Components (the only ones; a new screen is built from these)

| Need | Component |
|---|---|
| Section heading with its one action | `.viewhead` > `.headmark h2` + `.btn.btn-primary` with icon |
| Text facts | `dl.facts`: label over value; the column count follows the cell count (4, 5 or 6 across); two on a phone with the fifth spanning the row |
| Counts and money | `.tallies` > `.tallygroup` > `.kstep-title` + `.tally` > `.tally-cell` (`is-total`, `is-warn`); counts three across on a phone, money two across with the total spanning |
| Rows of records | `.crm-table` > `.crm-head` + `.crm-row` / `.svc-row` (`csv-row` service lines, `doc-row` documents, `cat-row` rate card, `ct-row` contacts, `team-row`); state column `var(--state-w)` second last, `.team-act` ⋯ cell last; the header row carries the same row classes (`crm-head svc-row csv-row`) so it shares the row's grid and every label sits over its column, one cell per column, empty over the ⋯; `uxaudit` fails a header cell off its column (`cols`); on a phone two or three lines by `grid-template-areas` (name and ⋯ / small facts / money left, state right), never one field per line |
| Completeness of a group | `.ringline` > `.ring` (`is-ok` when full) + "2 of 4" or "Complete" |
| One record with steps | `.kcard` > `.kcard-head` (name, chips, ⋯) + `.kstep` blocks; folds to one line in lists of ten or more |
| An act that cannot be taken back | A **sheet**, never `confirm()`, whenever something has to be typed: voiding a letter takes a reason, deleting one takes the reason and the reference typed back. The sheet says what the act will do in the record's own terms (which service lines go back, what is removed, whether it can be undone) before it asks. The menu item that opens it is drawn behind the section's Manage level (`data-need="clients:manage"`) and the database checks the same permission again when the button is pressed, so a permission taken away while the sheet is open is a refusal and not something that already happened |
| Rare or destructive actions | `.kmenu-btn` ⋯ + `.kmenu` > `.kmenu-item` (name only; `is-danger`). An item that leaves the building and cannot be recalled asks first, with `confirm()` naming what goes where: **Send invitation** sits one place from Edit in the same menu. A menu row is a control and clears the control floor like any other (`--ctl-h`: 38px, 44px under a finger); padding alone left it at 43px on a phone and nothing caught it until the walk opened a ⋯. An item that does not repaint the row behind it closes the menu itself, or the ⋯ sits open over the answer or behind the sheet it just opened. **The menu opens upwards where the room is above**, never past the bottom of the window, which is nowhere a phone can reach; and the scroll that closes it ignores the scroll the browser fires to reveal the button it has just focused, or the ⋯ closes itself the frame after it opens |
| A rare change to a row | The row states the value; the ⋯ opens the panel that edits it, and the same panel adds a new one. A control drawn on every row for something changed once a quarter is Hick's law failing twice: it repeats on every line what one heading or one word could say, and it fills the row with the thing nobody came for. A group's seven switches, a member's group, a service's rate: all read on the row, all changed in a panel |
| Status | One shape everywhere, including the review page: a chip with the word in it. `.status` on `/review/`, the Drive import rows and the saved posts drew a **coloured disc beside a word of the same colour**, which said nothing the word did not and is the one shape this system rules out for a status. `select.state-select` (tinted) for a state that **moves as part of the work** — a campaign step, a client stage, a request — where changing it is why somebody opened the page. A **lifecycle flag flipped once** (Active / Inactive on a rate card line, a colleague, a creator) is a chip on the row and a `Set inactive` / `Set active` item in the ⋯: a 124px tinted select on every line, for a decision taken once in the life of the row, was taller than the price it sat beside and painted the whole list one colour. `.tone` / `.chip-state` with a word for a value that is only read |
| The chosen one of several options | A filled shape, one language per component and never a shadow: the sidebar `.navitem.is-on` takes the `--line-soft` fill and weight 600, a `.tab.is-on` an ink underline and weight 600, an `.acttab.is-on` the ink fill with white text, a `.crow.is-on` the `--line-soft` fill, a `.bigcard.is-on` an ink border. Hover is always one step lighter than selected (`--sunk` where selected is `--line-soft`), never equal to it, and lives inside `@media (hover: hover)` so a phone cannot leave it stuck on the last thing tapped. `uxaudit` hovers an unselected option and fails when it renders the selected one's background (`hover`) |
| Form to add or edit | `.panel` > `.panelhead h3` + `.row` fields + Save / secondary / Cancel + `.msg`; one Save covers everything in the form, a file included, so a number and its PDF are never two saves, and Cancel repaints from what is stored. What is attached now sits with the field that changes it, above the actions, never stranded under them |
| Optional detail | `.panel.panel-collapse` > `.disclosure` (title, summary right) + `.disclosure-body` |
| Full-page state | `.cover` > `.cover-inner` > `.cover-panel`, centred, title then one line, `body.is-plain`, footer on the floor. **The line never restates the title**: the title says what happened, the line says what to do about it ("Selection closed" / "Please contact your ADspace account manager for any changes.", not "Selection is closed. Please contact…"). Both languages, every cover |
| Modal | `.sheet` > `.sheet-card`, from the bottom on a phone, fixed height when it filters |
| Undo | `.undobar` with one `Undo` button, eight seconds. A **quiet strip**: `--sunk` ground, a `--line` hairline, ordinary ink text, the ordinary outline `.btn-sm`. Never the ink fill: something was undone and there is a way back is a message, not the next thing to do, and a black bar the width of the page sitting above a black primary button reads as one enormous call to action whatever the button inside it looks like |
| Message | `.msg` (`ok`, `warn`, `err`) as one line under the control, never a card |
| Empty list | `.empty` with two words ("No entries.", "No links.", "No matches.", "Access denied."); never "yet", never a sentence. Drawn as a **line inside the panel the list would have filled**, never a 26px dashed rectangle with the words centred in it: a new client record drew four of those down the page and each heading was the smaller mark |
| A list that is loading, empty, or could not be read | `js/state.js` and nothing else. `skeleton(box, n)` draws the shape of what is coming; `emptyLine(box, text, action, fn)` says nothing is there and carries the way out; `failLine(box, what, why, again)` names what could not be loaded, what the database said, and offers Try again. **A read that failed is not an empty list**: "No content sets.", "0 posts" and "Nothing added yet." were printed over failed requests and sent people to build records that already existed. Nothing there and nothing left after a filter are two answers with two ways out ("Add the first lead" / "Clear the filters") |
| A record with more than three sections | A **workspace**: identity at the top, a `.rectabs` strip of panes, and a `.rec-rail` beside them carrying what is true whichever pane you are in (`.rec` grid, `minmax(0, 1.618fr) minmax(280px, 1fr)`; below 1100 the rail comes first and the panes follow; below 640 the tab strip scrolls sideways rather than wrapping to three rows). Seven sections in one column meant Documents was a scroll away from the services it quotes. The pane is in the address and **pushes** a history entry, because it is a move a person made, not a note of where the page ended up; Overview is the default and stays out of the address. **A pane is the disclosure**: opening Billing opens the fields, and a refusal that names a missing field lands on the pane that holds it |
| What a record is waiting on | One line under the identity (`.camp-next`), derived on every repaint and never stored: a state written once by the action that caused it goes stale the moment somebody reverts |
| One of many, then the one | A **queue** and an open record (`.queue` > `.qrow`, the creator's page): the queue orders by what has to be done, marks the one that needs the reader, and opens it by itself; the open one is in the address. Four full records stacked, each with its own upload box, is a page you have to read to find the one that matters |
| Deciding on one thing in a gallery | A **canvas** (`.canvas`): the thing at the size it deserves on a stage, and everything the decision rests on in a rail beside it — what it is, the copy in full, what was said last time, where it stands, and the one place to decide. Prev/next and the arrow keys step the set, Escape closes. The canvas **moves** the gallery item's own blocks into it and puts them back on close, so there is one decision control in the page and it cannot drift from the one in the gallery |
| Search, filter, count and the one action | `.cmdbar` > `.cmdbar-find` (a search box with its glyph, bounded 190 to 420px) + the filter selects + `.cmdbar-end` > `.cmdbar-count` + the `?` + one `.btn-sm.btn-primary`, on every console list: clients, my work, content review, campaigns, creators, short links, documents, the rate card, the team. The count reads `7 services` whole and `3 of 41` once a filter is on, never sits in a section head, and is not drawn at all when it is empty. The end group is one element so a wrap cannot split it: on a phone it takes the last row whole, the count and the `?` on the left and the actions on the right, and every route's bar is the same three rows |
| Links to reach a person | `.plink` chips (phone, WhatsApp, email); equal widths on a phone |
| A form that adds or edits one record | A **sheet** over the list (`js/sheet.js`, `.sheet-card.formsheet`): head with a close mark, a scrolling `.sheet-body`, a foot with Cancel quiet and the primary, equal halves below 560. The scrim closes it only while nothing has been typed; Escape and the close mark always do. One shape for a creator, a colleague and a user group |
| The command bar on a phone | Below 640 the bar is **one row**: a **search** mark and a **Filters** mark on the left (`.cmdbar-search`, `.cmdbar-filters`, the second carrying a badge that counts the filters off their default), then the count and the primary action as a filled `+` on the right, with the view segment as a second row where a route has one. Search **grows into the field** on the `.namebox` move and shuts again when it is left empty. The selects come up in a **sheet from the floor** (`#cmdSheet`) under labels, with Done and Clear; a second action is behind a **⋯** beside the primary. `js/cmdbar.js` is the one copy. The desk bar is untouched |
| What a section is for | The route's name in the console head (`.console-title`, a button with a 14px info glyph) opens the one line that says what the section is for. Not a `?` in the command bar: the line is about the section, and the section's name is where a reader looks for it |
| A directory of records | `ADspaceGroup.section` (`js/group.js`): `.crm-group` > `.crm-group-head` (the 15px heading, the count, the marks, the name as the fold) + `.crm-group-body` > `.crm-table.softpanel` with its own `.crm-head`; `ADspaceGroup.more` for the rows past thirty. One card per group on every console directory, folds remembered per browser, a filter opening every card, the card opening and shutting in place. **The card carries no outline**, and it is one token for every bounded card (`--card-line`, transparent in both themes, on `.panel` (the record head and every form), `.crm-table`, `.softpanel`, `.team-table`, `.ovcard` and `.bookreg`; nothing nests a card in a card, so a transparent edge never loses a surface): the user chose the Team card's look on 2026-09-22 and asked why one card could differ from the rest at all. It could because Team carried a local `border: 0` written when that page was rebuilt, and the first fix added a second local rule for the directories; both are gone, and a card that needs a different edge is a card that needs a different token. The card's own ground against the page is the edge, white on `--page` in light and a step lighter than the ground in dark. The 1px stays transparent so nothing is re-measured |

**The bar at the top of every page is one bar, so it is one height.** It used
to have none of its own: 14px of padding above and below whatever was tallest
inside, so `/admin` signed out (a 26px wordmark) stood 55px and `/client` (a
38px button) 67px; both changed again at the 640 breakpoint as somebody
resized, and the client bar wrapped to two rows and 105px at 390. A bar
measured by its contents is a different bar on every page. It takes `--head-h`
now, never wraps, and the page label is what gives way when the row runs out
of room: below 640 `.brand-kicker` is hidden rather than clipped to
"Client Po…", which reads as a fault rather than as a name, while
"Prepared for {client}" stays, because on a client's own page that is the one
thing the bar is telling them. `uxaudit` measures the bar on every page of the
walk and fails when one disagrees with the rest at the same width (`head`),
because the fault was only ever visible by comparing two pages.

**A matrix is a table that grows a column every time the product does.** The
user groups were a grid of groups against the seven `can_*` switches plus
Admin: nine columns, headings wrapping to two lines at 1440, a `min-width` of
900px so the table scrolled sideways inside the console, and a row of
disabled grey boxes on the locked Admin group that read as all-off rather than
as always-on. A group is read far more often than it is changed, so the row
now **says what the group opens in words** (`Clients · Content Review ·
Billing`, `Everything` for an admin group, `No access` for one with nothing)
and the switches live in the panel that edits it. Adding an eighth permission
now costs a word in a line, not a column in a table.

The same reading fixed the members table: a `Group` select on every row said
what the groups table below already said, three times over, and answered "who
is in Sales" only by reading every row. Members sit under their group as
`.svc-cat` sub-headings, exactly as the rate card lists services under a
category, and moving somebody is Edit in the ⋯. **Where a list has a natural
grouping, the grouping is a heading, never a column.**

**A column is a column on every row, or it is not a column.** Every row in
these tables is its own grid, so a track sized `auto` is sized by that row
alone: on the clients list "Proposal sent" opened the state column at 267px and
"Active" at 308px, and a status that starts somewhere different on every line
is what reads as unaligned, however neatly each row is built. The phone
template must fix every track it shares, **including the restatement lower in
the file** — an `auto` in the later `max-width: 640px` rule quietly undid the
column the `760px` rule had just set. A fixed track is measured, not chosen:
the clients state column is 120px because the widest thing it can ever draw is
"18 months · Overdue" at 119px, and a track narrower than its worst case is one
that wraps on the row somebody most needs to read. `uxaudit` compares the same
cell across every row of a table (`column`) and fails on more than 2px of
drift; the older `cols` check only ever compared the header to the first row,
and the phone hides the header, so this was invisible on exactly the width
where it happened.

**On a phone the last column is a right edge, not a track things sit at the
start of.** A fixed track makes a column, which is what stopped the state chip
drifting row to row — but the cell inside it was left at `justify-self: start`,
so the chip began at the same x on every row and *ended* wherever its own word
happened to end. "Lead" stopped 76px inside the card's padding, "Active" 69px,
"6 days · Overdue" almost reached it. The left of the list was a straight
margin and the right was ragged, on every register in the console, which is
what reads as a card that has not been laid out even when nobody can say why.
The cell fills the track it was given and its contents align right
(`justify-self: stretch` plus `text-align: right`, or `align-items: flex-end`
where the cell is a flex column), so the chip and the line under it both end
where the padding does and the card has two margins instead of one. Stretch
rather than `justify-self: end`, for the reason the service rows already state:
an end justified cell is only as wide as its own content, so two lines inside
it would start at different x.

The corollary is that **an empty action cell gives up its track**. The rate
card draws its ⋯ only for an admin, so for everybody else a fixed
`var(--ctl-h)` last column held 44px of nothing and the whole column of prices
stopped 44px short of an edge nobody could see: the row looked mis-centred and
the cause was invisible. The track is `auto` and the empty cell is hidden — and
only on a phone, because on a desktop that column is shared with rows that do
draw the ⋯, and a cell that leaves the grid takes its column with it and
slides everything after it one track left.

`uxaudit`'s `edge` rule measures this at 390: the **ink** of the last column,
not its box, because a stretched cell already reaches the edge while the chip
inside it does not. A cell that begins at the row's left margin is a summary
line rather than a column and is exempt, and one gutter step of slack is
allowed for the gap a collapsed action track leaves behind.

**A phone list is a two column table, not a card with things pushed right.**
The answer to "cards or a table on a phone" is that the card *is* the table
row: the left column is who they are over what we know about them, the right
column is where they stand over how long they have stood there, and both
columns are fixed and top aligned (`"name stage" / "meta stage"`). Anything
centred inside a row of unequal cells pushes the name off the top pad — 22px
above and 12px below on a 12px padding, which is the "spacing inconsistent"
nobody can name but everybody sees.

**A name is read, not parsed, so two rows a reader cannot tell apart are one
row.** `SteveCN` and `SteveCN ` look identical on every screen in this portal
and in every message about the person, and the difference that makes them two
creators is a character nobody can see. So the key a duplicate is judged on
trims both ends, collapses every run of whitespace to one and ignores case,
and the name is stored the way it is compared — keeping the spaces somebody
left behind is what lets the same creator be keyed in twice. A space *inside*
a name is a different name and stays a caution rather than a refusal, because
two people can genuinely be told apart by one. The refusal is named while the
form is still open, not only when Save is pressed: the point is to stop the
second row being typed, not to report it afterwards. And the check has to run
on the field the person is actually filling in first — this one was reached
only after a profile link had been typed, so the commonest way to key somebody
in twice, their name and nothing else yet, was the one path that said nothing.

**A cell in a list is read by its shape, so it holds what differs and not what
is longest.** The creators list named each creator's latest campaign for a
week. A campaign title is longer than the column, so it arrived truncated on
every row, and it answered a question nobody asks of a list — which campaign,
of the several, was most recent. What a roster is read for is whether somebody
has worked for us and how recently: a number and a month, which fit, line up
and can be scanned down. The names are on the creator's own card one press
away, where every one of them is legible.

**A page opens on the thing it is there for, and everything that explains it
folds.** The client's creator selection page opened on a summary card — the
brief, what the campaign is for, the creator count, the due date, the amount,
the progress bar — with the creators they came to choose below all of it. Every
one of those facts is worth having; none of them is what the page is *for*. So
the card folds and opens shut, and the page's first screen is the work. Two
things make that safe rather than merely shorter. **The summary a fold is read
for is on its head**, so the one fact with a consequence survives the shut
state; a fold whose head says only its own name is a fold nobody opens, and one
whose summary is blank is worse, because the dead space beside the label is
exactly where the reason to open it should be. A date needs no label there, and
where there is no date the next fact that is always known takes its place.
**And a line that explains the thing goes inside the thing**: the campaign's
purpose was drawn under the page title, outside the card, so it read as a
caption on the page rather than as the card's own content and could not fold
with the rest of it. The corollary is a cost, and it is accepted rather than
hidden: the amount fold is now a fold inside a fold and the figure is two
presses deep. That is what "the creators get the focus" buys.

**A bare button is a control, and the card's head is not exempt.** The fold's
label is the thing you press, so it clears the control floor like every other
control — 38px at a desk, 44 under a finger — and it takes the negative block
margin the rate card's ⋯ takes so its footprint stays the label's own line.
Without that the margin is real: a one-line head stood 66px at a desk and 72 on
a phone, which is a head taller than some of the rows below it, for one word.
`uxaudit`'s `target` rule is what says so, and it said so on the first run.

**A border inside a border groups nothing.** The file field's `Choose Files`
carried the same 1px `--line-ctl` ring as the field around it, on the field's
own white ground, so one control wore two identical borders and the inner one
was told apart from the outer by nothing at all. A border groups; a second
border inside the first only reads as a box drawn twice. The inner element is
**shaded** instead — the fill the account control and the bell already use to
say they are pressable — and the fill has to be visible: `--sunk` on white is
1.03:1, which is a control nothing identifies, so it is `--line-soft`.

**And a nested corner is concentric, or the two curves cross.** The field's
radius is 10px and its inset was 8, so the inner button's corner sat *inside*
the outer corner's arc: the reader sees the inner shape apparently covered by
the outer one, which is exactly how it was reported. An inner radius is the
outer radius less the inset — here 10 − 5 — written as the subtraction rather
than as a number, so it is the consequence of the two corners this system has
and not a third one beside them.

**The last thing that reads as "not centred" is usually two type sizes.** The
button's label was 12.5px beside the field's own 13px, so the pair sat on two
baselines however symmetric the boxes measured. This was reported three times;
the first two passes measured box heights, found 5px of slack on each side, and
answered a question nobody had asked. When something reads as misaligned and
the boxes are symmetric, measure the **ink**, the borders and the type sizes
before saying it is even.

**A card whose last line is a padded control reads bottom heavy.** The creators
list's rows end in profile links, and `.plink-bare` carries 5px of its own
padding above and below its word. Added to the row's 12px that made the foot
20px against a 14px head — a difference nobody can name and everybody sees,
reported as "a small spacing below which feels uneven". The row's padding
should be the only space in it, so the cell takes the control's padding back as
a negative block margin and each link keeps its full target. Only the bottom
half: the gap above that line is 4px, and pulling both ends would close it to
nothing. This is the third component to need the same correction, after the ⋯
and the selection tick, which is what makes it a rule rather than a patch.

**A placeholder is not data, and a row is not a form.** The clients list showed
`F&B · S$ · Aisyah`: a bare currency sign standing in for a figure, on every
row, including the rows that **had** a figure — the desktop column drew the
money and the phone line threw it away for its sign. A fact that is not known
is left out; the line carries the value when there is one and two facts when
there is not. Counting the atoms in a row is the test for "too many messages":
name, state, age, and two or three meta facts is the ceiling. **A missing value
in a column takes the mark its neighbours take, never a sentence.** The Last
activity column wrote "No calls yet" on all seven rows of a list where almost
nobody has been called: a sentence repeated seven times where one character
says it, under a heading that has already said what the cell is. The Industry
cell beside it was already using a mute em dash, so that is what the cell takes.
A null marker in a table cell is a convention, not copy, and is the one place
the no-dashes rule does not reach.

**A long list needs an axis, not a smaller row.** At eight contents a week
across thirty clients a task list gains about 290 rows a month. Banding by
when the work is owed answers "what do I do today" and cannot answer "how is
October going" or "what is piling up at client review": two hundred rows under
*Later* are unreadable whatever shape the row is. A **Group by** select in the
bar re-bands the same rows on the axis the question needs — by client, which
is how the work is sold and counted, by stage, by owner — and off the default
axis **every card is shut**, so the page is thirty headings with a count and an
overdue mark each rather than the 290 rows the axis exists to escape. The
heading then has to carry what a shut card would hide: a count of what is
overdue inside it. The fold is remembered **per axis**, because a client card
shut under By client says nothing about a stage card under By stage, while the
card keeps its own name on the page.

**A list that grows every month is read with a bound, and the bound is never
on the work somebody still owes.** A single limit over everything silently
stops showing older rows partway through the second month, which is worse than
refusing: the page looks complete. What grows without limit is *finished* work,
so that is what a period governs; open work is read in full however old it is,
because a task overdue since August is the first thing a queue exists to show.
The control that sets the period draws only while finished work can be on the
page — a control on screen while it decides nothing is one somebody has to work
out.

**The commonest act on a row belongs on the row.** Moving a stage is what
anybody does on a task list all day, so the stage cell is the portal's own
tinted state select and goes through the same function and the same gates as
the record does, with the refusal named under the row it was made on rather
than in a bar a screen away. The corollary is that the row stops being one
button: a control inside a control is one a screen reader trips over, so what
opens the record is the name cell — the widest, full row height, where the eye
already is — and the chevron goes, because a mark that is no longer a target is
furniture. A state that needs something typed before it means anything (Blocked
needs a category) is never in that select; it is asked for on the record.

**A fact is stated once on a screen, and a control that changes it answers.** The task record printed its three dates twice (an Overview section and the rail's Key dates), its owner three times (the identity line, a People row, and the select that changes it) and its number twice (a disc and a Details row), so a task with one sentence of brief ran to 3,700px on a phone and read as busy while saying almost nothing. Each fact has one place: the number heads the record, the dates are the rail's, the owner is on the identity line and in its own select. The test for a second copy is whether it is a *different* question being answered (the Overview's Progress line counts the checklist; the Checklist pane lists it) or the same one again. The same record's owner select showed the new name before Save was pressed and nothing near the control changed after it, so a refused save and a successful one looked identical: the control says `Saved.`, and a refusal puts the select back to what the database holds, because a screen never claims a change that did not happen. **And a record with nothing worth a mark has no mark.** A task has no logo and a monogram of its title says nothing; its number pressed into the 46px disc every other record wears read as a badly fitted logo. The number heads the record in the token face instead, a copy control like the Register's serial, and on a phone it is the one line that shares the top row with the state and the ⋯ while the title takes the card's width.

**A board is the same rows asked a different question, and it is one workflow at a time.** A kanban of 290 cards is a table drawn worse, so the board is scoped the way the work is scoped: the same search, filter and scope as the list, one workflow's stages as the columns because the columns and the work-in-progress guidance on them are the workflow's own, and the lanes a task steps out of the flow into gathered in one column, since a board is where the flow is read. The count on a column is read against the guidance (`4 / 5`) and turns warn past it, which is the whole of what the guidance is for. It scrolls sideways at a desk on purpose: eight columns at a legible width are wider than any screen, a board narrowed to fit is one nobody can read, and the rule against sideways tables is a rule about tables. On a phone the columns stack and an empty one is not drawn, which is the list grouped by stage, which is what a board is on a screen one column wide. **A calendar holds one date a task**: the commitment the queue is ordered by. Three dates a task in a cell is a cell nobody can read. **And a record tells the person it concerns, from where the event is written.** The notification is filed beside the event, in the one function every write already goes through, so the rule (the owner is told about a change somebody else made; nobody is told about their own act) is stated once and a write added next year keeps it without anybody remembering to.

**A board column is a place the work can go, so an empty one that nothing can
reach is not a column.** The video workflow has nine stages and most of them
are empty most of the time, so the board drew seven columns saying None and
one that mattered, side by side, wider than any screen. The rule is not "hide
what is empty" — that would take away the column somebody is about to move a
card into, which is the whole point of a board. It is: draw an empty column
where a task on this board could be moved into it next, and draw the
workflow's entry always, because a board with nowhere to start reads as one
missing its first step. On hold is the exception in the other direction: it is
where work steps out of the flow, so an empty one is a column for a thing that
has not happened, and it is drawn only while it holds something.

**Dragging a card is a second way to reach one move, never a second move.** It
goes through the same function and the same gates as the select on the card,
so a gate that refuses refuses either way and says so in the same place — on
the card it was made on. What the drag adds is that the board answers while
the card is still in hand: every column the workflow allows is marked and
every other dimmed, which is this file's own rule about constraining an
invalid choice rather than reporting it afterwards. A column that needs
something typed before it means anything is not a drop target at all; Blocked
takes a category, and a category is asked for on the record. The select stays
on every card whatever happens, because a keyboard has no drag: an interaction
available to one input is an addition; the same interaction replacing the
control everybody else used is a regression.

**And a finger drags too, from a grip.** It was HTML5 drag and drop, which
fires nothing under a touch, so it was set under `(pointer: fine)` and the
board could not be rearranged on the device this portal is mostly read on —
which is what the user asked about. Pointer events are one API for both, so
the drag is one path rather than two. What a phone then costs is the gesture
itself: a browser decides whether a touch is a scroll **at the moment it
lands**, before any class the page sets can say otherwise, so a press and hold
was cancelled the instant the finger moved and the card never lifted. The
answer is not a longer hold, it is a **handle that declares `touch-action:
none` on itself** — the browser never claims a gesture that starts there, the
rest of the card goes on scrolling a board that is taller than the screen, and
there is no hold to wait out. The grip is drawn at every width, because a
control that appears only on a phone is one somebody has to discover twice; at
a desk the whole card is a handle as well, since a mouse has no scroll to
lose. What follows the hand is a **clone**: taking the real card out of its
column reflows the board mid gesture, and the clone is `pointer-events: none`
so the column under the finger can be found at all.

**A card on a board is read in the order a board is scanned.** What it is, whose it is, when it is owed. The board card led with its serial in the token face at the same size as the client beside it, and carried no owner at all — the one fact a board exists to show, and the fact that decides whether a column is anybody's problem. The serial is demoted into the mute meta line, because a number is how a card is quoted in a message and never why somebody is looking at it; the title is the weight and is what opens the task; the foot is the owner as a small initials disc and a name, with the due date ending the line. The disc is the same device a contacts list uses and works here for the reason it failed on the creators list: a board column is a handful of people's work, not four hundred names in one alphabet.

**A control that is the same shape at every value is a control that says nothing.** The stage select on a task was toned only for terminal and waiting stages, so eight of the thirteen — Intake, Ready, In progress, Shooting, Editing, Revision, Approved, Delivered — drew the same neutral box, and a column of them could not be read down for where the work had got to, which is the one thing the control is there for. Four families, keyed on the stage group the workflow already carries: not started is mute, the work in hand carries no paint because it is the ordinary case and the accent marks the exception, anything waiting on a person is warn, anything cleared is green, and blocked is red, because it is a refusal. That is the palette this file already has; nothing new was added to make a stage legible.

**A move that repaints the list has to say it happened.** Changing a stage from a row rebuilds the list, moves the row into another band and destroys the select that was pressed, so a successful move and a dead control look the same. The outcome is named under the row the repaint draws, in the same place a refusal is named, and it leaves by itself. The corollary is the way back: **every forward move has a Revert**, and where the task came from is read off the last stage change in its own events rather than stored — a stored "previous stage" is a fact written once by the move that caused it and is wrong the moment somebody moves again. It is offered only where the workflow still allows that move, so it is the same function and the same gates, and it is a neutral outline button, never a second blue one beside the forward action.

**A stored key is not a word on a screen.** The task record printed `reel` under a template named Reel and `simple` under a field offering Simple, so the record contradicted the form that filled it one tab along. The key stays what it is and the words a person reads are named once, with sentence case as the fallback so a value somebody adds next year is still a word rather than a slug.

**The control that explains a thing comes from that control, and never opens by itself.** The line saying what a section is for was a block under the command bar, so it could only be reached from that route's directory: open a client, a campaign or a task and the bar is off the screen, and the one control that explains the section did nothing at all. It is a panel hung off the section's name now, which works in every state of every route. What it must not do is open on arrival: a surface over the page lands on the command bar, which is the row somebody came to use, and on a phone it intercepts the press. While a route is new the title's glyph carries the action colour instead, so the invitation is on the control and the screen stays the reader's; after three visits even that retires. And the line is **one sentence**: the first pass ran to two and named the panes inside a record, which explains the product rather than the section.

**A navigation rail is ordered by how often each route is opened, and its two
ends are the only positions that are genuinely different.** The serial position
effect is usually quoted as "first and last are remembered"; in an
always-visible rail it is a claim about where the eye lands and how quickly a
place is found, and it still holds. So the first slot goes to the route opened
many times a day — here the task queue somebody opens on arrival — and the last
to the route a person must be able to place without scanning, which by every
convention is the settings-like one. What is then lost in the middle is what is
opened by an event rather than by habit, and that is the right thing to lose.
Eight items is past Miller's comfortable span, so they are two chunks of four
under their own labels; a chunk whose every item is withheld hides its label
with it, because a heading over nothing is a table header over no rows. The
axis that was weighed and rejected is client-facing against internal: every
route in a console is internal, and half of them produce something a client
eventually sees, so it divides nothing. And the sequence, once chosen, is the
sequence everywhere it appears — the rail, the activity record's tabs, the
permission panel's blocks — because a person can hold one order and not four.

**A promise is moved by the person who made it.** A date on a task is the
commitment its creator put there, and the control that moved it moved it on
the press, so the person who set it learned afterwards, from a notification,
that a deadline had already gone. The round that was missing is the whole of
the fix: the person doing the work asks, the person who set the date answers,
and the date moves on the answer. Three things keep it from becoming
paperwork. A person moving a date on a task they created needs nobody, so the
same control does both jobs and the database decides which — a round with one
name on both ends is a form. The control is named for what pressing it will
actually do, because "Move a date" on a control that will only ask is a lie
the reader finds out about afterwards. And the ask is drawn where the dates
are, with the one action its reader has: the person asked sees Approve and
Decline, the person who asked sees Withdraw, and anybody else sees neither,
because a button that is not yours to press is a question about why it is
there. What is deliberately not gated is the team's own internal milestone:
the commitment a client is owed is the one an extension is about.

**A checklist is only a gate if the thing it gates is on the screen.** The
quality check shipped as fourteen rows drawn straight into the sheet card
rather than into the card's own scrolling body, so the list overflowed and the
foot — with Release in it — was pushed off the bottom of the screen. On a phone
every box could be ticked and there was then nothing to press: the gate had
become a wall. The body scrolls and the foot is fixed under it, which is what
every other sheet in this portal already does, and the count sits beside the
action at a desk and above two equal halves on a phone. Two further things the
same report settled. **Ticks are work, and work is not thrown away by closing a
window**: somebody who shuts the sheet to go and look at the file again is
doing the check, not abandoning it, so the ticks are kept per booking until the
release goes through and are cleared then, because a booking sent back for
changes is a different file. And **fourteen was too many for the wrong reason**
— not that fourteen checks are too much care, but that checks of the same kind
were two presses for one act: a person watching a video for spelling is
watching it for brand names in the same pass. Nine, three groups of three, with
every risk that costs money or takes a post down still on the list.

**A gate on the one step somebody else sees.** Every step on a creator's card
is the team recording its own progress except one, and that one puts the work
in front of a client the moment it is pressed. So that is the step that is
checked, and the check is the team's own list rather than a warning: what it
says, what the brief asked for, how the file plays. All of it is required,
because a check that can be skipped is a check nobody makes, and the count
beside the button is what says why the button will not move — a disabled
control with no count is a mystery, and a sentence explaining it is the
explanatory copy this portal does not have. Fourteen checks in one run read as
fourteen; in three groups they are three things to hold, which is what a
person can. What is recorded is who checked and when, and not a second copy of
the list: the step itself is the evidence, because nothing else opens the
gate.

**A gate the page draws is not a gate.** The nine checks were a sheet, and the
press behind them wrote the booking's state straight to the table — so a check
was a thing somebody could close, and nothing anywhere recorded that it had
been made. The rule that makes the second pair of eyes worth having, that the
second may not be the first, is a rule only a server can hold: two browsers,
two sessions, one table. So the release is a function, the check is a row with
the person and the revision round on it, and the same move made any other way
is refused by a trigger — because the table's own policy is permissive, and a
gate that lives only in the function is one a direct request walks past. The
page still says it first: Release is shut for the person who asked, and the
control that asks for a second is gone once somebody has. Saying it first is a
courtesy; refusing it is the database's job, and both are needed.

**Nobody is assigned, and that is the design.** The obvious shape is to name
the second reviewer, and it fails on the ordinary week: the named person is on
a shoot, or has left, and the booking sits behind an account nobody can open.
Anybody who may work the section can complete the check, as long as they are
not the person who asked for it — which is one unique constraint on
`(booking, person, round)` rather than a rule somebody wrote, so pressing
again is the same check and the count does not move. What the page then owes
is legibility, not notification: the card says, where the button that will not
move it is, who has checked and that it is waiting on a second, because the
ask is a sentence across the desk and the person walking past has to know what
to ask for.

**A figure the person typed is the figure they see.** A service line priced at
RM 400 over a three month term printed RM 444.44, because the term's factor
was applied to every line that carried a term. The arithmetic was right and
documented, and it was still wrong on the screen: the number somebody enters
is the number they mean, and one that comes back as something else makes them
work backwards through a rule they did not invoke to find their own figure.
The rule is not "never derive a value" — it is that a derivation with a
commercial consequence is a **decision**, and a decision is asked for. So the
adjustment is a tick on the line, offered only where the term actually carries
one, named for what pressing it does rather than for what it is, and silent on
the row when it is off, because a line billed at the rate that was typed has
nothing to explain.

**A default that is read three times has to be read the same way three times.**
The tick is stored on the line, but the same figure is worked out in three
places — the console, the letter and the client's own page — and one of those
reads a snapshot taken before the column existed. A missing flag therefore has
to mean *applied*, or every letter issued earlier redraws at a figure it never
printed; a new line has to mean *not applied*, or the fault comes straight
back. Those are not two defaults: only an explicit `false` turns it off, and
nothing is left to the column's default, because the form stores the flag on
every save and both server functions send it. The test for a change like this
is not "does the new case work" but "what reads this value, and what does each
of them see when it is absent".

**A field a finger uses is never under 16px.** iOS zooms the page the moment
one takes focus and does not zoom back out, so the reader is left on a page a
third too wide, hunting for the control they were about to use, and every tap
after that lands somewhere they did not aim. The token said 16px under a
coarse pointer and six rules stated their own size past it, which is the
failure mode of a token: it is only true where nothing later disagrees. The
answer is never `user-scalable=no` or `maximum-scale=1` — that stops the zoom
by taking pinch zoom away from everybody, fails WCAG 1.4.4 and contradicts the
200% pass this portal already runs. Make the field the size a phone reads, and
measure it: a zoom is a thing the phone does rather than a thing the page
draws, which is exactly why nobody sees it in a screenshot.

**One record, one way to edit it, and the way is a card over the thing.** A
creator was edited in a sheet and a colleague in a panel that unfolded at the
top of the section. On a phone that panel is a screen above the row somebody
pressed, so Edit read as nothing having happened, and at a desk it moved the
list under the pointer. The sheet is the shape: on a phone it comes up from the
floor over the row, at a desk it is a card over the list, and either way what
is being edited is in front of what it is being edited from. Two things make
it safe. **The scrim does not dismiss a sheet that holds typed changes** — a
click a few pixels wide of the card is not a decision to throw a form away,
and an untouched sheet still closes on it, because then there is nothing to
lose. And **Escape always closes**, touched or not: nobody presses Escape by
accident with a mouse, and a dialog a keyboard cannot leave is a dialog nobody
can leave.

**A bottom sheet is measured in the viewport the reader actually has.** `vh` on
iOS is the tall viewport, the one that assumes the browser's own bars have
scrolled away, so a sheet sized in it stands taller than the screen shows and
its foot — where Save is — starts below the fold. `dvh` follows the bars and
the keyboard as they come and go, behind `@supports` with the `vh` line as the
fallback. The card is what moves, so the card is what is promoted, and its
floor is the phone's floor (`env(safe-area-inset-bottom)`) and not the
screen's.

**A destructive item is red whether or not it carries a bold child.** The colour hung off `.kmenu-item.is-danger b`, so Delete on the client record — the one such item written as plain text — read in ordinary ink beside Edit and said nothing about what it does. A rule about a state belongs on the element that carries the state.

**A verb does not repeat the noun the context has already given.** Delete client, Delete campaign, Delete link, Delete permanently: four labels for one act, each naming what the menu it sits in has already named. The item is **Delete**, and the consequence is stated where it belongs — in the sheet that asks, which says what goes and that there is no restore. Asked for by the user on 2026-09-22, and it is the rule this file already carried ("no object the context gives"); the examples that contradicted it are corrected.

**Two actions in a row are two halves, not a slab and a remnant.** A sheet's foot let its buttons flex from their own label widths on a phone, so Save came out a black bar across most of the row with Cancel squeezed beside it — two actions of the same standing at two sizes, which the phone checklist has ruled out since it was written. Equal halves.

**The way out is last in its row, in every row, and it is measured.** This file
has said "Order in a row: Save / secondary / Cancel" since it was written, and
thirty-one rows in the portal obeyed it while three did not — the two Team
sheet feet and every `.changebox-actions` put Cancel first. Two orders in one
console is not a style inconsistency, it is somebody pressing the wrong button
when they move quickly, which is exactly what the user reported, on a phone and
at a desk alike: the hand learns a position, and a position that means Save on
one screen and Cancel on the next is worse than either order chosen badly.
Which order is right matters less than that there is one, and this portal had
already chosen: the primary reads first because it is what the row is *for*,
and the way out follows it. `uxaudit`'s `order` rule measures it by **x** and
not by markup order, because a row can reverse itself in CSS and what a person
presses is what they read; only a row holding both an action and a way out is
judged, and on a phone a wrapped foot is judged line by line.

**A sheet opens on what there is to change; the caret is the reader's to
place.** Every form sheet focused its first field on open, which on iOS raises
the keyboard *and* zooms the page — so the reader lands on a form scrolled and
magnified past most of what they opened it to read, already typing into a field
that is rarely the one they came for. Correcting a phone number should not
begin by deleting a half-typed name. The card takes focus instead, with
`tabindex="-1"` and no ring, which keeps everything focus was there for: Escape
closes, the trap holds, and a screen reader announces the dialog. The one
exception is a sheet whose whole purpose is a single value, where the field
*is* the sheet. The same rule retired the autofocus on the Add creator sheet,
the campaign form and the creator picker's search.

**One record, one way to edit it, on every route.** Seven forms were still
`.panel` blocks that unfolded at the top of their section or in place of the
record's head: adding a lead, a contact, a service line, a call, a request
reply, a rate card line and a short link. On a phone that is a form a screen
away from the row somebody pressed, so Edit read as nothing having happened;
worse, the client form was *moved into* the record and hid its head, so the
client vanished while their own details were being corrected. They are all
`js/sheet.js` now, which means they also inherit the two rules that file
exists for — the scrim refuses to dismiss a sheet holding typed work, and
Escape always closes. A sheet is over the page, so a form no longer has to be
carried to where the person is.

**A part that says what its section already says is not an exception.** The permission panel opens a section whose parts hold one, and the HR move wrote `register.hr` onto every group, `none` included — so every group carried a stored level identical to the one it would have inherited, and Documents was the one section that opened by itself on every screen, for a difference nobody had made. A stored level equal to the section's reads as Same as section, is not counted as an exception in the row's sentence, and is not written back.

**A loading state has the shape of what is loading.** The console is not drawn until the database has said who this person is, because its rail names every section of the tool — but the page still has to be something in the meantime, and what it was was the shared page bar over an empty body, which is exactly the composition the client-facing pages use. A colleague refreshing their own console read somebody else's portal for a second or two on every load. The shell, the rail and the bar are the console's from the first paint; what is withheld is the *content* of them — the nav's names, the bar's controls, the route's body — and the body is a skeleton. Withholding what a person may open and withholding the shape of the page are two different things, and only the first is a rule.

**A component borrowed for its shape carries its old flex into the new row, and the law it was written for does not always apply.** Three ways to reach one person share a phone row at equal widths, which is what that rule is for. Engagements borrows the same row for a name and a single Open, and at equal widths one outlined button became a slab across the phone — the banner every section head here has refused for months. One link is not a row of links.

**A page's own head is measured against the window; a pane's is measured against the pane.** The console's record head keys its phone template on `is-narrow`, which a `ResizeObserver` writes onto the panes, because at 1280 the pane is 591px and the window is the wrong number. The client portal's head is a page section and nothing observes it, so it kept the three-column template at every width and the client's name was squeezed to sixty pixels beside a state chip and a 150px action. There the window *is* the head's width, so a media query is not a shortcut, it is the correct measurement. The template itself is the console's, not a second one written for this page.

**A directory is a card per group, and every directory is the same card.**
Leads, Active clients and Paused and past were three floating panels for a
month, then one surface with the stages as uppercase divider rows inside it for
a week, and the user sent the divider rows back: the eyebrow face and its
spacing read as wrong, and the same rows were on Campaigns, the Creators List,
Services and Team while Content Review and Short Links were a bare card with no
heading at all. Seven routes, four shapes. So one component (`js/group.js`,
`ADspaceGroup.section`) draws them all: the 15px heading with the count and the
marks, the name as the fold, and a card with its own header row under it. The
test for what the groups are is still whether two rows in different groups are
the same kind of thing (a stage, a state, a fee band, a category, a user
group); where they are not, they are different routes. **Folds, not tabs, on a
long directory**: a tab hides the count and costs a click per group, a folded
card costs one line and still says how many it holds. A card that holds
everything on the page never shuts by default, or a route with every link
paused is a heading over nothing.

**The card opens from its heading and leaves into it.** A fold is a move
somebody made, and the eye follows a surface that arrives; a directory that
repaints around the fold blinks. The body is a grid row that runs from 0fr to
1fr, which is the one height CSS can animate without being told the height,
with the opacity alongside it at `--t-slow` / `--ease`; a shut card empties
itself once it has closed. The register this portal takes after is Apple's and
Cloudflare's, and what those pages have in common is not their palette but
that every change of state is a move the reader can follow: a surface that
comes from the control that opened it, a fold that closes onto its heading, a
menu that comes from its button. That is the standard a new control is held
to here before its colour is chosen.

**A whole row that opens a record is one control, with nothing inside it.** The
register row is a `<button>` carrying only spans, so the whole of it is the
target from a pointer and from the keyboard, there is no control nested in
another control for a screen reader to trip over, and the chevron at the end is
a mark rather than a second thing to press.

**A phone template names every cell it keeps, and hides the rest.** A cell left
showing with no area in `grid-template-areas` is not laid out, it is placed in
an implicit row of its own: Last activity took a third line under every row and
printed the same date the meta line already carried. Adding a column to a table
is two edits, the desktop track and the phone template, and the second is the
one that is forgotten.

**A cell whose heading leaves at the phone breakpoint carries its own word.**
`.crm-head` hides below 640, which is right for a row of names, states and
dates, because each of those says what it is. It is wrong for a bare figure:
the operations report drew `4` under a task title and `11 days` under a stage
name, and on a phone nothing on the screen said the first was days overdue or
the second the slowest tenth. The answer is not to keep the header — a header
row on a two line card is a third line of labels — it is for the qualifying
cell to name itself where the header is gone (a label span, hidden at the
desk) and for the figure to carry its unit at both widths. `Days over | 4`
reads on a desk and nowhere else; `Over by | 4 days` reads on both. The test
is to read one row with the heading covered and ask what each number is; no
alignment or contrast rule can catch this, because the geometry is correct and
the meaning is what has gone.

**A section that is empty is still a block in the stack.** The report drew its
empty sections into a wrapper, so the heading after one keyed on nothing and
sat 18px below it while every other heading sat 24px below the table above.
An empty state stands in for the block it replaces and is spaced as that
block, or the law of the stack holds everywhere except exactly where there is
least on the screen to distract from it.

**A report states the window its figures are taken over.** Everything but
"what is running now" is an aggregate over a period, and on a phone the select
that sets that period is inside the filters sheet — so the one control naming
the window is not on the screen with the numbers it governs. The report says
it itself, in dates rather than in the select's word: "This month" does not
say whether today is in it, and a figure whose window is ambiguous is a figure
nobody can quote in a meeting.

**A control in an empty state has to survive the repaint that pressing it
causes.** Filtering the clients list to nothing and pressing Clear the filters
did nothing at all: `input` and `change` both fire for one keystroke, and the
second of them arrives on **blur**, so focusing the button made the search box
fire `change` with the value it already had, the list repainted, and the button
was detached between mousedown and click. A list repaints when its filter has
actually changed and not otherwise. Two lessons: one control never carries two
listeners that do the same work, and a test drives a control the way a person
does — a dispatched `click` on the node the test is holding cannot see this,
because the node a person presses is the one that was there a frame earlier.

**A list long enough to scroll needs a way to cut it and somewhere to be
inside it.** Four hundred creators as one flat run of identical rows is a list
you have to read rather than scan, and no amount of row polish fixes it. Three
things together do: a **filter** on the axis the work fixes first (platform,
because a campaign picks one before it picks anybody), **bands** that divide
the list on the axis it is browsed by (fee, because every creator is in exactly
one and budget is how a campaign is planned), and a **per row anchor** — one
character in a neutral disc, the way every contacts list ever built makes a row
findable by eye. The bands are `.svc-cat` sub-headings with their count, the
same component the rate card and the Team page use. Stood down people are their
own band at the foot: they are not booked, so they do not belong in a budget
tier between two creators who are available. Alphabetical banding was weighed
and rejected — most of this roster is Chinese names, so a first letter index
puts nearly everything in one bucket or gives three hundred buckets of one.

**A row with two lines has one right margin, not three.** The creators list on
a phone drew three different right edges and the user reported it as uneven
spacing without being able to name it, which is exactly what that fault reads
as. The ⋯ spanned the first line only, so the record line ran to the card's
padding at 358 while the money above it stopped at 302; and `.cr-rec` is a
flex box, so the `text-align: right` it had been given moved nothing at all —
`—` sat at the *left* of a 148px track while `1 · Sept 2026` filled it and
looked right aligned, so the column could not be read down. Three lessons, all
already in this file and all missed here: the last column is a right edge and
the ⋯ spans every line of the row it acts on; `text-align` is not what aligns
a flex child, `justify-content` is; and both meta cells start at the top of
their line, or a record centred against a links cell that has wrapped to two
rows floats halfway down the card with nothing beside it.

**A list of people is told apart by what they have done, not by a device put
in front of their name.** The creators list gave every row a neutral monogram
disc, on the reasoning that a contacts list has always used one. It does not
work here and the reason was already written two paragraphs up: most of this
roster is Chinese names, so a first character index puts nearly everything in
one bucket, and 是yy呀 and 是甜甜啊 draw the same grey circle. Five identical
discs over five identical `rednote` chips over five identical `RM 360` is
decoration standing exactly where information should be. The disc is gone and
the row carries the **record** instead: where they post, how many campaigns
they have run for us, when they last shot, and an `On a campaign` chip while
one is live. A device that was added to make rows distinguishable and leaves
them identical is not a device to restyle, it is one to remove.

**A mark holds artwork or it is not a mark.** Two more monogram discs survived
that removal because neither sat on a list of creators: a 28px disc of one
initial beside the actor on every row of the client's and the campaign's
Activity panes, and a 20px initials disc beside the owner on every board card,
with a dashed empty one where there was no owner. Both are placeholders for a
profile picture, and this portal holds none and is not going to: nobody on this
team has an avatar anywhere in the data model, so what those discs actually
drew was the same grey circle down every row, and on the one axis where the
letter did vary it said nothing the full name beside it had not already said.
A dashed empty circle standing for an unassigned task is a placeholder for a
placeholder. The test is the one the creators list settled and it has two
halves, not one: a mark earns its place by **holding real artwork** —
`.rec-mark` carries the client's own `logo_url` and falls back to initials only
while we wait for one, `.mk-avatar` carries it into a platform's own UI — or by
making rows **findable by eye**, which one letter in one column cannot do. A
disc that does neither is decoration in the position information should be in,
and the name is the fact.

**An image sized by one axis inside a box that can clamp the other is a squash
waiting to happen.** `.brand-logo` was `height: 26px; width: auto`, and the
global `img { max-width: 100% }` then clamped the width in any box too narrow
for the mark at that height while the height stayed exactly where it was put —
so the wordmark was compressed horizontally and stopped being the wordmark.
Measured in the 244px console rail, where the box settles at 195px: every
stand-in past 8.13:1 drew at 8.13:1, and the wider the asset the worse the
compression, ratio 14 and ratio 10 both landing on the same squashed 8.13. The
fix must not depend on knowing the asset's intrinsic ratio — the mark is served
from the CDN and a new one can be uploaded any day — so it is `object-fit:
contain`, which fits the ink inside whatever box the layout gives it with the
ratio true, plus `object-position: left center` so it sits on the rail's own
margin rather than centred in the leftover width. The box still measures its
stated height, so nothing under it moves; what gives is the drawn height of a
mark too wide for the rail, which is the correct thing to give. A brand mark is
the one image on the screen whose proportions are not ours to adjust.

**A record opens on who it is, and its landing pane is the record.** The client
record was a thin title strip over a six row shortcut card, so the pane
somebody lands on carried less than any other and half the screen under it was
empty. Two things fix that and neither of them is a metric tile. The identity
area carries a mark (the client's own logo where we hold one, their initials
where we do not), the name, the state and the one control that edits it, and a
meta line of the facts that **identify** rather than describe — which language
we write to them in, who here owns the account — each omitted when it is not
known. The landing pane is then the record itself: flat titled sections divided
by hairlines inside one bounded surface, a heading and the one control that
opens each section's own pane, and concise real rows under it. Everything in it
comes from what the record has already read, so the pane costs nothing and
cannot hold a number that has gone stale; a section with nothing to show says
so in a line, because "None issued." is an answer and a section that vanishes
is a question.

**A record head is two parts that centre on each other.** Left, who this is:
the mark, the name with its stage on one line, the identifying facts under
them. Right, the one ⋯ that acts on the record, holding Edit and Delete. Edit
used to be drawn beside the stage on every record and it earned that position
perhaps four times in a client's life; on a phone it and the ⋯ wrapped to a
line of their own under the name, with the meta below them, which is the wrong
reading order, and on a desktop the controls sat on the name line, above the
card's middle on every record that carried a meta line. Two parts on one grid,
`align-items: center`, and the control is on the middle of the card at a desk
while a long name wraps under itself. On a phone the two parts become two
rows: the mark top left, the state and the ⋯ top right, and who this is under
them on the card's own margin, full width, because beside a 38px mark the name
had 130px and a campaign's state wrapped under it. Every line of the left part
(name, a campaign's purpose, the meta) sits inside that part on one margin;
a line drawn outside the grid sat on another and read as unaligned. The name
at 19px and the meta at 12px stand a golden ratio apart, which is what keeps
the second line reading as a note under the name and not as a second line of
it. **The state and the ⋯ in the right part are one line, centred on each
other.** The shared `.chip` rule pins a chip to the top of its flex row, which
is right beside a name; beside a 38px control (44px under a finger) it put the
campaign's state 11px above the ⋯'s centre, so the two things on the right of
the head read as two lines squeezed together. `.rec-ctl .chip` centres. The
client's stage select lives in the same right part, beside the ⋯, for the same
reason: on the name line it stood mid line on a phone with the card's whole
right half empty beside it. They are deliberately not split onto two lines: a state on a line of its own above
the name costs every campaign 30px to say what the chip beside the control
already says, and the console's tables put the state beside the ⋯ on every
row. `tests/six.js` measures the chip's centre against the ⋯'s at 1280 and
390.

**On a phone the rail is two groups, and the pane sits between them.** Below
the workspace width the rail is not a column beside the panes but a stack above
them, and a stack of five blocks put the record's own content (the contacts,
the services, the letters) a screen and a half down, behind a log nobody opens
a record to read. What needs acting on stays above the tabs: the stage and its
clock, the next action, the billing gate, the profile bar. What is only looked
up follows the pane: the dates, the details, the recent activity
(`.rail-after`). The rail dissolves into the page grid (`display: contents`)
and the blocks take their place by `order`, so the markup is one rail and the
desk is untouched. Recent activity is deliberately last: it is an excerpt of the
Activity pane, read after the record and not before it.

**A rail is one block per question, and a block with no data is not a block.**
Each carries a title at the pane's own section size and is divided from the
next by the same hairline the sections use. The order is what somebody needs
in the order they need it: where the record stands and for how long (the
stage chip and its clock, stated here and nowhere else on the rail), what to do
next, what is stopping the record (red, because it is a refusal and opens the
pane that clears it), how much of it is filled in, the dates it holds, the
facts, what has happened lately. A row in a list of dates or events carries a
neutral 16px glyph, so the list can be scanned by shape before it is read; the
glyph is never coloured, because the word beside it is the fact. Two rules keep it honest.
**A written next action beats a derived one** — a person wrote it on a call and
set its date; a derivation only inferred it. And **a row whose date nobody has
recorded is left out**, never drawn as "Not set" in a list of dates, because a
list of three dates where two say nothing is a list that has stopped being
read. The rule under the last block is therefore set in the paint, not left to
`:last-child`, which counts a hidden sibling and drew a hairline under nothing.

**A completion figure is never the whole message.** "25% complete" tells
somebody they are behind and not what to do, so the bar carries the count
beside it and the line under it names what is still missing and opens it. It is
counted over what the record genuinely tracks, and it is not a metric tile: it
is one block in a rail with a control on it.

**A column that spans two rows sizes the rows it spans.** The record grid puts
the rail across both the tab row and the pane row. Left at `auto auto`, a rail
taller than the two of them had its extra height shared between them, so a lead
— a short pane beside a full rail — opened with sixty pixels of page ground
between its tabs and its first section, and nothing in the pane could explain
it. The row a strip of tabs sits in is `auto` and the row under it is `1fr`.

**A phone row spends its first line on what the person came for.** The rate
card was three lines — the name with its ⋯, then the unit, then the price
beside a green Active select — so a row stood 310px and two and a half services
of thirty four fitted on a screen. The name and the money share the first line,
what qualifies the money (the unit, the platforms) goes under it, and the ⋯
ends the first line where the thumb already is. Ninety five pixels, and the
whole card on one screen. The same shape now carries the rate card and the
creator roster (`.cat-row`, `.cr-row`: `"name rate act" / "meta meta meta"`).

**A row is the same height whether or not its ⋯ is drawn.** The rate card
draws the ⋯ for an admin only, and on the first line of the phone row its 44px
target set that line's height: the same service was 97px on an admin's phone
and 68px on everybody else's, with the name pinned to the top of the tall one
and the unit floating 30px under it. Two people comparing screens saw two
different lists. The ⋯ takes the negative block margin the creator roster's
already had (`margin-block: calc((22px - var(--ctl-h)) / 2)`), so its
footprint is the name line's and its target is still 44px; the row is 73px for
everyone. A control whose presence depends on a permission must never be what
sizes the row it sits in.

**An instruction lasts as long as it is needed, and a tooltip is not one.**
This portal carries no explanatory copy, because a line that explains a step is
right the first few times somebody meets it and furniture ever after. Where a
step genuinely needs one, it goes behind a `?` (`.hintline`): open by itself
while the screen is new, retired behind its own mark once it has been read
three times, and still openable by anybody who wants it. A **button, never a
`title`**, because a hover tooltip cannot be reached on the device most of this
is read on — the same rule that retired the half opacity dot on a creator
profile.

**A value that is only read is not a field to type in.** The creator's access
code, their portal link and the client links were `readonly` inputs, which draw
the same box as every editable field on the page: a person is invited to change
something that cannot change, and the one thing they actually want to do with
it — copy it — is not what the box suggests. `.readfield` keeps the height and
the alignment, so a row still reads as one line, and takes the affordance away
rather than the shape.

**The account is not an action.** The control at the end of the console bar
carried a `--line-ctl` ring, so beside an Activity link and a bell that are
nothing but ink and a fill on hover, the person's own name read as the one
thing up there to press. That is the fault the bell's own ring already had, and
it is corrected the same way: no border in either shape, and the fill on hover
and while the menu is open is what says it is pressable. The three controls in
that bar are one shape.

**Copied is said one way.** Four buttons copied something and each answered
differently: one swapped its own label, one a span inside itself, one wrote a
message into a `.msg` line under the panel, one tinted itself. `js/copy.js` is
the only copy of that feedback now, so somebody who has learned what Copy link
does on Content Review does not learn it again on a campaign. An icon-only
button has no label to swap, so it takes the tick and the accent for the same
moment instead.

**A state hangs off the end of the line, never off the end of the name.** A
chip written straight after a title starts at a different x on every card,
because titles are different lengths: 恩比 put `Pending draft` at 205px and
Vini168小队长 put it at 325px, so a column of cards could not be read down for
where each one had got to, which is the one thing the chip is there for. Every
card head pins it instead: `.booking-head` right-aligns it with `margin-left:
auto`, and `.kcard-head` puts it **second from the end, beside the ⋯**, which
is exactly where this portal's tables already put a state column. `.kcard-head`
uses `order` rather than a move in the markup, because name then state then
summary is still the right reading order for anybody not looking at it. On a
phone the head wraps, and **what wraps is the summary, not the state**: left to
itself the state took a line of its own with an empty half beside it, while the
name it belongs to sat on the line above.

**A browser dialog is not a control this portal has.** `window.prompt` and
`confirm` cannot be styled, cannot be translated — the buttons stay in the
browser's language, so a Chinese reader gets half a dialog — and on a phone
they are a system sheet that takes the reader off the page. The rule was
already written for destructive acts ("a sheet, never `confirm()`, whenever
something has to be typed"); it holds for a single value too, and there the
answer is not a sheet but the field growing out of the control that needs it.
The name a client's decision is recorded under is the case: it used to be a
prompt on both client-facing pages, and it is `.namebox` now.

The console kept thirty-one of them anyway, because each one is a line of code
and the right control is a component. `js/confirm.js` is that component, and it
divides from `js/ask.js` on the rule already stated above: a value on its own
grows out of the control that needs it; an act with a **consequence** is a
sheet, because the consequence is exactly what a growing field has nowhere to
put. Four things a browser dialog cannot do are what the sheet is for. The
consequence reads as a line under the title rather than as a second paragraph
of it. The destructive answer is red and the way out is quiet, and a
destructive question opens focused on the way out, so a stray Enter costs
nothing. **A value is asked for in the same breath as the question**, never in
a second dialog after the decision has already been taken — setting a service
line by hand was a prompt for the state (free text, so a capital letter was a
refusal) followed by a prompt for the reason, and removing a client from
Content Review was a confirm followed by a naked "Type the client name
exactly:". And **the way back never asks**: reinstating a code, setting a
colleague active again, restoring a creator. A question in front of the
correction is one more thing between somebody and putting it right.

**A control that creates a need answers it in place.** Ticking a platform a
creator has no profile link for used to open a labelled field *after* the Add
button: what you type sat downstream of the control that sends it, the row
reflowed on every tick, and the creator's name wrapped to two lines to make
room. The tick **becomes** the field instead: the box grows from 92px to 281px
in place, keeping its own name on it, and shuts again when the tick goes. Both
ends of the width are stated, because a width of `auto` does not animate. A
box that carries a field is a control, so it clears the small control floor
(`--ctl-h-sm`) like everything else in that row, and on a phone it takes the
line it needs while the boxes around it wrap — with `flex-wrap` on the
container that follows them, or a full width box pushes the rate and Add past
the screen edge.

**A rule about a component asks the component's width, not the window's.**
The record pane sits inside a 243px sidebar and beside a 380px rail, so a
1280px window gives it 591px and a 1440px window 690px. Every
`@media (max-width: 640px)` rule governing something *inside* that pane was
therefore false at exactly the widths where it was needed: the client's
Services row kept a five column grid in 591px, the name track collapsed to
59px, and "Social media management for Instagram, Facebook and TikTok" came out
one word per line in a 210px tall row. The same fault is latent in every pane
row, and no viewport matrix can see it, because the viewport is not the number
that is wrong.

`ADspaceState.fit` measures `.console-body`, `.rec-pane` and `.rec-rail` with a
`ResizeObserver` and writes `is-narrow` (≤640) and `is-tight` (≤460) onto them;
the stylesheet keys on those instead of on a media query. One copy of each row
template then serves the phone and the narrow pane, because on a phone the pane
is narrow too.

**Container queries are the obvious answer here and are the wrong one.**
`container-type: inline-size` implies `contain: layout`, which makes the element
a containing block for `position: fixed` descendants — and `ADspaceMenu.place()`
positions every row ⋯ on the viewport with exactly that. Turning the pane into a
container would put every menu in the console a few hundred pixels out. The
measurement is done in script precisely so nothing gains containment.

**Two thresholds, because two things break at two widths.** At 640 a row of
four or five columns has to become two lines. At 460 even a two column row has
to give up its summary line: the booking register keyed to the single 640
threshold drew three line, 113px rows in a 591px pane that had room for one.

**A declared minimum that cannot be honoured is worse than no minimum.** The
services row states `minmax(180px, 1fr)` for the name and gives up 20px across
its two money tracks so the fixed tracks and gaps come to 672 — which fits the
690px pane a 1440px window leaves. Below that the row stacks on purpose rather
than overflowing.

**A phone row is two lines and its first line is a touch target.** 56 to 72px
is the one line register row and it cannot also hold on a phone: 44px for the
target, 20px for the state line and 24px of padding is 88px, and no arrangement
of a name, a state, a date and two controls in 358px is shorter. The band is
asserted where the row is one line; the phone is held to its own ceiling and to
the same consistency.

**A menu that is not a row menu still inherits the row menu's rules.** The
account menu took `.kmenu`'s 320px width and `.kmenu-item`'s
`flex-direction: column` — which exists so a row menu can stack a bold label
over a description — so Theme and Sign out came out as an icon above a word
above another word, centred, in a 320px panel. It states `flex-direction: row`,
`justify-content: flex-start`, `text-align: left` and its own 260px width
explicitly, and outranks `.kmenu` rather than merely disagreeing with it, because
`.kmenu` comes later in the file.

**A tab strip never wraps.** Wrapping put Activity alone on a second line and
pushed the pane down by a tab's height. One row always, scrolling sideways below
the width where the tabs fit, with `flex: 0 0 auto` on each so none is squeezed
to avoid the scroll.

**A strip's rule sits on the page's own margins, and the step under it has one
owner.** `.rectabs` bled to the screen edge on a phone (`margin-inline: -16px`)
so a tab scrolling out faded past the gutter rather than being cut at it — a
nicety that cost the one thing a hairline is for. At 390 the rule ran 0 to 390
while the rail's dividers above it and the card below it ran 16 to 374: the page
had two margins and the line under the tabs had none. `.tabrow` never bled, and
a scroller cut at the gutter is what the rest of this portal does. The step down
to the pane was split the same way — 4px on the strip and 12px on whichever
first child remembered to ask for it — so the client record stood 16px off its
tabs, the task record 4px and Campaigns 12px: three strips, three gaps, nothing
saying which was meant. The strip owns it, at the one block step, everywhere.

**A phone bar is what the person came for, and everything else is one press
away.** Stated as three rows, the command bar was still four rows of controls
before the first record at 390, on a screen 700px tall: the search, the view
segment, two rows of selects, then the count and the action. Every control
had the standing of every other, and only two of them are used all day. So on
a phone the bar keeps those two (the search, and the view where a route has
one) and puts the rest behind one Filters button, the way every list on a
phone already does: the selects come up in a sheet from the floor, each under
a label, with Done and Clear, and a badge on the button says how many are set
so a filtered list never looks like the whole. The primary action keeps its
fill and gives up its word, because a filled `+` beside a search box says
"add" in any language; a second action goes behind a ⋯, which is where this
portal already puts a rare act. What is deliberately not done is a second
copy of the selects: the sheet moves the bar's own elements in and puts them
back, so there is one set of listeners and one place a filter can be wrong.

**The control that explains a thing sits with the thing, and the thing here
is the section.** The line that says what a route is for was opened by a `?`
in the command bar, among the search, the filters and the one action — the
controls that act on the *list*, which is not what the line is about. It
belongs on the route's name, which is in the console head on every width, and
there it costs a 14px glyph beside the word rather than a 44px control of its
own. That matters: the head already holds four controls, and at 320 a fifth
would have clipped the route's name to one letter. Where the row still cannot
hold both, the glyph gives way and the name never does, because the name is
what the bar is there to say. And only the glyph answers when the line is
open: a fill on the title makes the route's name read as a selected chip, on
every screen the line is open on.

**A group that must stay together is a group in the markup, not a hope about
where a wrap will fall.** The command bar is one wrapping flex row of unlike
things — a search box, nought to four filters, the count, the `?`, one or two
actions — and loose items wrap by whatever is left over, so every route wrapped
differently: Services put the count and the `?` mid-row with the action
stranded on a line of its own, Documents crammed four things onto the last
line, Content Review left one outlined button against an empty half, My Work
pushed its action onto a fourth row at the left margin. That is what "positioned
everywhere" describes, and no amount of auto margins fixes it, because an auto
margin can only push within the line a wrap has already chosen. Two of them in
one line are worse still: they split the free space between them, which is how
the `?` came to rest in the middle of the bar with ninety pixels of nothing
either side. So the bar is three stated rows on a phone — the search, the
filters two to a row at equal halves, and `.cmdbar-end` carrying the count, the
`?` and the actions as **one element** at `flex-basis: 100%`, with the quiet
pair anchored left and the actions right by a single auto margin. A group cannot
be split by a wrap, so the composition is the same on all nine bars at every
width and on the desk as on the phone. The alternative considered and rejected
was counting the selects with `:nth-of-type` to make an odd one full width: it
is a guess about the markup that a hidden control breaks silently, and My Work's
hidden period select broke it the day it was written.

**A template that claims every header in the console will claim the wrong one.**
The clients list's seven columns hung off `.crm-head:not(.svc-row)`, which is a
rule that says "any header not wearing one particular class". Short Links wore
another, so its header took the client columns while its rows took their own
five: DESTINATION sat 91px right of every destination under it and LABEL 103px
left of every label, invisible at a glance because the labels are short and
mute, and missed by the `cols` check, which only compares a header with a row it
believes shares a grid. Every table states its own tracks now, on the header and
on the row alike, hung off that table's own row class.

**The last track is a track.** An `auto` final column is sized by its own row,
and a header whose last cell is empty over the actions sizes it at nothing, so
the three columns before it slide right of the rows beneath them. State it, at
the width the cell actually holds.

**An empty grid cell still holds its column.** `display: none` on an empty cell
removes it from the grid, and the cells after it slide one track left: a booking
with no summary put its state chip under the Booking heading. The cell stays on
a desktop and leaves only on a phone, where it is a named area in a template
that can afford to lose a row.

**A hidden button is not a second action.** `:only-of-type` and
`:has(.btn + .btn)` both count one, so a head whose second action is hidden
until its data exists gave its heading the whole row and stretched the one
visible button into a full width slab across the phone — the banner the rule was
written to stop, and the loudest thing on the screen once the primary was a
filled blue. The selectors read `:not([hidden])`.

**A component is borrowed for its shape, never for its convenience.** The
creator roster was drawn with `.slink`, the Short Links row, so a person's name
came out in the slug's monospace face and the phone layout put the two icon
buttons on a line of their own: three creators filled 810px with the actions
floating in the dead space. A creator is a person with a fee, so the row is the
one every other list of records uses, and edit and delete went into the ⋯ where
a destructive action belongs. Before reaching for a component, check that what
it was built to say is what this screen says.

**One action is an action, not a banner.** The rule the section head already
carried (`.viewhead .btn:only-of-type`) was missed by every other bar, so on a
phone `Add lead` stretched the full width above the client list and `Add
creator` and the short links action did the same: the heaviest thing on the
screen was the way to add a record, sitting on top of the records somebody came
to read. `.crm-bar`, `.filterbar` and `.linksbar` keep the action at its own
width at the end of the row.

**Nothing a phone cannot reach carries meaning.** A creator profile with no
handle was marked by a half opacity `·` carrying a `title` attribute: a hover
tooltip, on the device with no hover, doing the work of saying "short link, no
identity". Where the absence of something is the information, show what is
there and let the gap speak — the chip reads `Instagram popcorn.xx` where there
is a handle and `rednote` where there is not. A handle is shown only where it
reads as a name (18 characters or fewer); rednote keeps a profile id in that
field, and `5e3262fd00000000010015b6` is longer than the creator it belongs to
and says nothing to anybody.

**An overlay is positioned against the box it explains, never against the box
that contains it.** The Schedule's "Not set" hint is drawn on the cell, and on a
phone the cell holds the label as well as the field — so `top: 50%` of it is the
field's top third and the word printed across the box's own border. Correcting
that by re-anchoring to `bottom: 0` and restating the height from `--ctl-h-sm`
made it worse in kind, not better: it is a second guess at a box that is already
on the page and already has a height, and it was 6px out at the desk, where the
field is 38px and the token is 32. Wherever either guess is wrong the overlay
lands somewhere nobody chose, and no viewport matrix can see it, because the
number that is wrong is not the viewport. Give the field a wrapper of its own
(`.sched-field`) and centre on that: no height to state, no second rule per
breakpoint, and the one positioning rule is true at every width. The same test
applies to any hint, badge or adornment laid over a control.

**A write that changed nothing is not a write that worked.** PostgREST answers
a delete its policies refuse with 204 and **no error**: the row stays and the
caller is told nothing at all. Every `.then(function (r) { if (r.error) …})` in
this portal therefore reads a refusal as a success, and the two deletes in a
content set did exactly that — the panel closed, no message, and the set was
still in the list behind it, which is indistinguishable from a page that has
not repainted. A delete asks for what it removed (`.select('id')`) and treats
an empty answer as the refusal it is. The same holds for an update whose
policy can refuse it. The rule is not "check the error", it is **check that the
thing happened**.

**The way back is drawn where the act happened.** This portal's answer to a
destructive click is a soft remove and an eight second Undo, not a dialog — but
one Undo bar at the top of a record is not a way back from something done most
of a screen further down. Taking a creator's handed-in file off a booking put
the bar 223px above the top of the window, measured, while the × that was
pressed sat mid screen: the file vanished under the pointer and nothing visible
was offered. That reads as no safeguard at all, and no amount of it being
technically recoverable changes what the person saw. The bar goes directly
after the block the act belongs to, and names **what** went rather than its
category, because "Submission removed." over a grid of three files answers the
one question it was drawn to answer with nothing.

**One number, two parties, two meanings.** A booking's rate is what the client is quoted: it carries the agency's markup and is the figure the client's own selection page prints beside each creator. The creator's page read the same column and captioned it "Your fee", so the creator was shown the client's price and told it was their payment. Nothing about the column changed between those two screens; only who was reading it. Before a figure is put on a page, the question is not "is this the right field" but "whose number is this, and what will the person reading it take it to mean" — and where the two answers differ, the field does not travel. What a creator is owed is agreed with them and claimed on its own form, so their page needs no figure at all, and the one that existed is withheld by the function rather than hidden by the page, because the page is one anybody can open.

**A test can codify the leak it should have caught.** The assertion here read `their own fee, not the client's amount` and checked for `RM 380` — the client's amount. It passed on every run for as long as the defect existed, and its own name argued the defect was correct. A test that asserts a *value* is only as good as the belief behind the value; where a fact is withheld, assert the withholding — that the key is absent from what the function returned — because that is the thing the rule is actually about.

**An Undo covers a press you noticed.** This portal's answer to a destructive click is a soft remove and a visible Undo, and that was argued — here, in writing — to be better than a dialog, because a dialog taxes the everyday case to protect the rare one. It holds only while the person knows they pressed. The × that takes a creator's handed-in file off sits in the corner of the card their video is playing in; an accidental press there is one nobody sees, the eight seconds run out, and the work is gone with no way back but asking the creator to upload it again. Where the act destroys somebody else's work and the control sits inside the thing being looked at, the question is asked first — in place, taking the control's own position, naming what it would cost — and the soft remove and the Undo stay behind it. Three steps, not one. The test for which pattern applies is not how rare the act is but whether the person will know they made it.

**A record of a decision holds every party to it.** The activity record is what
answers "who approved this, and when", and it held only what the team did: a
client's approval lived in `reviews` alone, a creator's hand-in nowhere at all.
A table no screen reads as a history is not a record. Every client-facing and
creator-facing write that is a **decision** logs under the name the person
typed — approving a post, asking for changes, confirming a selection, handing
work in, rating a booking, withdrawing a request. What is not a decision stays
out: the creator selection autosaves on every tick, and a record full of
half-made selections is one nobody can read, so the commitment is logged and
the autosave is not. A tag a function writes is always one the console can
name and file, or the row arrives with no label and no section.

**A heading over a column that is nearly always empty reads as a fault.** Short
Links headed a STATUS column whose cell is blank on every live row, which is
almost all of them — the accent rule working correctly, and looking broken. The
rate card had already settled it: where a state is the default for its list, the
row says nothing while it holds and names the exception **beside the name**, not
in a column of its own. Drop the column; keep the chip.

**A number is not a link until it carries the country.** A Malaysian mobile is
keyed `0143132195`, and stripping the punctuation gave `wa.me/0143132195`, which
is not a number anywhere: the country code is missing and the leading zero is a
national prefix. Prefixing `6` keeps the zero and gives `60143132195`, the same
thing as 60 plus the number without it. A number already carrying its code is
left alone, and one with no leading zero takes its client's market, because a
Singapore mobile has eight digits and no prefix to replace. One builder, so the
contact row and the Overview cannot disagree.

**A document is drawn on one letterhead, whichever kind it is.** The Letter of
Offer held the only copy of the pen: the page size, the margins, the wordmark,
the address block, the monogram top right and bottom centre, the page count.
Writing a second letter meant writing those again, and two copies of a
letterhead drift the way two copies of a colour do. `js/documents.js` exports
the pen and `js/letters.js` draws the quotation cover, the client letters and
the HR letters with it, so a change to the letterhead reaches every document
the portal issues. What a letter says is the type's to seed and the person's
to edit; where it goes on the page is the engine's alone.

**A reference is answered, never a name.** The verify page every letter's foot
names takes one exact reference and answers with the kind, the date and
whether the document stands. It does not list, it does not match a prefix, and
it never prints who the document was addressed to: an HR letter is answered as
"HR letter" and nothing more, because the reason a reference is verifiable is
so a reader can trust the paper in their hand, not so a stranger can learn who
has been written to. What the page gives away is what the foot of the letter
already printed.

**HR letters answer to their own part.** A colleague's confirmation letter
is read by fewer people than a client's thank-you letter, so it is not one more
family under the Register's level but a part of its own (`register.hr`), gated
apart from `register.documents` and from `clients.documents`. The Register page opens for either; the
database's policy decides which rows arrive. The Activity record is told that
an HR letter was issued, voided or deleted and the kind it was, and not whom it
concerned, because the record is read by everybody with the Activity section.

**A serial is built by the database and spent once.** Each family has a rule:
the accounting portal's own reference for a quotation cover, typed; the client
code with the type's letters for a client letter, with SA where a service has
been engaged; the staff code and the month for an HR letter. A built serial
that is already spent takes a numbered suffix; a typed one is refused; a
deleted one is remembered, so it is never handed out again. The console shows
the rule's result and lets a person type over it, and never computes the
serial itself, because two browsers computing the next number is how two
letters share one.

**A permission is a level in a section, never a switch per verb.** Six section
booleans plus one global `can_remove` meant the authority to destroy was shared
by clients, contacts, letters, rate card lines, short links, creators and
content sets at once: granting it for one granted it for all seven, which is
not a permission but a blast radius. The obvious correction is a matrix of
sections against add, edit, delete and share — and it is the wrong axis twice
over. It is twenty eight switches a group, about sixteen of which name nothing
this portal does (there is no "share" on Services, no "add" on a log), and this
page had already removed one permission matrix because a matrix grows a column
every time the product does. And CRUD cuts across the line that actually
matters here rather than along it: **add, edit and publish are reversible, and
a permanent deletion is not**. So the ladder is none, view, work, manage, one
select per section, and the row reads back as a sentence. Adding an eighth
section costs one select; adding a fifth verb would have cost a column on every
one of them.

**A part is an exception to its section, never a second ladder.** The ask was
finer access: a group that works Clients but must not read Billing, a group
that reads the Register's client letters but not its HR letters. The obvious
shape is a select per pane per section, which is forty selects a group, nearly
all of them saying what the section select already said. So a part (the panes
and lists a section is made of, `clients.billing`, `review.sets`,
`campaigns.finance`, `register.hr`) has a level only where somebody set one,
and answers with its section's otherwise, in the database predicate and on the
page alike. The ordinary group is still one select per section; the parts sit directly
under their own section's select, store nothing at `Same as section`, and the
row reads the exception in brackets after the section it departs from. They
were first drawn as a separate Parts fold listing the sections again, and the
user sent it back: a part is read where its section is. A part is drawn from what a section is made
of, never from a verb: there is no `clients.billing.delete`.

**A screen already read a section at a time is a screen whose access is a section at a time.** The Activity record's tab strip has named its sections for months — Clients, My Work, Team, Content Review, Creator Campaigns, Short Links, Documents, Services — while its access was one switch over all of them, so a manager who wanted the team to see how campaigns were progressing had to hand them every client's billing change and every letter as well. The parts model was already the right shape: a part answers with its own level where one is set and its section's where none is, so the ordinary group is untouched and the exception is one select. What it needed was the thing a policy cannot guess — which section a row belongs to. That map lives in the console, about a third of it does not follow the tag's prefix, and a map restated in two places drifts, so the two copies are compared and the suite fails on any difference. A tag nothing has named yet answers a section that has no part, which falls back: a row written by next year's feature is read by whoever can read the record, rather than hidden from everybody by a map that has not caught up.

**A switch beside the ladder goes the day a level can say it.** Billing was one
(`can_billing`), kept because a pane inside a record is not a section. It hid
the pane and not the facts: the letters in Documents print the registered name
and the billing address, so a group without the switch read them anyway one tab
along, and a group that could open Clients without Billing read as a mistake
nobody had made. It is the part `clients.billing` now, with the same four
levels as everything else, read at View and typed at Work, and the database
refuses the save below Work through a trigger on exactly those columns. Voiding
a letter was the other switch and went the same day, into Clients: Manage. The
one-argument `allowed('billing')` refuses, which is what a retired switch
should do.

**A document that went out wrong is reissued, not edited and not replaced.**
A portal document is a snapshot and is never edited in place; a person who
finds a wrong name on a quotation cover after it was issued still has to fix
it. Reissue opens the same sheet filled from the version being replaced, with
what the document is, whose it is and its reference fixed and the words free,
and on Reissue the earlier version is voided as Reissued and kept, while the
new one takes the same serial and points back at it. The same serial, because
the reference has already been quoted to the client and printed on the paper
in their hand; a new one would make the corrected document a different
document. On the Register the team sees both versions and the replaced one
says so. **The verify page never says reissued**: it answers the version that
stands as Valid, since what the reader is asking is whether the paper they
hold is the document that stands, and the history of how it came to stand is
the team's and not theirs. Decided with the user on 2026-09-22.

**A component borrowed for its shape carries its old flex into the new row.**
The field that names a new content set grows out of New content set through
`.namebox`, the box the client's Approve row uses. That box takes `flex: 1.35`
because in the Approve row it splits the line with Request changes; in a
section head it took most of the row and put the one action 700px short of the
edge, which read as a button dropped in the wrong place. In a head the box
holds its own width on the right and the field opens to a stated 360px, so the
button slides left exactly as far as the field grows; on a phone the open box
takes the row. The test is the one already written two paragraphs up: what a
component was built to say, and whether the new row says it.

**A destructive control is drawn behind its capability, or it is a promise the
database will break.** `body.no-remove` already hid Delete client, the campaign
danger row and every `is-danger` menu item without `data-soft`; the content
set's trash was the one hard delete in the console drawn for everybody, so a
group without `can_remove` was offered it and then quietly refused. The two
halves go together: hide what cannot work, and say so if it is refused anyway,
because a permission can be taken away while the screen is open.

A field the browser draws itself (file, date, time, select) is reskinned
to our box: same height, same border, and its inner button is one of ours
(`::file-selector-button`: outline, `--line-ctl`, centred on the field's
line), never the platform's grey slab floating on a baseline of its own.
**A date field is a field, not a button.** iOS draws `input[type=date]` as a
pill with the value centred in it, so a full width date on a phone read as
something to press rather than something filled in, and an empty one drew
nothing at all. `appearance: none` takes the pill away,
`::-webkit-date-and-time-value { text-align: left }` puts the value where
every other field's value starts, and `display: block` holds the height of an
empty one. Under a finger the field carries its own glyph on the left (a
calendar for a date, a clock for a time, mute, 16px) because neither iOS nor
Android draws a picker mark and a tap anywhere opens the picker; at a desk
Chrome's own mark on the right is the pointer's route in, so it stays,
quietened to the mute ink, and no second calendar is drawn beside it. The
"Not set" hint starts where the value would and at the value's size.

Buttons: `.btn` outline, `.btn-primary` ink, `.btn-go` accent (the one
forward action in a view), `.btn-warn` outline warn (reversible caution:
Unpublish, Remove PDF), `.btn-quiet` text only, `.btn-sm`. Order in a
row: Save / secondary / Cancel. Same width and height for every control
in a row; `.row` aligns to the top and `.row > .btn` to the bottom.

### Responsive laws
- Breakpoints: 640px is the phone line (tables become stacked rows,
  `.crm-head` hides, facts go two across); 560px and 760px carry a few
  card and sheet adjustments; `pointer: coarse` raises every control to
  44px and field text to 16px. Test at 1280 and 390.
- No horizontal overflow at 390px. Side gutter 16px. Never a
  sideways-scrolling table; a results table becomes readable rows.
- Head card ends above the fold so the list under it is reachable.
  Nothing clipped under the sticky top bar. Sheets are full height on a
  phone.
- Phone checklist (read on every screenshot): no cell alone on its row;
  no value wrapping inside a cell; buttons that share a row share a
  width; the primary action nearest the thumb; a row of a table is two
  or three lines, not a stack; a field standing alone in a sheet or panel
  fills its container rather than sizing itself to its placeholder; a
  width pinned in a `style` attribute never survives the phone
  breakpoint.

### Fallbacks and error states
- Brand mark: the header uses `brandLogo` and shows the wordmark if it
  fails; the PDF uses `ADSPACE_ORG.logo` (the monogram), else `brandLogo`,
  and says "Logo not loaded." when neither loads. The PDF wordmark is
  always text in Optima. Fonts: `ADSPACE_ORG.font` /
  `.fontBold`, else Helvetica. Assets drawn into a PDF are fetched, so
  they must be same-origin or served with CORS.
- Client pages, one set of words: "Link not recognised / Please check the
  link or contact your ADspace account manager."; "Access code / Enter
  the access code provided."; "Unable to load / Please refresh…"; the
  Chinese set mirrors it.
- **Granting access is all the team should have to do.** Sign-ups are closed on
  the project, so a client whose auth login was never made is refused at the
  door in Supabase's own words. Making that login at the moment access is
  granted put the whole thing on one console call that nobody could see fail,
  and a client hit a wall days later. `/client/` asks `portal-login` first: it
  makes the login for an address that is a live contact with `portal_access`
  and refuses every other one, which is what keeps a page anyone can open from
  minting accounts, and it emails nothing, so the client gets the ordinary
  sign-in link and no invitation they did not expect. A flat refusal is the
  only answer the page acts on; anything else, the function not being deployed
  included, falls through to Supabase rather than locking everybody out over a
  call that was only ever a convenience.
- **A person can be a contact at more than one client.** Access is a switch on
  a contact, so one address holds it at as many clients as it is listed on:
  `portal_clients()` returns every one, `get_portal` sends the list, and the
  page shows a company select when there is more than one. A group of
  companies under different registered names is one login and one page.
- **A database's own words never reach a client.** The console shows the
  message a save failed with, because the person reading it can act on it; a
  client page shows ours. Supabase answers a sign-in for an address with no
  login with "Signups not allowed for this instance", which is an internal
  message in the wrong register naming a cause the client can do nothing
  with. `/client/` maps every sign-in failure to one of two lines: no account
  for this address sends them to their account manager, anything else (a rate
  limit, a network fault) says to try again. `signInWithOtp` also carries
  `shouldCreateUser: false`, because a page anyone can open must not be able
  to make an account.
- A save failure shows the database message in `.msg.err` under the
  control; the page never reloads; the control keeps what was typed. A
  success message is one word or two ("Saved.", "Asset added."), never
  the next step. A validation message names what is required ("A client
  is required.").
- A value cell with no amount shows the client's currency sign in mute
  (the currency is information; the missing amount is not), never a blank.
- Demo mode when Supabase config is blank (`/demo/sample.json`).
- Focus ring `0 0 0 3px rgba(31,122,77,.18)` on every control; never
  removed. `prefers-reduced-motion` turns transitions off.

### Copy and microcopy (part of the design system)

**A word two pages share is written once.** `js/words.js` holds the covers
(Link not recognised, Access code, Access denied, Unable to load, Selection
closed, No content pending review), the whole status vocabulary (campaign
steps, service line states, client stages, request states and kinds, campaign
states) and the actions every screen carries, in both languages. A page keeps
its own dictionary for what only it says and merges the shared one underneath
with `ADspaceWords.of({ en, zh })`; `/review/` has no language action in its
chrome, so it takes `ADspaceWords.en` directly. The console reads the same
file: `STAGES`, `SV_STATE`, `RQ_STATE`, `RQ_KIND` in `js/crm.js` and
`OPTION_WORD` and `STATE_WORD` in `js/campaigns.js` are built from it rather
than typed again.

**A campaign has one state and therefore one word for it.** `W.campState`
(Draft, Open for selection, In production, Completed) is that word, and the
Engagements row on a client record draws it as the `.tone` chip every other
state on that page is, not as mute text in a `·` joined line. It used to keep
a private map in `js/crm.js` saying "With the client" where the campaigns page
said "Open for selection", so one screen named a state the other screen did not
have. `tests/crm.js` reads the chip off the rendered row and compares it with
`ADspaceWords.en.campState`, so a private map put back is a failure rather than
a screenshot somebody has to notice.

The colour is the other half of a state and is not a language, so tones live
once in `W.TONE` and `W.tone(key)`, which is what makes "same status words
**and colours** on both sides" a fact about the code rather than a note in this
file. Before this, "Link not recognised" was written three times (a dictionary
in `creators.js`, another in `portal.js`, inline strings in `review.js`) and
the status vocabulary four, so changing one phrase meant finding every page
that said it, and one page quietly disagreeing with another was invisible
until a client saw it. `tests/portal.js` asserts the structure: every shared
word carries both languages, every state carries a colour, and a page word
still sits on top of the shared one.

- No explanatory copy: no hints, blurbs, notices, role descriptions or
  empty states that explain what a section is for. **One exception, asked
  for by the user on 2026-09-22 while the portal opens to the whole team**:
  each console route carries a one line purpose under its command bar
  (`.routeintro`, `INTRO` in `js/admin.js`), in official register, one or
  two sentences in the body face with **Hide** at its end; it is an
  instruction, so it follows the instruction pattern: open by itself the
  first three times the route is entered, retired after that or on Hide,
  and brought back by the `?` in the command bar, never a `title`. A
  standing fact about a route (where short links redirect from, where a
  reference is checked) is a `.routenote` line under the register, because
  it is true every day and is not an instruction. The heading and the
  controls are the explanation. Nothing says the same thing twice: a
  cover's line never repeats its title, a message never repeats the
  button it sits under, a chip never repeats the column it sits in. Where a line is unavoidable, one short
  neutral sentence in corporate register; no "we", no "you should". The
  sign-in page is a title, a field and a button; a section head is a
  heading and its one action; a hint under a destructive control states
  the consequence in one sentence.
- Buttons: one to three words, sentence case, verb first, no article, no
  object the context gives ("Add", "Save", "Confirm", "Delete campaign").
  Menu items are the action's name only. Never "Add a person", "Client
  replaced them", "Still to choose", "Something changed".
- Back is navigation; Revert undoes a state; Restore brings back a
  record; Reinstate brings back a person; never "Return".
- **The same two facts about the same person carry the same colour on every
  screen that shows them.** A contact's Portal access is green because a sign-in
  is live and Main contact is neutral because it is a designation; the client's
  own page had the two the wrong way round for as long as it had them.
- One status vocabulary on console and client page: Confirmed, Pending
  visit, Pending draft, Reviewing, Changes requested, Scheduled, Posted,
  Completed, Withdrawn; service lines Enquired, To quote, Confirmed;
  client stages Lead, Contacted, Proposal sent,
  Active, Paused, Past; requests Requested, Reviewing, Approved,
  Declined, Applied, Withdrawn (kinds Upgrade, Downgrade, Cancel, Change
  of details); on/off pairs are Active / Inactive. Pending and
  reviewing are warn colour.
- **A state is named for what is true when it is set, not for what it
  hopes to become.** A service line reads **To quote**, never Quoted: the
  flag is set while choosing what goes into the Letter of Offer, before
  any letter exists, so the past tense would claim the quotation had
  already gone out. Whether it has is the document's state, in Documents,
  and never the line's. Chinese follows the same tense (`待报价`, not
  `已报价`).
- **A control is named for what it does, not for the conversation around it.**
  The campaign switch that opens backups read "Ask the client for backups",
  which is an instruction to a colleague about a phone call and not a name for
  a setting; it is **Enable backup selection**. The same test retired "Key in a
  creator" for **Add creator**, and "roster" for **Creators List**: a house word
  the team happens to use is not the word on the screen unless it is also plain
  corporate English.
- **A field about a person records what we do, not what they can do.** A
  contact's language is a **Preferred language**, and the row reads
  "Prefers English": "Writes in English" describes the person, and reads
  as a judgement on their literacy when all the field holds is which
  language we write to them in. The same test applies to anything kept
  about a person.
- **A cover title names the outcome, not the paperwork.** The client page
  refusing an address reads **Access denied** (`无访问权限`), not "Access not
  assigned": the second describes our admin state, which is not the reader's
  business and does not sound like a decision. Sentence case, like every other
  cover title.
- **A section is named for what it tells you, not for the noun it holds.**
  The client portal's list of who can sign in was headed **Account** and read
  as the viewer's own settings, so the answer to "why is this here" was not on
  the screen. It is **Portal access** over **Person** and **Sign-in email**
  (`平台访问权限` / `姓名` / `登录邮箱`), and the purpose is then carried by the
  heading and the column, which is where it belongs: a line underneath
  explaining the section would be the explanatory copy this portal does not
  have.
- **Green is the live state, and it is spent once per row.** Where a row can
  carry two marks, the one that names something running takes the accent and
  the rest read neutral: a contact's **Portal access** is green because a
  sign-in is live, and **Main contact** is a designation, so it is not.
- A value the client only reads is a chip in the state column; the same
  row shape as the console, the select swapped for the chip, the ⋯ kept
  only where the client has an action.
- **A line addresses the client only where the client is the one who
  acts.** The state chip says where the work is; the Next line says what
  comes after it, in the team's words unless the next move is theirs.
  Pending draft reads "Draft in progress", never "Draft for your review":
  nothing has reached them yet, and a line naming them sends them looking
  for a link that does not exist until the team uploads it and the step
  becomes Reviewing. Reviewing ("Your approval") and Changes requested are
  the only steps that are theirs.
- Count creators, not slots. A campaign card shows the client's amount,
  not the invoice number. rednote (lower case, the brand sets it that way), never Xiaohongshu and never RedNote; Post, never Note.
- Placeholders: the field's name or John Doe, john@adspacestudios.com,
  COMPANY NAME SDN BHD; never a real client or creator.
- Brand names exactly: ADspace, S P Setia, CraftStone, Home Leader, The
  Mill International, EV SUN, Foodince, Furiku Matcha, HKL Lim, HKL Lim
  Motorsport, Star Living, Niro Granite, Dale & Cecil, Dale.
- Chinese is localised, not translated; same tokens, font stack swapped.
- No dashes in copy where avoidable. Dates `12 Sept 2026`, months
  `Oct 2026`, money `RM 8,490.00`.

### Architecture
- Console sections in order: Clients, Content Review, Creator Campaigns,
  Short Links, Services, Team. Clients first; everything hangs off a
  client; only active clients appear in Content Review and campaigns.
- The sale: support keys in the lead → sales logs the first call or
  visit (Contacted by itself) → billing details and brand profile as the
  deal firms → service lines with price, months, start date, confirmed →
  the Letter of Offer to the client, who signs it (Proposal sent); then
  the formal quotation and invoice outside the portal → billing
  complete and Active → engagements.
- The client record top to bottom follows that order; every section
  edits itself with its own Save; Edit replaces the head and Cancel
  returns to the record.
- Billing required before Active: registered company name (capitals),
  Business registration no., Billing contact (a select over Contacts,
  main contact by default), billing address. Optional: old registration
  no., TIN, SST no., finance email. A person is stored once, in Contacts.
- Access is enforced by the database: one user group per person
  (`team_roles` → trigger → `team_members` → `allowed(flag)`); never
  per-person switches; a policy on `team_members` never queries itself.
- **A login is not a colleague.** `auth.users` carries clients as well now, so
  nothing derives team membership from it. The cutover sweep in
  `supabase/schema.sql` runs only while `team_members` is still empty and
  never takes an address recorded as a client contact: without both guards,
  granting a contact portal access created their login and the next run of the
  file made them an active Account, which is read and write over every client
  and a name in the Person in charge list. A person joins the team from the
  Team page, where somebody decides it. A row that should not be there is
  stood down (`active = false`), never deleted, because `is_team()`,
  `allowed()` and the Person in charge list all ask whether the row is active,
  and Inactive on the Team page shows what a migration changed and puts it
  back with one click.
- **One person, one side.** The team list and a client's contacts answer two
  different questions and neither used to ask the other, which is how a client
  contact became an Account with read and write over every client. The database
  refuses the overlap now (`no_team_client_overlap` on both tables), and where
  one exists anyway the **client portal is the side that yields**
  (`portal_clients()` excludes an active team address): a colleague losing a
  client's own page costs them nothing they cannot see in the console, where a
  client reaching the console costs every other client. The trigger fires only
  on the move into the overlap, so a legacy row stays editable rather than
  frozen; the repair is what clears those.
- **Signed in is not allowed in.** `/admin/` keeps the console hidden until
  `me()` has answered. Its chrome names every section of the tool, and drawing
  it the moment a session existed showed that shape to anybody at all for as
  long as the call took. `/client/` already worked this way: `#app` starts
  hidden and only `get_portal` opens it.
- A client signs in with an email link to `/client/` and reaches its
  data only through `get_portal`, `portal_request` and
  `portal_withdraw`, keyed on the signed-in email against
  `client_contacts.portal_access`. A signed-in account is not the team:
  every team table is gated by `is_team()`, never by `authenticated`
  alone. The portal never writes a record; a request is a row the team
  applies in the console. A client sees one client.
- Client pages: Content Review and Creator Selection keep their token
  links (a manager forwards a link); the portal opens them by the same
  links. Pages: `/admin/`, `/client/`, `/creators/`, `/review/`.
- **A readable address never carries access.** A client's `slug`
  (`hkl-lim-team`, set once from the name, never following a rename)
  travels in the console address only: `/admin/?s=clients&client=<slug>`,
  behind Supabase Auth and RLS, where guessing a name reaches a sign-in
  page and nothing else. `/creators/` and `/review/` are opened by the
  random `?k=` token and read no other parameter; `/client/` reads none
  at all and is keyed on the signed-in email. Never put a slug, a name or
  a sequential number where a token is the access control. `tests/client.js`
  opens `/creators/` with guessed names and fails the sweep if any of them
  shows a page. `clientByKey()` asks the column the key's shape implies,
  because Postgres refuses a non-UUID against a uuid column; a UUID in a
  link shared before slugs existed still resolves.
- **A stage carries a clock.** Speed to first contact is the number that
  moves conversion and a deal stalls in a stage, so `clients.stage_since`
  and `clients.stage_log` are stamped by the `clients_stage_clock`
  trigger, never by a page: a value derived from a change belongs with
  the change, and four call sites that each have to remember to stamp it
  are three chances to forget. Only a real move restarts the clock, so
  saving a record without touching its stage cannot make a stalled lead
  look freshly worked. After a move the row is read back
  (`refreshClient`), because a timestamp guessed in the browser is one
  that disagrees with every other screen.

  **A trigger never forces a column back to its old value.** An update
  that does not mention a column already arrives carrying the old one,
  which is all that is needed to stop a plain save restarting the clock;
  writing `new.col := old.col` in an else branch as well also blocks the
  migration's own backfill, so the clock never started on a single row
  that already existed and every suite stayed green because none of them
  ran SQL. `tests/sql.js` runs the schema against a real Postgres now.

  The **working number** (time in the current stage) sits with the stage
  it times: a mute line under the chip in the Clients list, which is
  where someone scans for who has gone cold, and costs no column the
  phone has nowhere to put. The **retrospective** (Lead 2 days ·
  Contacted 9 days · Proposal sent 17 days · Active 12 days so far) is
  one mute line under the facts on the record, reading left to right as
  the journey. Durations are in the units a sales cycle is discussed in:
  Today, N days, then months once the exact day has stopped mattering.
  A stage move is its own activity tag (`client.stage`), not the generic
  `client.edited`, because the activity record can only show a history
  it was told about.

  **A stage that has run past its limit says so, in a word.** `STALE_H` in
  `js/crm.js` holds the limits in hours and nothing else does: **Lead 48
  hours** (the window to make first contact, measured in hours or a lead
  keyed in this morning reads overdue tomorrow) and **Proposal sent 21 days**
  (the longest a proposal should sit; a week is normal, so nothing is flagged
  before then). Calendar days, not working days: a lead that came in on
  Friday is just as cold on Monday, and a client waiting on a proposal does
  not count our weekends. **Contacted carries no limit**, because none has
  been set, and a threshold nobody has chosen is not one to invent at
  scanning time: a wrong one trains the team to ignore the mark. The age line
  under the chip turns warn and reads "2 days · Overdue", the word carrying
  it so the mark survives greyscale and a reader who cannot tell warn from
  mute, and the group head counts them ("Leads 3 · 1 overdue") so a stage
  with none over stays silent.
- Data: PDPA 2010 (MY) and PDPA 2012 (SG): collect what the page needs,
  a client sees only its own data, soft remove before hard delete.
- Numbering: Letter of Offer `AQT/INT/YYMMXXX` (per month); campaign
  invoice reference `AINVXXXXXX` entered by the team.
- Reversibility: Revert for a stage, Restore for a record, Undo for a
  removal (log entry, contact, service line, uploaded PDF), Void then
  Delete for an issued document, a number never reused. Anything a
  person can upload or attach, a person can remove.
- **Removed is not deleted, and both are wanted, for opposite reasons.** A
  person leaves a company and the calls we logged with them, the letter
  addressed to them and the billing contact they were still have to read
  correctly, so Remove hides the row and keeps all of that intact. PDPA pulls
  the other way: personal data we no longer need should not be kept for ever,
  and a contact keyed in by mistake should be able to go. So a contact follows
  the letter's pattern, Void then Delete: Remove first, then **Delete
  permanently** in the ⋯ of the removed row, behind a confirmation and behind
  `can_remove` (an admin's by default, through `body.no-remove` and the
  absence of `data-soft` on the item). It is safe to take the row out because
  both foreign keys to a contact are `on delete set null` and a request keeps
  the name it was raised under as text, so nothing that survives is left
  pointing at a hole. A **rate card line** follows the same two steps for the
  same two reasons, with one addition: it is refused while a live client
  service line names it, and the message says how many. A client's line keeps
  its own label and rate, so taking the card row out costs a signed engagement
  nothing; what it costs is the next quote, and a count is a better answer
  than a silent deletion or a flat no.
- **A seed is a first run, not a running list.** A migration that inserts
  catalogue rows on every pass undoes the deletions and corrections the people
  who own that catalogue made in the console, and `on conflict do nothing`
  does not save a deleted row, because a row that is gone raises no conflict.
  So the rate card seeds only into a database that has none, and `detail` only
  where it is null. The cost is explicit: a line added to the seed list never
  reaches an existing database, and a new service is added on the Services
  page by the person whose card it is.
- **Every forward move is walked backwards before it ships.** A state
  that is derived from data is derived in one place and recomputed on
  every load, never written once by the action that caused it: a
  campaign is In production because at least one creator is in
  production, so reverting, withdrawing or replacing the last of them
  puts it back to Open for selection (`syncCampState`, off `loadOptions`,
  not off each of the three menu actions). The two deliberate exceptions
  are decisions a person owns and a trigger must not: voiding a Letter of
  Offer does not pull the client back from Proposal sent, and approving a
  client request never edits a service line.
- Row ⋯ menus are placed on the viewport by their button; a faded row
  fades its content, never its ⋯; the global click handler spares
  `.kcard-head`, `.kmenu`, `.team-act`. A modal that filters keeps one
  height.

## 3. Design theories and laws (checked on every change at 1280 and 390)

- **Fitts**: targets 38px desktop, 44px touch; the primary action nearest
  the hand (end of a row on desktop, bottom of a card on a phone).
- **Hick**: one primary action per view; rare actions in the ⋯; a select
  once there are more than four choices.
- **Miller and chunking**: groups of three to five (facts, cells, fields);
  a group carries a label; six or more items fold or become a table.
- **Gestalt** (proximity, similarity, common region, alignment): a control
  sits with the thing it changes; the same kind of data looks the same
  everywhere; a border groups, whitespace separates; equal gaps between
  siblings; everything on one grid, nothing stepped.
- **Jakob and mental models**: table, disclosure, ⋯ menu, sheet, chip,
  select; nothing invented; the shapes of rework.com style operations
  software.
- **Von Restorff**: one accent per promise. **Blue is the action** (one per
  view, two at most); green is the live state and success; warn is caution; red
  destroys; ink outline is the total; nothing else coloured. Being
  chosen is a fill, not a colour and never a shadow: `--shadow` stays on
  panels and `--shadow-lift` on menus, as the colour table says.
- **Tesler**: the console carries the complexity; the client page does not.
- **Doherty**: feedback under 400ms; a saving state on the button; never a
  page reload; optimistic where safe.
- **Progressive disclosure**: folded cards, one open at a time; a step
  appears when its stage is reached; sections that cannot apply yet stay
  hidden, not disabled. A section that arrives with a state leaves again
  when that state is reverted, on the console and on the client's page
  alike: the campaign invoice arrives with the first confirmed creator
  and goes when the last one is reverted. What the client may not see is
  withheld by the security definer function, never only by the page.
- **Consistency**: same width and height for controls in a row; same order
  Save / secondary / Cancel; same glyph for the same action; same status
  words and colours on both sides.
- **Aesthetic usability**: flat, quiet, aligned; alignment errors, orphan
  cells, wrapped values and uneven gaps read as bugs.
- **Visual weight**: the name is the heaviest thing in a row, the money
  next, meta lightest and mute; the ⋯ is the lightest control; one bold
  amount per document.
- **WCAG 2.2 AA**: 4.5:1 text, 3:1 control boundaries, visible focus, a
  label on every field and icon-only button, no information by colour
  alone (a chip carries a word).
- **Apple HIG and Material**: 44pt / 48dp touch targets, system font,
  sheet from the bottom, clarity, deference, depth.
- **Global microcopy laws**: Back / Revert / Restore / Reinstate as above;
  no status narration; state the action and its consequence only.
