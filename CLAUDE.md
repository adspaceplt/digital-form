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
| `--line` / `--line-soft` | `#dee3e3` / `#eef1f1` | Borders, dividers |
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
44px, `--field-text` 16px (stops iOS zoom). Icon-only buttons 40px.

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
- Header and footer come from `js/chrome.js`
  (`<script src="/js/chrome.js" data-kicker=… data-actions="lang|qr">`).
  Footer: left `© {year} ADSPACE PLT. All Rights Reserved.`, right
  `Terms of Service` → https://adspacestudios.com/legal/policies. Footer
  stays at the bottom on short pages.
- New pages start from `docs/PAGE-TEMPLATE.html`.
- Icons: every primary action button in a `.viewhead` or `.filterbar`
  carries its 15px stroke icon (`+` for add, arrow-out for external links,
  copy glyph for copy). Icon-only buttons need `aria-label`. Same glyph for
  the same action everywhere; never mix outline and filled icon styles.
- Lists of ten or more cards fold by default to a one-line header (name,
  state, one summary line, chevron); one card open at a time is the norm.
- Laws to check on every change: Fitts (targets ≥ 38px desktop, 44px
  touch, primary action nearest the hand), proximity (a control sits with
  the thing it changes, never in a bar above it), Jakob (patterns people
  know: table, disclosure, ⋯ menu, sheet), hierarchy (one primary per view,
  one accent), consistency (same width and height for controls in a row,
  same order of Save / secondary / Cancel).
- Chinese UI text uses the same tokens; `lang="zh"` swaps the font stack only.

## Console structure

- Sections, in order: Clients (default), Content Review, Creator Campaigns,
  Short Links, Team (admin only). Clients is first because everything else
  hangs off a client.
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
