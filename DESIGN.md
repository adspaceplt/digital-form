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
| `--line-soft` | `#eeece7` | `#2d2f2a` | Row dividers, the selected fill |
| `--line-ctl` | `#8e8a80` | `#83857c` | Input, select, textarea and outline button borders: 3:1 on every background |
| `--page` | `#f5f5f5` | `#161814` | The ground. ADspace's own off white, the one paired with `#1a1a1a` on the website: a brand value, not a tuned one, and never "corrected" back to a warm grey |
| `--card` | `#ffffff` | `#1e201d` | Panels, tables, rows |
| `--sunk` | `#faf9f6` | `#262824` | Inset areas, table sub-headings, hover |
| `--fill` / `--on-fill` | `#1b1a17` / `#ffffff` | `#eff0ea` / `#191b17` | The solid ink surface and its text: primary button, selected `.acttab`, progress, the Undo bar |
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

**One value per semantic colour where it can do both jobs.** In dark,
`--ok` is legible as text on every surface *and* deep enough to carry
dark text as a fill, so there is still one green. A paler mint passed the
same checks and read as a highlighter pen, which is not this register.

**The grounds are neutral; the warmth is in the marks.** `--page` is the
brand's own `#f5f5f5` and `--card` is white, so the two largest surfaces
agree with each other, and the warm cast lives where it does the work: the
borders, the text and the inset surfaces. A warm page under white cards
was the mixed half of the first pass. `#f5f5f5` and the tuned `#f6f5f2`
it replaced have identical luminance, so nothing about contrast moved.

### Themes

Dark follows the reader's system and nothing else: no toggle, no stored
preference, no third state to get wrong. Only the colours move; every
size, space and shape is the same screen, so a layout that is right in
one theme is right in the other. All four pages have it (`/admin/`,
`/client/`, `/creators/`, `/review/`), because a client opens their link
at night on the same phone the team does.

Two things deliberately stay light in both themes:
- **The post mockups** (`.mk-*`, `.fb-*`, `.ig-*`, `.xhs-*` and the
  `.card-stage` they sit on) reproduce each platform's own UI. Instagram's
  feed is white; a dark one would stop being a preview of what the
  client's audience sees. They are outside the audit for the same reason.
- **The client logo disc** (`.bigcard-logo`, `.logopreview`, the mockup
  avatar). The logo is the client's artwork, usually dark on transparent,
  and it is not ours to invert. The ADspace wordmark is one flat colour
  on transparent, so that one *is* inverted rather than shipped twice.

`uxaudit` walks every page and state in **both themes at both widths**.
Contrast is the rule most easily broken by a colour written into a rule,
and a theme nobody audits is a theme that quietly fails AA.

### Shape and size tokens

| Token | Value | Use |
|---|---|---|
| `--radius` / `--radius-sm` | 10px / 7px | Panels and cards / controls and chips |
| `--ctl-h` | 38px (44px coarse pointer) | Every button, input, select, icon button |
| `--ctl-h-sm` | 32px (44px coarse) | `.btn-sm`, `.input-sm`, `.select-sm`, every status select |
| `--state-w` | 124px | Every status select, on a head as in a row |
| `--ctl-text` / `--field-text` | 13px / 14px (16px coarse, stops iOS zoom) | Control label / field text |
| Button min width | 116px | So a row of buttons does not step |
| Icon glyph | 15px stroke, 1.8 | Same glyph for the same action everywhere; never mix outline and filled |
| Icon button box | 38px (44px coarse) | `.iconbtn`, `.kfold`, `.kmenu-btn`, `.btn-icononly`: the glyph stays 16px, the target never shrinks with it |
| Ring | 18px, stroke 2.6 | `.ring` completeness indicator |

### Typography (system stack; `--font`: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial; Chinese adds PingFang SC, Microsoft YaHei by `lang="zh"`)

| Level | Size / weight / tracking | Where |
|---|---|---|
| Section heading | 19px / 600 / -.02em | `.viewhead h2`, `.crm-title h2` (record name) |
| Sub-heading | 16px / 600 / -.01em | `.viewhead h3` |
| Panel and group title | 15px / 600 / -.01em | `.panel h3`, `.crm-group-head h3`, `.kcard-name` |
| Body | 14px / 400, line-height 1.55 | `body`, `.facts dd`, `.svc-name b` (600) |
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
bottom centre. No Company Profile QR on a letter. The web UI stays on the system stack. Config holds file
paths, never font names.

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
| Rare or destructive actions | `.kmenu-btn` ⋯ + `.kmenu` > `.kmenu-item` (name only; `is-danger`) |
| Status | `select.state-select` (tinted) for a value that changes; `.tone` / `.chip-state` with a word for a value that is only read |
| The chosen one of several options | A filled shape, one language per component and never a shadow: the sidebar `.navitem.is-on` takes the `--line-soft` fill and weight 600, a `.tab.is-on` an ink underline and weight 600, an `.acttab.is-on` the ink fill with white text, a `.crow.is-on` the `--line-soft` fill, a `.bigcard.is-on` an ink border. Hover is always one step lighter than selected (`--sunk` where selected is `--line-soft`), never equal to it, and lives inside `@media (hover: hover)` so a phone cannot leave it stuck on the last thing tapped. `uxaudit` hovers an unselected option and fails when it renders the selected one's background (`hover`) |
| Form to add or edit | `.panel` > `.panelhead h3` + `.row` fields + Save / secondary / Cancel + `.msg`; one Save covers everything in the form, a file included, so a number and its PDF are never two saves, and Cancel repaints from what is stored. What is attached now sits with the field that changes it, above the actions, never stranded under them |
| Optional detail | `.panel.panel-collapse` > `.disclosure` (title, summary right) + `.disclosure-body` |
| Full-page state | `.cover` > `.cover-inner` > `.cover-panel`, centred, title then one line, `body.is-plain`, footer on the floor. **The line never restates the title**: the title says what happened, the line says what to do about it ("Selection closed" / "Please contact your ADspace account manager for any changes.", not "Selection is closed. Please contact…"). Both languages, every cover |
| Modal | `.sheet` > `.sheet-card`, from the bottom on a phone, fixed height when it filters |
| Undo | `.undobar` with one `Undo` button, eight seconds |
| Message | `.msg` (`ok`, `warn`, `err`) as one line under the control, never a card |
| Empty list | `.empty` with two words ("No entries.", "No links.", "No matches.", "Access not assigned."); never "yet", never a sentence |
| Links to reach a person | `.plink` chips (phone, WhatsApp, email); equal widths on a phone |

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
  not the invoice number. RedNote, never Xiaohongshu; Post, never Note.
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
- Data: PDPA 2010 (MY) and PDPA 2012 (SG): collect what the page needs,
  a client sees only its own data, soft remove before hard delete.
- Numbering: Letter of Offer `AQT/INT/YYMMXXX` (per month); campaign
  invoice reference `AINVXXXXXX` entered by the team.
- Reversibility: Revert for a stage, Restore for a record, Undo for a
  removal (log entry, contact, service line, uploaded PDF), Void then
  Delete for an issued document, a number never reused. Anything a
  person can upload or attach, a person can remove.
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
