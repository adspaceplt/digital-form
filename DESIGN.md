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
| `--accent` = `--ok` | `#1f7a4d` | `#4aa876` | The one green: go action, live state, complete ring |
| `--ok-bg` | `#ecf5f0` | `#17281f` | Its tint |
| `--ok-solid` / `--on-ok` | `#1f7a4d` / `#ffffff` | `#4aa876` / `#07150e` | A green **fill** and its text |
| `--warn` / `--warn-bg` | `#9c5c16` / `#fbf2e6` | `#cf9350` / `#2a2217` | Caution, unpublish, pending and reviewing states |
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
| Panel and group title | 15px / 600 / -.01em | `.panel h3`, `.crm-group-head h3`, `.kcard-name` |
| Body | 14px in the console, **16px on the four client facing pages** (`:root[data-face="client"]`, set on the `<html>` of `/creators/`, `/creator/`, `/review/`, `/client/`), line-height 1.55 | `body`, `.facts dd`, `.svc-name b` (600). The console is a dense tool read all day at a desk, which is the departure this portal documents; a client reads one page once, usually on a phone, and is being asked to decide something on it. Only what inherits moves: controls, labels and chips state their own size, so the shapes are identical on both sides |
| Money in a row | 13.5px, tabular | `.svc-rate` |
| Control, small text | 13px / 12.5px | `.btn`, `.btn-sm`, `.svc-calc`, `.backlink` |
| Meta and labels | 12px | `.field-label`, `.svc-name small`, `.crm-lang` |
| Chip and select | 12.5px / 600 and 11.5px / 600 | `.state-select`; `.tone`, `.chip`, `.chip-state` (one chip shape: 11.5px, radius 5px, padding 2px 8px, sentence case, never an uppercase pill) |
| Eyebrow | 11px / 600 / .06em uppercase, mute | `.facts dt`, `.kstep-title`, `.crm-head`, `.svc-cat`, `.sectionlabel` |
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
| An act that cannot be taken back | A **sheet**, never `confirm()`, whenever something has to be typed: voiding a letter takes a reason, deleting one takes the reason and the reference typed back. The sheet says what the act will do in the record's own terms (which service lines go back, what is removed, whether it can be undone) before it asks. The menu item that opens it is drawn behind the capability (`body.no-docvoid`, `body.no-remove`) and the database checks the same permission again when the button is pressed, so a permission taken away while the sheet is open is a refusal and not something that already happened |
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
| Search, filter, count and the one action | `.cmdbar` > `.cmdbar-find` (a search box with its glyph, bounded 190 to 420px) + the filter selects + `.cmdbar-count` + one `.btn-sm.btn-primary`, on every console list: clients, content review, campaigns, creators, short links, the rate card, the team. The count reads `7 services` whole and `3 of 41` once a filter is on, and never sits in a section head. On a phone it shares the action's line rather than taking a fourth row before the first record |
| Links to reach a person | `.plink` chips (phone, WhatsApp, email); equal widths on a phone |

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

**A phone list is a two column table, not a card with things pushed right.**
The answer to "cards or a table on a phone" is that the card *is* the table
row: the left column is who they are over what we know about them, the right
column is where they stand over how long they have stood there, and both
columns are fixed and top aligned (`"name stage" / "meta stage"`). Anything
centred inside a row of unequal cells pushes the name off the top pad — 22px
above and 12px below on a 12px padding, which is the "spacing inconsistent"
nobody can name but everybody sees.

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

**A list is one surface, and the groups inside it are dividers.** Leads, Active
clients and Paused and past were three floating panels, each carrying its own
copy of the same five column headings, with 24px of page ground between rows
that belong to one list and the third group pushed under the fold. A stage was
then something you read from which card a client sat in, rather than from the
column that already says it. One table, one header, and the groups as the
`.svc-cat` sub-heading this portal already uses on the rate card, the Team page
and the creators list. The test is whether two rows in different groups are
still the same kind of thing: where they are, the groups are headings inside
one table; where they are not, they are separate tables.

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

**A rail is one block per question, and a block with no data is not a block.**
Each carries an eyebrow title and is divided from the next by the same hairline
the sections use. The order is what somebody needs in the order they need it:
what to do next, what is stopping the record, how much of it is filled in, the
dates it holds, the facts, what has happened lately. Two rules keep it honest.
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

A field the browser draws itself (file, date, time, select) is reskinned
to our box: same height, same border, and its inner button is one of ours
(`::file-selector-button`: outline, `--line-ctl`, centred on the field's
line), never the platform's grey slab floating on a baseline of its own.

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
  empty states that explain what a section is for. The heading and the
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
- **Von Restorff**: one accent. Green is the go action and the live state;
  warn is caution; ink outline is the total; nothing else coloured. Being
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
