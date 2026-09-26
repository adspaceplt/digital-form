# ADspace Digital Portal — working rules

@DESIGN.md
@STANDARD.md

Static site, vanilla ES5 IIFE scripts, no build step, no framework, served by
GitHub Pages at digital.adspace.me (CNAME in the repo). Pages: `admin/`
(console), `client/` (client portal), `creators/` (the client's creator
selection), `creator/` (a creator's own page), `review/` (content review),
`verify/` (public reference check), `/` and `404.html` (covers). Supabase behind
`js/api.js`; schema in `supabase/schema.sql` (re-runnable; the user runs it by
hand in the SQL editor and must be told when). A change to one function or one
column ships as a dated file in `supabase/migrations/`: narrowly scoped, safe to
run twice, its own rollback, mirrored in `schema.sql`.

`DESIGN.md` holds the design system, components, laws, copy and architecture.
`STANDARD.md` holds the general standard, the working method, the completion
gate, and the Project Memory (departures, open findings, what is not built).
Where they disagree, `STANDARD.md` §2 settles it and this portal's documented
behaviour wins.

## 0. Where things are written

- These three files are **rules only**. The history behind every rule (what was
  reported, measured, tried and rejected, and why) is in `docs/DECISIONS.md`
  and `docs/DESIGN-NOTES.md`. They are not loaded.
- **Before changing an area, search the archive for it**
  (`grep -n -i "<class, function, table or word>" docs/DECISIONS.md docs/DESIGN-NOTES.md`)
  and read what matches. A rule that looks arbitrary has its reason there. Never
  undo a recorded decision without reading it.
- **One place per fact.** A rule learned is written the same push, as one line,
  in the one loaded file it belongs to (behaviour, data, tests, workflow: here;
  look, components, copy, architecture: `DESIGN.md`; general standard,
  departures, open items: `STANDARD.md`). Its story goes in `docs/DECISIONS.md`
  Part 3 as one dated entry. A superseded rule is replaced, never appended to.
  Never the same fact in two loaded files.

## 1. Tests and the gate

**Setup, first thing in a new session, before changing behaviour:**
```
git clone https://github.com/adspaceplt/digital-form-tests /home/user/digital-form-tests
ln -sfn /home/user/digital-form-tests /home/user/digital-form/tests
```
- The suites are in a private repository because this one is public
  (`_config.yml` also stops Pages publishing the notes and schema). `.gitignore`
  holds `tests` and `tests/`.
- A repair to a suite is committed and pushed to `digital-form-tests` in the
  same batch as the change it covers, or it is lost with the container.
- `tests/STATUS.md` says what each suite covers. Keep it true.
- `tests/stub2.js` is the Supabase stand-in. Add every new table, function and
  refusal to it, under the same names.
  - It must never be more generous than PostgREST. It refuses an ambiguous
    embed, honours `.order()`, `.gte()`, `.lte()`, `.in()` and embedded column
    lists, and treats a refused delete as 204 with no error.
  - It can refuse or delay on request: `window.__failRead`, `__slowRead`,
    `__refuseDelete`, `__refuseUpdate`, `__refuseRpc`, `__meet`.
- Harness facts:
  - `sessionStorage` is per tab, so a second tab starts from the seed.
  - The stand-in's permission map is rebuilt on every page load, so re-read by
    navigating inside the console or through `window.__rpc`.
  - The stand-in seeds no campaigns.
  - Postgres suites build cut-down tables, so a new column goes into their
    fixture too.
  - A `cut()` of `schema.sql` always ends at the next banner.

**One command, one result:** `bash tests/gate.sh <suites… | all | ui>`.
- It runs browser suites three at a time, the Postgres suites in their own
  lane, then uxaudit and matrix.
- It prints one line per suite and ends `gate: ok` or `gate: PROBLEM (n)`
  (also written to `$OUT`, default `/tmp/gate.txt`).
- Run it as **one background command and wait for its completion notice**.
  - Never poll with sleep.
  - Never watch suites one by one.
  - Never wait on a `pgrep` pattern: the loop's own command line matches it and
    the wait never ends.
- A suite passes on exit code 0. **Never count `FAIL` lines**: a suite that
  throws prints none.
- uxaudit and matrix pass only on their own `: ok` line; they exit 0 on
  PROBLEM too.
- `SKIP` is not a pass.
- If port 8899 is not up, the gate starts the local server itself:
  `setsid nohup npx --yes http-server -p 8899 -s . >/dev/null 2>&1 &`.

**Tiers: run what the change touched, and everything before a merge that changed behaviour.**

| Change | Run |
|---|---|
| Docs or `.md` only | Nothing, but confirm the `@` imports at the top of this file still name real files |
| Any `js/*.js` | `node --check` on each changed file, then the suites that cover it (map below) |
| CSS, markup, or anything visual | The above, plus `geom` and `ui` (uxaudit and matrix), plus screenshots at 1280 and 390 of every touched screen (both themes in the console), each opened and read against `DESIGN.md`'s phone checklist. `SHOTS=1 node tests/uxaudit.js tests` writes the walk to `tests/walk/` |
| A shared file: `css/portal.css`, `js/api.js`, `js/admin.js`, `js/sheet.js`, `js/form.js`, `js/menu.js`, `js/state.js`, `js/group.js`, `js/cmdbar.js`, `js/words.js`, `js/chrome.js`, `js/confirm.js`, `js/ask.js`, `tests/stub2.js` | `all` |
| `supabase/schema.sql` or a migration | `sql`, plus the area's Postgres suite (`ops`, `perf`, `smsql`, `levels`, `trail`). These run the file twice against a throwaway Postgres 16 and compare each canonical section with its migration byte for byte |
| A PDF (`documents.js`, `letters.js`, `smreport.js`, a perf print) | The area's suite, plus `pdfreal` and `pdfcases` (need `npm i pdfjs-dist@3.11.174 --prefix tests/pdfx`) |
| Before merging any batch that changed behaviour | `all` |

**File → suites** (at least these; `tests/STATUS.md` has the rest):

| File | Suites |
|---|---|
| `crm.js` | crm, register, six, datefloor, phone, letter |
| `ops.js` | work, keys, slide, cmdbar, phone, ops |
| `campaigns.js` | camp, prod, qc, undo, keyin, sch, camptime, six, race |
| `creators.js`, `decide.js` | cprod, bar, backup, client, canvas |
| `creator.js` | creator, cprofile |
| `review.js`, `mockups.js` | canvas, newbadge, regress, sets, setdel |
| `portal.js` | portal |
| `documents.js`, `letters.js`, `register.js`, `verify.js` | docs, letter |
| `team.js` | team, perms, levels |
| `perf.js` | perfui, perfguard, perf |
| `reports.js`, `smreport.js` | reports, adsreport, smsql |
| `passkey.js`, `captcha.js`, sign-in | passkey, signin, chrome |
| `refresh.js`, `admin/sw.js`, the manifest | pwa, phone |
| `money.js` | crm, letter, sgd |
| `workers/links/` | links |
| the Short Links route | qr, run |

**What the two walks measure:**
- **uxaudit** walks every page and state at 1280, and at 390 with a coarse
  pointer; the console again in dark at both widths. The review mockups
  (`.card-stage`) are exempt. It fails on:
  - sideways overflow; a cell alone on its row; uneven padding; a header cell
    off its column (`cols`); a cell drifting between rows (`column`); a phone
    row's last column short of the edge (`edge`); uneven gaps in a section
    (`stack`);
  - text under 11px (`type`); a wrapped or clipped value; a control under its
    floor (`target`); a field under the phone scale (`zoom`);
  - mismatched heights or widths in one row; a nameless field or icon button;
    more than two blue actions in a view (`accent`);
  - contrast under 4.5:1; a control border under 3:1; focus without a ring;
    the way out drawn on the wrong side, measured by x (`order`);
  - a bar height that differs between pages (`head`); a hover equal to
    selected (`hover`).
- **matrix** takes one screen per route at 320, 375, 390, 768, 1024, 1280 and
  1440, then 1280 and 1440 at 200% browser zoom (the viewport halved). It runs
  uxaudit's own `inPage()` and drives the keyboard through every dialog (Enter
  opens, the dialog is named, Escape closes, focus returns).

**Also required:**
- Every changed script or stylesheet tag carries `?v=YYYYMMDD` (`a`, `b`… for
  further pushes the same day). Bump it with one `sed` over every HTML file that
  carries one.
- A new route or pane joins `tests/uxaudit.js`'s walk and `tests/matrix.js`'s
  route list in the same push that builds it.
- A new state (a second row, a file, an error) is seeded in the walk, because a
  pane that walks empty is a pane nobody has measured.
- The deploy is confirmed from the GitHub Pages workflow run for the merge
  commit (`pages build and deployment`, success). `curl` to the site returns
  403 from the sandbox and proves nothing.
- Assert the mechanism, not the sentence: measure geometry. Never read a value
  out of markup or a comment.
- Assert that withheld data is absent from the function's payload. Never assert
  a value you believe correct.

## 2. Load-bearing invariants

Each line is a rule that broke once. Its reason is in the archive.

### Pages, chrome, boot
- `js/chrome.js` is the only header and footer.
  - The mark comes from `brandLogo`, the kicker from `data-kicker`, the actions
    from `data-actions` (`lang`, `qr`).
  - Footer: left `© {year} ADSPACE PLT. All Rights Reserved.`; right `Terms of
    Service` → https://adspacestudios.com/legal/policies.
  - The footer is drawn with the header and sits last from the first paint
    (`.portalfoot { order: 1 }`). It moves to the end of body once the page is
    parsed. It is hidden while it precedes an open console.
- Nothing moves after first paint.
  - The mark's ratio is kept in `localStorage` `adspace-logo-ratio` and drawn at
    that ratio (`aspect-ratio: auto R`).
  - On a first visit `.brand.is-waiting` hides the brand until the mark loads or
    fails (at most 2.5s). `ADspaceChrome.mark()` reserves the rail's mark the
    same way.
  - `data-boot` from the head script (off an `sb-*-auth-token` key; removed by
    `gate()` or a 4s timeout) paints signed-out white and signed-in without a
    sign-in bar.
- `.topbar .brand-logo` is `flex: 0 0 auto; max-width: 60vw`, because Safari
  drew it 0px wide. Safari cannot run in the sandbox; the user confirms on an
  iPhone.
- The console boots as `.console.is-booting`: its own shell and rail with the
  contents hidden and a skeleton (`#consoleBoot`) until `me()` answers.
  `applyAccess()` removes it. A refused team row goes to Access denied. Never
  draw the client pages' bar in its place.
- `/` is a scriptless cover:
  - the mark and `Digital Portal` at 15px/500 `--ink-soft`;
  - white to the edge (`--card`, `theme-color #ffffff`, `color-scheme: light`);
  - no sign-in and no list of rooms.
- `404.html` is the portal's cover:
  - English only, white, title 17px, line 14px;
  - Visit website and Contact support as `.btn-sm`;
  - no `noscript` redirect.
  - Both covers are in the uxaudit walk.
- One `.cover` for every full-page state (no link, bad link, access code,
  closed, confirmed, nothing to review, access denied), with the same words on
  every client page (`js/words.js`).
- Every page carries `viewport-fit=cover`. Sheets, feet, the confirm bar, the
  console body and the rail pad by `env(safe-area-inset-*)`.
- On iOS alone, `js/chrome.js` adds `maximum-scale=1` (stops the focus zoom,
  keeps pinch).
  - Never on Android.
  - Never `user-scalable=no`.
- Under a coarse pointer `.console-head` and `.topbar` take `--chrome-solid`
  with no backdrop filter, because Safari colours the status bar from an opaque
  bar. The `theme-color` meta follows the console's own theme (the head script
  and `wearTheme()`); client pages are white.
- The console is a PWA:
  - `admin/manifest.webmanifest`, with scope and start `/admin/`;
  - wordmark icons in `admin/icons/`.
- `admin/sw.js` caches only `offline.html` and the wordmark, and answers only a
  page load that failed. It never caches scripts or styles (the `?v=` stamps
  would serve yesterday's console). A failed registration is silent.
- Refresh app (account menu):
  - it unregisters the worker and empties Cache Storage;
  - it never touches localStorage, IndexedDB or the sign-in.
- Pull to refresh works only in the installed app, and only on a list with no
  record, sheet or menu open.

### One copy of each mechanism
- `js/api.js` is the only Supabase client.
- `js/money.js` is the only money formatter and the only place a price is
  adjusted.
  - RM for MY, S$ for SG.
  - SST 8% unless `sst_applies` is false.
  - Two decimals on every total.
  - `TERMS` holds the older factor table (used when `term_pct` is null).
- `js/menu.js` (`place`, `onScroll`) is the only copy of where a ⋯ opens.
  - Placed on the viewport; opens upward where the room is above.
  - Ignores the scroll that reveals its focused button (2px rule).
  - Follows its button on resize, and closes when the button leaves the page.
  - Inside a phone sheet it takes off the card's offset (the transformed card is
    the containing block).
  - Stacking: `.kmenu` z-index 50, over the select bar (20) and the confirm bar
    (40), under sheets (55+).
  - An open ⋯ answers Escape before the sheet under it does, and hands focus
    back to its button.
- `js/sheet.js` is the only copy of how a form sheet opens and shuts.
  - Opens at its top: the sheet and `.sheet-body` are scrolled up and the card
    is focused with `preventScroll`. A `MutationObserver` does the same for any
    `.sheet` unhidden directly.
  - Focuses the card (`tabindex="-1"`, no ring), never a field (iOS zoom).
    Exception: a sheet whose whole purpose is one value.
  - After a failed save, focus goes to the first invalid field.
  - The scrim closes only an untouched sheet. Escape and the close mark always
    close it. The close mark presses that sheet's own Cancel.
  - Focus is trapped, and handed back on close.
  - `sheet(id, on, swap)` swaps two sheets in one frame (`.is-swap`).
  - Cmd/Ctrl + Enter presses, in order: the caret's small form, then the top
    form sheet's foot primary, then the pane form's primary.
    - Never a red, disabled or hidden button.
    - Never on a sheet with no foot.
    - Never while an input method is composing.
    - The primary carries `aria-keyshortcuts`.
- `js/confirm.js` (`ADspaceConfirm.ask({title, body, go, tone, field|fields, match, cancel:false}, onYes)`)
  is every question with a consequence. **No `window.confirm`, `prompt` or
  `alert` anywhere.**
  - A destructive question opens on Cancel.
  - `#askGo` and `#askCancel` are stable ids. `#askSheet` sits at z-index 95,
    above any sheet.
  - The way back (reinstate, set active, restore) never asks.
- `js/ask.js` asks for one value.
  - `rename(host, btn)` edits in place. The pen becomes the ink tick. Enter
    saves, Escape restores, an empty value keeps the field open, and blur
    neither saves nor discards. `type`/`value` are available for a date.
  - `inline(btn)` grows the field out of the control.
  - `note(after)` is a textarea.
  - There is no sheet in it.
- `js/decide.js` records a client decision.
  - The name grows out of Approve (`.namebox`), key `adspace_reviewer`.
  - Request changes steps aside while it asks (`.approve-row.is-asking`).
  - An open note box carries `.changebox-who`.
- `js/copy.js` says Copied one way. The fallback is `execCommand('copy')` over
  an off-screen textarea.
- `js/state.js` owns loading, empty and failed (`skeleton`, `emptyLine`,
  `failLine`) and `initials`. **A failed read is never drawn as an empty list.**
  - `fit` writes `is-narrow` (≤640) and `is-tight` (≤460) on `.console-body`,
    `.rec-pane` and `.rec-rail` from a `ResizeObserver`. A list may state its
    own line (`data-narrow="860"`).
  - Never container queries: they contain the fixed ⋯ menus.
- `js/group.js` draws every directory card:
  `ADspaceGroup.section({route, key, memo, name, count, marks, shut, table})`,
  `table()`, `more()`, `keep()`.
  - Thirty rows, then Show more; once pressed it keeps every row while the page
    is open.
  - Folds are remembered under `adspace-groups` (by route and key; `memo` per
    axis).
  - A filter opens every card.
  - A card holding everything never shuts by default.
- `js/cmdbar.js` owns the command bar.
  - Below 640: a search mark and a Filters mark (with a badge counting filters
    off their default), then the count and the primary as a filled `+`; any
    view segment on a second row.
  - The bar's own selects are moved into `#cmdSheet` and back, never copied.
    Clear sets `data-default` (else the first option) and fires `change`.
    `data-nofilter` marks a select that is not a filter (`#workWf`,
    `#workScope`).
  - A second action goes behind `.cmd-more`.
  - A Filters button over only hidden selects is not drawn.
  - At a desk every bar's search is a 32px mark that grows into a 280px field
    and shuts on Escape or when left empty.
- `js/form.js` owns forms.
  - Segments (`select[data-seg]`, the select stays the source of truth, out of
    the tab order; `ADspaceForm.thumb()` slides the surface; `.is-snap` on
    first placement and resize).
  - `details.fmore` (its line from `data-none`/`data-some`/`data-on`).
  - `reveal(el)` opens a fold before a refusal focuses into it.
  - The required asterisk comes from `aria-required` (`.is-req`).
  - `ADspaceForm.title` sets formal names in title case.
  - `ADspaceForm.named` / `sequence`: every client or colleague offered in a
    console select reads code first (`AC190 · Brand`, `AD014 · Xue Yi`), A to
    Z by code with digits as numbers, the unnumbered after by name
    (`byClient`, `byStaff`). The Clients list itself stays newest first.
  - The `data-hint` date hint.
  - The date floor (below).
- `js/words.js` holds every word two pages share (covers, statuses, actions) in
  English and Chinese, plus the tones (`W.TONE`, `W.tone`) and `W.dept` /
  `W.roleStd`.
  - Pages merge with `ADspaceWords.of({en, zh})`; `/review/` takes
    `ADspaceWords.en`.
  - The console's `STAGES`, `SV_STATE`, `RQ_STATE`, `RQ_KIND`, `OPTION_WORD`
    and `STATE_WORD` are built from it, never typed again.
- `js/captcha.js` is Turnstile (`interaction-only`, `flexible`, `theme` from
  `data-theme`).
  - One box per `[data-cf]` card; otherwise after the button's row (grid or row
    flex), else after the button.
  - The site key is `ADSPACE_CONFIG.turnstileSiteKey`. A token rides every
    emailed sign-in; where Cloudflare is unreachable the email still goes.
- Dates (§5 of `js/form.js`): every date, month and date-time field is bounded
  to 14 Aug 2023 (ADSPACE PLT's registration) through 31 Dec 2099.
  - A lower `min` is raised.
  - A value out of range is cleared on blur and refused on Enter, with
    `.date-note`. `ADspaceAsk.rename` refuses it too.
  - `data-any-date` opts a field out. This is page-side only.
  - Room for the calendar (§6): at a desk, a date field too near the window's
    foot is lifted before its calendar opens (its scroller scrolls, else a
    `.pick-room` spacer), and a press that lifted it opens the calendar with
    `showPicker`. The spacer goes only as it leaves the view, never moving
    the screen under a press. A coarse pointer is left alone.

### Writes, refusals, reversibility
- **A write that changed nothing is not a success.** PostgREST answers a refused
  delete or update with 204 and no error. Every delete and every
  policy-refusable update takes `.select('id')`, and an empty answer is named
  (`Not deleted. The database refused the request.`).
- Use `.then(ok).catch(bad)`, never `.then(ok, bad)`: `bad` never sees what
  `ok` throws.
- A refusal is named in the team's words, never the database's (`SAID`-style
  maps). A missing function reads "This needs a database update".
- A client page never shows a database message. The console may.
- Back navigates, Revert undoes a state, Restore brings back a record,
  Reinstate brings back a person, Undo reverses a removal, Void then Delete
  retires an issued document.
- The way back is drawn where the act happened (`undoBar(text, undo, host)`,
  `.undobar-here`), naming what went.
- A soft remove comes before a hard delete. Anything a person can upload, a
  person can remove.
- An act that destroys somebody else's work, from a control inside that work,
  asks first in place: the ×, then `.filearm` naming the cost. The soft remove
  and the Undo stay behind it.
- A destructive control is drawn behind its permission (`data-need`), and the
  function re-checks at the press.
- A delete through a sheet re-checks the permission at the press, takes the
  name or serial typed back, and states what goes and that there is no restore.
  The label is **Delete**, never `Delete {noun}`.
- A state derived from data is derived on every load, never written by the
  action that caused it (`syncCampState`, `derive(t)`, `isLate()`, Last
  activity). The exceptions are decisions a person owns (voiding a letter never
  moves the client's stage; approving a request never edits a line).
- A value that depends on a change is stamped by a trigger, never by a page. A
  trigger never forces a column back to its old value.
- Every forward move is walked backwards before it ships.
- PL/pgSQL: declared names never match a column, and lookups are qualified. A
  shadowed name fails at run time, not at create time.
- PostgREST cannot choose between overloads a call fits, so a changed signature
  drops the old one first.
- An embed across two foreign keys names the key
  (`team_members!ops_task_assignees_team_member_id_fkey(name)`). A refused read
  of who owns what fails the list; it never draws an unowned row.
- A seed is a first run, not a running list.
  - Catalogue rows (the rate card, `detail`, Marketing and Sales) seed only
    into an empty table.
  - Admin alone is ensured on every run.
  - `on conflict do nothing` does not protect a deleted row.
- Every `ops_`/`perf_` write goes through a security-definer function. The
  tables carry a select policy only, or no policy at all (`perf_`).
- A catalogue change (for example a rate card revision) ships as a migration
  guarded line by line on the seed's value. It comes with a `-preview.sql` that
  reads and writes nothing and reports per line `will change`, `already`, or
  `edited in the console, left alone`.
- `expected_version` refuses a stale write with the current row, and the page
  repaints from it.
- Row level security is stated one `alter table … enable row level security`
  line per table, never in a `do $$` loop.
- A comparison of two copies (a migration and its schema section; the
  `ACTION_LABEL` map and `activity_section()`) is enforced by a suite.

### Access
- Access is a level per section, **none < view < work < manage**, in
  `team_roles.access` / `team_members.access`. `allowed(section, level)` is
  every policy's predicate.
  - Select is view, insert and update are work, delete is manage.
  - The levels are drawn on reversibility (add, edit and publish are
    reversible; a permanent delete is not), never on CRUD verbs.
- One user group per person (`team_roles` → trigger → `team_members`); no
  per-person switches. A policy on `team_members` never queries itself.
- The group seeded as Account is named Marketing. Its slug `account` never
  moves.
- Sections: `ops` (My Work), `clients`, `review`, `campaigns`, `register`
  (Documents), `reports`, `links`, `services`, `team`, `activity`.
- A part (`clients.billing`, `register.hr`, `activity.campaigns`…) answers with
  its own level where one is set, else its section's, in `allowed()` and the
  page's `may()` alike. Only exceptions are stored. A stored level equal to the
  section reads Same as section.
- Granted parts never inherit (`ops_granted()`): `ops.all`, `ops.reports`,
  `ops.workflows`, `ops.time`, `ops.numbering`, `team.performance`. Their unset
  option reads `No access`, and each offers only the levels the database checks
  (`PART_LEVELS`). A stored level outside them is shown and saved as what it
  grants (`offered()`).
- `ops.list`, `ops.board` and `ops.calendar` follow My Work unless set to No
  access.
- Columns other parts write are guarded by trigger at the part's Work level:
  `clients_billing_guard` (skipping a cascade, `pg_trigger_depth() > 1`) and
  `campaigns_finance_guard`.
- Retired switches refuse:
  - `can_billing` → `clients.billing`;
  - `can_doc_void` → Clients Manage;
  - `hr` → `register.hr`.
  - One-argument `allowed(x)` means work, and survives for `admin`.
  - `allowed('remove')` is gone.
- `level()` returns 0 for a missing key, above the admin branch. A permission
  check refuses and never throws. `navItems()` selects `.navitem[data-section]`.
- On the page, `may(key, level)` and one body class per section and part
  (`no-manage-review`, `no-work-clients-billing`) hide controls. Every control
  names its part (`data-need="clients.documents:manage"`, listed in
  `css/portal.css`). A tab with `data-part` draws only where readable, and the
  address falls back to Overview.
- `is_team()` gates every team table and edge function. `authenticated` is not
  the team, because clients hold logins.
  - The team list is never derived from `auth.users`. The cutover sweep runs
    only while `team_members` is empty and skips client contacts.
  - A wrong row is stood down (`active = false`), never deleted.
  - `no_team_client_overlap`: one address is never both a colleague and a live
    portal contact. Where a legacy overlap exists, `portal_clients()` returns
    nothing for a team address.
- The Team group panel:
  - `#grSum` reads the panel back as one sentence.
  - Start from Admin / Manager / Staff / View only (Custom when the panel
    matches none, worked out and never stored). Admin in Start from is the only
    way to make a group admin.
  - Each section is a segment with one line for its level (`DESC`).
  - The parts sit under Advanced (n), where n counts exceptions only.
  - No preset below Admin opens Team, HR letters or performance reviews.
- The Admin group has no ⋯ and cannot be deleted. A group delete takes
  `.select('slug')` and names a refusal.

### Directories and the command bar
- Every console directory is a card per group via `js/group.js`:
  - Clients by stage;
  - Content Review as one card;
  - Campaigns by state (Completed shut);
  - the Creators List by fee band (Inactive shut);
  - Short Links Live/Paused (Paused shut);
  - Documents by family;
  - Services by category;
  - Team by user group;
  - My Work by its axis.
- A filter repaints only when its value changed: `input` and `change` both fire,
  and `change` on blur detached Clear the filters.
- `.cmdbar-end` > `.cmdbar-quiet` (count) + `.cmdbar-acts` is one element, so a
  wrap cannot split it. An empty count is not drawn.
- The rail's order (see `DESIGN.md`) drives `SECTIONS`, the Activity record's
  tabs and `ACT_SECTION`, `PARTS.activity`, and the Team panel's blocks. One
  sequence everywhere.
- The route's purpose line opens from the route name (`.console-title` button,
  14px glyph, `aria-expanded`; `.aboutpop` placed by `ADspaceMenu.place(btn, pop, 'left')`).
  - One sentence per route, from `INTRO`.
  - Never opens by itself. While a route is new, the glyph carries `--action`.
  - Below 400px the glyph gives way and the name never does.
- A standing fact about a route is a `.routenote` under the register:
  - the verify page as a link;
  - the redirect hosts `hi.adspace.me` and `go.adspace.me` as links.

### Clients (`js/crm.js`)
- Three bands:
  - Leads;
  - Clients (active and paused);
  - Past clients (shut by default, remembered, keeping their count).
  - Each band draws thirty, then Show N more.
- Columns: Client, Stage, Industry, Person in charge, Last activity, chevron.
  - No Value column and no value on a heading.
  - Rows run newest Client ID first (digits as numbers), unnumbered after,
    newest first.
  - The row is one `<button>` with nothing nested.
  - The Client ID sits under the name in the token face and is searched.
  - On a phone the row is two columns: name over meta, and the chip over the
    age in a fixed 120px track, top aligned. The meta omits what is not known,
    never showing a bare currency sign.
- Last activity (`loadLastSeen()`): the newest of a logged call or visit, a
  stage move (`stage_since`; `Added` while it has never moved), or a document
  issued. The date sits over a mute word for which one.
  - A refused read is left out.
  - A future date never counts.
  - Nothing reads as a mute em dash.
- The Client ID is typed by hand (`^[A-Z0-9]{2,12}$`, unique) and is load
  bearing: the letter serial uses it.
- The slug is set once from the name, never follows a rename, and a clash is
  numbered. It lives only in the console address (`clientByKey()` resolves a
  slug or a UUID by shape) and never grants access.
- Stage clock: `stage_since` and `stage_log` are stamped by
  `clients_stage_clock`, and only a real move restarts it. After a move the row
  is re-read (`refreshClient`). The move is tagged `client.stage`.
- `STALE_H`:
  - Lead 48 hours;
  - Proposal sent 21 days (calendar days);
  - Contacted has no limit.
  - An over-run stage reads "N days · Overdue" in warn, and the group head
    counts them.
- Intake: Brand name (the trading name; the registered name belongs to Billing),
  Source, Contact person, Phone, WhatsApp username, Email, Enquiry, Owner,
  Industry, Market, Urgency to commence (`clients.commence`, blank until
  asked). After intake the enquiry is edited like any other fact, and a person
  becomes a row in Contacts.
- The record head `.rec-id` (`auto minmax(0,1fr) auto`, centred):
  - Mark: `logo_url`, or `initialsOf()` (two characters of a Chinese name; else
    the first letters of the first two words that start with a letter).
  - The name and its meta (the main contact's preferred language and the person
    in charge; each left out when unknown).
  - `.rec-ctl`: the stage select plus one ⋯ holding Edit and Delete (the item
    carries `data-need="clients:manage"`).
  - Phone (`.is-narrow`): `"mark . ctl" / "who who who"`.
- Panes (`tab=`, pushed to history; Overview stays out of the address):
  - Overview, Contacts, Billing, Brand, Services, Documents, Reports, Activity;
  - Requests once a contact has portal access or a request exists.
  - There is no Work pane. `tab=work` lands in My Work's Clients view
    (`view=clients&wc=slug`).
- Below 1100 the rail splits. `.rec:not(.cportal) > .rec-rail` is
  `display: contents`, and the blocks take `order`:
  - Next action, the billing gate and Profile come before the tabs.
  - `.rail-after` (Timeline, Details, Recent activity) follows the pane.
- `.rec` is `grid-template-rows: auto 1fr`.
- Overview:
  - One `.ovcard`: Contact details, Services, Letters, Calls and visits.
  - Built only from what the record has already loaded.
  - Enquired lines are left out.
  - An empty section says so in one line.
- Rail blocks (`.railblock`, `.railtitle` at 15px):
  - Next action: a written `next_action`/`next_at` beats `nextStep()`.
  - The billing gate: `.railgate` in red, only while a billing field is
    missing on a record that is not Active; it opens Billing where
    `maySeeBilling()`.
  - Profile: a bar with its missing list.
  - Timeline, Details, Recent activity (the last three `activity_log` rows,
    read once into `state.log`).
  - A block with no data leaves. `paintRail` sets the last rule; never rely on
    `:last-child`.
- Timeline (`railDates`, `journeyOf`):
  - One row per stage (name with a mute date, and the duration). Two tracks,
    never three nowrap cells.
  - The running stage carries `.tl-row.is-now` and the overdue mark.
  - Every stage date and Client since are edited in place
    (`ADspaceAsk.rename`, type date).
    - Client since is the first stage's start.
    - A stage never begins before the one before it, and no date is in the
      future.
    - One save writes `stage_log`, `stage_since` and `created_at`, with
      `.select('id')`.
- Billing required before Active:
  - registered company name (capitals);
  - BRN;
  - billing contact (a select over Contacts, main contact by default);
  - billing address.
  - Optional: old registration no., TIN, SST no., finance email.
  - Billing and Brand read first; Edit opens `#crmBillSheet` /
    `#crmBrandSheet`. The Active gate opens the sheet on the first missing
    field.
- One set of handles and one logo per client:
  - Brand and Content Review settings both edit `handle_*` and `logo_url`.
  - `social_*` is backfilled by `handle_of()` (a bare handle, or a URL's last
    segment; nothing where that segment is a route) and never written.
  - `profileUrl()` derives the links.
  - Both screens re-read the row on open, keeping any field already changed.
- Contacts:
  - A table, with `.plink` reach links.
  - WhatsApp: a username field with `@` prefilled (letters, digits, `.` and `_`;
    a pasted `wa.me/@name` taken whole). `client_contacts.whatsapp` holds
    `@name` or the number.
  - One builder for every wa.me link: a Malaysian number with a leading zero
    takes `6` in front; a number with no leading zero takes its market's code.
  - Remove is soft, then Delete permanently at Manage.
- Portal access is one switch per contact (Enable / Revoke in the ⋯, with
  Undo), shown as a green chip.
  - Enabling opens a sheet with **Send invitation email unticked**.
  - Send invitation stays in the ⋯. Undo emails nobody.
- Services:
  - Quantity × rate × months from a start date.
  - Enquired / To quote / Confirmed.
  - `detail` and `min_months` are seeded from the rate card and stay editable.
- The term adjustment is a tick with a percentage (`term_pct`, stored whether
  the tick is on or not).
  - Prefilled from `termPct(months)`: 1–3 months +25%, 4–5 +15%, 6–11 quoted,
    12+ −5%, 24+ −10%.
  - The field follows the card only while it still holds the card's figure
    (`svPctCard`).
  - `rateFor(rate, months, adjust, pct)`: a percentage bills the rate × pct;
    `null` uses the older factor table; only an explicit `false` turns it off.
    Rounded to the cent where charged.
  - `issue_letter` snapshots it and `get_portal` sends it.
- Calls and visits carry next actions and an Undo.
- Requests (Request · Fee · State · ⋯):
  - Requested → Reviewing → Approved / Declined → Applied; Withdrawn is a chip.
  - Reply sets a fee and a reply the client reads.
  - Approval never edits a service line.
- Engagements show only once Active. A campaign's state chip reads
  `W.campState`.
- Delete client:
  - in the record's ⋯, as a sheet counting from the loaded record;
  - the name typed back, plus the delete code where `delete_code_set()`;
  - `delete_client` re-checks at the press.
  - Paused and Past are the everyday exits.
- Person in charge (`owner` holds a name as text):
  - Standing a colleague down asks who takes their clients and open campaigns.
    Keep is first, and only active colleagues are offered.
  - The move takes `.select('id')` and files `client.edited` /
    `campaign.edited`.
  - A completed campaign keeps who ran it.
  - A rename carries onto every record.

### Documents (`js/documents.js`, `js/letters.js`, `js/register.js`, `js/verify.js`, `?s=register`)
- One pen (`ADspaceDocs.pen`) and one letterhead for every document. The PDF is
  never stored: a row holds the snapshot and the file is redrawn on Download.
- Letter of Offer (kind `offer`; older rows `intent`, `cover`):
  - Serial `AQL/{client_code}/{YYMM}{NN}` from the lowest free slot. The
    counter's row lock serialises; the scan is capped (`no-serial`); two
    digits is a floor, not a width.
  - A typed reference (`p_serial`, the `#pickRef` field, placeholder "Numbered
    automatically") spends no number and is refused where taken
    (`serial-taken`) or badly shaped (`serial-shape`).
  - A client with no Client ID gets a caution in the sheet, not a refusal.
  - The file name swaps `/` for `-`.
- Letter content:
  - Only To quote lines.
  - Priced by the month when every line shares a term ("Payable monthly"; the
    commitment stated in TERMS). Otherwise Total.
  - `priceOf()` computes the snapshot and the drawing.
  - `legalName` is resolved once.
  - Every line wraps.
- Letter layout:
  - The closing is reserved on its own. The acceptance page carries the
    sentence naming the reference, date, page count and figure.
  - Four transparent AcroForm fields in Helvetica.
  - The reference and initials on every page but the signed one; the monogram
    only top right on page one.
- `issuer_name_ok`: the signatory is a real team name. It is never blank, never
  an email, never a role word.
- Void (verified letters only, with a reason) and Delete (the serial typed back
  and a reason) are Clients Manage, re-checked. Both revert only the lines that
  letter alone held (`letter_sole_services`).
  - A deletion row keeps no content.
  - A deletion frees its serial (`serial_taken()` ignores deletions); voided
    and superseded letters keep theirs.
- The Register lists `documents` and `client_documents` (`asOffer()`, family
  `offer`), banded Quotation Covers / Letters of Offer / Client Letters / HR
  Letters / Other.
  - Rows: Document · Brand · Recipient · Issued · ⋯. The HR card heads Team in
    place of Brand (`teamOf()`: `member_id`, else an Employee ID in the
    reference).
  - An offer row answers to `clients.documents` and offers Open client record,
    never Void/Delete/Reissue.
- Serials per family:
  - a quotation cover takes the accounting portal's, typed;
  - a client letter `AD/[SA/]{client_code}/{code}`;
  - an HR letter `ADHR/{staff_code}/{code}{YYMM}`.
  - `-2`, `-3` where a base is spent. `serial_taken()` spans both tables.
- HR is its own part:
  - `register_may(family, level)` is the read policy and the check in every
    write;
  - an HR row never arrives without `register.hr`;
  - the activity record logs the kind alone, under subject `HR`.
- Add entry (`register_add` / `register_update`, nine arguments with
  `p_member`):
  - an HR entry names a team member and no client;
  - the document type is picked from the types already used for the family,
    with `__new` to type one, saved through `ADspaceForm.title`;
  - the date may be blank;
  - Edit applies to manual rows only.
- The client picker offers every record in the directory's bands, each A to Z
  by Client ID (`ADspaceForm.named`). A pick fills the recipient with the registered name,
  editable, and never replaces a typed one.
- Reissue (Work level, `document_reissue`):
  - voids the earlier version as Reissued and keeps it;
  - the new version keeps the serial and points back (`documents.replaces`);
  - the unique index covers standing documents only;
  - `/verify/` answers the standing version as Valid and never says reissued.
- `/verify/` (`verify_serial()`, granted to anon) answers an exact reference
  with the kind, the date and Valid / Void (Replaced for a superseded Letter of
  Offer), in English and Chinese, with `?s=` prefilled. A reference typed with
  dashes for slashes (the file name's form) is the same reference; an exact
  match is answered first.
  - It never shows the recipient.
  - HR is shown as "HR letter".
- The Chinese face (`ADSPACE_ORG.fontCjk`):
  - A CFF face is embedded whole, never subset (`isCff()`).
  - An unreachable face refuses the letter by name.
  - `fontMed` falls back to Slate Regular.
- Issue document (`#docSheet`):
  - The kind decides the fields.
  - The type seeds the title, salutation and body, with `{first name}` and
    `{role}` filled. A body somebody has edited is never overwritten.
  - The signatory is the signed-in person and their `designation`.
  - The sheet runs in the letter's own order.
  - `doc_types` is seeded once and is the team's to edit.
  - The Register sorts newest first, with Oldest first and By reference in the
    bar.
- The reference on a row is a copy control (`.serial-copy`).
- A hand-added row's second line is its kind alone.
- The old list is imported by a SQL file handed to the user, never committed
  (real names).

### Content Review (`review/`, `js/review.js`, `js/mockups.js`)
- Mockups per platform:
  - Instagram feed 4:5 (1080×1350); Reels and Stories 9:16 at the cover ratio;
  - TikTok;
  - Facebook feed and carousel (2 side by side; 4 as 2×2; 5 as 2 over 3 with
    `+N` greyed on the fifth);
  - rednote.
- On the mockup:
  - The handle, never the client name.
  - The logo fills the circle, with no border or shadow.
  - A placeholder avatar is an illuminance gradient.
  - Instagram's own concave send dart.
  - Save at the far right (`.mk-act-save`).
  - `more` rides the clamped line over a fade.
  - `br + br` collapses while clamped.
  - Likes, caption and comments sit 4px apart.
- Approve needs a name. Approved reads outlined, with Request changes hidden.
  - The Copywriting label, and the copy control at the top.
  - No Save as PDF.
  - og:title `{client name} Content Review Portal by ADspace`, on `review/`
    only.
- The Review Canvas moves the card's own blocks and puts them back; there is
  one decision control. Prev/next, the arrow keys and Escape work.
- Console:
  - Sets are folded, one open at a time.
  - Publish / Unpublish (warn).
  - Resend with a note.
  - Drive import with progress (a folder link only).
  - S3 signed PUT.
  - Active clients only.
  - A set's name grows out of New content set; a title is renamed in place.
- Deleting a set is `can_remove` / Manage, drawn behind it
  (`body.no-remove #deleteSet`). Both deletes take `.select('id')`.
- Every everyday write leaves an activity row. An edit names the fields it
  changed.

### Creator Campaigns (`js/campaigns.js`), creators, the creator portal
- Booking steps:
  - Confirmed → Pending visit → Pending draft → Submitted → Reviewing →
    Changes requested → Scheduled → Posted → Completed, each gated by its data,
    each with Revert.
  - Withdraw / Replace / Reinstate in the ⋯.
  - In production is derived (`syncCampState` off `loadOptions`).
- Release to client (Submitted → Reviewing) goes only through
  `campaign_qc_pass(p_option, p_want_second)`. A trigger refuses any other
  route.
  - Nine required checks in three groups, kept per booking (`qcKept`) until
    release. The list scrolls in `.sheet-body`, with `.qcfoot` fixed.
  - Tick all (`#qcAll`) above them ticks or clears the nine and reads mixed
    while only some are ticked.
  - A second reviewer is optional and never assigned: anybody but the asker
    completes it (unique `(option_id, team_member_id, round)`).
  - The ask is outstanding only while `qc_second_wanted && checks < 2`. The
    asker is the earliest check.
  - A send-back is checked from the top (`revision_round`).
  - `.qc-hold` names who checked. No notification.
- Exactly one blue step on a card: Release to client.
- `submitted` opens by itself and carries `.is-waiting`.
- A video plays (`.filecard-video`, 9:16, black ground). Media are 9:16 cards;
  anything else is a `.filepin-row` line.
- The team hands a file in for a creator (`teamDeliver()`, at pending draft /
  changes / submitted), with `campaign.file_added`. 1 GB per file
  (`ADSPACE_CONFIG.s3.maxUploadMB` 1024).
- Removing a handed-in file arms first (`.filearm`), then soft removes, then
  offers Undo in place.
- A campaign name that would render as nothing reads `Untitled campaign` and
  stays editable. A new one is refused on save.
- The campaign record:
  - Its panes (`pane=`) are Overview, Creators, Schedule, Deliverables, Client
    selection, Finance, Activity.
  - Schedule, Deliverables and Client selection are views over the bookings.
    They never write.
  - `.camp-next` is derived on every repaint.
- Next shoot means the earliest date from today; if none, the row reads Last
  shoot.
- `nextAction()` counts undated / upcoming / passed Pending visit bookings
  correctly.
- `#bulkBox` moves under the head that asked for it (`bulkOpen(btn)`).
- Events are filed under the campaign's raw title (`logSubject()`), with the
  creator named in the detail.
- The invoice fold arrives with the first confirmed creator and leaves with the
  last.
  - One Save covers the number (`AINV` + six digits) and the PDF.
  - Remove PDF, with Undo.
  - `get_campaign` withholds `invoice_no` and `invoice_url` until a creator is
    confirmed.
- Confirm creators is reachable from Client selection, from the Creators tab
  (`#campLock2`), and from the header line's Review and confirm (`#campNextGo`).
- Timing (`paintCampTiming`) is read from `campaigns.state_log`,
  `campaign_confirmations.created_at`, `confirmed_at` and `completed_at` (all
  stamped by triggers). A stage it cannot date is left out.
- The Creators List:
  - Creator · Profiles · Campaigns · Fee · ⋯, with no monogram.
  - Fee bands: Up to RM 300, RM 301 to 500, RM 501 to 800, Above RM 800, On
    quote. Inactive in its own band.
  - A platform filter.
  - The record cell counts and dates (`DONE_STATES` from `confirmed`,
    `submitted` included) and never names a campaign.
  - `nameKey()` trims, collapses whitespace and ignores case. The name is
    stored that way, and the duplicate is refused before any link is typed.
  - The word is Creators List, never "roster".
- Add creators: Existing creators (search and count), New creators (folded).
  Ticking a platform with no link grows the box into the field (`.pbox`), saved
  through `readProfile()`.
- A creator's profile links (`creator_profiles`) are saved only through
  `profiles_replace()`:
  - `creator_set_profiles` (the creator) and `creator_save_profiles` (Work).
  - `profile_of()` accepts only real profiles on the four platforms and
    rebuilds the link.
  - A profile another creator holds is refused.
  - A creator cannot empty their set.
  - Each change is filed twice (`creator_profile_changes` plus activity).
  - Link history offers Restore (`creator_restore_profiles`).
- Creator portal (`creator/`, `js/creator.js`):
  - Signs in with an eight-character code (`creators.access_code`, 31-character
    alphabet), carried in the link and kept in `localStorage`. Reset in the
    record.
  - `get_creator` sends the creator's own booking only.
    - Never the client's stage, commercial state, amount, other creators or
      notes.
    - Never `rate` or `currency`: the rate is the client's price with markup.
  - Uploads: `creator_can_deliver` at pending draft / changes / submitted;
    `creator_can_retract` shuts at submitted.
  - A file's kind falls back on its extension (`typeOf`, `kindOf`,
    `mediaKind()`).
  - Signed PUT via `sign-upload`, using `creator_may_upload` with a key built
    from the verified option.
  - The row is written before the file is uploaded. Every failure is named
    after the repaint.
  - AP01 is named on approval, at scheduled and posted, not at completed.
  - `creator_rate` takes 1 to 5 at completed and is never shown to the client.
  - The countdown is amber, then red once passed.
  - The page is a queue ordered by what is owed, with one booking open in
    `location.hash`.
  - The Draft step's `?` hint opens by itself three times, then retires
    (`hint()`, `bumpHint()`).
  - Sign out is named, and hidden until there is a session.
- Creators selection page (`creators/`, `js/creators.js`):
  - The detail card is folded and shut by default. The purpose and brief sit
    inside it; the due date (else the count) is on the head.
  - When the slots fill, the unpicked leave.
  - Backups only with `campaigns.backups_open` (`save_selection` refuses
    otherwise).
  - A placement line on each row (`platsOf()`).
  - A draft is decided on the card (`draftPreview`).
  - `review_draft` logs under the typed name. `get_campaign` sends the last
    review.
- Client-side decisions write an activity row under the typed name:
  `submit_review`, `confirm_selection`, `creator_submit`, `creator_rate`,
  `portal_withdraw`. `save_selection` does not (it autosaves).

### My Work (`js/ops.js`, `?s=work`, permission key `ops`, mapped once in `sectionAllowed()`)
- Views (`view=`):
  - list (default, out of the address), board, calendar, clients, report.
  - Each draws through `paint()` and `viewBox()`, never straight into a hidden
    box (`setView` draws a frame after the press).
  - A view without its permission falls back to the list.
- The list:
  - My day by default, banded Overdue, Due today, In progress, Ready for
    review, Upcoming, No due date, Waiting, Completed today (shut).
  - Views by `stage_group`, never by one workflow's key.
  - Group by day / stage / status / Task Owner / client / engagement; every
    card is shut off the day axis, and the heading carries its overdue count
    (`marksOf()`).
  - A search opens every card; a stage filter does not.
  - Whose work (`#workScope`) is a view, not a filter; The whole team only with
    `ops.all`.
  - Mine keys on the owner's id, never their name.
  - The count is read against the chosen view.
- The read is bounded, and open work is not part of the bound. Open work is
  read in full; finished work is read from the period on (three filters, not
  one `.or()`). The period select draws only while finished work can be on the
  page.
- The row:
  - A tick (everyday task) or a progress ring (content task).
  - The name cell opens the task; the row is not one button.
  - The stage select moves the task (`moveTo()` is the one path for the row,
    the card and a drop).
  - The outcome or refusal is named under the row (`.task-note`).
  - Blocked is never offered there.
  - The stage track is 160px. A narrow row ends with the stage at a stated
    width; `is-tight` gives it its own line.
- Stage tone by `stage_group`:
  - not started: mute;
  - in hand: no paint;
  - waiting on a person: warn;
  - cleared: green;
  - blocked: `--err`.
- The board is one workflow at a time (`#workWf`, filled before the empty
  state; a retired workflow is offered while its tasks are in view).
  - WIP shows `n / wip_guidance`, `.is-over` past it.
  - On hold gathers blocked, waiting and kiv, and is drawn only while it holds
    something; it is not a drop target.
  - An empty column is drawn only where a task could move next, or at the
    workflow's entry.
  - The drag uses pointer events from `.bcard-grip` (`touch-action: none`),
    with a clone following the hand. Allowed columns are marked. The select
    stays on every card.
  - The capacity strip counts this week's sessions against
    `capacity_minutes_week`.
- The calendar shows every task on its due date (the stage tone) and its
  publish date (`--pub`), with a Due / Publish key. A task whose next date is
  its publish date shows once.
- Clients view (`view=clients&wc=`): a client select, then that client's
  months, meetings and tasks (`clientWork()`), remembered per browser.
- The report (`ops_report(p_from, p_to)`, `ops.reports`, no new schema):
  - Median with the 90th percentile and a count.
  - Replanning counted beside on-time, never inside it.
  - By person, with no score and no ranking.
  - The period is always stated in dates.
  - Formal headings.
- The phase 1 model:
  - The original commitment is written once; a date move takes a reason
    category and files the old and new value.
  - Cycle time, stage time and recorded work are three measures, never summed.
    Nothing records idle time, keystrokes, screens or location.
  - One open work session per person across every task, and one accountable
    owner per task (each a partial unique index as well as a function check).
    An ended assignment is kept.
  - Stage gates are data. Ready needs an owner and a date. Client review needs
    a draft link or a note. Delivered needs a final link. Done needs a
    delivery or a stated reason.
  - A second press of create, revise or generate is the same act (retry safe).
- `forwardOf()` reads the forward move off the workflow: the nearest stage
  ahead by `position`, skipping side lanes by `stage_group`. Never a
  hand-written list.
- Revert's target is read off the last `stage_changed` event, offered only
  where the workflow allows it.
- Reason categories are stored keys, named by `reasonWord()`: Client request,
  Scope change, Internal capacity, Pending assets, Pending confirmation,
  Incorrect date listed.
- Task fields:
  - Type: Engagement, Ad hoc, Goodwill, Special.
  - Format: the rate card's formats, optional.
  - Priority: Urgent, High, Normal, Low. Urgent and High carry a chip.
  - Complexity: Light, Standard, Complex (the key `simple` reads as Light).
  - The scheduled publish date is tentative and never required. It seeds the
    content month and week until they are touched (`ntTouched`).
- Duplicate (`ops_duplicate_task`: a new code, none of the history).
- Repeat (`ops_set_recurring`: weekly, monthly on a day, or every N days; ends
  on a date or a count). `ops_generate_recurring` is idempotent on rule and
  date.
- The bar's ⋯ holds Bulk add, From template, Run repeating tasks, Select tasks
  (Manage: a sticky bar with Assign task owner and Delete) and Task numbering
  (admin).
- A task is named by a code plus a description.
  - The code (`ops_code_of`: `YYMMW{week}{NN}` for the content month) is made
    once under an advisory lock and never rewritten.
  - The description is edited in place (`ops_set_content_desc`).
  - The number is `#WT00001` (`ops_serial`). The next number is set by an admin
    (`ops_set_next_task_no`, refused at or below the highest in use).
- Scope is Client / Lead / Internal, checked once at creation
  (`ops_scope_error`):
  - Client offers active clients (paused by default; past on request);
  - Lead offers lead / contacted / proposal.
- Add task asks for a client or Internal every time.
- Add task and the content form open on one segment, Task / Content
  deliverable (`.kindseg`). Switching swaps the sheet in place.
- Add task is one act: it saves, the sheet shuts, the list is read again and
  the new row says Added. (`state.rowSaid`).
- Kept report figures are drawn through `paint()` (which hides the other
  views), never straight to `paintReport()`.
- Every task has an owner from creation (the creator by default); the sheets
  offer no Nobody.
- **Only the owner or an admin moves a task** (`ops_owner_may_move()`;
  `not-owner`). `mayMove(t)` hides the controls. The step says who has it.
- The step asks who takes the work.
  - A hand-off shows the person, with Keep me as the Task Owner unticked.
  - The owner's own steps have it ticked.
  - `ops_transition_task` takes `p_assignee` and `p_skip_reason`.
- Skipping a step is ops Work with a reason, and never into a revision. Owner
  change and hand-over (`ops_hand_over_task`) are Manage.
- Revert names where it goes and asks why.
- Reopen works on every cancelled task, back to the stage it was cancelled
  from, else the workflow's exit. Leaving Cancelled clears `cancelled_at`.
- `derive(t)` is the one source for the head status, the next step and the
  stepper.
  - Blue only for a hand-off; the ink fill for your own progress.
  - Everything uncommon sits in the ⋯.
  - `factHere()`: a step's fact buttons act on the sheet's row while the sheet
    is open.
- The SOP workflow: Planning, Ready to start, In progress, AQC review
  (↔ Revision (Internal)), Client review (↔ Revision (Client)), Approved,
  Scheduled, Live (`ops_mark_live`; a reason where the date differs),
  Performance review (+3 days, back to the creator), Completed / Taken down,
  rated 1–5 (`ops_rate_task`). General and Video are retired for new tasks.
- A draft link is optional. Without one the step reads Sent on WhatsApp, and
  the database accepts the link or a note.
- The quick sheet (`#taskDrawer`, `.sheet-side`, `open=`):
  - Next step, facts, Brief, Checklist and Comments stay open.
  - Files and links, Time records and Recent activity fold under More
    (`#dwMore`, shut each open).
  - The full record is one press further.
- Everything added can be corrected and taken back:
  - checklist items, links and comments (edit and delete are later events);
  - the brief and the priority (`ops_update_task`).
  - A required check has no ⋯.
  - A checklist tick repaints its own row only.
- Dates:
  - The first draft is the team's own (`ops_due_decider` null) and must fall
    before the final date by calendar day (`ops_due_order_ok`, checked inside
    `ops_change_due_date`).
  - The final date moves only through the creator's approval
    (`ops_request_due_change` → `ops_decide_due_change`), except for its
    creator or an admin, who move it directly.
  - Late = past the final date and short of client review (`isLate()`,
    `reviewFloor()`).
  - The control is named for what it will do: Request extension, or Change due
    date.
  - The ask is drawn under the dates:
    - Approve and Decline for the person asked;
    - Withdraw (`ops_withdraw_due_change`) for the asker;
    - nothing for anyone else.
  - The word "Move" is on no date control.
- A notification is written by `ops_log` / `ops_notify`, deduplicated per
  minute (a comment by its words).
  - The owner is told about another person's change.
  - A new owner is told they were assigned.
  - Nobody is told about their own act.
  - The bell re-reads every minute while visible, and on return.
- The month (engagement):
  - Two checks (Onboarding checklist, Pre-advertising checklist), seeded only on
    a client's first month and handed on when that month is deleted
    (`ops_engagements_hand_on_checks`).
  - `ops_engagement_set_check` stamps who ticked it.
  - Ready and In production are the database's to grant.
  - The meeting is `meeting_minutes` (15–240) plus a link (Meet, Zoom or Teams
    only).
- Every client deliverable goes into a confirmed month: one that exists, is
  open, and has its meeting set or marked not applicable (`no-month`,
  `month-closed`, `month-not-confirmed`). This holds for New task, templates,
  Duplicate, repeats and Bulk add. Everyday, internal and lead tasks are exempt.
- Bulk add is one flow: a client, one of their confirmed months (First month or
  Recurring month), and the count prefilled as planned less held.
  - Week `floor(i*4/n)+1`, with publish dates inside the week.
  - Formats: one for every task, or Set each task (`formats`, in creation
    order).
  - Preview is a dry run.
  - Run repeating tasks lives in the ⋯, and a repeat waits for a confirmed
    month (`held`).
- Google Meet: only `meet-create` touches the calendar (the refresh token lives
  in its secrets).
  - It asks `ops_engagement_meet_prepare` as the caller.
  - It refuses an overlapping slot (`slot-taken`).
  - It re-reads until `hangoutLink` appears, and records `meet-pending`.
  - It names a setup fault (`meet-not-set-up` with the missing names;
    `google-token`; `google-refused`).
  - `ops_engagement_set_meet` accepts only a `meet.google.com` link. A null
    pair removes the event and its link, and leaves a typed Zoom or Teams link
    alone.
  - Not connected is not a failure of the save.
  - `clientMessage()` is the one bilingual template.
- The client portal shows meetings read-only (`portal_meetings`), never a task.
- Deletes:
  - `ops_delete_task` (Manage; the number typed back; a reason; an
    `ops.deleted` activity row);
  - `ops_delete_tasks` (bulk; the count typed back);
  - `ops_delete_engagement` (a reason; its tasks stay).
- The task sheets live in `#workSheets`, outside the section.

### Performance (`js/perf.js`, `?s=team&tab=performance`, `?s=mine`)
- Grades: Distinction, Strong, Baseline, Needs Guidance, Performance Review.
  - C is reward eligible unless the month before was also C.
  - An L3 or L4 breach makes the month not eligible.
  - Pacing counts only for people who run ads.
  - Deductions are capped at 35.
  - L3 caps at B; L4 caps at D.
- A member sees nothing of a month, breaches included, until it is released.
  - A dispute window of 3 days, item by item.
  - Management answers, then it is acknowledged and finalised.
  - `result` is a snapshot.
  - Reference `ADHR/{staff_code}/PR{YYMM}`; an Employee ID is required.
- Every `perf_` table has RLS on and no policy. Everything is revoked from
  public, anon and authenticated, then only the API functions are granted.
- Management is two locks: `team.performance` (granted) plus the master code
  (bcrypt in `app_secrets`, set only in the SQL editor with
  `perf_code_reset`).
  - An unlock lasts 15 minutes from last use.
  - Five wrong tries lock the person out for 15 minutes.
  - Nobody acts on their own review.
- A member's page always asks for a fresh proof (`perf_guarded()` true;
  `perf_code_fresh()` reads `otp`, `magiclink`, `webauthn` or `passkey` in the
  token's `amr` within 15 minutes): Unlock with a passkey first where the
  browser can use one, Email a code beside it. The code field takes 6 to 10
  digits. The Magic Link template prints `{{ .Token }}`.
- The review list is chosen (`perf_people.reviewed`, off by default; admins
  off unless added). The month lists the people on it plus anyone whose
  review of that month has begun; the Review list sheet ticks colleagues code
  first, A to Z (`perf_profile_set`, Work).
- Department (Creative, Marketing) and role standard (`role_family`) live on
  `team_members`. Performance reads them; `perf_profile_set` sets only its two
  ticks.
- Months start from June 2026. The padlock sits beside the Performance tab.
- The print is drawn in the browser on the letterhead and never stored. It
  carries no version and no signature lines: a member acknowledges in the
  portal.
  - The download is filed first (`perf_printed` answers the server's time,
    who, their address and the released / acknowledged / finalised steps); a
    refused filing makes no file.
  - The file prints Record of this document (step, name, email, time in MYT,
    Document ID, the verify line) and every foot names who downloaded it.
  - A downloaded record is listed under HR Letters (`perf_register`, both
    `register.hr` and `team.performance` at View, own left out; its only act
    is Open review) and `/verify/` answers it as HR Letter, Valid (Replaced
    while reopened).
- History reads Downloaded for a print, and a save names each scorecard and
  rate it changed, from and to (`perf_save` files `changed`; a save that
  changed nothing files nothing).
- Both locks (the master code and the email code) are one centred `.lockcard`.
- Notifications never carry a score.

### Reports (`js/reports.js`, `js/smreport.js`, `?s=reports`)
- Reports is its own section (`reports` View / Work / Manage), not a part of
  Clients. `clients_read` also answers Reports View.
- Flow:
  - Draft → Submit for review (Work) → Confirm (Manage; never the submitter) →
    Publish to client (Manage).
  - Then Revise (the next version as a draft) or Unpublish (with a reason).
  - A trigger refuses row edits once a report is not a draft, and refuses
    status or stamp changes outside `sm_report_*`.
  - Publishing freezes `sm_report_versions.snapshot`.
  - A report a client has seen is never deleted.
- The list groups reports by stage (Drafts, In review, Confirmed, Published
  shut). New report opens on the type as a segment. Only Active clients.
- Four steps, a strip with each step's summary, Next: {step}, and Check and
  submit.
  - The commentary is four fields, with no title or headline.
- The client record's tab shows finished reports only (`sm_client_reports`,
  `sm_report_file`).
- The client portal reads only the newest version that has not been withdrawn
  (`portal_reports`, `portal_report`).
- Accounts carry forward.
- Posts paste from a spreadsheet by header name. Thumbnails are 320px JPEG data
  URLs.
- Ads reports (`kind = 'ads'`):
  - `first_month` carries the reading guidance; a later month compares against
    the previous period, which is carried forward.
  - One row per ad and objective.
  - Ads Manager's own cost per result (reach per 1,000).
  - Paste from an Ads Manager export, with the age breakdown gathered.
  - The age split must total 100% (±0.5).
- Figure fields (`numFields()`, `data-num`) show a count with separators, a
  percentage to 1 decimal, and money as RM or S$. `numIn()` reads them back.
- Money fields take `inputmode="decimal"`; counts take `numeric`.
- New report: Month and Custom period are never both live, End's `min` is
  Start, and an empty date reads Select date.
- The ads PDF:
  - Ads are grouped by objective; the cheapest is marked only among results of
    the same kind.
  - The tax note follows the market: WHT and SST for MY; DCC and GST for SG.
  - Ad names never break at an underscore.
- Import controls read Import from spreadsheet and Import from Ads Manager.
- The PDF:
  - Every section on its own page, on a golden-ratio scale, with a 33.3pt
    margin; no Methodology page.
  - Named `{client} {report} {period}.pdf`.
  - The first kind is the Social Media Accounts Report.

### Services (the rate card)
- Two tables, Services and Add-ons, with categories that carry their count.
  Admins edit; everyone reads. Rates are in RM.
- `detail` (one inclusion per line) and `min_months` seed a client's line.
- A line leaves by Set inactive, then Delete permanently (Manage). The delete is
  refused while any live `client_services` line names the slug, and the refusal
  says how many.
- The schema seeds the whole card once, into an empty table, and `detail` only
  where it is null. A new service is added on the page.

### Client portal (`client/`, `js/portal.js`)
- It is one client at a time (a company select where one login holds access at
  several). The head is the console record's (`.rec-mark`, `.rec-who`,
  `.rec-ctl`).
- Section order:
  - Overview: facts, contacts read-only, and Request change.
  - Services: confirmed and To quote lines (enquired never shown), with
    Upgrade / Downgrade / Cancel in a confirmed line's ⋯.
  - Requests: once one exists; Withdraw with Undo while Requested.
  - Letters: Download redraws the snapshot.
  - Engagements: the token links; hidden when empty.
  - Reports.
  - Content meetings.
  - Payment: only once `ADSPACE_ORG.bank` is set.
  - Portal access: Person · Sign-in email.
- The portal never writes a record. A request is a row the team applies.
- A sign-in address is text, never a mailto pill.
- Covers: Client sign-in, Check your email, Access denied, Unable to load.

### Short Links (`workers/links/`, `hi.adspace.me`)
- The Worker reads `link_resolve(p_slug, p_qr)` with the anon key and gives one
  of four answers (ok, missing, paused, revoked).
  - Redirects are 302 and `no-store`.
  - The client's parameters are carried over, minus `q`.
  - `go.adspace.me` is never retired: printed QR codes encode it.
  - The host is `ADSPACE_CONFIG.linkHost`.
- Pause and Resume live in the ⋯ (`links:work`).
  - Pause asks first; Resume asks nothing.
  - Both take `.select('id')`, filed as `shortlink.updated` with the detail.
  - `ADspaceGroup.keep` opens the card the row moves into.
- No Status column. Paused is a chip beside the slug.

### Team (`js/team.js`)
- Members sit under their group. Your own row shows the neutral `You` chip.
- Set inactive / Set active sits in the ⋯ (never on your own row). Send
  invitation asks first.
- Changing a member's email asks first.
- A member row carries:
  - Employee ID (`staff_code`, `^[A-Z0-9]{3,8}$`);
  - department (a segment);
  - Position (`designation`);
  - role standard;
  - `capacity_minutes_week` (entered as hours).
- A colleague is never deleted, only stood down.

### Activity record
- Every tag written is named in `ACTION_LABEL` (`js/admin.js`).
  `activity_section()` in SQL restates the map, and `tests/sql.js` §21 compares
  the two.
- A tag nothing names files as `other` and falls back to the section.
- One part per tab (`activity.clients`, `.ops`, `.team`, `.review`,
  `.campaigns`, `.links`, `.register`, `.services`). The link draws where any
  tab is readable.
- Performance follows Team (`team.performance` View, no master code), read
  through `perf_activity()`: when, the step, whose month, who; never a score,
  a grade, a breach or a dispute's words, and never the caller's own review.
- The tabs are My Work's view strip (`.cmdbar-views.actviews`), scrolling
  sideways with faded edges at every width.
- The panes key on the subject the row was written with, so a rename leaves
  older rows behind.
- `SECTION_ICON` and `logIcon` in `js/crm.js` cover every section. The document
  test is `/^document\.|^register\./`.
- `document.*` and `register.*` rows file under Documents.

### Sign-in, security, secrets
- `/admin/` signs in with the emailed link or the code (`#authCode`, 6 to 10
  digits, `verifyOtp` type `email`), or with a passkey (supabase-js 2.117.2 on
  `/admin/` only).
  - Passkeys are managed in the account menu.
  - The passkey offer shows once per browser (`adspace-passkey-offer`).
- `/client/`:
  - Asks `portal-login` first. It makes a login only for a live contact with
    `portal_access`, and answers `{ok: true}` to every address.
  - `signInWithOtp` with `shouldCreateUser: false`.
  - Reads only through `get_portal`, `portal_request` and `portal_withdraw`.
  - A company select appears where one address holds access at several
    clients.
- Sign-in never says whether an address has an account ("If {email} is
  registered, …").
- Secrets never enter the repo or the chat:
  - The Supabase anon key and the Google browser key are public by design.
  - The Turnstile secret, the Google refresh token and the performance master
    code live only in Supabase.
  - The delete code lives in the database.
- The S3 key should only write under `content/`. The portal never deletes from
  S3 (see `STANDARD.md` for what is not built).

## 3. Workflow and constraints

### Git and delivery
- Branch `cl/exciting-mayer-fvg0dc`; one PR per batch, squash-merged by Claude.
- After a merge, reset the branch onto `origin/main`
  (`git checkout -B … origin/main`, force-with-lease push). Never stack on
  merged history.
- Commits: a one-line title in plain English about what the person gains, a
  body in the same register, then the session's trailers.
- PR body: What changed, Test plan (ticked), footer.
- No model identifiers in any repo artifact.
- "Proceed and merge" mode: build, test, push both repos, open the PR, merge,
  confirm the Pages build, report.
  - Ask only when readings differ materially.
  - Never re-explain settled decisions.
- The report lists what the user runs by hand:
  - a migration;
  - `schema.sql`;
  - an edge function to deploy (`sign-upload`, `invite-member`, `portal-login`,
    `meet-create`; Verify JWT off);
  - a dashboard setting.
- Never ask for a URL, key or asset the repo or config already holds. Check
  `js/config.js` and `css/` first.

### Folder and file rules
- Never edit the user's root files: `ap01.html`, `ap02.html`, `ap03.html`,
  `ap-dale.html`, `accv-new.html`, `3pform.html`, `einvoiceinfo.html`,
  `interview-quiz.html`, `sales-program.html`, `supplier.html`. `index.html`
  and `404.html` are the portal's.
- `drafts/` (holding the old Jotform verify page) is excluded from Pages.
- Portal pages are folders with an `index.html` and clean paths; never `.html`
  in a URL.
- New pages start from `docs/PAGE-TEMPLATE.html`.
- One stylesheet (`css/portal.css`), one script per section, and the one-copy
  mechanisms above.
- Server code that is not a Supabase edge function lives in `workers/`, one
  folder per Worker, with a README.
- Setup docs live in `docs/` (`*-SETUP.md`, `S3-STORAGE.md`,
  `SIGN-IN-SECURITY.md`, …).
- State lives in the URL: `?s=`, `client=`, `campaign=`, `tab=`, `pane=`,
  `set=`, `new=`, `view=`, `open=`, `wc=`. A refresh lands where the person
  was. There is no path routing on Pages.
- The URL pushes history only for a record's pane; everything else replaces.

### Infrastructure (established; never re-ask)
- Hosting is GitHub Pages (`digital.adspace.me` CNAME → `adspaceplt.github.io`).
  There are no PR preview builds: the Cloudflare Pages project `adspace-form`
  was deleted on 2026-09-26 at the user's choice. The only Cloudflare compute
  is the `adspace-links` Worker.
- Supabase project `hwwuigvdfubuymchsvyx`.
- S3:
  - bucket `myadspace`, region `ap-southeast-5`, prefix `content`;
  - public through CloudFront at https://mycdn.adspace.me;
  - signed PUT from `sign-upload`;
  - video goes to S3 (Supabase storage is capped at 50 MB).
- Brand assets:
  - header mark https://mycdn.adspace.me/adspace-brandname.png (`brandLogo`);
  - favicon and og:image https://mycdn.adspace.me/adspace-favicon.png;
  - in the repo: `css/adspace-mark.png`, `css/SlateBook.TTF`,
    `css/SlateRg.TTF` (and `.woff2`), `css/SlateMedium.TTF`, `css/OPTIMA.TTF`.
  - `ADspace.png` and the website favicon were rejected.
- The issuer (`ADSPACE_ORG`): ADSPACE PLT, 202304002162, SST
  J31-2401-32100002, 61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100
  Johor Bahru, Johor, Malaysia, advertise@adspacestudios.com, (60)18 762 5233,
  adspacestudios.com. The bank line is blank.
- Emails:
  - support and issuer: advertise@adspacestudios.com;
  - account manager: marketing@adspacestudios.com;
  - admin login: adspacestudios@gmail.com.
- Google Drive import uses the browser key (restricted to
  `digital.adspace.me/*`, Drive API only).

### Guardrails the user gave
- "This should be automatic on your structure when designing": every rule in
  `DESIGN.md` is applied before the user sees a screenshot.
- "Do not state the obvious." "Be concise and direct." No explanatory copy.
- "Every action needs a way back." "Same status throughout." "Prefilled, not
  fixed." "A phone screenshot is reviewed, not just taken." "Intake asks for
  what is known on day one." "Not AI SaaS."
- **Replies to the user are corporate, short and instructions first**: what
  changed, what it means for them, what they must do. No narration, no essays.
