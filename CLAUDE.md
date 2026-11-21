# ADspace Digital Portal — working rules

@DESIGN.md
@STANDARD.md

Static site, vanilla ES5 IIFE scripts, no build step, no framework, served by
GitHub Pages at digital.adspace.me (CNAME in the repo). Pages: `admin/`
(console), `client/` (client portal), `creators/` (the client's creator
selection), `creator/` (a creator's own page), `review/` (content review),
`script/` (a client's video scripts), `verify/` (public reference check), `card/` (a colleague's namecard), `quote/`
(a prospect's own quotation), `details/` (a client's billing details form),
`supplier/` (a supplier's details form; `supplier-details/` forwards to it),
`careers/` (a candidate's own page), `/` and
`404.html` (covers). Supabase behind
`js/api.js`; schema in `supabase/schema.sql` (re-runnable). Migrations are
applied by Claude through the Supabase connector (§3). A change to one function or one
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
  in the one file it belongs to (behaviour, data, tests, workflow: here, or
  an area's own `docs/rules/` file for that area alone; look, components,
  copy, architecture: `DESIGN.md`; general standard, departures, open items:
  `STANDARD.md`). Its story goes in `docs/DECISIONS.md`
  Part 3 as one dated entry. A superseded rule is replaced, never appended to.
  Never the same fact in two loaded files.

## 1. Tests and the gate

**Setup** is the cloud session's start hook (`.claude/hooks/session-start.sh`):
it clones the suites (or fast-forwards a clean clone on main), links them,
installs `tests/pdfx` with `npm ci` when its lock changed, and warns where
Postgres 16 or Playwright is missing. Its last line names the tests commit; a
warning in its place means the setup is not done. By hand, before changing
behaviour:
```
git clone https://github.com/adspaceplt/digital-form-tests /home/user/digital-form-tests
ln -sfn /home/user/digital-form-tests /home/user/digital-form/tests
npm ci --prefix /home/user/digital-form-tests/pdfx
```
- The suites are in a private repository because this one is public
  (`_config.yml` also stops Pages publishing the notes and schema). `.gitignore`
  holds `tests` and `tests/`.
- A repair to a suite is committed and pushed to `digital-form-tests` in the
  same batch as the change it covers, or it is lost with the container.
- `tests/STATUS.md` says what each suite covers. Keep it true.
- `tests/stub2.js` is the Supabase stand-in. Add every new table, function and
  refusal to it, under the same names.
  - It is also the demo's engine: a push that changes it runs
    `node tests/demo-build.js` and commits `demo/engine.js` (the seed and
    comments left out; `demo` fails while they differ).
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
  - uxaudit and matrix have an hour each (`gate.sh`); a suite measuring
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
  - Browser suites run on Malaysia's clock (`gate.sh` sets
    `TZ=Asia/Kuala_Lumpur`; the Postgres lane keeps the machine's), so a
    suite's today is the page's; one that wants another zone names it
    (`timezoneId`, `tests/myclock.js`, `tests/tzbar.js`).

**One command, one result:** `bash tests/gate.sh <suites… | all | ui>`.
- Every shell command runs without a permission prompt (`.claude/settings.json`
  `Bash`; the user, 2026-10-10: "Auto allow bash"), as do the read-only GitHub
  and Supabase lookups (workflow runs, a PR, edge functions, logs,
  migrations; 2026-10-04). Supabase's logs are read only while a fault is
  being found, for the shortest window that holds it, never to confirm a
  deploy (the Pages run and a live read do that): every log read counts
  against the organisation's log query allowance (the user, 2026-10-15). So
  is a release's own work (the user,
  2026-10-11: "auto merge all PRs and allow all sessions"): opening,
  updating and merging a PR, applying its migration and deploying its edge
  function, in the order the release states, and starting or messaging a
  session and adding a repository it needs; any other write still asks.
- It runs browser suites three at a time, the Postgres suites in their own
  lane, then uxaudit and matrix side by side (each its own browser, output
  and server).
- The slowest suites wait for what the page shows, never for time
  (`tests/settle.js`: `settle(p)` after an act, `ready(p)` after a load or a
  sign-in, ten seconds at most; `settle` lets two frames render first, so a
  ResizeObserver's refit after a resize is read, 2026-11-20); a fixed sleep
  stays only where the thing measured is time itself.
- It prints one line per suite, ending in its wall time, then the total,
  and ends `gate: ok` or `gate: PROBLEM (n)`
  (also written to `$OUT`, default `/tmp/gate.txt`); a pass that warned
  keeps its whole output in `/tmp/gate-warn-{suite}.log`.
- Run it as **one background command and wait for its completion notice**.
  - Run it through `bash tests/snap.sh <suites… | all | ui>`: it gates a
    frozen copy of HEAD (commit first), so the next change is built while it
    runs. The machine has 4 CPUs and one gate fills them: one gate at a time.
  - The snapshot is served on 8898 (its suites rewritten to it); 8899 always
    serves the repo, so a suite run by hand meanwhile tests the live code.
  - `$OUT` reads `running: <sha>` until the gate ends. A result counts only
    under its `snapshot: <sha>` line, matching the commit it was run for.
  - Give it the two-hour limit (`timeout` 7200000): the background default
    of 30 minutes stops a full gate partway, with no result.
  - Merge first, gate once a day (the user, 2026-10-12: "Once ready pr u
    can merge then only run the gate … wait till all tasks completed then
    run a full gate full suite … build all and merge first"). A request is
    built, `node tests/affected.js --run` passes (never uxaudit or matrix,
    which run once, in the day's full gate; the user, 2026-11-20: "Only run
    once. Run during full gate would do right"), its touched
    screens are screenshotted and read (1280 and 390, both themes in the
    console; every screen a shared layout, CSS or component change
    reaches), and it merges at once on its own PR, never held for the next
    (one request, one release; the user, 2026-10-11). Beyond the suites
    the diff reaches, a suite runs by hand only while a fault is being
    found. A migration still runs `sql` and its
    area's Postgres suite before it is applied to the live database. Once
    the day's requests are all merged, one full gate (`all`: every suite,
    `ui`, uxaudit and matrix, included) runs on main; what it finds is the
    next batch, each fix its own release. Never weaken an assertion or
    change an expectation merely to pass. A failure in code a request did
    not touch is logged under `STANDARD.md` Logged defects until it ships.
  - uxaudit and matrix run side by side only where their browser
    profiles, mutable fixtures, output files and server are shown to be
    their own; both exit codes are read and either failing fails the gate;
    else they run one after the other. A run stops only the processes it
    started, never a server it did not.
  - Evidence: every result names the application commit, the tests commit
    and the configuration. A result is reused only where nothing since
    touches what it covers, said in one line. Mocked suites prove nothing
    about the live database, the CDN or a physical device.
  - Never poll with sleep.
  - Never watch suites one by one.
  - Never wait on a `pgrep` pattern: the loop's own command line matches it and
    the wait never ends.
- A suite passes on exit code 0, some output, and no line starting `FAIL`
  anywhere in it (2026-10-10, audit T1: a FAIL before the last line, or an
  empty output, passed). **Never count `FAIL` lines** to call a suite
  green: a suite that throws prints none. Every suite asserts what it walks;
  one that only prints what it saw is a diagnostic, never in the gate
  (audit T3). `tests/gateself.js` runs the gate's own judgement on
  synthetic suites.
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
- Every CDN script on a portal page names its version and carries its
  `integrity` hash and `crossorigin="anonymous"` (`tests/sql.js`); a new
  version is hashed from the file the CDN serves.

**Tiers: what checks each kind of change, in the day's full gate and by hand while a fault is found; before a merge, only the row's screenshots and `node --check` (a migration also its Postgres suite).**

| Change | Run |
|---|---|
| Docs or `.md` only | Nothing, but confirm the `@` imports at the top of this file still name real files |
| Any `js/*.js` | `node --check` on each changed file, then the suites that cover it (`node tests/affected.js --run`) |
| Copy, markup a script draws, a state of one screen | The above, plus screenshots at 1280 and 390 of every touched screen (both themes in the console), each opened and read against `DESIGN.md`'s phone checklist. `SHOTS=1 node tests/uxaudit.js tests` writes the walk to `tests/walk/` |
| Shared layout, navigation, `css/portal.css` or `css/console.css`, a component | The above for every screen it reaches, plus `cssguard` (and `geom` and `fit` for a layout change); `ui` waits for the daily run |
| A shared script: `js/api.js`, `js/admin.js`, `js/sheet.js`, `js/form.js`, `js/menu.js`, `js/state.js`, `js/group.js`, `js/cmdbar.js`, `js/words.js`, `js/chrome.js`, `js/confirm.js`, `js/ask.js`, `js/guide.js`, `tests/stub2.js` | The suites that call what changed (`grep -l`), plus screenshots where what it draws changed; `all` (with `ui`) once a day after the merges |
| `supabase/schema.sql` or a migration | `sql` and `policies`, plus the area's Postgres suite (`ops`, `perf`, `smsql`, `levels`, `trail`, `s3sql`, `confirmonce`, `meetmsgsql`). These run the file twice against a throwaway Postgres 16 and compare each canonical section with its migration byte for byte |
| A PDF (`documents.js`, `letters.js`, `smreport.js`, a perf print) | The area's suite, plus `pdfreal` and `pdfcases` (need `npm i pdfjs-dist@3.11.174 --prefix tests/pdfx`) |
| Once the day's requests are merged | `all` on main, `ui` included; its findings are the next batch |

**Which suites a change reaches** is data in the tests repository
(`tests/affected.json`: a row's path triggers, word triggers and schema
banners, its suites), read by `node tests/affected.js [base]`, which also
adds a suite naming a changed script, a changed suite itself and the
standing rules (schema: `sql`, `policies`; a stylesheet: `cssguard`, `geom`,
`fit`; the stand-in: `demo`, `stubpolicy`). A new area or suite joins the
map in the same push. The map lives with the suites, never with the
portal, so a change cannot rewrite what checks it.

**Before every merge** (2026-11-17, the user: "ok all", the verification
loop): `node tests/affected.js --run` (`node --check` on each changed
script, then those suites through `gate.sh`, in the background, uxaudit and
matrix left out and named as the full gate's; it writes
`/tmp/affected-pass/{commit}` on a pass). A run stopped partway is stopped
with every suite process it started, never its shell alone (2026-11-20: an
orphaned `levels.js` shut the next run's Postgres cluster). The merge check
(`.claude/hooks/verify-gate.sh`, mode in `verify-gate.mode`: off, observe,
enforce) reads it; a merge without a pass carries `Verify: skipped, {reason}`
in its message. A suite that fails is fixed at its cause in up to three
rounds; then it stops and goes to the user. A flaky suite is never re-run
until it passes, given a sleep or skipped: its cause is fixed, else the
check is deleted with its reason in `docs/DECISIONS.md` Part 3.

**Expectations a change moves** are listed by `node tests/expectations.js`
(every `check()` a suite lost or changed against `origin/main`; also printed
by `affected.js`) and go in the PR body under Expectations changed, for the
user to approve. A check only added is not listed.

**Global > parent > child** (the user, 2026-10-11, the light version): a
base element (button, field, select, chip) is styled by its own rule and its
variants; a section arranges it and never restyles it. `tests/cssguard.js`
(run with `ui`) fails a new section rule that sets a base element's ground,
edge, corner, height, colour or shadow; the ones standing on 2026-10-11 are
its baseline, folded into the shared rules as each area is touched, and the
baseline only shrinks (`--write` refuses to add).

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

**Also required:**
- Before a push, scan the diff for a number, word, colour, address or id
  typed into logic (the user, 2026-10-08): a business figure goes to
  `app_settings` / `perf_settings`, shared words to `js/words.js`, a colour or
  size to a token, an id or endpoint to `js/config.js`, a secret to Supabase
  only. The report names what became configurable.
- Every changed script or stylesheet tag carries `?v=YYYYMMDD` (`a`, `b`… for
  further pushes the same day). Bump it with one `sed` over every HTML file that
  carries one, never inside `.claude/` (agents' worktrees live there).
- A new route or pane joins `tests/uxaudit.js`'s walk and `tests/matrix.js`'s
  route list in the same push that builds it.
- A new portal page joins Page availability in the same push that builds it
  (the user, 2026-11-21: "Every new pages added should also go into the
  availability section"): its key taken by `page_set`, the page loading
  `js/maintenance.js`, its row in `#pgSheet`.
- A new state (a second row, a file, an error) is seeded in the walk, because a
  pane that walks empty is a pane nobody has measured.
- The deploy is confirmed from the GitHub Pages workflow run for the merge
  commit (`pages build and deployment`, success). A deploy GitHub cancelled on its
  timeout is never re-run (the re-run reuses the cancelled deployment): the
  next commit on main deploys the site whole. `curl` to the site returns
  403 from the sandbox and proves nothing.
- Assert the mechanism, not the sentence: measure geometry. Never read a value
  out of markup or a comment.
- Assert that withheld data is absent from the function's payload. Never assert
  a value you believe correct.
- A link handed out for one step of a record ends when the record moves
  past that step, and a suite seeds the link still open at that move
  (2026-10-20: an approved supplier's details form stood open).
- A control hidden, a message moved or words taken off a row is first
  grepped by its id or words across the suites and `GUIDES`, and each suite that reads
  it is changed in the same push (2026-10-21: six pressed a Publish #691
  hid, myhr read a line #693 moved, uxaudit a month #693 took off a row).
- Before a push, every word the diff puts in front of a person is drafted
  and checked by DESIGN.md §6, How copy is drafted, and `tests/words.js`
  passes (a word the user rejects is added to it in the same push); copy is
  never left for the user to review (2026-10-29). Before the merge, those
  words are read by a second reader: the `/copy-review` skill lists them
  (`tests/copyscan.js`) and hands them, with §6 alone, to a fresh agent
  that did not build the change; every finding is fixed or answered, and
  the PR's Test plan names the review (2026-11-04, the user: "every new
  build didnt follow your tone etc. rules"). A line two screens say lives
  once in `ADspaceWords.line` (`js/words.js`); `tests/words.js` fails a
  script that types one, and its PATTERNS stop kinds of wording (a system
  word, a refusal that is no instruction, a tab named wrongly), not only
  phrases already met.
- A word table holds one key a word: a new field's label takes a key of
  its own, grepped in the table first (2026-10-29: /quote/'s Planned
  commencement took `start`, and the opening page's Start button read it).
- A function's name is declared once in its script: a second declaration
  of the same name replaces the first for every caller (2026-11-09 form.js's
  `shape`, 2026-11-10 campaigns.js's `money`); `tests/jsdupes.js` holds it.
- A function removed is first grepped by name across the suites with no
  cap on the output: a suite that cuts a script at `'  function name('`
  uses it (2026-10-19: `smsql` cut `periodWord` at `mix`).

## 2. Load-bearing invariants

Each line is a rule that broke once. Its reason is in the archive.

### Pages, chrome, boot
- `js/chrome.js` is the only header and footer.
  - The mark comes from `brandLogo`, the kicker from `data-kicker`, the actions
    from `data-actions` (`lang`, `qr`, `push`).
  - Footer: left `© {year} ADSPACE PLT. All Rights Reserved.`; right `Terms of
    Service` → https://adspacestudios.com/legal/policies.
  - The footer is drawn with the header and sits last from the first paint
    (`.portalfoot { order: 1 }`). It moves to the end of body once the page is
    parsed. It is hidden while it precedes an open console.
  - A client page's bar reads left to right bell, sign out, 中文 (the page's
    own controls go in just before `#langToggle`), all one tonal family of
    one height and corner. On a phone the name the page is for takes two
    lines, its label over it (`.brand-for-label`).
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
- `loadMe` asks `me()`, the business figures, the system accounts, the VIC
  clients and the departments at once, never one after another
  (2026-10-26); a `me()` asked again after a session refresh asks the VIC
  clients and departments again under it.
- The console boots as `.console.is-booting`: its own shell and rail with the
  contents hidden and a skeleton (`#consoleBoot`) until `me()` answers.
  `applyAccess()` removes it. A refused team row goes to Access denied; a
  `me()` that errors is asked again once after `refreshSession()`, and an
  error still standing reads Unable to load with Try again, never a console
  drawn with no access read. Never draw the client pages' bar in its place.
- `/` is the front door and the host's one listed page, a visitor card after
  Apple's visitor centre page (`body.lp`):
  - one centred column (`--lp-col` 980px, 560 at 900 and under; `--lp-gut`
    24px) holds the content but the photograph: the name, the ticks, the
    hours and address, so the content has one left and one right edge at
    every width (`tests/seo.js` asserts the markup; the edges are measured
    by hand at 390, 768, 1045, 1280, 1440); the bar and the foot run to the
    screen's edges as on every page (the mark 24px from the left);
  - the chrome header and footer, the kicker reading Creative Advertising
    Agency on `/` alone (16px/400, 14 on a phone, kept on a phone); no menu,
    no sign-in, no list of rooms;
  - the name centred: `h1.lp-title` ADspace in Optima (`ADspace Optima`,
    `css/OPTIMA.TTF` after `local('Optima')`, never preloaded: it swaps in), over the tagline
    `advertising | marketing | branding` in Slate Regular (`.lp-tagline`);
    never an opening status (a studio, not a shop). ADspace alone, never
    "ADspace Studio";
  - the website's ways in as ticks: Home, About us (`/about`), Our services
    (`/services`), Our works (`/project`), Contact us (`/contact`) on
    adspacestudios.com, five across the column with the first at its left
    edge, the last at its right and equal gaps (`max-content` tracks,
    `space-between`); the ticks in the brand's monochrome (`--fill` with an
    `--on-fill` tick);
  - one photograph, whole at 16:9 and full width up to 1920
    (`img/front-door-{800,1200,2000,2560}`, WebP with a JPEG fallback, each
    URL stamped `?v=` so a replaced photo is fetched again), which is also the
    og:image; it offers no drag, right-click menu or iPhone Save to Photos
    (a screenshot cannot be stopped);
  - above 900: the name, the ticks, the photograph; at 900 and under (the
    ticks as a list): the name, the photograph, the list
    (`.lp-band, .lp-duo { order: 1 }`), the markup keeping the desk's order;
  - Service hours: a dated week from today in Malaysia time, Monday to
    Friday 10:00 to 18:00, redrawn every minute and on return to the tab,
    the page's own and never the team's Working hours setting (the user,
    2026-11-20: "keep the website front page same");
    a public holiday on the list reads Closed with its name under the date
    (`public_holidays_between`, read once a visit, a fortnight ahead; a
    failed read leaves the hours);
  - Visit: the address and Get directions (the Google Maps listing);
  - How can we help?: one sentence, then Chat on WhatsApp opening
    `wa.me/adspace` (the blue one); a tonal `.btn-sm` Chat on WhatsApp
    under the tagline puts it in the first screen (2026-10-15); the number
    is never on the page or in its business details;
  - the head: the title and descriptions name ADspace as adspacestudios.com
    does (Digital Marketing Agency in Johor Bahru & Singapore), Open Graph
    and a large-image card, and one JSON-LD graph (the Organization, the
    ProfessionalService office with its hours and address, the WebSite);
  - white to the edge (`--card`, `theme-color #ffffff`, `color-scheme: light`).
- The favicon on every portal page is the ADspace wordmark in Optima on white
  (never the monogram): `/favicon.ico` (16, 32, 48), `img/favicon-{48,96,192}.png`,
  `img/apple-touch-icon.png` and `img/icon-512.png`. A link sent to a
  client or a creator (`review/`, `creators/`, `creator/`, `script/`,
  `client/`, `verify/`, `quote/`, `details/`, `supplier/`, `careers/`) names no share image, so WhatsApp reads it as its
  title and address as it does a Google Drive link (`twitter:card` summary;
  the user, 2026-10-12, `tests/seo.js`); the console and the namecard keep
  `img/share-1200.png` (1200×630, `summary_large_image`): the wordmark in
  Optima over Digital Portal in Slate Regular, on white. No icon
  hangs on the CDN.
- Only `/` may be listed: every other page carries noindex, `robots.txt`
  disallows nothing (a blocked page's noindex cannot be read), and
  `sitemap.xml` names `/` alone (`tests/seo.js`).
- `404.html` is the portal's cover:
  - English only, white, title 17px, line 14px;
  - Client sign-in (`/client/`, the one blue), Visit website and Contact
    support as `.btn-sm`, Client sign-in taking its own row on a phone
    (2026-10-15); the portal's foot as static markup;
  - no `noscript` redirect.
  - The front door and the 404 are in the uxaudit walk.
- One `.cover` for every full-page state (no link, bad link, access code,
  closed, confirmed, nothing to review, access denied, the console's
  sign-in, a quotation waiting for the team), with the same words on
  every client page (`js/words.js`). Where the browser holds a sign-in (the console, the
  client portal), every cover ends Reference {code}, the sign-in's code as a
  colleague's Devices block cuts it (`ADspaceAPI.sessionCode()`: the access
  token's `session_id` claim, no request; `sessionShort`, the one cut, Devices
  too), drawn by one watcher in `js/maintenance.js`; signed out, no line;
  never the token (`tests/covers.js`).
- The console's sign-in page and every cover are white to the edge
  (`body.is-plain`); the grey frame is the signed-in console's alone (the
  user, 2026-11-13: "fully white would be ok"). Client pages stay as they
  are, never v3 (the user, 2026-11-13).
- Malaysia's clock (`js/chrome.js`, 2026-10-12; the user: "this entire
  portal should follow the timezone of malaysia"): a device whose clock is
  not GMT+8 (Malaysia and Singapore share it) is told on every page that
  loads `chrome.js`, under its bar (`#tzBar`, `.tzbar`, the warn ground led
  by the amber dot; in the console's column, edge to edge under a client
  page's bar): Time zone difference detected: this device is on GMT+9
  (Asia/Tokyo). The portal follows Malaysia time (GMT+8)., in Chinese after
  the 中文 switch; its × hides it for the visit (`adspace-tz-hide`). An
  automated browser is not told unless it sets `window.__tzBar`
  (`tests/tzbar.js`).
- Every page carries `viewport-fit=cover`. Sheets, feet, the confirm bar, the
  console body and the rail pad by `env(safe-area-inset-*)`.
- On iOS alone, `js/chrome.js` adds `maximum-scale=1` (stops the focus zoom,
  keeps pinch).
  - Never on Android.
  - Never `user-scalable=no`.
- Under a coarse pointer `.console-head` takes `--chrome-solid` with no
  backdrop filter, because Safari colours the status bar from an opaque bar.
  A client page's `.topbar` is opaque there too (`--chrome-solid`;
  its glass, kept 2026-10-10, read grey behind the status bar on 2026-11-14),
  the root painted `--card` so the status bar takes white, never the grey page. The console's root
  is painted `--chrome-solid` under a finger too: WebKit colours the status
  bar from the root's background, never the head (2026-11-14). The `theme-color` meta follows the console's own theme (the head script
  and `wearTheme()`); client pages are white.
- The bar is two families: the console's `.console-head` (`css/console.css`)
  and every client page's `.topbar` (`js/chrome.js`, `css/portal.css`), one
  height, `--head-h` (64 at a desk, 56 on a phone), the console's signed-in
  head too; no page sets its own (the user, 2026-11-21); a
  change to one is checked on the other in the same push (2026-11-14: the
  status bar fixed on the console reached the client pages a release later).
- The console is a PWA:
  - `admin/manifest.webmanifest`, with scope and start `/admin/`;
  - wordmark icons in `admin/icons/`.
  - iOS draws a launch picture before the page's first byte
    (`apple-touch-startup-image`, `admin/launch/`): the wordmark over
    Digital Portal on white or the dark ground, one a device size and
    orientation, dark lines first; a size with no exact match is a blank
    screen, so a new device is added through `tests/launch-build.js`
    (`tests/launch.js`). iOS takes it when the app is added to the Home
    Screen.
- The phone tab bar (`#tabBar`, js/admin.js; the user, 2026-10-09): on a
  touch screen narrower than a desk (a foldable open or shut, a tablet
  upright) and on any window at 640 and under, the one media query
  `ADSPACE_TABBAR` (the head script, which sets `:root.has-tabbar` before
  first paint) puts the first four sections the person may open, in the
  rail's order, at the foot with More (`#tabMore`) opening the rest above
  it; five or fewer take the bar whole. More lists only what the bar does
  not (`.is-tabbed`), then the rail's foot: one line of the build at the
  left, then Settings' mark and the Activity record's at the right edge
  (each named for a screen reader and on hover); at a desk the rail is
  212px and its marks take a row of their own on the sections' left edge,
  the build under them (the user, 2026-11-13: "the left panel could width
  could be smaller") (the user, 2026-10-10: "activity log can go inline with version
  code", "just activity record icons would do"; 2026-10-11: "the settings
  button to fit beside activity record as just icons same as it", "the
  rearrange tabs also next to settings"), Arrange sections' mark first. The menu toggle gives way to it; the drawer stays for a narrow desk window.
  What pops up (a docked card, a ⋯ menu, More, the confirm bar) keeps above
  it through `--tabbar-space`; every panel (a sheet, a question, search,
  the task, the finder) is a card above it inside the gutters with the
  large corner, the bar in sight under its scrim and out of reach
  (`--sheet-floor`, `--sheet-top`; the user, 2026-10-11: "every panel
  opens a card above the bar on mobile"); a field taking the
  keyboard under a finger hides it (`is-typing`), never a select, date or
  time, which opens the system's picker (a card that moved under it jumped
  back under the finger; 2026-10-15). It floats (the user,
  2026-10-11, after Instagram's): a glass pill 10px above the home bar
  inside the gutters. The chosen tab is one fill (`.tabbar-thumb`) that
  slides to it and follows a finger dragged along the bar, letting go
  on a tab opening it ("allow the selected … button to slide around left
  right"); a section More holds chooses More. The Dashboard carries a red
  dot while Waiting for you holds anything (`ADspaceAdmin.waiting(n)`, from
  `paintWaiting`; read once on sign-in, the rail's Dashboard row counting
  it too; 2026-11-13), never a profile
  photo tab (`tests/tabbar.js`, `tests/waiting.js`). It sits low, 14px
  less than the home bar's inset above the edge (`--tabbar-bottom`; the
  user: "can go abit down"), and scrolling down draws it in to its glyphs
  (`.tabbar-min`: 54px, 56px a tab), scrolling up, the page's top, More or
  a press bringing the words back; the room the page keeps clear never
  changes. Where a phone's page stands upright and narrower than its
  screen (the iPhone Duo's front screen, Safari's controls in a column at
  its right; `ADSPACE_TABSIDE` in the head script, `:root.tabbar-side`,
  measured on the layout's width and never while pinched in),
  the bar stands upright at the right edge, its tabs glyphs alone named for
  a screen reader, the page keeping its column clear (`--tabbar-room`),
  More and every panel opening beside it, never drawn in, a finger drawn
  down it as along it (the user, 2026-10-27: "at the right as portrait
  tabs", "just the glyphs icons"; `tests/tabbar.js`). My Work held half a
  second opens My Work with Add task (`ADspaceOps.add`, My Work at Work;
  the user, 2026-10-11); a shorter press is a tap.
- Arrange sections (`2026-10-10-rail-order.sql`; the user, 2026-10-10:
  "mobile tab and web … both sync edits"): one order a colleague for the
  web rail and the phone tab bar alike. `#railEdit`, a mark at the rail's
  foot before Settings' (drawn with three sections or more; 2026-10-11, the
  user: "the rearrange tabs also next to settings") opens
  `#railSheet`: the rail's groups (Work, Internal) as lists, a section
  dragged by its grip or moved with the arrow keys on it within its group,
  the Dashboard fixed first; under the bar the rows it will hold read Tab
  bar; Reset order puts the standard back in the sheet; Save keeps it
  (`rail_order_set(p_sections)`, known keys once each, `bad-order`; empty
  is the standard). `rail_orders` has RLS on, no policy, no grant;
  `rail_order_mine()` is read once `me()` answers, a copy in this browser
  (`adspace-rail:{id}`) for the first paint. The page reorders the rail's
  own items (`applyRail`), so the bar, which takes the rail's first
  sections, follows. A section not named comes after in the standard
  order. The Activity record's Section select, the Team panel and search
  keep the standard order. Not filed in the Activity record.
- Settings (`?s=settings`, `js/settings.js`, 2026-10-10; the user,
  2026-10-09: the account menu grew long and AI usage hid under Reports):
  a mark at the rail's foot beside the Activity record's (`#settingsOpen`,
  the gear, `is-on` while the page is open; 2026-10-11), offered to
  a colleague holding any of `team.upgrade`, `team.announce`,
  `team.notice`, `team.settings`, `reports.ai`, `register.types`,
  `ops.numbering`, `ops.workflows`, `team.performance` (View), or Suppliers, WhatsApp or Services at
  Full Access (2026-10-22, SET2-11; 2026-10-29); its address falls back for anyone else. Ten groups
  (2026-10-11, the queue's task 46; regrouped 2026-11-10, the overnight
  review, after Apple's System Settings), each led by a rail glyph and its
  rows in inset cards of five at most under short headings: Portal (Pages
  and notices: Page availability, Announcements, Notices, Demo access;
  Portal switches: AI, Email, WhatsApp (`portal_switch_set`, `team.settings`),
  User groups (an admin's, opening Team's Groups; 2026-11-17);
  Company: Public holidays, Departments, AutoCount HRMS, Working hours, Overseas approval, Signed-in devices, Health check-ins, Health data
  kept), Clients (Clients: Industries, Follow-up limits, Details forms: a
  client's and a supplier's link alike, Analytics; Creators: Creator and
  campaign IDs, Creator payments, Creator payments sheet), My Work (Due
  dates, Priority deadlines, Task reminders, Delivery targets, Task numbering), Reports (Meta
  checks, Posts linked to tasks, Reach allowance, Ad benchmarks), Accounting (Tax
  and terms, Tax codes, Bukku), AI (AI usage and limits, AI prices),
  Messages (Email: Automatic emails, Send by email, Email templates, Sent
  again: WhatsApp and emails; WhatsApp: Automatic WhatsApp, WhatsApp
  templates at WhatsApp Full Access, Meeting
  message, Website quotations: how many a day are told on WhatsApp),
  Performance (Months, Quarters, Bonus and trip, Commission at
  `team.performance` View, behind the master code; 2026-10-29), Hiring
  (Candidates: Time limits at `team.settings`, Interview scorecards at
  `team.hiring`, its row the Standard's criteria and how many positions hold
  their own, Standard: 5 criteria · 1 position with its own; New colleagues:
  Welcome Kit; 2026-11-17), Templates
  (Document types, Task templates at `ops.workflows`, Rate card wording at
  Services Full Access). Email templates (`js/mailtpl.js`,
  `ADspaceMailTpl.open`, at `team.settings` or Suppliers Full Access; a
  supplier's every template, fixed or New email's, at either, a client's and
  a creator's at `team.settings` alone: `email_template_may`, 2026-11-10) lists
  every email by recipient (Clients: Quotation, Letter of Offer, Client
  letter, Overdue reminder, Invoice email and New email's own; Suppliers:
  Supplier approved, Document and New email's own; Creators: the six
  creator emails; Candidates: the eleven candidate emails, each with its own
  switch (`hiring_email_templates`, 2026-11-21); Sign-in and codes: Verification code, the one email every
  code the portal sends goes out in (`code_email_template`, its fields
  {name}, {code}, {minutes}, {purpose}, {code} never in the subject,
  `code_email_template_save` at `team.settings`, read by `quote-request` and `hiring-mail`
  through `_shared/mail.ts` `codeEmail`; 2026-11-17, SEAL-SPEC decision 9),
  and Supabase's Sign-in code and Invitation listed with no Edit), each saved through its own function, and one editor
  (`#mtEdSheet`): the words at the left, the email as it reads at the right
  (stacked under 720), the sender's fields from `template_fields_all()` as
  chips inserting at the caret, a field it cannot fill marked as it is
  typed; no test email (Send test to me removed, the user, 2026-11-10;
  `2026-11-10-template-test-email-removed.sql`). A row carries what a press opens (`open`); a switch acts at the
  press with Undo under its own row (Turned on. / Turned off.; the user, 2026-11-13). A search heads the group list (a
  phone's page), finding a row by its name, group or value across every
  group and opening its group on its control (Enter takes the first);
  each setting has this one place: no Tax and terms
  on the Services bar, no Templates, Task numbering or Due dates in My
  Work's ⋯, no Document types on Documents, no Templates tab in WhatsApp,
  no Wording tab in Services; a group with
  no row drawn is left out. One group at a time (the user, 2026-10-24:
  "the business settings are getting longer … categorize or structure it
  into a proper settings page"): at a desk the groups run down the left,
  a press showing that group's card alone under its heading, the page at
  its top; at 640 and under the groups are the view strip (`#stgStrip`,
  `.actstrip.stg-strip`), sticky under the head, a press or a sideways
  swipe on the group (`data-swipe`) showing the next; the group shown is
  in the address (`tab=`, the first left out; replaced, never pushed), so
  a refresh lands on it. Still one press from Settings to a row and one to
  its sheet, never a drill-down (refused 2026-10-11: "It now takes five
  layers"); with fewer than three groups every group shows. Each row drawn only for its
  part, its value under its name, a switch, Edit or Open at the right edge
  opening the one sheet that already edits it; a figure changed from a
  later day reads `From 14 Nov 2026: SST 6%` under the value
  (`ADspaceMoney.next`), and a press answers on its own row (`.stg-said`),
  never on a line out of view (2026-10-14, ux-audit SET-1, SET-2). An Open
  row states what it holds (Team n live · Clients n live, Last sent, Next
  #WT…, Used today n of N, n of N on, n types offered), each from its
  section's own read once a visit, filled in place and read again when
  its sheet hands focus back (asked a tick later, so a sheet swapping for
  another is read once both shut; 2026-10-27, SET-2); a value line is a value, never a sentence
  (SET-6, SET-7). The list of groups is drawn only with three groups or
  more (SET-5). The
  account menu reads, in compact rows at a desk (a control's height; 48px
  docked on a phone): who you are; You (My records, My namecard);
  This device
  (Theme, Passkeys, Notifications); Sign out. The Reports bar
  holds no AI usage (`tests/adminparts.js`, `tests/run.js`).
- `admin/sw.js` keeps `offline.html` and the wordmark for a page load that
  failed, and every same-origin file whose address carries `?v=`
  (`adspace-console-assets`), answered from the store first, one copy a
  file, the copy under an older stamp let go when the new one is stored
  (2026-10-26: a reopen after ten minutes asked the server about 69 files).
  The page itself always goes to the network (navigation preload on), and
  an unstamped file is never kept: a changed file without a new stamp would
  be served stale, so the `?v=` bump below is load bearing. It also holds a
  PDF the console drew, for an hour, at `/admin/file/` (`js/file-sw.js`,
  `adspace-files`; see `ADspaceDocs.save`). `client/sw.js` holds that
  alone, at `/client/file/`, registered by `js/portal.js`. A failed
  registration is silent.
- The rail's foot names the build with Settings' and the Activity record's marks (`#appVersion`,
  `.appver`, 11px mute): `{YYMMDD}.{commit}`, the deploy's day in
  Malaysia and the merge commit's last four characters as one token
  (`261006.b43a`; the user, 2026-10-06: short, but which build; 2026-11-17:
  shorter), read from
  `/version.json` (its name and hover hold all seven characters), which the Pages build writes through Jekyll
  (`site.github.build_revision`, `site.time`); never typed by hand. Read raw
  (no build) or missing, the line is hidden (`tests/appver.js`). The line is
  Refresh app (the user, 2026-10-12): a button drawn as its words (no box,
  no underline, the mute ink, the soft ink on hover), the line's height its
  target, named `Refresh app, {build}` for a screen reader and on hover; the
  account menu holds no Refresh app.
- Refresh app (the build line):
  - it unregisters the console's own worker (`/admin/`) and empties its own
    caches (`adspace-console-*`, and `/admin/file/` in `adspace-files`),
    never the creator's, the selection page's or the client portal's
    (audit F7, 2026-10-10);
  - it never touches localStorage, IndexedDB or the sign-in;
  - notifications survive it: the next load subscribes again without asking
    (`ADspacePush.heal`, off the `adspace-push:{scope}` flag).
- The latest build (`2026-11-17-latest-build.sql`; the user, 2026-11-17:
  "ok build it", everyone on the same merged build): each minute the
  console's check runs (`often`'s `each`) it reads `/version.json` from
  Pages (no metered line); a build newer than the page's draws `#buildBar`
  (laid as `.upgradebar`: A new version is available., Refresh) and never
  refreshes by itself (review 2026-11-17: an unsaved commentary was lost to
  it). Settings, Portal:
  Require latest version (`team.upgrade`) stores the live build
  (`build_require(p_commit, p_built)`, `app_flags` `build:min`, `bad-build`
  for a build time ahead of now,
  filed `team.changed` under Portal from and to, Undo putting the one before
  back); `page_pulse` answers it to the console as `build`, its commit
  and time alone, never who set it, and a console below it, on screen,
  refreshes within the minute once idle, once for each build required
  (`adspace-build-for`; still below it after, it waits for Refresh now),
  its bar reading Refresh now. Idle: nothing open over the page (a sheet, question, menu, popover,
  finder, guide, bulk bar), no field holding the caret, no request out
  (`ADspaceAPI.loading.busy`), and no page's own `beforeunload` guard
  objecting (asked with a probe event). A refresh is Refresh app's, at most
  once in three minutes a tab; raw, nothing happens; client pages are
  untouched (`tests/buildsync.js`).
- Pull to refresh works only in the installed app, and only on a list with no
  record, sheet or menu open.
- Page availability (`js/maintenance.js`, `2026-10-29-page-availability.sql`;
  Upgrade mode a page at a time since 2026-10-29, the user: "Upgrade for
  /client page, Temporarily Unavailable for /admin, or selectively") is a
  cover, never a lock: the database keeps answering, but the quotation
  website covered makes nothing (`quote_website_create` `unavailable`).
  - A row of `app_flags` a page (`page:{key}`: admin, client, review,
    script, details, creators, creator, quote, supplier, verify, careers, and the system pages home, notfound, card; RLS on, no
    policy, no grant), its `kind` (`upgrade` Upgrade in progress, `paused`
    Temporarily unavailable), window, note, Chinese note and whether its
    cover offers Chat on WhatsApp. `page_states()` (anon) answers every page
    set, the console's notes (English and 中文) to the team alone; `page_set(p_pages, p_kind,
    p_note, p_note_zh, p_starts, p_ends, p_whatsapp)` (`team.upgrade`;
    `bad-page`, `bad-kind`, `bad-window`) sets several at once, filed
    `team.changed` under Portal ("Page availability: Client portal: Available
    → Temporarily unavailable · until … · note", Malaysia time);
    `page_states_all()` reads them for Settings. `maintenance_state` and
    `maintenance_set`, for a page served before, read and set every page.
  - Every portal page loads it (after `api.js`; `/` and the 404, which hold
    no database library, ask `page_states` by `fetch`), the system pages
    included (`home` the front door, `notfound` the 404 by its tag's
    `data-page`, `card` namecards; EVERY PAGE AVAILABLE, 2026-11-21, the
    user: "makes all pages up, including the main page"); a page reads its
    own row by its address. Short links (the Worker) are not a page. A
    client page covers itself under its own bar (`.maint-cover`, z-index 39;
    the rest `inert`): Upgrade in progress / 系统升级中 (`W.maintTitle`;
    `maintText` The portal will be available again shortly. / 系统将稍后恢复使用。;
    `maintBack` The portal will be available again by, then on its own line
    20 Nov 2026 (Friday), 12:30pm. / 系统将于以下时间前恢复使用：, then the date), or Temporarily unavailable / 暂时无法使用
    (`W.pausedTitle`, `pausedText`, Chat on WhatsApp where set), its note in
    the page's language, following the 中文 switch. A quotation link already
    sent (`/quote/?q=`) keeps opening while the website is only paused. Every
    open page, the console included, asks again every minute while on screen
    and on every return (`ADspaceMaintenance.often`), and at a set start or
    end: covered, it covers itself; uncovered, a covered page reloads (to its
    latest version). A read that fails (`ask(true)` answers null) changes
    nothing.
  - An open page's minute is one request (`page_pulse(p_audience, p_bell)`,
    `2026-10-09-one-check-a-minute.sql`, anon too): upgrade mode, the
    announcements and the bell, each as its own function answers it; a part
    joins with `often(key, take, alone, opts)`, and on a database without the
    function every part asks alone (every request is a line Supabase logs and
    meters; `tests/upgrade.js`, `tests/smsql.js` §9ze); to the console it
    also answers the build required (`build`).
  - The console's row covers it for anybody but an admin (the whole screen,
    with Sign out); an admin works on under `.upgradebar` (led by the amber
    dot, Console: Upgrade in progress until …, Turn off ending the
    console's alone). Settings, Portal: Page availability (`team.upgrade`,
    All pages available or n pages unavailable) opens `#pgSheet`: the pages
    by group (Team, Clients, Creators, Public with the Candidate page), then
    System pages (Front page, Page not found, Namecards) under their own
    heading, whose tick chooses the three while Select all never does; each one line at a desk (the
    name and its address, the state and when, the pen; on a phone the name
    over its address, the state over when, the pen beside), revamp D,
    2026-11-04; Select ticks several (a press on a row, or the tick for all), Set availability asking once for all. The
    question asks Availability (a segment), Starts, Ends (each a date beside
    its time, MYT; empty start is now, empty end waits, a time with no date
    is today's), a note, a 中文 note and Show Chat on WhatsApp (not the
    console's), saying under the choice what it does to that page, refusing
    in the sheet a window that does not end after its start and now; Undo
    puts each page back. It opens on Upgrading, never Available, unless the
    pages chosen share a set state (that state, their window kept where it
    is one; where their times or notes differ, the fields open empty over
    a mute line saying so, and each page keeps its own of every field left
    empty, only what is typed laid over all, `tests/upgrade.js`); Available lays the window and notes aside (the state chosen
    again brings them back), and a window typed under Available is refused
    (Choose Upgrading or Unavailable to set a start, an end or a note.; the user, 2026-11-20).
    Every date and time field is one height (`--ctl-h`, the small one
    `--ctl-h-sm`), never a floor, so a pair's labels share one line.
- Announcements (`js/announce.js`, `2026-10-07-announcements.sql`,
  `2026-10-07-announcements-several.sql`): one bar under the top bar, the
  team's on the console (laid like `.upgradebar`) and the clients' on every
  client page that loads `maintenance.js` (edge to edge under its bar)
  (`announcements`, RLS on, no policy, no grant). Several may be live for
  each audience (the user, 2026-10-07: "i want multiples for internal and
  also clients"): `announcement_now(audience)` answers every live one as a
  list (started or no start, its end ahead or none, not ended; Important
  first, then the newest, ten at most), the clients' to anyone and the
  team's to the team, never who wrote it; asked on load (the console once
  `me()` answers), every minute while on screen and on return. They share
  the one bar, never stacked: a slide each, with ‹ n/N › once there are two
  (the arrows and a swipe, round from the last to the first), the bar as
  tall as its longest line so moving along never moves the page. Info is
  the tonal ground, Important the same led by the amber dot; the words
  follow the page's language (中文 where given); an https link opens in a
  new tab; the reader's × hides the one on show in this browser
  (`adspace-ann-hide:{id}:{updated_at}`, so an edit returns it). Team:
  Announcements (`team.announce`, granted) on the Settings page opens the
  list (`#annSheet`: Team and Clients, each every line, live with Edit /
  Stop, which asks, stopped or ended with Restore (never asks, while its end
  is ahead) and Delete, and New): `announcement_save` (an ADspaceConfirm
  sheet: Tone, English, 中文 (a team's asks one Message: the console is
  English alone; the user, 2026-10-11), Link, Starts and Ends as a date
  beside its time, MYT; posting one adds it, never ending another),
  `announcement_end(id, on)` and `announcement_delete(id)` (asked first, no
  restore; refused `live` until stopped or ended; a row's own act is Edit,
  else Restore, its ⋯ Stop, or Delete last once stopped or ended); each filed `team.changed`
  under subject Announcements. A plain line, never a scrolling marquee. No
  bar is made while upgrade mode's cover is up (a box made after the cover
  would sit outside its `inert`).
- Notices (`js/notice.js`, `2026-10-09-team-notices.sql`; the user,
  2026-10-09: "send custom in-app notifications to all members, or to
  specific team member(s)"): Team: Notices (`team.notice`) on the Settings
  page opens the list (`#ntcSheet`: every notice sent, newest first, To,
  when, by whom, Read by n of N, Withdraw (asked: it leaves every bell; a
  push already on a phone stays) and Restore (never asks), and once
  withdrawn the row's ⋯ Delete (asked, no restore; `team_notice_delete`,
  refused `live` until withdrawn, the notice and every copy;
  `2026-10-10-notice-delete.sql`, run in the SQL Editor)) and New
  (`#ntcNewSheet`: Send to All colleagues / Selected colleagues, the
  colleagues ticked code first, Title (one line, 120) and Message (1,000),
  the count beside Send). `team_notice_send(p_title, p_body, p_to)` writes
  one `ops_notifications` row (kind `notice`, `notice_id`, `from_name`) to
  each active colleague but the sender (`bad-title`,
  `bad-body`, `no-one`; ten a sender in any hour, `too-many` with when the
  next can go, `2026-10-18-ten-notices-an-hour.sql`), so it reaches the bell
  and a push;
  `team_notices_list()` and `team_notice_withdraw(p_id, p_restore)`
  (`hidden_at` on every copy). `team_notices` has RLS on, no policy, no
  grant. Each is filed `team.changed` under subject Notices.

- Public holidays (`2026-10-14-public-holidays.sql`; the user, 2026-10-14:
  "prefill and let manually change and apply to my work"): the days the
  office is closed, `public_holidays` (day, name; RLS on, no policy, no
  grant), seeded once into an empty table with Johor's 2026 and 2027.
  Settings' Portal group, Public holidays (`team.settings`): the next one
  under the name; Open lists a year at a time (`#holSheet`, Year as a
  segment) as Industries' table (Date · Holiday · the pen; revamp A,
  2026-11-04): the pen opens its row as the date and name fields (Enter
  saves, Escape leaves), the last row adds one
  (`public_holiday_save(p_day, p_name, p_was)`: `taken` naming the holiday,
  `bad-name`, `bad-day`), Delete in the open row (`public_holiday_delete`,
  asked, no restore); each filed `team.changed` under Public holidays, from and
  to. `public_holidays_between(p_from, p_to)` (anon, 800 days at most) is
  the one read: the front door, Settings (this year and the next) and My
  Work (once a visit) ask it. My Work's calendar names a holiday on its
  day (`.cal-hol`, the day shaded; on a phone a holiday shows in a month
  with no tasks), and a My Work date set on one is told so under its field
  (`.hol-note`, "8 Nov 2026 is a public holiday: Deepavali."); the noon
  reminder and the task reminders skip a holiday (their cron commands ask
  `public_holiday_on`). Due dates are not moved.

### One copy of each mechanism
- `js/api.js` is the only Supabase client. Demo content is only for a copy
  with no database configured: a configured page whose database library
  failed to load reads Unable to load and records nothing, and a review
  decision is shown only on the database's own `ok` (audit F5, 2026-10-10). It retries a GET once when the
  connection drops before the answer (`steadyFetch`); a write is never sent
  twice. Every request it sends is counted: one out `showAfter` (300ms)
  draws the loading line (`.loadbar`, appended inside its host on each
  request so whatever is laid over the host draws over it, 2px under the page's own bar across
  its width, under an open sheet's head across its card while one is open; the minute's `page_pulse` never shows it) until the last
  answers; a read (GET) unanswered at `giveUpAfter` (20s) is given up,
  never tried again, so the page says it could not load with Try again; a
  write is never cut off; a skeleton past `slowAfter` (8s) reads Still
  loading… (`ADspaceState.stillLoading`), and a dropped connection reads
  `W.offline`, never the browser's words; the three from
  `ADSPACE_CONFIG.loading` (the user, 2026-11-10: "is it really loading?";
  `tests/loadbar.js`). Refresh app and pull to refresh turn their ring and
  run the line until the page reloads.
- `js/money.js` is the only money formatter and the only place a price is
  adjusted.
  - RM, or S$ for a Singapore client billed in S$ (`curOf(c)`: a payload's
    `bill_market`, else `market` SG with `bill_sgd`; the market alone never
    picks the currency); a Singapore client billed in RM reads its total's
    S$ beside it (`approx(n, c, at)`, ` (approx. S$ 952.38)` at `fx_sgd`).
  - SST at the rate in force on the document's own day (`taxOf(sub, m,
    applies, at)`, `taxLabel(m, at)`; a letter passes its `issued_at`, a
    campaign's booked creators the client's last confirmation (`kind`
    client), a selection still to confirm none)
    unless `sst_applies` is false.
  - Two decimals on every total, each charged figure (`rateFor`, `taxOf`)
    rounded by `cents()`, a half away from nought as Postgres rounds, the
    float nudged first (1,234.50 × 0.95 is 1,172.7749… in a float).
  - `TERMS` holds the older factor table (used when `term_pct` is null).
  - `ADspaceMoney.load()` reads the business figures once a page
    (`app_settings_read()`, anon too) and `setting(key, at)` answers them;
    the console waits for it beside `me()`, the client portal beside
    `get_portal`, the selection page beside `get_campaign`. `FIRST` is used
    only where the read fails, and is the one copy of a default (no page
    keeps its own); a failed read is not kept, so the next `load()` asks
    again. A figure is read at the day it applies to, as the database reads
    it (a report's deadline at its period's end).
- `js/menu.js` (`place`, `pop`, `onScroll`, `items`, `item`, `groupOf`,
  `tidy`) is the only copy of where a ⋯ or a popover card opens, and of
  what a ⋯ holds and in what order (DESIGN.md §5 Menus and action groups):
  every item carries its group (`data-g` 1 to 6; `groupOf(label)` is the
  one table of the standard's words, `item(a, label, need)` one item
  written from it), and `tidy` puts the items in group order, lays roles,
  separators and the red each time a menu shows; every ⋯ hangs from its
  button at every width, a record head's too (the user, 2026-10-24: the
  foot dock opened away from the finger). A new act's
  word joins `groupOf` and `tests/menus.js` together.
  - `pop(btn, card, align)` lays a popover card (`.popcard`: the bell's
    `#pushPop`, the section's `#sectionAbout`). It moves the card to body; at
    a desk it hangs from its control with a caret (`--caret`, `is-up`); under
    640 it docks at the foot of the screen inside the gutters and above the
    home bar (`is-dock`), rising from the floor.
  - Placed on the viewport; opens upward where the room is above.
  - Ignores the scroll that reveals its focused button (2px rule).
  - Follows its button on resize, and closes when the button leaves the page.
  - It is placed from where a fixed box beside it actually lands (a probe at
    0,0 in its own container), which covers a transformed sheet card and an
    iPhone after the date picker alike.
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
  - On a phone (≤640): a sheet is pulled down from its head (the grabber) to
    close, pressing its close mark (90px, or a flick); a form sheet (a foot
    with a filled action, fields) keeps a draft of the fields the person
    changed when it is left any way but its action (`sessionStorage`
    `adspace-draft:{sheet id}`, against the state it opened in, hidden
    fields included), restores it on the next open in that state with
    `.draftline` Draft restored · Discard, and so its scrim closes it even
    when touched. Pressing the action ends the draft. Files, passwords and
    `data-nodraft` fields are never kept. A desk keeps no drafts.
  - Focus is trapped, and handed back on close: to its opener where drawn,
    else to what held focus at the open (a `data-rare` button's ⋯; 2026-10-23).
  - `sheet(id, on, swap)` swaps two sheets in one frame (`.is-swap`).
  - Cmd/Ctrl + Enter presses, in order: the caret's small form, then the top
    form sheet's foot primary, then the pane form's primary.
    - Never a red, disabled or hidden button.
    - Never on a sheet with no foot.
    - Never while an input method is composing.
    - The primary carries `aria-keyshortcuts`.
  - A plain Enter presses the top sheet's foot primary too (the user,
    2026-10-11), from the card or a one-line field only: never from a
    search box (`type=search`, a combobox, `inputmode=search`,
    `data-noenter`), a box of lines, a button, a select, a segment or a
    switch, never inside a form that submits itself, never on the question
    sheet (it answers its own Enter) or with the finder open, never a red
    button. A sheet opened by `js/ops.js` holds its card, never its close
    mark (Enter there had shut the step sheet).
- `js/confirm.js` (`ADspaceConfirm.ask({title, body, go, tone, field|fields, match, cancel:false}, onYes)`)
  is every question with a consequence. **No `window.confirm`, `prompt` or
  `alert` anywhere.**
  - A field marked `half` sits beside the next one (a date and its time),
    `third` three across (a named section of three figures, `.is-third`);
    `head` opens a section with its heading (`.askhead`), and `note` is one
    mute line under the field (`.asknote`, its `aria-describedby`); a spec
    of `line` alone is one mute line the row's whole width (`.askrow`).
  - A field marked `tick` is a checkbox (`.tickline`, answering `on` or
    nothing, never required); a `choices` field marked `seg` is a segment.
    Focus lands on the first typed field, never a segment or a tick;
    `focus` names another, and under a finger it lands on the card.
  - A field asked for words (no `type`, no `rows`) is a one-line box
    (`data-oneline`); one whose `match` or seeded `value` is digits stays a
    field with the number keyboard. Enter answers from any field, never
    while an input method is composing (pinyin's Enter picks the word).
  - `check(values)` refuses in place what the fields cannot state alone (an
    end before its start): the sheet and what was typed stay.
  - `no` runs when the question is left unanswered (Cancel, the close
    mark, the scrim, Escape); a field marked `code` is an emailed code
    (the number keyboard, `one-time-code`).
  - A destructive question opens on Cancel; one that asks a name typed back
    opens on that field, where an empty Enter is refused.
  - `#askGo` and `#askCancel` are stable ids. `#askSheet` sits at z-index 95,
    above any sheet.
  - The way back (reinstate, set active, restore) never asks.
- `js/ask.js` asks for one value.
  - `rename(host, btn)` edits in place. The pen becomes the ink tick. Enter
    saves, Escape restores (before any sheet's Escape), an empty value keeps
    the field open, and blur neither saves nor discards. `type`/`value` are
    available for a date.
  - The field is the value itself: its own type and box height read from the
    value, one `.input.askfield` rule (tonal, no box line, no glyph, pulled
    back so the words keep their place; a date a date's width, `.is-date`).
    No screen sizes its own field. `tests/inplace.js` opens every one at a
    desk and under a finger.
  - `inline(btn)` grows the field out of the control.
  - `note(after)` is a textarea; `once` removes it with its answer, and the
    handle carries `box`.
  - `rename`'s `check(v)` refuses in place: the field stays open with what
    was typed and the refusal under it (`.askmsg`), as a sheet refuses
    (2026-10-20, TEAM-4); a number box holding what is no number is
    refused so (Enter a number.), never saved as nothing (2026-10-27,
    SVC-10).
  - There is no sheet in it.
- `js/decide.js` records a client decision.
  - The name grows out of Approve (`.namebox`), key `adspace_reviewer`.
  - While a name is held, the review and selection pages' name card ends in
    one line, Deciding as {name} · Change · Forget (`.decide-as`,
    `ADspaceDecide.whoLine`, words in `js/words.js`): Change edits it in
    place, Forget removes it from this device and the name field returns to
    a request. Decisions already made keep the name they were made under.
    The selection page's Confirm opens its name on it (2026-10-27, SEL-4).
  - Request changes steps aside while it asks (`.approve-row.is-asking`).
  - An open note box carries `.changebox-who`.
- `js/swipe.js` is the only swipe: on touch, a sideways swipe inside a
  `data-swipe` region presses the tab beside its strip's chosen one (nearest
  region wins). It is left alone within 24px of an edge, on a field, select,
  editable text, drag grip or `data-noswipe`, inside anything that scrolls
  sideways, with a ⋯ menu or the rail drawer open, over selected text, in a
  sheet without its own region, and unless plainly sideways (across 1.5 times
  the down), at least 56px or a fifth of the width, within 0.8s. A region may
  name a pair of buttons instead (`data-swipe-prev` / `data-swipe-next`, the
  Review Canvas): the finger moving left presses Next, a disabled one is left
  alone, and `data-swipe-media` lets a swipe start on a video above its
  controls.
- `js/chart.js` (`ADspaceChart.draw(host, spec)`) is the only chart, in the
  page's tokens: bars (label and figure over the bar, a mark for a limit),
  columns, a line (one of zeros is data, never No entries.; 2026-10-20), and a ring only for two to five parts of a whole (else
  bars), and a `meter` ring for one share of two parts (2026-10-12). Options:
  bars `inline` (label, bar and figure on one line; a row's `part` red at
  the bar's end), pie `total` (the whole in the middle) and status `tone`s
  on its slices, columns `labels` (the figure over each) and a category's
  `tone`; a row of columns or a line keeps every label its own width holds,
  else every second, else every third, counted back from the last, measured
  on the chart (`fitLabels`), never on the pane, so months never run
  together in a narrow card beside another (2026-10-27, the iPhone Duo). `ADspaceChart.spark(values, tone)` is a tile's trend, an image its
  words already state. The figures fold under every chart as a table; a
  column, a point and a slice give their figure on hover or a tap. No chart
  library.
- `js/media.js` (`ADspaceMedia.tag(url, attrs)`, `attach(video, url)`) is
  every video player: it names the H.264 copy `name.web.mp4` first (typed
  MP4) and the original after, so a browser plays the copy once it exists
  and the original until then. Never `<video src>` for an uploaded file.
  A thumbnail of a video is `ADspaceMedia.still(url)`, its first frame
  (`#t=0.1`; iPhone Safari draws a bare video blank until it plays): a
  console row, and the selection page's post rows (the user, 2026-10-10).
  It also holds the media pass (`ADspaceMedia.pass(proof)`, 2026-10-03):
  with `ADSPACE_CONFIG.s3.privateMedia` on, a page that has proved its link
  (`{review}`, `{campaign}` with the passcode), a creator's code
  (`{creator}`) or a sign-in (`{}`: a colleague, or a client contact with
  live portal access, the client portal asking before it draws; 2026-10-08)
  asks `media-pass` for CloudFront's three
  signed cookies before it draws a file, set on
  `mediaCookieDomain` (adspace.me) for twelve hours and asked again under two
  left (load, return to the tab). A pass is held to the folders its caller
  may see (audit F3, 2026-10-10): `passes`, one policy a folder, each set on
  that folder's own cookie path so the browser sends it there alone: the
  review link its client's `content/{clientId}/`, the selection link that and
  each booking's `content/creator/{optionId}/`, a creator their bookings'
  drafts alone, a client's contact each client they hold access at, a
  colleague the whole of `content/` (path `/content/`), only while
  `is_team()` answers for them as the caller (active is not enough: held
  overseas, or access passed before the expiry run; audit 2026-10-29). A client page's pass
  takes away a root pass left by an earlier page, and is fresh only for the
  proof it was asked with (`adspace-media-for`). Every pass keeps the folders
  it set (`adspace-media-paths`, this browser) and the next pass takes them
  away: CloudFront refuses a file sent two passes, which a client's link
  opened beside the console left (2026-10-12); a file refused on a folder
  another page left a pass on loads again once it is taken away
  (`ADspaceMedia.renew`). A colleague's pass is never taken away by a client
  page: a client page opened while a colleague's pass is live (the team
  previewing a link in the console's browser) sets no pass of its own and
  draws on the colleague's, and the console takes away every folder a client
  page left each time it asks, fresh or not (2026-10-15, the second outage:
  the fix of 2026-10-12 covered the client page first, never the console
  first; `tests/mediapass.js` holds both orders). Add assets' check that the CDN serves a stored
  file reads it with the pass, asked again once; with the pass on, a file
  S3 took is never refused by that check. An answer in the earlier
  shape (one pass over `content/`, no `passes`) is set on the root as before,
  so a page served before `media-pass` is deployed keeps its media. A file under `content/` that fails asks
  again once and reloads (a video at its second), the page's own `onerror`
  held until the answer; a `.web.mp4` copy not made yet never asks. Stored
  addresses never change. A refused or slow pass (6s) never holds a page.
  Signing out takes the pass with it (`ADspaceMedia.forget()`: the three
  cookies on the root, content/ and every remembered folder, and the
  pass's marks): the console's Sign out, which also removes the browser's
  `adspace-*-notes:`, `adspace-*-inputs:` and `adspace_drafts_` keys, the
  client portal's, and the creator's Forget this device (`{ client: true }`,
  leaving a colleague's live pass alone).
- `js/acts.js` (`ADspaceActs`) is the one table of act glyphs and the one
  pending state (the user, 2026-10-10): every console `.btn` whose words are
  an act carries its mark (Publish the plane, Unpublish the struck eye,
  Edit the pen, Download the file, Copy the copy mark, Preview and Preview
  PDF the leaving mark after the words, Add and New the plus, Issue Letter of Offer the letter, Invite and an email sent the envelope, Open in Bukku the leaving mark after, Open {a console page} and View the chevron after; a quiet button as a filled one), given as the
  button is drawn where a screen wrote words alone; a form's own commit
  stays words. A press whose write disables its button shows, after 150ms,
  a turning ring in the button's ink at the button's width until it is let
  go. A new act joins the table, never a screen (`tests/acts.js`).
- `js/clock.js` (`ADspaceClock`: `day`, `today`, `parts`, `start`, `at`,
  `time`, `addDays`, `addMonths`, `between`, `weekday`; the words `date`,
  `clock`, `month`, English and Chinese) is Malaysia's clock (2026-10-12),
  loaded by the console and every client page: every page reads a day, a
  month, a weekday, a time of day and "today" from it, never from a Date's
  own getters, `setHours`, `new Date(y, m, d)`, `toLocaleDateString`
  without the zone (each the device's zone) or `toISOString().slice(0,
  10)` (the UTC day, yesterday before 8am here). A day alone (`2026-10-12`)
  is that Malaysian day; a date and time with no zone (a date field and a
  time field) is Malaysian time; a stored day keeps its form
  (`YYYY-MM-DDT00:00:00Z`). A client page writes a time 10:00am, no
  space (`clock(v)`; 上午10:00 with `zh`). Days are counted on the calendar, never by a
  device's midnight. Left as they are: calendar arithmetic in UTC on day
  strings, the report PDF's days (`dateOf`: the Malaysian day held as a
  local midnight), and the spreadsheet and CSV importers' own date reading
  (the user, 2026-10-12: never touched). `tests/myclock.js` holds Tokyo and
  Los Angeles across a month's end.
- `js/otp.js` (`ADspaceOtp`) is the code from an email typed as a box a
  digit (the user, 2026-11-11): the console's sign-in (`#authCode`), the
  client portal's (`#signCode`) and My records' lock (`#mineCode`), each an
  `input[data-otp-boxes]` kept as the value and laid unseen over
  `ADSPACE_CONFIG.signCodeDigits` boxes (8, Supabase's Email OTP length), so
  a paste, the iPhone's code from Mail and a screen reader meet a plain
  field; a whole code arriving presses the field's Enter, which signs in.
- `ADspaceAPI.phoneWord` (`js/api.js`) is how every phone number reads,
  on every page (+60 12-345 6789, +60 7-123 4567, +65 8123 4567), whatever
  was typed (2026-11-18, the user: one portal showed 60167690532,
  0127106561 and +60 16-776 6878); a `tel:` link dials `+{waNumber}`. The
  stored value keeps what was typed; no page draws it raw (`tests/phones.js`).
- `ADspaceAPI.openStored(bucket, path, secs)` (`js/api.js`) is the one way
  a file kept in Supabase Storage opens: the tab at the press, a signed
  link, no opener, the tab shut on a refusal (the Handbook, a candidate's CV
  and documents, an HR document's sealed copy; 2026-11-19: Documents held a
  fourth copy, `tests/pwapdf.js`).
- `js/copy.js` says Copied one way. The fallback is `execCommand('copy')` over
  an off-screen textarea.
- `js/icons.js` (`ADspaceIcons.svg(name, cls)`, `platform(key)`,
  `journey(words, at)`) is the client pages' one icon set, the leaving mark
  (`out`, the drawing `js/acts.js` holds) and the chevron among them (outline glyphs at
  15px, stroke 1.8, in ink; never filled or coloured; a name it does not hold
  draws nothing) and the booking's one step track (`.cx-journey`), drawn
  alike on the selection page and the creator's page, its words `W.journey`
  in `js/words.js` (Booked, Shoot visit or Delivery, Draft due, Client
  review, Post date, Results; never a bare verb or a word that could read
  as one, the user, 2026-10-15), each breaking at its space, never cut.
- `js/grow.js` (`ADspaceGrow.fit(el)`) is the only way a typed box grows
  (the user, 2026-10-07: "Cell not increasing as i typed? Why still these
  issues again"): every textarea on a page that loads it (the console, the
  client portal, the selection page, the creator's page, the review page,
  `docs/PAGE-TEMPLATE.html`) fits its words as it is typed in, as it comes
  into view holding words, when a page sets its `value` (the setter is
  wrapped) and when the width changes, up to 60% of the screen, then
  scrolls; every scroller around it keeps its place while it is measured.
  `data-nogrow` keeps one still. No page grows its own (`tests/grow.js`).
  - Its handle only makes a box taller (the user, the same day: "couldnt be
    drag around like a toy"): never sideways, never below the words it holds
    (its `min-height` is the fitted height), never past 85% of the screen; a
    height dragged to is kept while typing (`data-floor`) and forgotten when
    the page sets new words.
  - A one-line field that may hold more than its width (a title, a link, a
    next action, a reason, a name typed back) is a textarea marked
    `data-oneline`: a field's height, its words wrapping onto more lines
    rather than sliding out of sight, no handle, never a line break (a
    pasted one becomes a space), Enter submitting its form as a field's
    would. `ADspaceAsk.rename` opens words in one; a date, a time, a number
    or a code stays an `input`.
- `js/guide.js` (`ADspaceGuide.offer(key, guide)`, `open`, `leave`, `can`,
  `useServer`) is the only first-visit guide (the user, 2026-10-07: "a one
  time tutorial kind into the entire portal"):
  - A guide is up to three steps, each on a control the page draws (`at`):
    the first three drawn, so a step whose control is not drawn (a
    permission, an empty list, the other state of a screen) is left out, and
    a guide with none left waits for a visit that has one. `within` names
    the sheet a guide lives in (that sheet is not over the page; the card
    stands above it, `.is-insheet`, and Escape ends the guide before the
    sheet); `then` runs once it is finished or skipped, never on leaving.
  - `offer` opens it once, by itself, when nothing is drawn over the page
    (a sheet, a menu or popover card, a question, the review canvas, the
    finder, a cover, the console booting; drawn, not merely present: the
    Access denied cover sits in a hidden shell) and the section has finished
    drawing (no `.skel` on screen, the same steps on two reads); `open` is
    asked for.
  - A card (`.guidecard`, never `.kmenu`: the pages shut every menu on a
    press elsewhere), not a cover: laid by `ADspaceMenu.pop` from its step's
    control, which wears `.guide-on` (the focus ring, drawn inside a row,
    which its table clips); docked at the foot on a phone, its control
    brought to the middle of the screen, clear of the card; never over the
    command bar; nothing under it locked. Skip, then
    Next or Done; Escape (unless something is over it: that hears the key
    first), pressing the ringed control, opening something over it (a sheet,
    a menu, a post) or leaving the route ends it, and each counts it met. A
    scroll re-lays the card on its control and never pulls the page back.
  - Met is kept per person: a colleague's in `guide_seen`
    (`2026-10-07-first-visit-guides.sql`: `guides_seen()`,
    `guide_seen_mark(p_guide)`; RLS on, no policy, no grant), asked once
    `me()` answers, so a guide met at a desk is not met on a phone; a client
    page's in this browser (`adspace-guide:{key}`). The browser keeps a copy
    either way.
  - The console's guides are `GUIDES` in `js/admin.js`, a screen each
    (the user, 2026-10-10: "the entire portal of these sections"): a route,
    else a tab, a report's step or a sheet, as `guideKey()` reads the page
    (`settings`, `whatsapp.templates`, `whatsapp.compose`, `arrange`,
    `mine.health` before agreeing and `mine.checkin` after, `team.health`,
    `reports.entry`, `reports.text`, `reports.check`, `reports.review`;
    batch 2, 2026-11-21: `campaigns.record`, `campaigns.roster`,
    `campaigns.payments`, `whatsapp.email`, `overview.team`, and
    `analytics.tab` on any Analytics tab after the first), offered as the screen
    first appears (an address change, or the page settling after a sheet, a
    tab or a step is drawn); on a phone the tab bar's guide (`phone`: the
    sections, More, the name that arranges them) comes first, then the
    screen's. Show me around in the ⓘ card reopens the screen's own, else
    the section's, while a step of it is on screen; the client portal's, the review page's, the
    selection page's and the creator's page's are in their own scripts, in
    English and Chinese where the page has 中文 (it follows the switch).
  - The stand-in seeds every guide as met; `window.__guidesFresh` (or the
    tab's `adspace-guides-fresh`) starts a person on none (`tests/guides.js`).
- `js/state.js` owns loading, empty and failed (`skeleton`, `emptyLine`,
  `failLine`) and `initials`. **A failed read is never drawn as an empty list.**
  - `fit` writes `is-narrow` (≤640) and `is-tight` (≤460) on `.console-body`,
    `.rec-pane` and `.rec-rail` from a `ResizeObserver`. A list may state its
    own line (`data-narrow="860"`) and its own tight line (`data-tight`: a
    booking register at 575, so a date and its time never cut), and a sheet outside the console body
    states one to be fitted at all (`#taskDrawer` `data-narrow="460"`).
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
    off their default), then the count and the primary as a filled `+`; a
    view segment it holds on a row of its own above them.
  - Tabs first, then the bar, on every section at every width (the user,
    2026-11-03: "why are some up and some below"): a section's strip (Clients,
    Creator Campaigns and its stages, Reports, Services, Team) stands over its
    bar, 12px above the search, and every strip on its own row is the tab
    row's height; a desk keeps My Work's views at the left of the bar's own
    line (`tests/cmdbar.js`).
  - A record's pane heads itself one way (2026-11-03, the user: Calls and
    visits beside Quotations): each part an `h2` in `.viewhead` (15/600,
    the panel title's size, inside its card since 2026-11-13), its act a
    `.btn-sm` (quiet where it adds), and an empty list
    words alone, its act the heading's; `.empty` and `.emptyline` are one
    look and one height (the mute ink at 400; `tests/cmdbar.js`).
  - Every record leaves by one Back (`.backlink`: the arrow and the word
    Back) at one height, its section's own strip stepping away while it is
    open, and heads itself with `.rec-id` (the disc where the record holds
    a picture, a client's or a campaign's, else none: a supplier and a
    colleague head with the name, `.is-nomark`, 2026-11-04; the name over
    its meta, the state and the ⋯); Select is behind the bar's ⋯ in every section; an
    empty status line takes no room (2026-11-03, the user: "check all
    others too"; `tests/cmdbar.js`).
  - The bar's own selects are moved into `#cmdSheet` and back, never copied.
    Clear sets `data-default` (else the first option) and fires `change`.
    A field the page hides (`.cmdbar-find[hidden]`) takes its search mark with it.
    `data-nofilter` marks a select that is not a filter (`#workWf`,
    `#workScope`). `data-view` marks a view kept in the card (`#workGroup`,
    `#regSort`): never counted by the badge, never reset by Clear.
  - A bar's primary whose words a page writes later (Create n bills) writes
    them into its `.btn-word` and its name, never its `textContent`, which
    takes the phone's glyph away (2026-11-15).
  - A second action goes behind `.cmd-more` beside a primary; a bar of plain
    actions keeps its first and puts the rest there once it has three (the
    Performance Months bar); a button marked `data-rare` (with its `data-g`)
    is behind the ⋯ at every width, the ⋯ drawn at a desk for it alone and
    taking the focus back from what the item opens (Compare groups, Bulk
    import; SHELL-5, 2026-10-22); each item carries its button's
    `data-need` and follows its `hidden`, and the ⋯ leaves when nothing in it
    can be pressed. Its glyph is the row ⋯'s three dots across. A ⋯
    that would hold one item is not drawn: that item's own button stands
    on the bar (`.cmd-solo`; a section's own ⋯, My Work's and Reports',
    through `ADspaceMenu.solo`; the user, 2026-11-17).
  - Every filter is a pill (v3, 2026-11-12): at a desk on the bar's own
    line between the search and the count (the user, 2026-11-13: "we're
    wasting one row for the filters"), on a row of their own under it
    where the line cannot hold them, the count and the acts keeping the
    line (`fitPills`, measured as the bar or its search resizes), each filter whatever its value (`Stage: All stages`, its
    value in ink on the deeper tonal step once set), a press opening its
    choices as a menu under it (`.cmdpill-menu`, the arrows, Escape back to
    the pill); on a phone, on a row of their own under the bar, only the filters set, a press putting that one
    back (`.cmdbar-chips`, Label: Value with its ×). A view never a pill;
    Clear filters stays the card's and the empty list's
  - The Filters sheet focuses its card, never a select (a focused select wears
    the ring, and iOS does not open a select that already has focus).
  - A select the page shows or hides while the card or sheet is open is
    shown or hidden there at once (a `MutationObserver` on its `hidden`).
  - A Filters button over only hidden selects is not drawn.
  - At a desk every bar's search is a 32px mark that grows into a 280px field
    and shuts on Escape or when left empty.
  - At a desk the Filters mark (after the bar's last select) is drawn only
    for a select no pill holds (a view kept in the card: `#workGroup`,
    `#regSort`), its card hung from it (`#cmdPop`, `ADspaceMenu.pop`, Clear,
    Escape or a press elsewhere shuts it); a bar whose filters are all pills
    draws none (the user, 2026-11-13: a duplicate); a `data-nofilter` select
    is a view and stays in the bar at a desk.
- `js/form.js` owns forms.
  - Segments (`select[data-seg]`, the select stays the source of truth, out of
    the tab order; `ADspaceForm.thumb()` slides the surface; `.is-snap` on
    first placement and resize). One whose words do not fit equal columns
    first gives each option the room its words need (`is-auto`), then wraps;
    the words are measured with half a pixel of slack, never by a button's
    `scrollWidth`, which Chromium reports unclipped under an ellipsis
    (2026-10-29: Unavaila… read as fitting).
  - `details.fmore` (its line from `data-none`/`data-some`/`data-on`, a
    tick's off state from `data-off`; a field not on show, or inside
    `data-nosum`, stays off the line).
  - `reveal(el)` opens a fold before a refusal focuses into it.
  - The required asterisk comes from `aria-required` (`.is-req`).
  - `ADspaceForm.title` sets formal names in title case.
  - `ADspaceForm.named` / `sequence`: every client or colleague offered in a
    console select reads code first (`AC190 · Brand`, `AD014 · Xue Yi`), A to
    Z by code with digits as numbers, the unnumbered after by name
    (`byClient`, `byStaff`). The Clients list itself stays newest first.
  - The `data-hint` date hint.
  - A number of a known shape (`input[data-shape]`: # a digit, X a letter
    or digit, any other character laid in by itself) takes only what it
    holds as it is typed: an NRIC `######-##-####`, a BRN 12 digits, a
    passport 20 letters or digits; the creator's payment details and the
    supplier form alike, a kind changed clearing the number (the user,
    2026-11-09: "it says 12 digits but you never lock").
  - The date floor (below).
  - A long list is searched (§8): a select of ten options or more opens a
    finder (`#pickerBox`, `.picker`) in place of the browser's list, the
    field matching every word typed anywhere in an option's label (a name,
    a code, or part of either). The select stays the visible control and the
    source of truth: a pick sets its value and fires `input` and `change`; a
    value set from outside shuts the finder. A press, Space, Enter, the
    arrows or a key typed on the select opens it (the key typed is the first
    of the search; it reads Name or code, else the select's
    `data-find-hint`); Enter or a press picks, Escape, Tab and a press elsewhere
    shut it; Escape shuts it first wherever focus is, before a sheet under it. At a desk it hangs under the
    field; at 640 and under, or under a coarse pointer, it is a card above the tab bar of the
    screen's height named by the field's label, with a close mark, and a tap
    (not a scroll) opens it. Never on a `data-seg`, a multiple, a
    `.state-select`, a disabled select or `data-nofind`. Safari cannot run in
    the sandbox; the user confirms the iPhone tap.
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
- A short month is `Sept`, never the browser's `Sep` (Safari): every English
  short-month format ends `.replace(/\bSep\b/, 'Sept')`, and My Work builds
  its dates from `MON_SHORT`.
- Dates (§5 of `js/form.js`): every date, month and date-time field is bounded
  to 14 Aug 2023 (ADSPACE PLT's registration) through 31 Dec 2099.
  - A lower `min` is raised.
  - A value out of range is cleared on blur and refused on Enter, with
    `.date-note`. `ADspaceAsk.rename` refuses it too.
  - `data-any-date` opts a field out. This is page-side only.
  - DD/MM/YYYY (§7): at a desk every `input[type=date]` becomes a text box
    (`.dmy`) showing DD/MM/YYYY, digits typed straight in taking their
    slashes and YYYY-MM-DD accepted; its calendar mark at the right edge (or
    the down arrow) opens the browser's picker through one hidden native
    field. Its `value` still reads and writes YYYY-MM-DD, so pages never
    change; the field's own min and max are held on blur ("Choose a date up
    to …"), and a part-typed date says "Enter the date as DD/MM/YYYY." A
    coarse pointer keeps the system's own box, as `data-native` keeps any
    one (My Work's pickers that open in place). Playwright's `inputValue()`
    reads the shown DD/MM/YYYY; the page's `value` is read in the page.
    The calendar is taken down after a day is picked, on a press elsewhere
    and on Escape (`shutPick()`: the hidden field's type cycled), because
    Safari left it over the page once the field it belonged to was gone.
    A picked day is read in the hidden field's `change` and everything
    else waits a tick (`setTimeout`): its type changed inside Safari's own
    change crashed the page, which Safari reloaded.
  - Room for the calendar (§6): at a desk, a date field too near the window's
    foot is lifted before its calendar opens (its scroller scrolls, else a
    `.pick-room` spacer), and a press that lifted it opens the calendar with
    `showPicker`. The spacer goes only as it leaves the view, never moving
    the screen under a press. A coarse pointer is left alone.

### Writes, refusals, reversibility
- An import from another system (Bukku, Meta, a spreadsheet) lists what
  it found and takes only what the person ticks, never all of it at once;
  and whatever a person can add, they can delete (where nothing names it)
  from its own ⋯ and several at once through Select (the user, 2026-10-22:
  Read from Bukku took 32 tax codes and offered no Delete, "mentioned many
  times").
- A column added to a table a page reads through column grants
  (`clients`, `team_members`, `quotations`) is granted in the same file
  (2026-11-06: `quotations.sent_out_at` without its grant refused the
  whole Quotations list; `tests/sql.js` reads the list's columns against
  the schema's grants).
- A security definer function replaced keeps every refusal of the one
  before it (2026-10-17: `delete_client` lost its own and refused no one).
- A guard trigger holds an insert as it holds an update, a page's insert
  read against a blank row (2026-10-22, SEC-1: a client could be inserted
  Active with billing by a colleague without the Billing part).
- A public form's typed name is never an actor: it is filed under the form
  (Details form, Supplier form, Quotation website), the name in the detail
  (2026-10-22, BE-3).
- Every email box takes an address alone (`ADspaceWords.emailOk`, the one
  reading; the user, 2026-10-27: "every email boxes"): a value that is no
  address (digits, a host with no domain, a space, a list) is refused where
  it was typed as Enter a valid email address., nothing written; the
  console's sign-in, the client portal's, a lead's, a contact's, Billing's
  finance email, a colleague's, a supplier's, the details and supplier forms
  and /quote/ alike (`tests/emailbox.js`). Page-side only.
- Every page's `esc` is `ADspaceWords.esc` (`js/chrome.js` keeps its own,
  loaded before it; one copy, 2026-10-26), escaping `"` and `'` as well as `&`, `<`, `>`: a stored
  value is drawn inside attributes (2026-10-17: a creator's file address
  holding a quote ran script in the console).
- A value is never drawn raw because of what it starts with: a fact not set
  is a flag (`null` drawn as Not set), never sniffed from its text (2026-10-19:
  an Industry or push format reading `<span…` drew as markup).
- A stored address drawn as a link is held to the web twice: a check on its
  column (`^https?://`, an invoice `https://` or `private/`) and the page
  drawing it only on http or https (`ADspaceWords.absUrl`, the one copy, answers nothing for another
  scheme, nor for a space, quote, `<`, `>`, backtick or backslash the
  column's check refuses; 2026-10-17: `javascript://` passed the scheme test; a
  booking's file and a document's file link likewise, opened by `window.open`
  too, 2026-11-07). A link typed
  bare takes `https://` (a month's Drive folder too, its column https
  alone); one `absUrl` answers nothing for is refused where it was typed
  (Enter a web address.), never saved as none. A value
  drawn as HTML is escaped where it is put in, never where it is joined.
- What a client page or a creator writes through a function is held to a
  length: a name 80, a note 2,000, a caption 5,000, refused `too-long`
  before anything is written (`submit_review` `too_long`; `review_draft`,
  `confirm_selection_with`, `creator_submit`,
  `portal_request_once`; `2026-10-18-what-a-client-types-is-held-to-a-length.sql`).
- **A write that changed nothing is not a success.** PostgREST answers a refused
  delete or update with 204 and no error. Every delete and every
  policy-refusable update takes `.select('id')`, and an empty answer is named
  (`Not deleted. The database refused the request.`).
- Use `.then(ok).catch(bad)`, never `.then(ok, bad)`: `bad` never sees what
  `ok` throws.
- A template is saved only with the fields its sender fills
  (`2026-11-10-template-fields-checked.sql`; the overnight review,
  2026-11-10): every template save (supplier, client, Email templates, both
  invoice emails, creator emails, the Meeting message) asks
  `template_check(text, kind)` against `template_fields(kind)`, the one list
  of each sender's fields, refusing `unknown-field` with the field and the
  list, said as `ADspaceWords.line.unknownField` (Unknown field {x}. Use …);
  `template_fields_all()` answers the lists to the team (`tests/tplfieldsql.js`).
- A function's refusal reaches the page whole: a call wrapper hands back the
  answer with what came with it (`recent`, `paid`), never the code alone
  (2026-10-29: a reminder refused `recent` read "Reminded . Not sent again.").
- A refusal is named in the team's words, never the database's (`SAID`-style
  maps). A missing function reads "This feature is not available yet. Please contact an admin."; a refused permission "You do not have permission to {act}. Please ask an admin.", never a section and a level; a setup fault (a key, a token, Google) names no tool to a colleague ("… is not set up yet / not available at the moment. Please contact an admin.").
- A client page never shows a database message. The console may. A refused
  load reads its cover's words; a refused send reads `W.notSent`.
- Back navigates, Revert undoes a state, Restore brings back a record,
  Reinstate brings back a person, Undo reverses a removal, Void then Delete
  retires an issued document.
- The way back is drawn where the act happened (`ADspaceAdmin.undoHere(text,
  undo, host)`, `.undobar-here`, one bar a host on its own clock), naming
  what went.
- A soft remove comes before a hard delete. Anything a person can upload, a
  person can remove.
- An act that destroys somebody else's work, from a control inside that work,
  asks first in place: the ×, then `.filearm` naming the cost. The soft remove
  and the Undo stay behind it.
- A destructive control is drawn behind its permission (`data-need`), and the
  function re-checks at the press.
- A control the database would refuse is not drawn, writes included: a group
  at View meets nothing that writes on any route, and a ⋯ whose every item
  is withheld is not drawn (`tests/viewonly.js` walks every route at View).
- A delete through a sheet re-checks the permission at the press, takes the
  name or serial typed back, and states what goes and that there is no restore.
  The label is **Delete**, never `Delete {noun}`.
- A state derived from data is derived on every load, never written by the
  action that caused it (`syncCampState`, `derive(t)`, `isLate()`,
  `engPhase()`, Last activity). The exceptions are decisions a person owns (voiding a letter never
  moves the client's stage; approving a request never edits a line).
- A value that depends on a change is stamped by a trigger, never by a page. A
  trigger never forces a column back to its old value.
- Every forward move is walked backwards before it ships.
- PL/pgSQL: declared names never match a column, and lookups are qualified. A
  shadowed name fails at run time, not at create time. A `for a, b in select …`
  loop's targets are scalars alone: a row variable among them fails at run
  time, never at create time (2026-11-12, `review_revert_confirm`, caught
  live before it was applied).
- A function's today, and a column's default day, is Malaysia's, `(now() at time zone 'Asia/Kuala_Lumpur')::date`,
  never `current_date` or `now()::date` (`tests/sql.js` reads every
  column's default; 2026-10-22, BE-9) (the database runs on UTC: yesterday
  until 8am; 2026-10-17, `tests/sql.js` reads every function's last
  definition). The database's TimeZone stays UTC: PostgREST writes timestamps
  in it and the pages read them so. Months are taken off Malaysia's local
  time before it is made a moment (`(date_trunc('month', now() at time zone
  'Asia/Kuala_Lumpur') - interval '3 months') at time zone 'Asia/Kuala_Lumpur'`):
  `at time zone` binds before `-`, so the other order counts on UTC's
  calendar (2026-10-17, `portal_meetings`).
- A day a function writes in words is `register_day` of its Malaysian day
  (`5 Sept 2026`), never `to_char(…, 'Mon')` (`Sep`, and the UTC day;
  2026-10-19, a moved date's notice).
- PostgREST cannot choose between overloads a call fits, so a changed signature
  drops the old one first.
- An embed across two foreign keys names the key
  (`team_members!ops_task_assignees_team_member_id_fkey(name)`). A refused read
  of who owns what fails the list; it never draws an unowned row.
- A check a later band widens (`wa_templates_purpose_check`) is added `not
  valid` in every earlier band, so the schema runs again over rows the later
  band allows (2026-11-11: `representative` made the re-run fail three times).
- A seed is a first run, not a running list.
  - Catalogue rows (the rate card, `detail`, Marketing and Sales) seed only
    into an empty table.
  - Admin alone is ensured on every run.
  - `on conflict do nothing` does not protect a deleted row.
- A record whose rows are written only by security-definer functions takes
  no direct write policy (`with check (false)`): `reviews`,
  `option_reviews` and `creator_profiles` as `campaign_confirmations`
  (security audit 2026-11-09: a colleague at Work filed approvals as the
  client's and stored any profile link); a post's `round` moves only by
  the database (`posts_round_guard`, run as the caller).
- A trigger that calls a function closed to `authenticated` is security
  definer itself (2026-11-09: the creator and campaign ID triggers called
  `id_take` as the colleague, so adding either failed).
- Every `ops_`/`perf_` write goes through a security-definer function. The
  tables carry a select policy only, or no policy at all (`perf_`).
- Supabase grants EXECUTE on every new function to `anon` and
  `authenticated`. A helper no page calls (only other functions do) revokes
  itself from `public, anon, authenticated` in the file that creates it;
  one used by a policy, a view, a default or an invoker function keeps
  `authenticated`. A helper restated later keeps its revoke, never the
  grant of its first definition (2026-10-18: three were reopened so;
  `tests/sql.js` reads each helper's last word in the schema).
- No table or view in public grants anon anything (`2026-11-15-database-safeguards.sql`,
  revoked on every pass, Supabase's default grants included; phase 2 audit
  19): a signed-out page reads through functions alone, and a table made
  later is revoked by the band's next run (`tests/sql.js`).
- Function hygiene (`2026-10-07-function-hygiene.sql`, `functions_tidy()`,
  the owner's alone): every function in public names its search path
  (`public`), and anon runs a security definer function only where a public
  page calls it: `open_to_anon`, exactly the functions `schema.sql` grants
  to anon (`tests/sql.js` holds the two equal). It revokes from `public,
  anon` and gives `authenticated` and `service_role` back what they had.
  `schema.sql` ends with `select public.functions_tidy();`, and so does every
  migration that adds or replaces a function. A new function a public page
  calls is granted to anon and joins `open_to_anon` in the same push.
- A catalogue change (for example a rate card revision) ships as a migration
  guarded line by line on the seed's value. It comes with a `-preview.sql` that
  reads and writes nothing and reports per line `will change`, `already`, or
  `edited in the console, left alone`.
- A business figure the team may change (an amount, a threshold, a rate, a
  limit) is a setting an admin edits, effective from a date or period, read
  by the function that applies it; never a number typed into code (the user,
  2026-10-05: "what if i need changes the next quarter"). Outside
  Performance they are `app_settings` (`2026-10-05-app-settings.sql`, key,
  from_date, value; RLS on, no policy, no grant): `app_setting(key, at)` for
  functions, `app_settings_read()` for pages (anyone the team does not hold
  is answered `sst_pct`, the term percentages and `fx_sgd` alone, what a client page
  prices with; `2026-10-19-settings-a-client-page-reads.sql`), `app_settings_set(p_from,
  p_values)` an admin's, from today (MYT) or later (`past`); a figure is the
  one in force on the day, the first row standing in for an earlier day
  only where the schema seeded it (`app_setting`, `setting()`; a figure
  planned for a later day is unset before it; 2026-10-22, BE-5), filed
  `team.changed` under Settings; a value saved for a planned day that equals
  the one in force the day before withdraws that day's row, filed "planned
  change withdrawn" (`2026-10-19-planned-setting-withdrawn.sql`). An edge
  function reads a setting in force from `app_settings_read` through one
  helper (`settingsAt`; `app_setting` is closed to a caller). One sheet edits a group of them
  (`ADspaceAdmin.editSettings`, open until the database answers, a refusal
  said in it with every figure kept (2026-11-10): From, then each figure, under its
  section's heading where a key names one, a change already set from a
  later day said under its field with its unit as the Settings row says it
  and Withdraw on it; each untouched figure shows the value in force on the
  From day, and only a figure differing from it is sent, so one typed back
  to the figure before a planned change withdraws it (2026-10-20, SET-1)):
  Follow-up limits, Tax and terms (`ADspaceAdmin.TAX_KEYS`, eight figures
  in three sections), Due dates (report and revision days, past dates on new tasks), each the
  Settings page's alone (2026-10-29), `team.settings`. Every sheet is
  `ADspaceAdmin.SETTING_SHEETS`, read by the Settings rows and every other
  door alike, so it asks and says the same from each (2026-10-22, SET2-4);
  it opens on its first figure at a desk and on its card under a finger
  (`ADspaceConfirm.ask` `focus`, SET2-6), and AI prices has its Settings
  row alone, never a button in AI usage (SET2-5).
- `expected_version` refuses a stale write with the current row, and the page
  repaints from it.
- Row level security is stated one `alter table … enable row level security`
  line per table, never in a `do $$` loop.
- A comparison of two copies (a migration and its schema section; the
  `ACTION_LABEL` map and `activity_section()`) is enforced by a suite.
- A merge leaves no conflict marker in any file (2026-10-18: a `=======`
  line from #491 stood in `schema.sql`, `tests/sql.js`; 2026-11-18: one
  reached `docs/DECISIONS.md` through #1238): the merge check
  (`verify-gate.sh`) holds a commit carrying one in every mode but off.
- Two releases restating one function merge in turn: the later one's
  restatement holds the other's change and its band follows the other's in
  `schema.sql` (2026-11-06: #925 restated `app_settings_set` without
  #924's `report_post_links`).

### Access
- Access is a level per section, **none < view < work < manage**, in
  `team_roles.access` / `team_members.access`. `allowed(section, level)` is
  every policy's predicate.
  - The page names them Off, View, Edit, Full control (`LEVELS` in
    `js/team.js`; the access restructure, 2026-11-17); the stored keys
    never move.
  - One rule, top to bottom (`2026-11-17-group-switches.sql`, plan version
    4): a portal switch (Business settings `ai_on`, `email_on`,
    `whatsapp_on`, set by `portal_switch_set` at `team.settings`, on from
    the start), then the group's switches (`team_roles.ai_on`, `email_on`,
    `whatsapp_on`, `sensitive_on`, copied onto each colleague by
    `team_role_defaults`, an admin holding all; Use AI, Send email, Send
    WhatsApp, Sensitive details, with Clients they see and Reports to
    (`reports_to`, never round to itself, `reports-loop`) under Main
    settings), then the section, then a tab, which never exceeds its
    section in `allowed()` and the page's `level()` alike (a granted part
    aside). AI off answers `ai_cap` 0; a send off refuses `send-off`: a
    send by hand asks `send_ok` / `send_ok_of` (`2026-11-21-send-switches.sql`:
    the portal's switch, then Send by email `client_email_on` or Send on
    WhatsApp `client_wa_on` (`manual_send_on`, `manual_send_set`), then the
    group's), every email or WhatsApp a colleague sends by hand alike (each
    email's prepare or begin, Send again, `wa_may_send`, a quotation sent on
    WhatsApp); an automatic send asks `auto_send_on` (the portal's switch and
    Automatic emails or Automatic WhatsApp); a sign-in code, an invitation
    and a verification code ask none. Sensitive details shuts client
    billing, creator payment details and supplier bank details, the two
    payment parts following their section. The page asks `may('use.ai')`,
    `may('send.email')` and `may('send.whatsapp')` (the group's alone: not
    permitted, the act is hidden; `:root.no-ai` hides every button carrying
    the AI mark (`svg.ai-mark`) and the Assistant). An act Settings or a
    daily limit stopped carries `data-gate` (`email`, `whatsapp`, `ai` or
    `ai:{use}`, `bukku`, `meet`, `meta` or `meta:checks`, `quotewa`; several
    space-separated, the first that stops it said; a button holding the AI
    mark is `ai` by itself) and,
    while `ADspaceAdmin.gateState(key)` reads it off, `js/admin.js` draws it
    disabled, a press, hover or focus opening `#gateWhy` with what stopped
    it and who can change it: the portal's switch, the send by hand under
    it, the portal's AI, the use's daily limit (`ai_uses_left()`, read as an
    AI act is drawn, again as one is redrawn after 30s and on return), Bukku
    not connected (`bukku_ready()`: no nightly read in three days), Meta
    checks off, Website quotations at 0; Google Meet, Meta and Bukku
    answering that they are not set up is heard once for every call
    (`functions` wrapped in `js/admin.js`) and kept an hour in this browser
    (`adspace-gate-off:{key}`, `ADspaceAdmin.gateLearn`); a link the team
    hands out (`data-page-link` on its tools) says under it while its page
    is set Upgrade in progress or Temporarily unavailable, now or ahead
    (`ADspaceMaintenance.pages()`), the link still copying; what the
    portal sends by itself warns where the team relies on it
    (`ADspaceAdmin.autoOff`, a `.msg.warn` line: an open campaign's Client
    link, Add task under Task reminders at 0) and the step still stands
    (`tests/sendswitch.js`, `tests/switchstate.js`). The five
    WhatsApp parts and the billing and payment parts are gone, their stored
    levels taken off (`2026-11-17-access-cleanup.sql`). `access_keys` (RLS
    on, no policy, no grant) lists every key and its tier, and `allowed()`
    reads the granted parts from it; the page's one list is
    `ADspaceAdmin.GRANTED` (the Team panel reads it), held equal to
    `access_keys` and the stand-in by `tests/access.js`.
  - Select is view, insert and update are work, delete is manage, each a
    policy of its own: never one `for all` policy, since Postgres checks a
    delete against USING alone (one reading at View let View delete;
    `2026-10-08-delete-at-its-level.sql`, `tests/sql.js` §DL). A draft
    report's rows delete at Work, the report's own steps.
  - A Delete at Edit is a request (`js/delreq.js`,
    `2026-11-17-delete-requests.sql`; the user, 2026-11-17: "Full control
    deletes; Edit files a request an admin approves"): its ⋯ reads Request
    delete, the screen's own question adds a Reason, and the call the
    screen then makes (a function on `delete_kinds`, or a table's delete by
    its key) is filed by `delete_request_file` in its place (`denied`,
    `may-delete` at Full control, `bad-kind`, `bad-reason`, `already`,
    `too-many` past 30 a day, `not-found` outside client scope), the record
    left and every admin told (`delete.request`), Undo where it happened
    withdrawing it. An admin decides in Settings, Portal: Delete requests,
    or from its own mark at the rail's foot (`#delReqOpen`, an admin's
    alone, after Settings'; in More's foot on a phone), which carries the
    red dot while any request waits (More too), the Settings row reading
    n waiting in red; the count is `delete_requests_list` read with the
    sign-in reads and again at each read of the list (2026-11-17)
    (`delete_request_decide`): Approve asks first, then the page makes that
    same call as the admin and closes it (`delete_request_done`; refused,
    the request waits again with the refusal); Decline asks a note. The
    requester is told either way. A list's records (several tasks) and a
    kind with no name column (a report's version, a booking) are each held
    and named as the request is filed (`not-found` outside the requester's
    sight); an admin never decides a request they filed (`own`), and only
    the admin who approved one closes it (`not-yours`;
    `2026-11-17-deletes-and-builds-held.sql`). A new delete function or table joins
    `delete_kinds` and the stand-in's `DK` together. `delete_kinds` and
    `delete_requests` have RLS on, no policy, no grant (`tests/delreq.js`).
  - The levels are drawn on reversibility (add, edit and publish are
    reversible; a permanent delete is not), never on CRUD verbs.
- One user group per person (`team_roles` → trigger → `team_members`); no
  per-person switches. A policy on `team_members` never queries itself; it
  takes inserts and updates at Team Full Access (`team_insert`,
  `team_update`) and no delete from any page
  (`2026-10-18-colleague-row-never-deleted.sql`): a removed colleague is
  deleted by `team_member_purge` alone (below).
- The group seeded as Account is named Marketing. Its slug `account` never
  moves.
- Sections: `ops` (My Work), `clients`, `whatsapp`, `review`, `scripts` (Video Scripts),
  `campaigns`, `reports`, `register` (Documents), `suppliers`, `links`, `services`, `team`, `activity`. The
  Handbook is not a section: every colleague reads it, an admin writes it.
- A part (`clients.billing`, `register.hr`, `activity.campaigns`…) answers with
  its own level where one is set, else its section's, in `allowed()` and the
  page's `may()` alike. Only exceptions are stored. A stored level equal to the
  section reads Same as section.
- Granted parts never inherit (`ops_granted()`, which stops answering the minute access ends as `allowed()` does; `2026-10-24-admin-tools-end-on-the-minute.sql`): `ops.all`, `ops.reports`,
  `ops.workflows`, `ops.time`, `ops.numbering`, `team.performance`,
  `reports.whitelabel` (on for Managers from 2026-10-07). Every act an admin
  alone could take is one (`2026-10-07-admin-parts.sql`; an admin's by
  itself, no other group given any): `ops.numbering` (Task numbering),
  `ops.override` (move anybody's task and its final date), `team.perfadmin`
  (`perf_is_admin()`: revenue and profit, Performance settings, a month's
  record removed, the department scores), `team.settings` (Business settings), `team.upgrade`,
  `team.invite` (asked by `invite-member` as the caller), `team.handbook`
  (the four functions and the bucket's add and remove policies),
  `reports.transfer`, `reports.ai`, `team.announce` (Announcements,
  2026-10-07), `register.types` (Document types, 2026-10-07) and
  `team.notice` (Notices, 2026-10-09) and `reports.meta`
  (Meta import and audit, 2026-10-10) and `campaigns.files_delete` (Delete
  approved files, 2026-10-10) and `clients.vic` (Mark VIC clients,
  2026-10-15) and `team.analytics` (Analytics, 2026-10-25) and
  `team.personnel` (Personnel, 2026-11-16) and `team.sessions` (Signed-in
  devices, 2026-11-20); each offers Manage
  alone (on or off). Team: Health (every colleague's answers by name) is
  no part: an admin's alone, never offered to a group (2026-10-18, below).
  `suppliers.pay` (Supplier bank details,
  2026-10-18) is granted too, at View (read) or Work (write). A
  new admin-only act is a granted part, never `allowed('admin')`. Their unset
  option reads `No Access`, and each offers only the levels the database checks
  (`PART_LEVELS`). A stored level outside them is shown and saved as what it
  grants (`offered()`).
- `ops.list`, `ops.board` and `ops.calendar` follow My Work unless set to No
  access.
- A client's record has a part a tab (`2026-10-22-client-parts-for-each-tab.sql`;
  the user, 2026-10-22: "AMV quote, AMV Service Lines, AMV Issue documents"):
  Contacts, Billing, Quotations (`clients.quotes`: Build quote, the
  quotations, their PDF and WhatsApp send, the rate card read, a checklist's
  quotation), Service lines (`clients.services`), Letters
  (`clients.documents`), Requests, Calls and visits, Brand (`clients.brand`:
  the Brand profile, content brief and brand notes by trigger
  `clients_brand_guard`, `brand-columns`; Meta accounts; the Brand analysis)
  and Checklists (`clients.checklists`), each following Clients where a group
  sets none and named in the panel over one line of what it covers
  (`PART_DESC`). Issue document on the record asks
  Letters or Documents: Client documents at Work (`register_may`); a tab of
  several parts (Services: Quotations, Service lines, Requests; Documents;
  Brand with Reports: White label) is drawn where any is readable
  (`PARTS_OF`, `data-parts`).
- Client scope (`2026-10-03-client-scope.sql`): `clients.leads` (Lead,
  Contacted, Proposal sent) and `clients.past` (Past) narrow Clients and never
  widen it (`PART_LEVELS` View and Manage); a group's `client_scope` is `all`
  or `own` (Person in charge, plus any lead nobody holds, to see and take,
  plus every client whose Sales by is the colleague: `clients.sales_by`,
  `2026-10-23-sales-by.sql`; the user, 2026-10-23: a sales executive keeps
  sight of a client handed to operations, at their group's own level).
  One rule, `client_row_seen_by(stage, owner, owner_id, sales_by, level)`,
  the Person in charge matched by `clients.owner_id` (stamped by trigger
  `client_owner_id_stamp` from the name, kept while that colleague holds it;
  never the name alone: a newcomer sharing a removed colleague's name sees
  none of theirs; `2026-11-17-access-security-fixes.sql`), held by a restrictive
  `client_scope` read policy and a `client_scope_guard` trigger (writes at
  Manage, `client-scope`) on the client and every table under it, by
  `ops_may_see_task` / `ops_may_see_engagement` / `ops_scope_error` /
  `ops_report` (every task read in it: open, finished, spans and reviews
  reached; a colleague's own tasks always), and inside `client_billing`,
  `sm_client_reports`, `sm_report_file` and `sm_report_snapshot`. A new table
  hanging off a client joins the do-block's list; a policy of its own asks
  `client_scope_free` / `client_scope_ok`, never `client_seen` (closed to a
  login, so the read fails for everyone). A removal from `clients`,
  `client_documents`, `documents`, `sm_reports` or `ops_engagements` asks it
  at Manage (`client_scope_removal`, before delete,
  `2026-10-03-client-scope-on-removal.sql`), so the delete functions keep to
  it too. The Activity record is not scoped. The stand-in holds the same rule
  (`scopeRowOk`).
- Columns other parts write are guarded by trigger at the part's Work level:
  `clients_billing_guard` (skipping a cascade, `pg_trigger_depth() > 1`, and a write with no signed-in caller: Bukku's read, the SQL Editor; 2026-11-04) and
  `campaigns_finance_guard`; a page's write on `clients` without Clients at
  Work changes only the review columns (`client_review_columns`,
  `review-columns`).
- Retired switches refuse:
  - `can_billing` → `clients.billing`;
  - `can_doc_void` → Clients Manage;
  - `hr` → `register.hr`.
  - One-argument `allowed(x)` means work, and survives for `admin`.
  - `allowed('remove')` is gone.
- `level()` returns 0 for a missing key, above the admin branch. A permission
  check refuses and never throws. `navItems()` selects `.navitem[data-section]`.
- On the page, `may(key, level)` hides controls: every control names its
  section or part and level (`data-need="clients.documents:manage"`), and
  `applyAccess` writes one rule over every key and level the person may not
  use (`#accessHide`); no stylesheet types a hide rule. A tab with
  `data-part` draws only where readable, and the address falls back to
  Overview.
- The team table answers a browser only the columns every page reads
  (`2026-10-18-team-list-holds-what-colleagues-need.sql`): the mobile, the
  access map, the access dates, the expiry, the removal, the erasure and
  `card_email` are withheld; every column of every colleague is Team's at
  View through `team_rows()`, and who takes tasks is `team_task_takers()`
  (My Work's pickers). A read of `team_members` names its columns, never
  `*` (refused); a new column is granted by running that file's part 3
  again with it named. The stand-in refuses the same.
- `is_team()` gates every team table and edge function. `authenticated` is not
  the team, because clients hold logins.
- A system account (`team_members.system`, `2026-10-08-system-account.sql`;
  IT's login, the user, 2026-10-08) is a full admin never offered for work:
  every colleague picker, the capacity bars, the review list, Health and the
  report reviewers leave it out (`ADspaceAdmin.isSystem`, one read beside
  `me()`; `sm_report_may_review`); Set access expiry for everyone skips it.
  It is the super admin (`2026-11-14-super-admin.sql`; the user,
  2026-11-14: "the most highest power on the portal"): it takes no work
  notice (trigger `ops_notifications_a_super_quiet` writes none to it, so no
  bell, push or WhatsApp; a failed scheduled job's `jobs.failed` still
  reaches it), and while it is active it alone makes or removes an admin
  (below).
  The mark is set only with no sign-in (the connector or the SQL editor;
  a signed-in insert sending it, a `removed_at` or an `erased_at` is refused
  by trigger `team_members_insert_guard`, `2026-10-18-new-colleague-added-plain.sql`);
  trigger `team_members_system_guard` lets only the account itself change its
  standing, access date, group, admin mark or email (`system-account`).
  Team shows it with a Super admin tag and no ⋯ for anyone else.
  - The team list is never derived from `auth.users`. The cutover sweep runs
    only while `team_members` is empty and skips client contacts.
  - A wrong row is stood down (`active = false`), removed, then deleted
    by an admin where it should not exist.
  - `no_team_client_overlap`: one address is never both a colleague and a live
    portal contact. Where a legacy overlap exists, `portal_clients()` returns
    nothing for a team address.
- The Team group panel (two parts since 2026-11-17, the user: "just main
  settings, and sections access (with advanced sections control)"; layout
  only, the stored map and every check unchanged):
  - `#grSum` reads the panel back as one sentence under the name.
  - Main settings: Start from Admin / Manager / Staff / View only (a panel
    matching none reads `Custom: n changes from {nearest}` in plain words
    beside it, `#grPresetNote`, worked out and never stored, no fold; a
    preset chosen over a Custom panel asks first, `Start from Staff?` · n
    changes will be replaced., S7; Admin in Start from is the only way to
    make a group admin, offered to the super admin alone), then the
    Dashboard (`#grDash`, Off / On, filed `Team dashboard: On → Off`), Use
    AI, Send email, Send WhatsApp, Sensitive details, Clients they see
    (`#grScope`) and Reports to (`#grReports`), a hairline between each.
  - Section access: one row a section in the rail's order (`CHUNKS`), the
    name, its segment at the right edge, the line for its level (`DESC`),
    and one Advanced (n) fold (`advItems`): the section's own parts, the
    admin tools that act on it as switches (`TOOL_HOME`: the portal's own,
    Upgrade mode to Analytics, under Team), and its line of the Activity
    record (`activity.{section}`, Same as Activity record; HR Letters under
    Documents, the Handbook under Team; `ACT_HOME`); shut,
    `#grDiff-{section}` names only what differs. No Admin tools block, no
    Customise. The My Work views (List, Board, Calendar) are not offered; a
    stored one is kept through a save.
  - Each group row reads its access as phrases held whole (`team-part`),
    and one ⋯ holding Edit then Delete for an admin alone, nothing beside
    it (a user group is made, changed and deleted by an admin: `roles_admin`
    and `team_roles_admin_guard`, `admin-only`; none on the Admin group, nor
    on an admin group for anyone but the super admin; the user, 2026-11-17:
    "menu only sit one option, edit stays outside?"). Services offers No Access,
    View and Full Access; Leads and Past clients offer no level above
    Clients; a client part that follows Clients is greyed while Clients is
    No Access (N2, N3).
  - Compare groups (the bar's ⋯, `#groupCmpBox`) reads every section and
    the admin tools for every group, read only.
  - Own clients only is never given with any Activity record access, a
    section or a tab (the record is not scoped): the sheet refuses it and
    trigger `team_roles_scope_guard` (`scope-activity`) holds it for every
    group but an admin's (`2026-10-10-letters-held-to-their-lines.sql`).
  - No preset below Admin opens Team, HR letters or performance reviews,
    their history included (`activity.team`, `activity.hr` shut; S5).
- User groups are Team's Groups tab (`tab=groups`, `#teamGroupsPane`); the
  strip reads Members, Hiring (`tab=hiring`), Groups, Performance and Health
  (`tab=health`, an admin's alone), each drawn only where readable, the strip
  only where two tabs show.
- The Admin group has no ⋯ and cannot be deleted. A group is deleted by
  `team_role_delete(p_slug, p_to)` (`2026-11-17-group-delete.sql`; the user,
  2026-11-17: "delete options for every create"): an admin's (`admin-only`),
  an admin group or a move into one the super admin's (`super-only`), the
  Admin group never (`fixed`); a group holding colleagues, removed ones
  too, asks New group for its n members (`no-target` without it) and moves them
  in the same transaction, each taking that group's access, the last admin
  kept (`last-admin`); then the name typed back; filed
  `team.group_removed` with how many moved and where.
- While an active system account exists, it alone (the super admin) makes
  a colleague or a group admin, or changes an admin's group, admin mark or
  standing, or makes or deletes an admin group (`team_super_ok()`,
  `super-only`, `2026-11-14-super-admin.sql`; with none active an admin
  does); the page offers an admin group, Admin in Start from, and Set
  inactive or Delete on an admin only to it (`ADspaceAdmin.isSuper`).
- Only an admin makes a colleague or a group admin, or changes an admin's
  group, access, access date, email or standing (`team_admin_guard`,
  `team_roles_admin_guard`, `admin-only`; 2026-10-17), and only an admin
  changes their own group (`2026-11-07-own-group-through-an-admin.sql`): Team Full Access is
  not admin, and is drawn no Set inactive, Delete or Access until pen on an
  admin's record (2026-10-27, TEAM-1). Nor does anyone but an admin turn on, change or take off a
  granted part (an admin tool, Performance, Supplier bank details …) on any
  group, their own included: the guard compares every key `ops_granted` is
  asked for, the page stills those switches and selects and saves them as
  stored (`2026-10-24-admin-tools-admins-only.sql`, S2; the user declined
  delegating Performance or HR Letters). A signed-in write never takes away the last active admin: it
  takes the team's admin lock first, so two admins standing each other down
  at once leave one (`team_members_last_admin`, `last-admin`;
  `2026-10-18-the-last-admin-is-kept.sql`).

### Directories and the command bar
- Every console directory is a card per group via `js/group.js`:
  - Clients by stage;
  - a client's Engagements by content month;
  - Content Review as one card; a client's sets by content month;
  - Creator Campaigns as a tab a state (`#campStages`: Draft, Open for
    selection, In production, Completed, each counted, opening on the first
    that holds any), a card a month made (MYT) under it, newest open; a row
    reads Updated where the state would repeat its tab, and Booked n of N
    (creators booked of its slots, never the slots alone; 2026-10-22, CMP-8);
    on a phone the client and Booked n of N under the name, the amount under
    the date at the right edge (the user, 2026-11-14);
  - the Creators List by fee band (Inactive shut);
  - Short Links Live, Namecards, Paused (Paused shut);
  - Documents by family;
  - Services by category;
  - Team by user group;
  - the Handbook by category (Archived shut, `team.handbook` alone);
  - My Work by its axis.
- A filter never repeats the cards' own grouping: no state, kind, group or
  category filter on a route whose cards are those groups (Creator Campaigns,
  Documents, Team, Services, Handbook, Short Links). An option for all reads
  All stages, All people, All months, never Every …, Everyone or Everything.
- A list puts what needs acting on first and what is finished last (2026-11-03,
  the user: "the more user friendly sequencing order"), the order otherwise
  kept: My Work's rows and board columns a VIC client's open work first, then
  priority and due date, finished work newest finished first (`rowOrder`);
  Leads past their follow-up time first; a client's quotations needing the
  team, then standing, then settled, then over (Expired, Revised,
  Cancelled); requests open first; service lines To quote, Confirmed,
  Enquired, each newest first; a void or replaced letter, a withdrawn
  notice, an inactive rate line, a cancelled month and a posted or completed
  booking after the rest; Content Review's sets in a month with changes
  requested first, then drafts, then published; a report month's rows on
  Published not sent first, then A to Z by the name they read; the client
  portal's meetings ahead first, soonest first, then held, latest first;
  Video Scripts' No month last. A history stays newest first and what waits
  on the reader oldest first.
- A filter repaints only when its value changed: `input` and `change` both fire,
  and `change` on blur detached Clear filters.
- A list reads what its rows show in one request (`.in()`, paged by the
  thousand), never one a row, and a repaint or a key typed reads nothing
  again: every request is a logged line Supabase meters (Content Review's
  read a client was a sixth of the live traffic, 2026-10-09; `tests/sets.js`).
- `.cmdbar-end` > `.cmdbar-quiet` (count) + `.cmdbar-acts` is one element, so a
  wrap cannot split it. An empty count is not drawn.
- The rail's order (see `DESIGN.md`) drives `SECTIONS`, the Activity record's
  sections (`ACT_SECTION`), `PARTS.activity`, and the Team panel's blocks. One
  sequence everywhere.
- The route's purpose line opens from the route name (`.console-title` button,
  14px glyph, `aria-expanded`; `.aboutpop` laid by `ADspaceMenu.pop(btn, pop, 'left')`).
  - One sentence per route, from `INTRO`.
  - Never opens by itself (the first-visit guide is the one that does). While
    a route is new, the glyph carries `--action`.
  - Below 400px the glyph gives way and the name never does.
- A standing fact about a route is a `.routenote` under the register:
  - the verify page as a link;
  - the redirect hosts `hi.adspace.me` and `go.adspace.me` as links.

### Area rules (read before changing an area)

Each area's rules live in its own file under `docs/rules/`, out of what every
session loads (2026-11-17, the user: "ok all"; the cost of loading every rule
in every session). Before changing an area, read its file whole. The first
edit of a path in its triggers prints the file's name (`.claude/hooks/area-rules.sh`);
a change reaching an area with no path of its own (a schema band, a function)
is found with `grep -rln "<function, table or word>" docs/rules/`. A rule
learned about an area is written in its file, never here.

| Area | Rules | Paths that name it |
|---|---|---|
| The Assistant | `docs/rules/assistant.md` | `js/agent.js`, `supabase/functions/portal-agent` |
| Console search | `docs/rules/search.md` | `js/search.js` |
| Clients | `docs/rules/clients.md` | `js/crm.js`, `js/engage.js`, `js/sales.js`, `js/checklists.js`, `js/details.js`, `details/`, `supabase/functions/brand-analysis`, `supabase/functions/checklist-draft` |
| Documents | `docs/rules/documents.md` | `js/documents.js`, `js/letters.js`, `js/register.js`, `js/verify.js`, `verify/`, `js/docmail.js` |
| Suppliers | `docs/rules/suppliers.md` | `js/suppliers.js`, `js/supplierform.js`, `supplier/`, `supabase/functions/supplier-mail` |
| Signed documents | `docs/rules/signed-documents.md` | `js/seal.js` |
| Hiring | `docs/rules/hiring.md` | `js/hiring.js`, `js/careers.js`, `js/hrdocs.js`, `js/onboard.js`, `careers/`, `supabase/functions/hiring-mail` |
| Bukku | `docs/rules/bukku.md` | `js/bukku.js`, `js/invoices.js`, `supabase/functions/bukku-sync` |
| Content Review | `docs/rules/content-review.md` | `review/`, `js/review.js`, `js/mockups.js`, `js/media.js`, `supabase/functions/caption-draft` |
| Creator Campaigns | `docs/rules/creator-campaigns.md` | `js/campaigns.js`, `js/creators.js`, `js/creator.js`, `js/decide.js`, `creators/`, `creator/`, `supabase/functions/creator-mail` |
| Dashboard | `docs/rules/dashboard.md` | `js/overview.js` |
| Analytics | `docs/rules/analytics.md` | `js/analytics.js`, `supabase/functions/analytics-read` |
| My Work | `docs/rules/my-work.md` | `js/ops.js`, `supabase/functions/meet-create` |
| Performance | `docs/rules/performance.md` | `js/perf.js` |
| Personnel | `docs/rules/personnel.md` | `js/personnel.js`, `js/xlsx.js` |
| Health | `docs/rules/health.md` | `js/health.js` |
| Reports | `docs/rules/reports.md` | `js/reports.js`, `js/smreport.js`, `supabase/functions/report-draft`, `supabase/functions/meta-import` |
| Services | `docs/rules/services.md` | `js/quotes.js`, `js/quotepdf.js`, `js/ratecardpdf.js`, `js/quote.js`, `quote/`, `supabase/functions/quote-request`, `js/money.js` |
| Client portal | `docs/rules/client-portal.md` | `client/`, `js/portal.js` |
| Short Links | `docs/rules/short-links.md` | `workers/links` |
| Video Scripts | `docs/rules/video-scripts.md` | `js/scripts.js`, `js/scriptpdf.js`, `js/script.js`, `script/`, `js/frames.js`, `js/animatic.js`, `supabase/functions/script-draft`, `supabase/functions/script-pictures` |
| Handbook | `docs/rules/handbook.md` | `js/handbook.js` |
| Team | `docs/rules/team.md` | `js/team.js`, `js/namecard.js`, `js/card.js`, `card/`, `supabase/functions/invite-member` |
| Activity record | `docs/rules/activity.md` | `js/records.js` |
| Messages: WhatsApp and Email | `docs/rules/messages.md` | `js/whatsapp.js`, `js/mailtpl.js`, `supabase/functions/wa-send`, `supabase/functions/wa-hook`, `supabase/functions/_shared/mail.ts` |
| Push notifications | `docs/rules/push.md` | `js/push.js`, `js/push-sw.js`, `supabase/functions/push-send` |

### Sign-in, security, secrets
- Send invitation always sends one (2026-11-11, the user: two went
  nowhere): Supabase invites only an address with no login, so for one that
  has a login `invite-member` sends the same invitation itself through
  `_shared/mail.ts` (from the team's sender, a one-time sign-in
  link from `generateLink`, a key of its own each send), and a page says
  Invitation sent only on `sent`, never on `already`. A colleague is
  greeted by the name on their record, an admin alone wording it otherwise
  (audit 2026-11-11).
- An active colleague's first sign-in makes their login (2026-11-11, the
  user: one added with no invitation read Active and was sent no code): the
  console asks `portal-login` before the code, which makes a login for a
  live portal contact or an active colleague not removed or erased, and for
  nobody else, answering alike either way.
- A sign-in email's button opens the portal's own page, never supabase.co
  (2026-11-18, Resend's check: a link off the sending domain reads as
  spam): `?token_hash=…&type=email` (an invitation `invite`) on the page
  asked from, proved by `js/api.js` before any read of the session, the two
  words taken out of the address; the dashboard's templates
  (`docs/SIGN-IN-EMAILS.md`) and invite-member's own invitation
  (`hashed_token`) alike (`tests/signin.js`, `tests/invitefn.js`).
- `/admin/` signs in with the emailed link or the code (`#authCode`, 6 to 10
  digits, `verifyOtp` type `email`), or with a passkey (supabase-js 2.117.2 on
  `/admin/` only).
- The demo (`js/demo.js`, `2026-10-27-demo-access.sql`; the user,
  2026-10-27: "fake populated data unable to add anything … so i can sell
  ppl this portal", "Just enter in the email input"): four to eight digits
  in the sign-in's email box are asked of `demo_pin_ok` (anon, true only
  while Demo access is on and the PIN right, wrong ones counted as a
  link's passcode, `link_passcode` kind `demo`); the box takes an email
  address or that PIN alone: a wrong PIN and any value that is no address
  read Enter a valid email address., the same words, so the box never says
  a PIN exists (the client portal's sign-in refuses one alike). A right PIN keeps
  `adspace-demo` in this browser for twelve hours, and the head then loads
  `demo/seed.js` (a made-up agency, Sample Studio, its six colleagues and 48
  clients over two years, built on every load relative to today) and
  `demo/engine.js` (the stand-in, `tests/demo-build.js`) in place of the
  database, which the page never reaches again. Signed in as the sample
  director; every write refused (a table's insert, update or delete, a
  function whose name changes something, an edge function but Bukku's
  invoices read, which the engine answers with none held, an upload) with
  Demo: changes are not saved.; the mark, letterhead, foot and title the
  sample agency's; a bar over the console (`#demoBar`, the upgrade line's
  look) with Client pages (a menu of the client portal, Content Review, the
  creator selection, a creator's page, Video Scripts and a namecard, each
  on its sample link in a tab of its own, so nobody needs an address; the
  user, 2026-10-27) and Exit demo, which Sign out does too. The client pages
  (`/client/`, `/review/`, `/creators/`, `/creator/`, `/script/`, `/card/`,
  `/verify/`)
  load the same while it stands: the client portal signed in as a sample
  client's main contact (`client@example.com`), the rest on their sample
  links alone, each key holding a 0 that no real key's alphabet holds
  (`demo0r…`, `demo0c…`, `DEMO0…`, `demo0s…`, `demo0…`), so a real link
  opened while the demo stands is the real page; `/verify/` loads it for
  any reference (Verify document in Client pages opens it on the sealed
  sample's), answering the seed's January 1988 documents alone, a real
  reference Not found, and File check matching only a copy of the sealed
  sample the demo console drew (`adspace-demo-seals`, the hashes it handed
  out; the user, 2026-11-20, option A); each under the bar edge
  to edge (`.annbar.demobar`; the namecard has no bar); the creator's page
  opened bare, with no code kept, opens a sample creator holding a booking,
  and Exit demo lets go of a sample code it kept; signing out of
  the client portal returns to the console. A demo whose sample data did
  not arrive takes the real library away, never the real database: a client
  page reads Unable to load under the bar, the console Unable to load with
  Exit demo on its signed-out page; Sign out in the demo is Exit demo, never the
  console's clearing of the colleague's notes and drafts; a sheet's draft
  is let go as the demo starts and ends (audit, 2026-10-27). The sample data
  holds no registration a company could hold (zeros) and no real handle
  (`.sample`), and the demo opens no chat, call or profile (wa.me, `tel:`,
  Instagram, Facebook, TikTok, rednote), saying so in its bar; the client
  pages' guides it marks met are listed (`adspace-demo-guides`) and offered
  again on Exit demo (2026-10-29). Settings, Portal: Demo
  access (`team.settings`): On / Off and a PIN, a new one 6 to 8 digits
  (one of 4 or 5 set before keeps opening; audit 2026-11-15), kept as a
  bcrypt hash (`demo_state`, `demo_set`: `bad-pin`, `no-pin`; a new PIN
  clears the demo's wrong tries and locks), filed
  `team.changed` under Demo access, never the PIN.
  - Passkeys are managed in the account menu.
  - The passkey offer shows once per browser (`adspace-passkey-offer`).
  - A passkey that proves the person already signed in goes through
    `ADspacePasskey.prove()`, never a bare `signInWithPasskey` (which signs
    in whichever account's passkey the browser offers). It is offered only
    to a person with a passkey of their own (`mine()`); the console holds its
    auth events meanwhile (`ADspaceAdmin.hold`); another account's answer is
    revoked on this device (`signOut({ scope: 'local' })`) and the person's
    own session put back (`setSession`), else the console signs out.
- Overseas access (`2026-10-24-overseas-access.sql`,
  `2026-10-24-admin-notices-system-account.sql`, their SQL Editor parts
  `2026-10-24-overseas-access-days.sql` and
  `2026-10-24-overseas-reminder-setting.sql`; the user, 2026-10-24: "Allowed in
  Malaysia Singapore", "14 days per cycle", "Admins only"): the console
  answers a colleague outside Malaysia and Singapore only once an admin
  approves it. The country is Cloudflare's `cf-ipcountry` header
  (`request_country()`, which a caller cannot set; none, as for pg_cron, is
  never held); `team_place_ok` (an admin, MY or SG, no country, or an
  approved `team_abroad` row whose day (MYT) has not passed) is asked by
  `is_team()`, `allowed(p_section, p_level)`, `ops_granted`, `ops_me()` and
  `me()`, so every policy and function refuses the colleague; client pages
  never ask them. `me()` answering nothing, the console asks `abroad_state()`
  and a held colleague meets the cover (`paintAbroad`, js/admin.js: Access
  from {country} needs approval, Reason and Until, Request access; then
  Request sent with Change request and Check again; a decline, an end or a
  day passed said under it); `abroad_request` (`bad-reason` 3 to 300,
  `bad-until` today to today plus `abroad_days`, a waiting request
  replaced) tells every active admin (kind `abroad.request`, the bell
  opening the colleague's record, the request its `dedupe_key` names
  (`abroad:{id}:…`), never a namesake's), and while it waits, its colleague active and
  its day not passed, `abroad_remind()` (pg_cron `abroad-remind`, every
  fifteen minutes from 08:00 to 22:45 MYT; `team_abroad.reminded_at`, a
  request asked again starting afresh) tells them again every
  `abroad_remind_hours` (2, 0 to 24, 0 sends none; Overseas approval's
  sheet) as Overseas access waiting. The colleague's record decides it
  (the user, 2026-10-24: "Build its from me"): an admin's Team read asks
  `abroad_list()` beside `team_rows()`, the list's state column reads
  Overseas request while one waits, and Overview leads with Overseas
  access while the colleague holds a request of the last 90 days (the one
  waiting or approved as facts, Decline and Approve on the group, Approve
  asking Until, or End access in its ⋯; the rest under Earlier); nobody
  else reads it (`tests/abroadrec.js`); Settings holds no list of
  requests. `abroad_decide` / `abroad_end` filed `team.changed`
  under Overseas access and told to the colleague (`abroad.decided`);
  Overseas approval (`abroad_days`, 14, 1 to 30, and the reminder hours,
  Business settings). An
  approval covers any country until its day. A VPN or roaming data reads as
  where it exits; an edge function reads as where it runs (Singapore for a
  colleague here). The stand-in reads `window.__country` (Malaysia unset).
- One person per console: a session that turns into somebody else's (another
  tab, any sign-in over this one) restarts the console from the top
  (`gate()`, after 1.5s unless the session has come back).
- `/client/`:
  - Asks `portal-login` first. It makes a login only for a live contact with
    `portal_access`, and answers `{ok: true}` to every address, each in the
    same least time (`FLOOR_MS`, 1,500 ms, a slower run at the next whole
    step; a fault logged, never a 500), so
    the wait never says who is a client (2026-10-25, `tests/portalloginfn.js`).
  - `signInWithOtp` with `shouldCreateUser: false`.
  - The email's code signs in on the page as well as its link (`#signCode`,
    6 to 10 digits, `verifyOtp` type `email`), with Use another email; a wrong
    code reads the same for every address.
  - Reads only through `get_portal`, `portal_request` and `portal_withdraw`.
  - A company select appears where one address holds access at several
    clients.
- Sign-in never says whether an address has an account ("If {email} is
  registered, …").
- An edge function reads a caller's address as `cf-connecting-ip`, else the
  last X-Forwarded-For entry, never the first (`media-pass`, `sign-download`,
  `quote-request`; 2026-10-25).
- An email is matched as itself in every edge function (`exactEmail`: `_`
  and `%` are letters, never wildcards; audit P2, 2026-10-10).
- A colleague's upload names its purpose and record, and `sign-upload`
  signs it only for that (audit P1, 2026-10-10): `review` a content set
  (`batchId`, Content Review: Sets at Work), `logo` the client (Clients or
  Content Review: Client settings at Work), `campaign` a booking whose draft
  is owed (`optionId`, Creator Campaigns: Campaigns at Work), `invoice` a
  campaign (`campaignId`, Creator Campaigns: Finance at Work, private where
  set up), `report` a report version (`versionId`, Reports at Work, always
  private, its scope asked of the report's client), `thumb` a report's
  picture (`reportId`, Reports at Work, always private, a JPEG under
  `private/{client}/thumbs/`); the record must be the named client's and the caller's client
  scope must reach it, each asked as the caller. Work in one section signs
  nothing for another; a page that names no purpose is asked to reload.
- `sign-upload` signs only the extensions the pages upload (`EXT_TYPE`:
  video, picture, PDF, ZIP; never HTML, SVG or script; `bad_extension`),
  each with its one type, and signs that type and the size claimed into
  the PUT for fifteen minutes (`X-Amz-Expires` 900); every page PUTs with
  the `contentType` it answers (2026-10-17, audit finding 4). Every picker
  that feeds it offers only those extensions (`ADspaceAPI.uploadAccept`),
  and its refusal, a non-2xx that supabase-js leaves on `r.error.context`,
  is read by `ADspaceAPI.fnRefusal` and said in words (`W.uploadType`),
  never "non-2xx".
- A client's review link and a campaign's selection link carry an
  eight-character key (`?k=`, alphabet `23456789abcdefghjkmnpqrstuvwxyz`),
  made by `ADspaceAPI.accessToken()` in the console and `new_link_key()` in
  SQL (`2026-10-01-short-links.sql`), never `Math.random`. A long key from
  before is kept as `moved_token`: it opens nothing itself, and
  `link_moved(kind, token)` answers it with the current key, which the page
  puts in the address and loads. Changing a key (Reset link) clears
  the moved key by trigger, so a reset retires every earlier link. A
  campaign's is reset from its ⋯ (`campaign_reset_link`, Creator
  Campaigns: Campaigns at Work, a key from `new_link_key()`), and
  `get_campaign` answers `not-found` once the client is Past (2026-10-18),
  so `sign-download` and `media-pass` close with it, as do
  `save_selection`, `confirm_selection_with` and
  `review_draft`, before the passcode, and `share_link_preview` names no
  Past client (`2026-10-18-past-client-links-act-on-nothing.sql`); a
  completed campaign stays readable for its results, a Past client's too,
  read only (`selection_closed`, no backups; every write above still
  refuses; `2026-10-18-completed-campaigns-stay-readable.sql`, the user:
  988's results were never read).
  A link's passcode is asked through `link_passcode(kind, token, stored,
  given)` by `get_review_feed`, `submit_review`, `submit_review_seen`,
  `get_campaign`, `save_selection`,
  `confirm_selection_with` and `review_draft`
  (`2026-10-18-passcode-locks-per-caller.sql`,
  `2026-10-18-review-decisions-ask-the-passcode.sql`): asked without one is never
  counted; wrong ones are counted per link and caller address
  (`link_tries`, `request_ip()`: the address Cloudflare saw,
  `cf-connecting-ip`, else the last X-Forwarded-For entry, never the first,
  which the caller writes, an IPv6 address read as its /64
  (`2026-10-29-review-fixes.sql`); `media-pass`, `sign-download` and the
  links Worker (its `IP_RELAY_SECRET`, a creator's preview) pass their
  caller's on as `x-adspace-ip` beside `x-adspace-relay`, the
  `ip_relay_secret` in `app_secrets`, the only way it is taken;
  `2026-10-18-a-callers-address-is-cloudflares.sql`; both rows taken under
  a row lock before any passcode is compared, so guesses sent at once are
  counted in turn, `2026-11-07-passcode-tries-counted-first.sql`), five within
  15 minutes locking that address out, the right one included, for 15
  minutes, then an hour, then a day where it is locked again within a day
  of the last lock ending (`strikes`, `struck_until`; the right code and
  Clear start the steps again; `2026-10-18-passcode-locks-lengthen.sql`);
  a new or changed access code is six characters at least (trigger
  `passcode_long_enough`, `passcode-short`; Access code says so before
  it saves), one set before keeping its place; the link's own count (`link_attempts`, 100 within an hour)
  locks it for an hour for every address but one that opened it in the
  last 30 days; each answered `locked` with its minutes (`link_locked`),
  said on the page as Link temporarily locked (`W.lockedLine`), and a
  stored code that no longer opens the review link is let go, the media
  pass not asked again. The team reads a lock under the link
  (`link_lock_state`, `.linklock`) and clears it (`link_lock_clear`, the
  section at Work, filed). A passcode asked for names nobody; the tables
  have RLS on, no policy, no grant.
- Secrets never enter the repo or the chat:
  - The Supabase anon key and the Google browser key are public by design.
  - The Turnstile secret, the Google refresh token, the Meta system user's
    token and the performance master code live only in Supabase.
  - The delete code lives in the database.
- S3 (`docs/S3-STORAGE.md`): the upload key only writes under `content/`,
  and under `private/` (write and read, for invoices, each published
  report's kept PDF and every report picture, `private/{client}/thumbs/`,
  read through S3 links sign-download signs, the bucket's CORS allowing
  GET and PUT from the portal; S3-STORAGE §7) once §5 is done;
  `private/` reaches CloudFront only through its own `private/*` behaviour,
  each link signed by `sign-download` for one file with `private/`'s own
  key (`cf_private_files_private`, `cf_private_files_key_id`, key group
  `adspace-portal-private`), never the media pass's (2026-11-21). `content/` is
  served only with the media pass (§6 done; CloudFront's `content/*`
  behaviour requires it since 2026-10-09) (`media-pass` signs with a
  key it made and keeps in `app_secrets`, `cf_media_private`; CloudFront's
  ID for it is `cf_media_key_id`, and until it is stored the function
  answers `{ off: true }`).
  Nothing deletes from S3: every uploaded file is kept, Content Review files
  and creator drafts included. `s3-sweep` is a daily report only (pg_cron,
  03:17 MYT, `s3-sweep-daily`): with a list-only key it lists `content/`,
  asks `s3_keys_in_use()` (service role only; each column read once a run,
  `2026-10-18-s3-keys-read-once.sql`) which files a row still names,
  judges only objects over 7 days old, and files the counts in `s3_sweeps`.
  Its code has no delete request, and `tests/s3sweep.js` holds that. A
  video's `.web.mp4` copy counts as in use while its original is.
- Scheduled jobs are watched (`2026-10-18-scheduled-jobs-watched.sql`):
  `jobs_watch()` (pg_cron `jobs-watch`, 08:20 MYT) tells each active admin
  (none active: Team Full Access) once a day (kind `jobs.failed`) of the
  scheduled runs that failed since its own last successful run (24 hours
  to seven days, a failed check of its own named first), by job, of an S3
  report filed as failed or not arrived in 26 hours, of a nightly Bukku read
  that failed or wrote no beat in 26 hours (`job_beats`, RLS on, no policy,
  no grant), of creator emails failed or not confirmed, and of each repeat rule
  that could not make its task, named (client, rule or task, its number;
  five, then a count), the notice opening the first one's task; the morning
  run keeps a rule nobody active can make, or whose task its colleague
  cannot see, as its error, which the task card's Repeats line shows
  (`2026-10-18-failed-jobs-named.sql`), and of the automatic WhatsApp
  messages that failed in the window, counted (`2026-10-26-jobs-watch-whatsapp.sql`); `jobs_prune()` (`jobs-prune`, 03:40 MYT) removes job history
  over 14 days and notices read over 90 days ago or unread over 180
  (`2026-10-19-unread-notices-pruned.sql`), never a colleague's notice. Neither is a page's to call.
- The database is kept every night (`workers/db-backup/`,
  `.github/workflows/db-backup.yml`, 02:37 MYT; the user, 2026-10-10: the
  Free plan keeps no backups): Supabase's own dump (roles, schema, data),
  refused when it holds no client row (an empty clients table too; its
  workflow's actions pinned to commits, 2026-10-22, SEC-2, BE-10),
  encrypted with `BACKUP_PASSPHRASE`, put
  at `private/backups/db/db-{MYT day}.tar.gz.gpg` by a key that may only add
  there; it runs on its schedule or by hand, never on a pull request, and
  reads, lists and deletes nothing (`tests/dbbackup.js`). Storage objects
  (the Handbook) are not in it.
- Video conversion (`workers/video-convert/`, AWS Lambda `adspace-video-convert`
  on the bucket's ObjectCreated under `content/`, the user's own setup from
  its README): every video a picker takes (mov, mp4, m4v, qt, mkv, webm,
  mpg, mpeg; `js/media.js` asks the copy of each; 2026-10-22, BE-1) that is
  not already H.264 in an MP4 indexed first
  gets an AWS Elemental MediaConvert job writing `name.web.mp4` beside it
  (H.264, AAC, upright, Rec. 709, fitted to 1080 × 1920 either way up at up
  to 60 fps, never enlarged). It reads and asks; it never deletes, copies or
  touches an original. `{ "all": true }` converts what came before, and
  `{ "all": true, "redo": true }` remakes only copies over the cap. One file
  that cannot be read or asked for is its own `error: …` line, never the
  run's (an upload trigger never fails); a walk stops 30 seconds before its
  time and answers `next`, run again as `startAfter`, and leaves an upload
  under 30 minutes old to its trigger; a size the file does not give is
  asked of MediaConvert's probe, else fitted inside 1920 × 1920
  (`FIT_NO_UPSCALE`); MediaConvert's role writes `content/*.web.mp4` alone
  (2026-11-15, phase 2 audit).

## 3. Workflow and constraints

### Git and delivery
- The branch the session is given (any account: the work carries in the
  repositories, a release in progress on its PR, never in a session); a
  branch with an open PR is continued, not replaced. Squash-merged by
  Claude. Releases are
  grouped by risk (the user, 2026-10-10): related batches share one PR and
  one deploy where the combined diff, the migration sequence and the
  rollback stay understandable; unrelated or independently risky changes
  go apart.
- Sessions run at once (the user, 2026-10-11: "allow all sessions"; until
  then one at a time): each holds one request on its own branch and PR,
  merges `main` in where another merged first, and merges as soon as it
  is built, never waiting to be asked. One gate a machine still holds.
  "Hand over" means: commit and push both repositories, then post
  or replace one comment on the open PR (else a draft PR) stating the
  commits, the checks passed, failed and not run, the steps done and
  still open in order with their rollback, and what waits on the user. A
  session opening on an open PR reads its latest handover first and
  continues its branch.
- A release with a migration or a function states its order (pages,
  each migration, each function), what an old open tab meets at every
  intermediate state, what a failed step leaves and which steps reverse.
  No order is assumed safe. The full schema file is never run on
  production.
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
- A migration is applied by Claude through the Supabase connector (project
  `hwwuigvdfubuymchsvyx`, the user, 2026-09-28), or through the Management
  API (`api.supabase.com/v1/projects/{ref}/database/query`, the token never
  printed) in a session whose connector belongs to another organisation
  (2026-11-20); never a connector on another organisation, in the order the release
  states (commonly after the Pages deploy, so the page stops asking before
  the database stops answering), and verified on the live database
  afterwards. The report names what was applied.
  - The connector holds any statement holding `drop` or `delete` (a function
    body included) for a confirmation it cannot show, and times out: apply
    the rest in small `execute_sql` pieces (`create or replace trigger`, a
    policy created under `if not exists`), then hand the user the held part
    for the SQL Editor as its own run. A storage policy goes in a run of its
    own, since the editor may not alter `storage.objects` and a failure rolls
    back the whole run.
- An edge function (`sign-upload`, `sign-download`, `media-pass`, `invite-member`,
  `portal-login`, `meet-create`, `push-send`, `s3-sweep`, `report-draft`,
  `meta-import`, `caption-draft`, `script-draft`, `wa-send`, `wa-hook`, `brand-analysis`, `quote-request`, `checklist-draft`, `supplier-mail`, `bukku-sync`, `analytics-read`, `creator-mail`, `portal-agent`, `hiring-mail`) is
  deployed by Claude through the
  Supabase connector from the repo copy, keeping its Verify JWT setting, and
  the live source is read back (the user, 2026-09-30) and compared with the
  repo file before anything else; a file is always sent whole, never in
  part (2026-10-16: a half file broke `report-draft` for three minutes),
  its content pasted in the call itself, never a placeholder to fill later
  (2026-10-19: `meet-create` served a placeholder for 50 seconds).
  Before a deploy, `main` is fetched and merged into the branch, and the
  live version compared with `main`'s file: sessions run at once, and a
  deploy from a branch behind `main` takes away what another session
  deployed (2026-10-29: `bukku-sync` v12 removed #814's button for five
  minutes).
  The connector turns a `\u` escape into its character, so a function file
  writes such characters as themselves, keeping the read-back byte for byte.
  A function that imports `../_shared/` is sent with that file in the same
  call (`wa-send`, `supplier-mail`: `_shared/pdfref.ts`; `supplier-mail`,
  `bukku-sync`: `_shared/mail.ts`, the one email layout and Resend send; every function a
  browser calls: `_shared/cors.ts`, the one list of origins and the one
  answer's headers, `tests/mailfn.js`), and both read back.
- The report lists what the user does by hand: a dashboard setting.
- Every go-live report names the version the console shows exactly as the rail reads it (`{YYMMDD}.{commit}`), so the person can match it.
- Never ask for a URL, key or asset the repo or config already holds. Check
  `js/config.js` and `css/` first.

### Folder and file rules
- Never edit the user's root files: `ap01.html` and `accv-new.html`, the
  Jotform pages left (the user, 2026-11-12, every other removed: AP02,
  AP03, AP Dale, 3P form, e-Invoice info, interview quiz, sales
  programme). `index.html` and `404.html` are the portal's;
  `supplier.html` was retired for `/supplier/` (the user, 2026-10-18: "no
  longer in use").
- `drafts/` (holding the old Jotform verify page) is excluded from Pages.
- Portal pages are folders with an `index.html` and clean paths; never `.html`
  in a URL.
- New pages start from `docs/PAGE-TEMPLATE.html`.
- Two stylesheets, never more (second audit, item 19, 2026-10-18):
  `css/portal.css` holds the tokens and every rule a client page can meet,
  and is the only sheet a client page loads; `css/console.css` holds the
  rules only the console meets, loaded by `admin/` alone right after it. A
  rule moved between them keeps its place in the cascade (equal
  specificity and a shared property against a later rule of the other
  sheet keep it in `portal.css`); a console base and its own `@media`
  override share a sheet, the override after it (`cssguard`; 2026-10-18,
  the upload preview). One script per section, and the one-copy
  mechanisms above.
- Server code that is not a Supabase edge function lives in `workers/`, one
  folder per Worker, with a README.
- Setup docs live in `docs/` (`*-SETUP.md`, `S3-STORAGE.md`,
  `SIGN-IN-SECURITY.md`, …).
- State lives in the URL: `?s=`, `client=`, `campaign=`, `tab=`, `pane=`,
  `set=`, `new=`, `view=`, `open=`, `wc=`. A refresh lands where the person
  was. There is no path routing on Pages.
- The URL pushes history only for a record's pane; everything else replaces.
- A record (client, campaign, report) opens at its top; Back returns to the
  list's own scroll, and a refresh restores the record's. A list opens at
  its top on a visit or a refresh; a section reached from the rail is a
  visit, at its top however far its list was scrolled before
  (`visitSection`; the user, 2026-10-09; `tests/visit.js`); a press on
  the section already open (the rail, the tab bar, a mark at the rail's
  foot) goes back to its list, as an iPhone's tab bar does: the open
  record is left by its own Back, one at a time, never pressed twice, and
  a press on the list takes it to its top; the bell and search still open
  the record whose address they wrote (`railPress`; the user, 2026-11-19:
  "return to the list like iPhone"); only Back and
  Forward restore its scroll, and nothing is saved until the person scrolls (`bootScroll`,
  `personScrolled` in `js/admin.js`: bars drawn above a list while it
  loaded once saved a lower place each visit).

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
  - favicon: the wordmark set in the repo (`/favicon.ico`, `img/favicon-*`,
    `img/apple-touch-icon.png`, `img/icon-512.png`), never the monogram;
  - in the repo: `css/adspace-mark.png` (the monogram, the letterhead's
    alone), `css/SlateBook.TTF`,
    `css/SlateRg.TTF` (and `.woff2`), `css/SlateMedium.TTF`, `css/OPTIMA.TTF`.
  - `ADspace.png` and the website favicon were rejected.
- The issuer (`ADSPACE_ORG`): ADSPACE PLT, 202304002162, SST
  J31-2401-32100002, 61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100
  Johor Bahru, Johor, Malaysia, advertise@adspacestudios.com, (60)18 762 5233,
  adspacestudios.com. The bank line is blank.
  Every PDF reads the issuer from it and the agency's name from
  `agencyName` at the draw (the pen's wordmark, a quotation's lines, a
  sealed copy's Record page), the Service Terms address from
  `serviceTermsUrl`; never typed (2026-11-21: the demo's quotation printed
  ADspace's; `tests/demo.js`).
- Emails:  - support and issuer: advertise@adspacestudios.com (the client portal's
    contact line too);
  - every email the portal sends goes from `portal@sc.adspace.me` under its
    section's name (clients, suppliers, creators, careers, finance, team;
    `mail_senders`, `mail_sender(p_key)` through `_shared/mail.ts` `sender`;
    never a no-reply address, 2026-11-18, `2026-11-18-portal-sender.sql`;
    Supabase's own sign-in emails from the same address, set in its SMTP
    settings), and replies to a company mailbox, never a
    colleague's own address (the user, 2026-11-17): General
    advertise@ (clients, invitations to colleagues, all else), HR hr@
    (careers: every email to a candidate; the user, 2026-11-20), Accounts
    payable ap@ (suppliers, creators), Finance finance@ (invoices and
    reminders), e-Invoice einvoice@ (e-invoice submissions alone), Legal
    and compliance legal@ (named by /verify/ where a copy does not match,
    `verify_details` `contact`; 2026-11-20); the six are
    Settings, Messages: Reply-to mailboxes (`mail_boxes`,
    `mail_boxes_set`, `team.settings`, filed `team.changed` under Reply-to
    mailboxes), the pages reading them through `mail_senders_read`
    (`ADspaceDocMail.showSender`) and the Email log's From through
    `mail_log` `senders`;
  - every link an email carries is on adspace.me (the sending domain,
    `sc.adspace.me`), the foot's website `adspace.me` in its words too,
    and the wordmark at the head opens it (2026-11-19, Resend's check: a
    link off the sending domain reads as spam);
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
- The same error twice is a stop: name the cause, never try a third time.
- A fault between two pages, tabs or sides (a cookie, a pass, a lock) is
  fixed and tested in both orders, never only the one reported. A file that
  will not load is tested at its source before any page is blamed: ask
  `media-pass` as the page does and fetch the file with its cookies
  (refused without, served with, is a browser fault). The media pass broke
  this way twice (2026-10-12, 2026-10-15).
- Partial work is labelled partial, never reported as done.
- Every change adds value the portal keeps (the user, 2026-11-18: "every
  changes, every fixes must add new values … else … waste of usage, waste
  of limits, waste of time"): a fix goes to its cause in the shared
  mechanism, so the same fault cannot recur elsewhere, never a patch on the
  one screen reported; a change with no lasting gain is not made.
- A change asked of one list or screen is made on every one of the same
  shape in the same push (2026-11-10, the user: "why need me to point out
  one by one": the client logo asked of Content Review was owed to Video
  Scripts, Reports and Creator Campaigns too).
- A value only read is drawn as words at the field's height with no box
  (`.readfield` on a `p` or `div` is that, on an `.input` the shaded copy
  field): a shaded slab with its words on the edge, out of line with the
  fields under it, reached the user twice (Reports' Amount spent; Send
  email's From, Replies go to and To; 2026-10-18), so a sheet's screenshot
  is read for every value only read, and `tests/suppliers.js` measures it.
- Every mistake that reaches the user or the gate is written in the push
  that fixes it (the user, 2026-10-16: "note down all mistakes"): the rule,
  one line, in its loaded file; the story in `docs/DECISIONS.md` Part 3
  (what broke, why, how it was found).
