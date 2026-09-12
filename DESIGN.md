# ADspace Digital Portal — design system, architecture and laws

Imported by `CLAUDE.md`. Every screen, every push, every screenshot is
checked against this file.

## 2. Design system

### Register
Apple / Cloudflare: clarity, deference, depth by layering not by
shadow. Flat, quiet, one accent, corporate. Never "AI SaaS": no rainbow
gradients, no decorative shadows, no coloured dots for status, no
explanatory blurbs.

### Colour tokens (`css/portal.css` `:root`)

| Token | Value | Use |
|---|---|---|
| `--ink` | `#13181a` | Text, primary buttons |
| `--ink-soft` | `#4b5457` | Secondary text, default button text |
| `--ink-mute` | `#646e71` | Labels, hints, quiet buttons (4.5:1 on every background) |
| `--line` | `#dee3e3` | Card borders, table rules |
| `--line-soft` | `#eef1f1` | Row dividers |
| `--line-ctl` | `#868b8b` | Input, select, textarea and outline button borders: 3:1 on every background |
| `--page` / `--card` / `--sunk` | `#f4f6f6` / `#ffffff` / `#f7f9f9` | Page, panels, inset areas and table sub-headings |
| `--accent` = `--ok` | `#1f7a4d`, bg `#ecf5f0` | The one green: go action, live state, focus ring, complete ring |
| `--warn` | `#9c5c16`, bg `#fbf2e6` | Caution, unpublish, pending and reviewing states |
| error text | `#b3261e` | `.msg.err` only; never a red button |
| `--shadow` | `0 1px 2px rgba(19,24,26,.05)` | Panels only |
| `--shadow-lift` | menus only | Nothing else casts a shadow |

Chips: `.tone` (neutral, `is-ok`, `is-warn`, `is-danger`), `.chip-state`
with the state word. Status selects are tinted like their chip:
`state-select is-ok / is-warn / is-off`.

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

Print (the Letter of Intent) follows the ADspace letterhead: wordmark
"ADspace" in Optima 14pt (`ADSPACE_ORG.fontMark` = `/css/OPTIMA.TTF`), body
in Slate Book 11pt on a 14.5pt line with 14pt between paragraphs
(`ADSPACE_ORG.font` = `/css/SlateBook.TTF`), the heavier lines (PRIVATE &
CONFIDENTIAL, the subject, ADSPACE PLT) in Slate Regular
(`ADSPACE_ORG.fontBold` = `/css/SlateRg.TTF`; no Medium file exists),
registration 9pt, table 10pt, notes 8.5pt, page count 7.5pt. Margins 54pt.
The monogram (`/css/adspace-mark.png`) sits 21pt tall top right and 20pt
bottom centre; the Company Profile QR (`/css/adspace-profile-qr.png`) 64pt
bottom right. The web UI stays on the system stack. Config holds file
paths, never font names.

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

### Components (the only ones; a new screen is built from these)

| Need | Component |
|---|---|
| Section heading with its one action | `.viewhead` > `.headmark h2` + `.btn.btn-primary` with icon |
| Text facts | `dl.facts`: label over value; the column count follows the cell count (4, 5 or 6 across); two on a phone with the fifth spanning the row |
| Counts and money | `.tallies` > `.tallygroup` > `.kstep-title` + `.tally` > `.tally-cell` (`is-total`, `is-warn`); counts three across on a phone, money two across with the total spanning |
| Rows of records | `.crm-table` > `.crm-head` + `.crm-row` / `.svc-row` (`csv-row` service lines, `doc-row` documents, `cat-row` rate card, `ct-row` contacts, `team-row`); state column `var(--state-w)` second last, `.team-act` ⋯ cell last; on a phone two or three lines by `grid-template-areas` (name and ⋯ / small facts / money left, state right), never one field per line |
| Completeness of a group | `.ringline` > `.ring` (`is-ok` when full) + "2 of 4" or "Complete" |
| One record with steps | `.kcard` > `.kcard-head` (name, chips, ⋯) + `.kstep` blocks; folds to one line in lists of ten or more |
| Rare or destructive actions | `.kmenu-btn` ⋯ + `.kmenu` > `.kmenu-item` (name only; `is-danger`) |
| Status | `select.state-select` (tinted) for a value that changes; `.tone` / `.chip-state` with a word for a value that is only read |
| Form to add or edit | `.panel` > `.panelhead h3` + `.row` fields + Save / secondary / Cancel + `.msg` |
| Optional detail | `.panel.panel-collapse` > `.disclosure` (title, summary right) + `.disclosure-body` |
| Full-page state | `.cover` > `.cover-inner` > `.cover-panel`, centred, title then one line, `body.is-plain`, footer on the floor |
| Modal | `.sheet` > `.sheet-card`, from the bottom on a phone, fixed height when it filters |
| Undo | `.undobar` with one `Undo` button, eight seconds |
| Message | `.msg` (`ok`, `warn`, `err`) as one line under the control, never a card |
| Empty list | `.empty` with two words ("No entries.", "No links.", "No matches.", "Access not assigned."); never "yet", never a sentence |
| Links to reach a person | `.plink` chips (phone, WhatsApp, email); equal widths on a phone |

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
  or three lines, not a stack.

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
  controls are the explanation. Where a line is unavoidable, one short
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
  Completed, Withdrawn; client stages Lead, Contacted, Proposal sent,
  Active, Paused, Past; on/off pairs are Active / Inactive. Pending and
  reviewing are warn colour.
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
  the Letter of Intent for the quotation team (Proposal sent) → billing
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
- Data: PDPA 2010 (MY) and PDPA 2012 (SG): collect what the page needs,
  a client sees only its own data, soft remove before hard delete.
- Numbering: Letter of Intent `AQT/INT/YYMMXXX` (per month); campaign
  invoice reference `AINV2XXXXXX` entered by the team.
- Reversibility: Revert for a stage, Restore for a record, Undo for a
  removal (log entry, contact, service line, uploaded PDF), Void then
  Delete for an issued document, a number never reused. Anything a
  person can upload or attach, a person can remove.
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
  warn is caution; ink outline is the total; nothing else coloured.
- **Tesler**: the console carries the complexity; the client page does not.
- **Doherty**: feedback under 400ms; a saving state on the button; never a
  page reload; optimistic where safe.
- **Progressive disclosure**: folded cards, one open at a time; a step
  appears when its stage is reached; sections that cannot apply yet stay
  hidden, not disabled.
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
