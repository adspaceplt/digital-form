# ADspace Digital Portal — working rules

Static site, vanilla JS, no build step. Pages: `admin/` (console), `creators/`
(client-facing creator selection), `review/` (client-facing content review).
Supabase behind `js/api.js`; schema in `supabase/schema.sql` (re-runnable).

## Copy

- No explanatory copy. No hints, blurbs, notices, role descriptions or empty
  states that explain what a section is for, how the data model works, or why
  a rule exists. The heading and the controls are the explanation.
- Where a line is unavoidable (a format the person must follow, a destructive
  consequence), one short neutral sentence. Corporate register. No "we", no
  "you should", no reasoning.
- Dialogs and messages state the action and its consequence only.
- Client-facing pages (`creators/`, `review/`) are held to this most strictly,
  in English and Chinese alike. Chinese is localised, not translated.
- Placeholders never reuse a real name, client, creator or campaign from the
  business. Use the field's name ("Company name", "Campaign name") or a
  universal stand-in: John Doe, john@adspacestudios.com, COMPANY NAME SDN BHD.
- Buttons: one to three words, sentence case, verb first, no article, no
  object the context already gives ("Add", "Save", "Back", "Confirm",
  "Delete campaign"). Never "Add a person", "Save to the log", "Back to all
  clients", "Client replaced them". Menu items are the action's name only,
  no subtitle. Destructive items carry `is-danger`, nothing else.
- Do not state the obvious ("Uploading again replaces it"). No status
  narration, no transition words, no filler.
- Global microcopy: **Back** is navigation only (to a list or previous
  screen). **Revert** undoes a state change (a creator's stage, a
  campaign's stage). **Restore** brings back an archived record. **Reinstate**
  brings back a withdrawn or replaced person. Never "Return" for any of
  these.
- One status vocabulary. The client's page uses the same state words and the
  same chip colours as the console (Confirmed, Pending visit, Pending draft,
  Reviewing, Changes requested, Scheduled, Posted, Completed, Withdrawn);
  the Chinese set mirrors it. Pending and reviewing states are warn colour.
- Client pages share one set of link states, word for word: a missing or
  unknown token is "Link not recognised / Please check the link or contact
  your ADspace account manager."; a code gate is "Access code / Enter the
  access code provided."; a failure is "Unable to load / Please refresh…".
  The Chinese set mirrors it.
- Count creators, not "slots". A campaign card shows the client's final
  amount, not the invoice number.
- Brand names are spelled exactly: ADspace, S P Setia, CraftStone, Home Leader,
  The Mill International, EV SUN, Foodince, Furiku Matcha, HKL Lim,
  HKL Lim Motorsport, Star Living, Niro Granite, Dale & Cecil, Dale.
- No dashes in generated copy where avoidable.

## Design system (`css/portal.css`)

Apple / Cloudflare register: flat, quiet, one accent. Not "AI SaaS".

Tokens (`:root`):

| Token | Value | Use |
|---|---|---|
| `--ink` | `#13181a` | Text, primary buttons |
| `--ink-soft` | `#4b5457` | Secondary text, default button text |
| `--ink-mute` | `#7e888b` | Labels, hints, quiet buttons |
| `--line` / `--line-soft` | `#dee3e3` / `#eef1f1` | Card borders, dividers |
| `--line-ctl` | `#868b8b` | Control boundaries (input, select, textarea, outline button): 3:1 on every background |
| `--page` / `--card` / `--sunk` | `#f4f6f6` / `#ffffff` / `#f7f9f9` | Page, panels, inset areas |
| `--accent`, `--ok` | `#1f7a4d` (bg `#ecf5f0`) | The one green: go actions, live states, focus ring |
| `--warn` | `#9c5c16` (bg `#fbf2e6`) | Caution, unpublish, pending |
| error text | `#b3261e` | `.msg.err` only |
| `--radius` / `--radius-sm` | `10px` / `7px` | Panels / controls |
| `--ctl-h` / `--ctl-h-sm` | `38px` / `32px` | Every button, input, select |
| `--ctl-text` / `--field-text` | `13px` / `14px` | Control label / field text |
| `--shadow` / `--shadow-lift` | subtle / menus only | No decorative shadows |
| `--font` | system stack + PingFang SC, Microsoft YaHei | One family everywhere |

Coarse pointer (`@media (pointer: coarse)`): `--ctl-h` and `--ctl-h-sm` become
44px, `--field-text` 16px (stops iOS zoom). Icon-only buttons 44px.

Rules:

- One control height. A button, input and select side by side must align.
  `.row` aligns to top; `.row > .btn { align-self: flex-end }`.
- Buttons: `.btn` (outline), `.btn-primary` (ink), `.btn-go` (accent, the
  forward action), `.btn-warn` (outline warn, reversible caution),
  `.btn-quiet` (text only), `.btn-sm`. Min width 116px so rows do not step.
- Rare or destructive actions live in the card's `.kmenu` (⋯), not as buttons
  in the row. Every action is reversible where the data allows; soft remove
  (`archived_at`) before hard delete.
- Focus ring `0 0 0 3px rgba(31,122,77,.18)`. Never remove focus styles.
- Cards (`.kcard`) are flat: border, no shadow, `position: relative` so menus
  can overflow.
- Tables (`.crm-row`, `.team-row`) become stacked cards under 640px. Never a
  sideways-scrolling table on a phone.
- No horizontal overflow at 390px. Side gutter ≥ 16px.
- A phone screenshot is reviewed, not just taken. Before a push, check at
  390px: no cell in a grid sits alone on its row (column count follows cell
  count, `.tally` does this by `:has()`; a money group runs two across with
  the total spanning the row); a value never wraps inside a cell; buttons
  that share a row share a width (`.row > .btn`, `.kactions .btn`,
  `.linkbox .btn` flex equally);
  a head card ends above the fold so the list it heads is reachable
  without scrolling past it; nothing is clipped under the sticky top bar.
- Header and footer come from `js/chrome.js`
  (`<script src="/js/chrome.js" data-kicker=… data-actions="lang|qr">`).
  Footer: left `© {year} ADSPACE PLT. All Rights Reserved.`, right
  `Terms of Service` → https://adspacestudios.com/legal/policies. Footer
  stays at the bottom on short pages.
- New pages start from `docs/PAGE-TEMPLATE.html`.
- Full-page states (no link, access code, selection closed, confirmed,
  nothing to review, access not assigned) use one component on every page:
  `.cover > .cover-inner > .cover-panel`, centred in the viewport, title
  then one line, `body.is-plain`, footer on the floor. Never a left-aligned
  block, never a boxed panel.
- Icons: every primary action button in a `.viewhead` or `.filterbar`
  carries its 15px stroke icon (`+` for add, arrow-out for external links,
  copy glyph for copy). Icon-only buttons need `aria-label`. Same glyph for
  the same action everywhere; never mix outline and filled icon styles.
- Lists of ten or more cards fold by default to a one-line header (name,
  state, one summary line, chevron); one card open at a time is the norm.
- Laws to check on every change, at 1280 and 390:
  - Fitts: targets ≥ 38px desktop, 44px touch; the primary action nearest
    the hand (bottom of a card on a phone, end of a row on desktop).
  - Hick: one primary per view; rare actions in the ⋯ menu; a select over
    a row of buttons once there are more than four choices.
  - Miller and chunking: groups of three to five (facts, cells, fields);
    a group carries a label; six or more items fold or become a table.
  - Gestalt proximity, similarity, common region: a control sits with the
    thing it changes; the same kind of data looks the same everywhere
    (cells for counts and money, `.facts` for text, a table for rows);
    a border groups, whitespace separates.
  - Jakob: patterns people know (table, disclosure, ⋯ menu, sheet, chip),
    nothing invented.
  - Von Restorff: one accent. Green is the go action and live states only;
    warn for caution; ink outline for the total. Nothing else is coloured.
  - Tesler: the console carries the complexity, the client page does not.
  - Doherty: feedback under 400ms; a saving state on the button, never a
    page reload; optimistic where safe.
  - Progressive disclosure: folded cards, one open at a time; a step
    appears when its stage is reached (draft link after Pending draft).
  - Consistency: same width and height for controls in a row; same order
    Save / secondary / Cancel; same glyph for the same action.
  - Aesthetic usability: flat, quiet, aligned. Alignment errors, orphan
    cells and wrapped values read as bugs.
  - WCAG 2.2 AA: contrast ≥ 4.5:1 for text, ≥ 3:1 for controls; focus
    visible; labels on every field and icon-only button; no information
    by colour alone (a chip carries a word).
  - Apple HIG and Material: 44pt / 48dp touch targets; system font;
    sheet from the bottom on a phone.
  - Data: Malaysian PDPA 2010 and Singapore PDPA 2012. Collect what the
    page needs, show a person only their own client's data, soft remove
    before hard delete.
- Chinese UI text uses the same tokens; `lang="zh"` swaps the font stack only.

## Console structure

- Sections, in order: Clients (default), Content Review, Creator Campaigns,
  Short Links, Services (the rate card; admins edit, everyone reads), Team
  (admin only). Clients is first because everything else hangs off a client.
- A new lead is a person who asked for something: Client name, Source,
  Contact person (required), phone, email, Enquiry. Owner, Industry and
  Market sit beside them. Nothing else at intake: no website, socials,
  billing or deal value. Those live on the record.
- The sale, in order: support keys in the lead (Lead); sales logs the
  first call or visit (the record moves to Contacted by itself); billing
  details and brand profile are filled as the deal firms up; sales adds
  service lines with price, months and start month and confirms them; a
  quotation is issued for the client to sign (Proposal sent); billing
  complete and Active; only then engagements.
- The client record, top to bottom, follows that order: head (Source,
  Owner, Industry, Market, Value, Added; Edit opens in place of the head
  and changes only these and the stage), Client details (contacts, then
  the Billing details and Brand profile folds), Calls and visits, Services
  (lines from the rate card with qty × rate × months, Enquired / Quoted /
  Confirmed; the confirmed total, else the quoted total, is the Value),
  Documents (quotation, invoice), Engagements (shown only once Active).
- Stages: Lead, Contacted, Proposal sent, Active, Paused, Past.
- Every section on the record edits itself with its own Save. Choosing
  Active in Edit with billing missing saves the rest, keeps the stage and
  opens Billing details on the first missing field.
- A table with no column header has no pad above its first row; the
  first row sits as far from the top as the last does from the bottom
  (`.crm-table:has(> .crm-head)` carries the pad). The audit fails on
  uneven card padding.
- Documents (`js/documents.js`): a quotation takes quoted and confirmed
  lines; an invoice takes confirmed lines and is offered only when the
  client is Active with billing complete. Numbers are `AQTYYMMDDXXX` and
  `AINVYYMMDDXXX`, sequence per day. Each is stored as issued
  (`client_documents`: bill-to, lines, totals) and redrawn from that
  snapshot; Void and Restore, never delete. The PDF is drawn in the browser
  with pdf-lib in Helvetica, English only; the issuer block comes from
  `ADSPACE_ORG` in `js/config.js`.
- URL carries state: `?s=clients|review|campaigns|links|team`, `client=`,
  `campaign=`, `tab=`, `set=`, `new=<clientId>`. A refresh lands where the
  person was, with what they typed.
- Only active clients appear in Content Review and campaign pickers.
- Activity record is a table (when, tag, subject, detail, who), grouped by day,
  filterable by section. Records removals and visibility changes only.

## Data

- Currency follows the client (`market` MY → RM, SG → S$). Tax is Malaysian
  SST 8% for every client (ADspace is a Malaysian entity) unless
  `sst_applies` is false. `js/money.js` is the only place money is formatted.
- Stage → Active requires all ten e-invoice billing fields; company legal
  name is stored in capitals.
- Access is enforced by the database. A person belongs to one **user group**
  (`team_roles`: Admin, Account, Sales built in; admins can add more). The
  group holds the seven `can_*` switches and `is_admin`; a trigger copies
  them onto `team_members`, which `me()` and `allowed(flag)` read. The
  console only hides what would be refused. Never add per-person switches.
- A policy on `team_members` must not query `team_members` directly (infinite
  recursion); go through `allowed()`.
- `invite-member` edge function creates logins; Verify JWT off.

## Testing

- Playwright headless suites live outside the repo; they stub Supabase. Run
  the full sweep before every push. Screenshot at 390 and 1280 for any
  layout change.
- The sweep includes `uxaudit`, which walks every page and state at 1280
  and at 390 with a coarse pointer and fails on: sideways overflow, a cell
  alone on its row, a value that wraps or clips, buttons in one row at
  different heights (or widths on a phone), a control under 38px (44px
  touch; `.btn-sm` and `.input-sm` may be 32px on desktop), a field or
  icon-only button without a name, more than one green action in a view,
  text under 4.5:1, a control border under 3:1, a control that takes focus
  without a ring. A red audit blocks the push.
- Every page's stylesheet and script tags carry `?v=YYYYMMDD` (a second
  push on the same day appends a letter: `20260912b`). Bump it in
  every page on a push that changes CSS or JS (one `sed` over
  `admin/index.html creators/index.html review/index.html
  docs/PAGE-TEMPLATE.html admin/drive-test/index.html`), so a deploy is
  seen at once rather than after the host's ten minute cache.
- The review page's post mockups reproduce each platform's own UI and are
  outside the audit.
