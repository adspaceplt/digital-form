<!-- triggers: tests/ -->
# Tests: the stand-in, harness facts, the gate's workings and the walks

Moved from `CLAUDE.md` §1 on 2026-11-23. Read whole before changing a suite or the stand-in. The setup, the gate command, the tiers and the before-merge loop stay in `CLAUDE.md`.

- `tests/stub2.js`, the Supabase stand-in (its first rule, add every new table,
  function and refusal to it, stays in `CLAUDE.md`):
  - It is also the demo's engine: a push that changes it runs
    `node tests/demo-build.js` and commits `demo/engine.js` (the seed and
    comments left out; `demo` fails while they differ).
  - A function it answers is named in `LIVE_FNS` with its arguments, else
    every call is refused PGRST202 as PostgREST refuses a function it does
    not hold (2026-11-25: `quote_preflight` read as missing).
  - It must never be more generous than PostgREST. It refuses an ambiguous
    embed, honours `.order()`, `.gte()`, `.lte()`, `.in()` and embedded column
    lists, treats a refused delete as 204 with no error, and refuses
    `.single()` on anything but one row (PGRST116; `.maybeSingle()` on more
    than one), and answers a read 1,000 rows at most (max-rows). Every read and every function's answer is fresh JSON, so a
    page changing what it read never changes the row.
  - It refuses, as PostgREST does, a table, column, function or argument the
    live database does not hold (PGRST205, PGRST204, PGRST202), from its
    LIVE SCHEMA map (`tests/schema-map.sql` refreshes it). A push that adds
    a column or an argument adds it to the map.
  - It holds every table whose policies ask a level to them (`POLICY`, read
    from pg_policies: a refused read no rows, a refused insert 42501, a
    refused update or delete no rows and no error; `tests/policies.js` holds
    it equal to schema.sql), and every function to the signed-in colleague's
    own levels; `__teamCan` only takes one away (audit 2026-10-24: a Sales
    colleague deleted a letter). A policy changed joins the map in the same
    push.
  - Its seed holds the live groups' access maps: a change to who a page
    offers or allows is checked against the live map (`team_roles.access`)
    and the seed before it merges (2026-10-15: the seed's Marketing group
    held no My Work, so the gate's pickers offered nobody). A change to the
    seed's maps runs every suite that signs in as that group (`grep -l`
    its colleague), since a suite may rest on the old map; one that needs
    another map sets it in its own seed (2026-10-16: `search`).
  - It can refuse or delay on request: `window.__failRead`, `__slowRead`,
    `__refuseDelete`, `__refuseUpdate`, `__refuseRpc`, `__meet`.
- Harness facts:
  - `sessionStorage` is per tab, so a second tab starts from the seed.
  - The stand-in's permission map is rebuilt on every page load, so re-read by
    navigating inside the console or through `window.__rpc`.
  - The stand-in seeds no campaigns.
  - A suite that writes `window.__DB` by hand stamps what the database's
    triggers stamp (`updated_at`, as `clients_touch` does): a page knows a
    row moved by its stamp (2026-10-23, `datefloor`).
  - A change to a size token (`--ctl-h`, `--ctl-h-sm`) greps the suites
    for the old figure in the same push: twelve suites still asked 38 or 44
    of controls #740 made 34 and 36 (2026-10-23).
  - A suite names a section's command bar by its id (`#crmBar`), never
    `#section… .cmdbar`: a view's own bar beside it breaks every locator
    (2026-10-29: Overdue invoices' `#odBar` crashed `cmdbar`).
  - A suite that answers the CDN itself answers a video address with a
    playable video (`revise`'s WebM), never a picture: a reel fed a PNG
    fails to decode and draws the missing tile (2026-10-22).
  - Every Postgres suite starts its cluster on UTC (`-c timezone=UTC`), as
    the live database runs: a cluster started from a shell on Malaysia time
    read date literals and `current_date` in MYT (2026-10-21).
  - Postgres suites build cut-down tables, so a new column goes into their
    fixture too.
  - A function body is parsed only where a suite makes it with bodies
    checked: `auditfix` loads the whole schema as the live database does and
    fails a syntax error or a function the schema makes that never got
    made, and every schema change runs it (2026-11-19: `public.ops_me().id`
    passed `sql`, which sets `check_function_bodies` off, and the live
    database refused the whole migration).
  - uxaudit and each half of matrix have an hour each (`gate.sh`); a suite measuring
    what a page refits a frame later waits for the frames, never a fixed
    time (2026-10-30: geom read 144 segments 400ms after unhiding them).
  - A suite types a date from today (`todayKey()`, a day ahead), never a
    fixed day of the month: a fixed day is a passed date on any later day
    (2026-10-28: `work` typed the 27th on the 28th). A seed's day is
    Malaysia's, never `toISOString().slice(0, 10)` (the UTC day, yesterday
    before 8am here; 2026-10-29: `overview` read a booking 5 days late,
    not 4, after midnight).
  - A suite never compares a page's today taken at one moment with its own
    taken at another: it reads today on both sides of the act that set it
    (or reads the page's own), so a run crossing midnight holds
    (2026-11-20: `quotes` read Build quote's Date limit against a today
    read minutes after the sheet opened).
  - A suite names every month it counts on: a task's content month is
    given, never left to the month the suite runs in, and a figure read
    for this month holds a record made this hour, never days back
    (2026-11-05: `ops` held 2611W101 once November came, `overview` read
    nothing moved on the 1st to the 4th).
  - A `cut()` of `schema.sql` always ends at the next banner.
  - A full-page screenshot under a finger drops the touch pointer and a
    reload does not bring it back: uxaudit and uxsection shoot through
    `fullShot`, which re-sends touch emulation on a session kept open
    (2026-10-31: phone states after a shot measured at desk sizes).
  - A seed written inside a template literal (uxaudit's `WHATSAPP`, `CRM`)
    writes a line break in a string as `\\n`: a bare `\n` breaks the string
    and the whole seed, and the walk crashes at its first sign-in
    (2026-11-04: the Email tab's seed).
  - A walk that reloads the console signs in again (`__signIn`) before it
    reports: the stand-in keeps no sign-in across a load. `report()` fails a
    console screen measured on the Sign in page (2026-11-24: My Work's
    Outstation passed twice on the sign-in form, then the walk crashed).
  - Every browser suite that waits with `settle` or `ready` tracks its
    browser (`track(await chromium.launch(...))`): without the probe
    `settle` sees no request or timer and returns at once (2026-11-24:
    `sendswitch` read Settings before `settings.js` arrived under load).
  - A suite follows a record by its id, never by being the first card: a
    list's order moves when the order rules do (2026-11-04: `prod` read
    another booking once a posted one sank to the end).
  - A suite that only needs an act pressed presses it through
    `tests/press.js` (`press(scope, sel, word)`: its own button where
    drawn, else the item of its words in the ⋯ beside it); one asserting
    where an act stands checks that itself (2026-11-18: `run` and
    `seenpage` waited on buttons the menu standard moved into a ⋯).
  - A `?v=` stamp is eight digits and any letters after (`zzzf` follows
    `z`); a suite reading one never caps the letters (2026-11-18: `seo`).
  - A walk that ends a step inside a record leaves it by its Back before
    it moves on, never counting on the rail to (2026-11-18: uxaudit waited
    on Team's Members inside a candidate).
  - uxaudit's `head` holds every bar on the walk to one height at each
    width, the console's head and a client page's bar alike, naming the bar
    drawn (2026-11-21: grouped by page, the signed-out console's bar read as
    the console's and 431 screens failed; then every bar became 64).
  - A suite types a question's answer into its field by name
    (`getByLabel`), never into whatever holds focus: under a finger
    `ADspaceConfirm` focuses its card, never a field (2026-11-21:
    `cprofile` set a creator inactive at 390 with no reason).
  - A suite that loads an edge function in Node swaps a package import by
    a pattern taking any version, never its exact text (2026-11-21:
    `analyticsfn` crashed on the AI client pinned to `@1.10.0`).
  - A suite setting `window.__meet` or `window.__meta` stands for Google
    Meet or Meta being set up: the stand-in lets go of the refusal the
    console learned from them (SWITCHED-OFF ACTS, release B), so a press
    after it is not held disabled.
  - A suite reading a script a client page fetches on demand
    (`#lazyScripts`) asks for it as the page does
    (`ADspaceChrome.need`), never waits for it to arrive at boot; a seed's
    row carries every key the page reads it by (`activity_log.client_id`)
    (2026-11-27: `pdflibhash` and uxaudit's Clients).
  - Browser suites run on Malaysia's clock (`gate.sh` sets
    `TZ=Asia/Kuala_Lumpur`; the Postgres lane keeps the machine's), so a
    suite's today is the page's; one that wants another zone names it
    (`timezoneId`, `tests/myclock.js`, `tests/tzbar.js`).


- `all` is every `tests/*.js` but `NOT_SUITES` in `gate.sh` (modules,
  builders, screenshot diagnostics); a suite needs no list to run, one
  starting its own Postgres takes that lane, and a helper is named there
  or fails the gate (2026-11-22: hiring and 24 more never ran in a full gate).
- A suite starting its own Postgres first stops any server left on its
  folder (`pg_ctl -D … -m immediate stop`): a run killed partway leaves one,
  which, started over beside, shuts down a minute later and takes the shared
  socket (2026-11-27, `sql` twice at 60s; held in `sql.js`).
- It runs browser suites three at a time, the Postgres suites in their own
  lane, then three walks side by side: uxaudit, and matrix in two halves
  (`MATRIX_PART=1` the Duo, `OWN` and the keyboard; `2` the four widths and
  200% zoom), each its own browser and output, the halves on the walks'
  second server; whole, matrix took 3,549 of a 6,933-second gate against
  the two-hour limit (2026-11-25; split, the gate ran 5,503 s).
- The slowest suites wait for what the page shows, never for time
  (`tests/settle.js`: `settle(p)` after an act, `ready(p)` after a load or a
  sign-in, ten seconds at most; `settle` lets two frames render first, so a
  ResizeObserver's refit after a resize is read, 2026-11-20); a fixed sleep
  stays only where the thing measured is time itself.
- It prints one line per suite, ending in its wall time, then the total,
  and ends `gate: ok` or `gate: PROBLEM (n)`
  (also written to `$OUT`, default `/tmp/gate.txt`); a pass that warned
  keeps its whole output in `/tmp/gate-warn-{suite}.log`.

  - uxaudit and matrix run side by side only where their browser
    profiles, mutable fixtures, output files and server are shown to be
    their own; both exit codes are read and either failing fails the gate;
    else they run one after the other. A run stops only the processes it
    started, never a server it did not.
  - Evidence: every result names the application commit, the tests commit
    and the configuration. A result is reused only where nothing since
    touches what it covers, said in one line. Mocked suites prove nothing
    about the live database, the CDN or a physical device.

- The gate never tests another checkout: run alone, it refuses port 8899
  serving any folder but its own; `snap.sh` names the tests' commit beside
  the portal's (`snapshot: <sha> · tests <sha>`, `+uncommitted` where the
  tests held unsaved edits).
- uxaudit and matrix pass only on their own `: ok` line; they exit 0 on
  PROBLEM too. A walk that crashed is run again once fixed, before the day's
  gate is read: a crash hides every screen after it (2026-10-21: nine
  findings stood behind one crash on Reports). A crash never excuses what
  it hid: no gate is reported reviewed until the walk has run clean and
  every client page's screens at 390 and 1280 are read by eye against
  DESIGN.md (2026-10-31: /quote/'s figures at 16px reached the user behind
  a crash at its quotation step; the user: "It crashes don't mean that you
  could compromise the walks and checks").
- `SKIP` is not a pass.
- If port 8899 is not up, the gate starts the local server itself:
  `setsid nohup node tests/serve.js 8899 >/dev/null 2>&1 &` (http-server's
  answers with the pages' script integrity taken off, so the stand-in loads;
  2026-10-17). A suite that runs a server of its own (`pwa`) runs
  `tests/serve.js` too, never http-server.

**What the two walks measure:**
- **uxaudit** walks every page and state at 1280, and at 390 with a coarse
  pointer; the console again in dark at both widths. The review mockups
  (`.card-stage`) are exempt. It fails on:
  - sideways overflow; a cell alone on its row; uneven padding; a header cell
    off its column (`cols`); a cell drifting between rows (`column`); a phone
    row's last column short of the edge (`edge`); uneven gaps in a section
    (`stack`);
  - a card-sized box drawing a visible outline (`outline`); a button drawn
    outlined rather than tonal, the contact chip `.plink` aside (`btnline`);
    a button's glyph in another ink than its words (`glyphink`);
  - text under 11px (`type`); a figure in a row, table, list of facts or
    total above 14px (`figsize`); a wrapped or clipped value; a control under its
    floor (`target`); a page setting a size or text token to a figure of its own
    (`ctlh`); a field under the phone scale (`zoom`);
  - mismatched heights or widths in one row; a nameless field or icon button;
    more than two blue actions in a view (`accent`);
  - contrast under 4.5:1; a control border under 3:1; focus without a ring;
    the way out drawn on the wrong side, measured by x (`order`);
  - a bar height that differs between pages (`head`); a hover equal to
    selected (`hover`);
  - a strip short of its row on a phone (every strip; a record's, a card's
    and a report's steps at every width), a strip that scrolls with no faded
    edge, or a sliding surface off its chosen option, segments included
    (`strip`); every strip on its list met at 1280 and 390.
- **matrix** takes one screen per route at 320, 768, 1024 and 1440, the
  iPhone Duo's three screens under a finger, then 1280 and 1440 at 200%
  browser zoom (the viewport halved); at 1280 and 390, where uxaudit walks,
  only the screens uxaudit never reaches there (`OWN`). It runs uxaudit's
  own `inPage()` and focus walk, and drives the keyboard through every
  dialog (Enter opens, the dialog is named, Escape closes, focus returns).

**A section's UI and UX audit** is the `/ux-audit <section | all | changed>`
skill (`.claude/skills/ux-audit/SKILL.md`, the user, 2026-10-07): it reports
and never fixes. It measures with `tests/uxsection.js` (what a person faces
on each screen, and the interface as the eye meets it; never in the gate),
walks the key flows with the four walkthrough questions, reads every screen
against the UI lenses and DESIGN.md §8's theories, grades UX and UI apart (A
to E), and merges each section into `tests/ux-audit/results.json`, which the
board mod reads (`.claude/mods/ux-audit`, `/ux-board`; listed by
`.claude-plugin/marketplace.json`). A section added to one of the three is
added to all three in the same push.
- A worktree of the suites links `pdfx/node_modules` to the main clone's
  folder; the path is ignored whatever it is (`pdfx/node_modules`, no
  slash), since a link committed once broke every clone's pull
  (2026-11-24, tests #229 and #230). `demo-build.js` builds the engine of
  the portal it is run in.
- A check that a value is absent from an answer reads its field, or strips every uuid first: a digit string matched over a payload holding uuids fails by chance (2026-11-25: `/999/` over eight uuids failed `sql` one run in twenty).
