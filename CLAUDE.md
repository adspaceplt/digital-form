# ADspace Digital Portal — working rules

@DESIGN.md
@STANDARD.md

Static site, vanilla ES5 IIFE scripts, no build step, no framework, served by
GitHub Pages at digital.adspace.me (CNAME in the repo). Pages: `admin/`
(console), `client/` (client portal), `creators/` (the client's creator
selection), `creator/` (a creator's own page), `review/` (content review),
`script/` (a client's video scripts), `verify/` (public reference check), `card/` (a colleague's namecard), `quote/`
(a prospect's own quotation), `details/` (a client's billing details form),
`supplier/` (a supplier's details form; `supplier-details/` forwards to it), `/` and
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
  in the one loaded file it belongs to (behaviour, data, tests, workflow: here;
  look, components, copy, architecture: `DESIGN.md`; general standard,
  departures, open items: `STANDARD.md`). Its story goes in `docs/DECISIONS.md`
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
  - uxaudit and matrix have an hour each (`gate.sh`); a suite measuring
    what a page refits a frame later waits for the frames, never a fixed
    time (2026-10-30: geom read 144 segments 400ms after unhiding them).
  - A suite types a date from today (`todayKey()`, a day ahead), never a
    fixed day of the month: a fixed day is a passed date on any later day
    (2026-10-28: `work` typed the 27th on the 28th). A seed's day is
    Malaysia's, never `toISOString().slice(0, 10)` (the UTC day, yesterday
    before 8am here; 2026-10-29: `overview` read a booking 5 days late,
    not 4, after midnight).
  - A `cut()` of `schema.sql` always ends at the next banner.
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
  sign-in, ten seconds at most); a fixed sleep stays only where the thing
  measured is time itself.
- It prints one line per suite, ending in its wall time, then the total,
  and ends `gate: ok` or `gate: PROBLEM (n)`
  (also written to `$OUT`, default `/tmp/gate.txt`).
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
    built, `node --check` passes on each changed script, its touched
    screens are screenshotted and read (1280 and 390, both themes in the
    console; every screen a shared layout, CSS or component change
    reaches), and it merges at once on its own PR, never held for the next
    (one request, one release; the user, 2026-10-11). A suite runs by hand
    only while a fault is being found. A migration still runs `sql` and its
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
  findings stood behind one crash on Reports).
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
| Any `js/*.js` | `node --check` on each changed file, then the suites that cover it (map below) |
| Copy, markup a script draws, a state of one screen | The above, plus screenshots at 1280 and 390 of every touched screen (both themes in the console), each opened and read against `DESIGN.md`'s phone checklist. `SHOTS=1 node tests/uxaudit.js tests` writes the walk to `tests/walk/` |
| Shared layout, navigation, `css/portal.css` or `css/console.css`, a component | The above for every screen it reaches, plus `cssguard` (and `geom` for a layout change); `ui` waits for the daily run |
| A shared script: `js/api.js`, `js/admin.js`, `js/sheet.js`, `js/form.js`, `js/menu.js`, `js/state.js`, `js/group.js`, `js/cmdbar.js`, `js/words.js`, `js/chrome.js`, `js/confirm.js`, `js/ask.js`, `js/guide.js`, `tests/stub2.js` | The suites that call what changed (`grep -l`), plus screenshots where what it draws changed; `all` (with `ui`) once a day after the merges |
| `supabase/schema.sql` or a migration | `sql` and `policies`, plus the area's Postgres suite (`ops`, `perf`, `smsql`, `levels`, `trail`, `s3sql`, `confirmonce`, `meetmsgsql`). These run the file twice against a throwaway Postgres 16 and compare each canonical section with its migration byte for byte |
| A PDF (`documents.js`, `letters.js`, `smreport.js`, a perf print) | The area's suite, plus `pdfreal` and `pdfcases` (need `npm i pdfjs-dist@3.11.174 --prefix tests/pdfx`) |
| Once the day's requests are merged | `all` on main, `ui` included; its findings are the next batch |

**File → suites** (at least these; `tests/STATUS.md` has the rest):

| File | Suites |
|---|---|
| `crm.js` | crm, register, six, datefloor, phone, letter, scope, viewonly, leave, sales, waiting, engage, seenpage, ratecard, vic |
| Sales by (`clients.sales_by`, `client_row_seen_by`, the SALES BY section) | levels, scope, crm, vic, viewonly, clientparts, sql, then `ui` |
| VIC clients (`client_vic_set`, `vic_clients`, `ADspaceAdmin.vicTag`) | vic, crm, perms, search, overview, sql, then `ui` |
| `engage.js` (the record's Engagements) | engage, crm, reports, viewonly, then `ui` |
| `sales.js` | sales, crm, then `ui` |
| `ops.js` | work, keys, slide, cmdbar, phone, ops, reflink, take, leave, waiting, myclock |
| `js/clock.js` | myclock, then `all` (every script reads it) |
| `campaigns.js` | camp, prod, qc, undo, keyin, sch, camptime, six, race, reflink, loop, waiting, confirmpage, seenpage, seensql |
| `creators.js`, `decide.js` | cprod, bar, backup, client, canvas, confirmpage |
| `creator.js` | creator, cprofile, results, push |
| `push.js`, `push-sw.js`, `supabase/functions/push-send/` | push, pushcrypto, sql |
| `review.js`, `mockups.js` | canvas, newbadge, regress, sets, setdel, revise, pairs, seenpage, seensql |
| `portal.js` | portal, confirmpage |
| `documents.js`, `letters.js`, `register.js`, `verify.js` | docs, letter, hrshare, savename, lettersql, pdflibhash |
| `team.js` | team, perms, clientparts, levels, card, scope, perfui, viewonly, lettersql, depts |
| Departments (`departments`, `ADspaceAdmin.depts`, the DEPARTMENTS sections) | depts, perf, perfui, team, teamrec, settings, sql, then `ui` |
| `namecard.js`, `card.js` | card, then `ui` |
| `acts.js`, the act glyphs, a button's pending state | acts, then `ui` |
| a Delete anywhere, `confirm.js` | deletes, then the area's suite |
| Any ⋯ menu, a bulk bar, `ADspaceMenu.items` | menus, deletes, then `ui` |
| `handbook.js` | handbook |
| The Activity record (`loadActivity`, `ACTION_LABEL`) | activity, run, crm |
| `scripts.js`, `scriptpdf.js`, `script.js`, the VIDEO SCRIPTS section | vs, vssql, sql, then `ui` |
| `supabase/functions/script-draft/`, Write script, the SCRIPT WRITER section | vs, smsql, reports |
| `js/whatsapp.js`, `supabase/functions/wa-send/`, `supabase/functions/wa-hook/`, the WHATSAPP sections | whatsapp, wafn, waapprove, smsql, crm, perms, sql, then `ui` |
| `perf.js` | perfui, perfguard, perf, hrshare |
| `search.js` | search, then `ui` |
| `maintenance.js` | upgrade, sql, then `ui` |
| `announce.js` | announce, smsql, then `ui` |
| `notice.js`, the bell | notice, smsql, then `ui` |
| `overview.js` | overview, leave, then `ui` |
| `analytics.js`, the Analytics trends (`js/sales.js`, `js/chart.js` line bands) | analytics, overview, sales, levels, team, then `ui` |
| `supabase/functions/analytics-read/`, Analytics' Write with AI, the ANALYTICS READ WITH AI and ANALYTICS ALERTS sections | analytics, analyticsfn, smsql, abroadsql, mailfn, settings, sql |
| Public holidays (`settings.js`, the front door's hours, the My Work calendar) | holidays, sql, ops, seo, then `ui` |
| `reports.js`, `smreport.js` | reports, adsreport, audit, metaimport, smsql, engage |
| `passkey.js`, `captcha.js`, sign-in | passkey, signin, chrome |
| Overseas access (`team_place_ok`, `abroad_*`, the OVERSEAS ACCESS sections, `paintAbroad`, Settings' Overseas approval) | abroadsql, abroad, abroadrec, sql, settings, team, teamrec, then `ui` |
| the phone tab bar (`admin.js`, `menu.js`) | tabbar, visit, run, then `ui` |
| `refresh.js`, `admin/sw.js`, the manifest | pwa, phone, fileworker |
| `money.js`, the settings sheets | crm, letter, sgd, settings |
| `ratecardpdf.js`, the rate card versions | ratecard, crm, sql |
| `quotes.js`, `quotepdf.js`, the QUOTATIONS section | quotes, crm, sql, settings |
| `checklists.js`, the CLIENT CHECKLISTS section, `supabase/functions/checklist-draft/`, the CHECKLIST WRITER section | checklists, work, overview, sql, smsql, then `ui` |
| `details.js`, `details/`, the CLIENT DETAILS FORM section | detailsform, sql, seo, crm, then `ui` |
| `suppliers.js`, `supplierform.js`, `supplier/`, the SUPPLIERS section | suppliers, suppliersql, docs, sql, seo, then `ui` |
| `supabase/functions/supplier-mail/`, the SUPPLIER EMAILS section | mailfn, suppliersql, suppliers, settings |
| `js/docmail.js`, Send by email, the CLIENT DOCUMENT EMAILS section | docmail, clientmailsql, mailfn, quotes, letter, register, settings, menus, sql |
| `js/bukku.js`, `supabase/functions/bukku-sync/`, the BUKKU CONTACTS section | bukku, bukkufn, bukkusql, sql, then `ui` |
| Billing from Bukku (the BILLING FROM BUKKU section, `bukku-sync` `read`/`save`/`hold`/`nightly`) | bukku, bukkufn, entitysql, entities, crm, sql, then `ui` |
| Billing entities (`client_entities_list`, the BILLING ENTITIES section, `#crmEntities`), Bill to (the BILL TO section) | entities, entitysql, lettersql, letter, docs, crm, billgate, bukku, search, sql, then `ui` |
| The MEETING MESSAGE section, `clientMessage` (`js/ops.js`), Settings' Meeting message | meetmsgsql, work, settings, sql, demo |
| `js/invoices.js`, bukku-sync's `invoices` and `remind`, `_shared/mail.ts`, the OVERDUE INVOICE REMINDERS section | overdue, invoicesql, bukkufn, mailfn, suppliersql, sql, settings, overview, then `ui` |
| Tax codes (`tax_codes`, a line's `tax_code`, `ADspaceMoney.sstOf`), the TAX CODES PER LINE and TAX CODES CHOSEN AND DELETED sections | taxcodes, lettersql, sql, quotes, letter, crm, settings, bukkufn |
| `quote.js`, `quote/`, `supabase/functions/quote-request/`, the QUOTATION WEBSITE section | quotesite, quotes, sql, seo, then `ui` |
| `supabase/functions/meta-import/`, Import from Meta, the Report audit | metashape, metaimport, audit, smsql, reports, adsreport |
| `workers/links/` | links |
| `supabase/functions/caption-draft/`, Write caption | caption, smsql, reports |
| `supabase/functions/brand-analysis/`, the Brand pane's analysis, the BRAND ANALYSIS section | analysis, smsql, caption, crm, then `ui` |
| `supabase/functions/s3-sweep/`, the S3 SWEEP section | s3sweep, s3sql |
| `js/media.js`, `workers/video-convert/`, `supabase/functions/media-pass/` | vconvert, canvas, cprod, camp, mediapass, mediapassfn |
| the Short Links route | qr, shortlinks, run |
| `workers/db-backup/`, `.github/workflows/db-backup.yml` | dbbackup |
| `js/demo.js`, `demo/`, the DEMO ACCESS section, `tests/stub2.js` | demo, sql, settings |
| An email box, `ADspaceWords.emailOk` | emailbox, demo, portal, signin, detailsform, suppliers, quotesite, team |

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
  - text under 11px (`type`); a wrapped or clipped value; a control under its
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
- A new state (a second row, a file, an error) is seeded in the walk, because a
  pane that walks empty is a pane nobody has measured.
- The deploy is confirmed from the GitHub Pages workflow run for the merge
  commit (`pages build and deployment`, success). `curl` to the site returns
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
  never left for the user to review (2026-10-29).
- A word table holds one key a word: a new field's label takes a key of
  its own, grepped in the table first (2026-10-29: /quote/'s Planned
  commencement took `start`, and the opening page's Start button read it).
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
    Friday 10:00 to 18:00, redrawn every minute and on return to the tab;
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
  `client/`, `verify/`, `quote/`, `details/`, `supplier/`) names no share image, so WhatsApp reads it as its
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
  closed, confirmed, nothing to review, access denied), with the same words on
  every client page (`js/words.js`).
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
  A client page's `.topbar` keeps its glass there (2026-10-10), the root
  painted `--card` so the status bar takes white, never the grey page. The `theme-color` meta follows the console's own theme (the head script
  and `wearTheme()`); client pages are white.
- The console is a PWA:
  - `admin/manifest.webmanifest`, with scope and start `/admin/`;
  - wordmark icons in `admin/icons/`.
- The phone tab bar (`#tabBar`, js/admin.js; the user, 2026-10-09): on a
  touch screen narrower than a desk (a foldable open or shut, a tablet
  upright) and on any window at 640 and under, the one media query
  `ADSPACE_TABBAR` (the head script, which sets `:root.has-tabbar` before
  first paint) puts the first four sections the person may open, in the
  rail's order, at the foot with More (`#tabMore`) opening the rest above
  it; five or fewer take the bar whole. More lists only what the bar does
  not (`.is-tabbed`), then the rail's foot: one line of the build at the
  left, then Settings' mark and the Activity record's at the right edge
  (each named for a screen reader and on hover), at a desk as under the
  bar (the user, 2026-10-10: "activity log can go inline with version
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
  right"); a section More holds chooses More. My Work carries a red dot
  while Waiting for you holds anything (`ADspaceAdmin.waiting(n)`, from
  `paintWaiting`; read once on sign-in under the bar), never a profile
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
  Full Access (2026-10-22, SET2-11; 2026-10-29); its address falls back for anyone else. Eight groups
  (2026-10-11, the queue's task 46): Portal
  (Page availability, Announcements, Notices, Public holidays, Departments, Overseas approval, Health data kept), Clients (Follow-up limits, Details forms: a
  client's and a supplier's link alike, Analytics, Send by email), My
  Work (Due dates, Priority deadlines, Task reminders, Task numbering), Reports (Meta
  checks, Reach allowance, Ad benchmarks),
  Money (Tax and terms, Tax codes, Bukku), AI (AI usage and limits, AI prices), WhatsApp
  (Sent again: WhatsApp and
  emails, Website quotations: how many a day are told on WhatsApp), Performance
  (Months, Quarters, Bonus and trip, Commission at `team.performance` View,
  behind the master code; 2026-10-29), Templates (the user,
  2026-10-29: every template in one place: WhatsApp templates at WhatsApp
  Full Access, Supplier emails at Suppliers Full Access, Client emails, Overdue reminder,
  Meeting message, Document types, Task templates at `ops.workflows`, Rate card wording at
  Services Full Access); each setting has this one place: no Tax and terms
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
- The rail's foot names the build beside Settings' and the Activity record's marks (`#appVersion`,
  `.appver`, 11px mute): `v{YY.MM.DD} · {commit}`, the deploy's day in
  Malaysia and the merge commit's first seven characters (`v26.10.06 ·
  fb89b43`; the user, 2026-10-06: short, but which build), read from
  `/version.json`, which the Pages build writes through Jekyll
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
- Pull to refresh works only in the installed app, and only on a list with no
  record, sheet or menu open.
- Page availability (`js/maintenance.js`, `2026-10-29-page-availability.sql`;
  Upgrade mode a page at a time since 2026-10-29, the user: "Upgrade for
  /client page, Temporarily Unavailable for /admin, or selectively") is a
  cover, never a lock: the database keeps answering, but the quotation
  website covered makes nothing (`quote_website_create` `unavailable`).
  - A row of `app_flags` a page (`page:{key}`: admin, client, review,
    script, details, creators, creator, quote, supplier, verify; RLS on, no
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
  - Every portal page loads it after `api.js` but `/`, the 404 and `/card/`,
    so the front door, short links and every colleague's namecard (a
    printed QR's page) stay up; a page reads its own row by its address. A
    client page covers itself under its own bar (`.maint-cover`, z-index 39;
    the rest `inert`): Upgrade in progress / 系统升级中 (`W.maintTitle`;
    `maintText` The portal will be available again shortly. / 系统将于稍后恢复使用。;
    `maintBack` Expected back by {end}), or Temporarily unavailable / 暂时无法使用
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
    meters; `tests/upgrade.js`, `tests/smsql.js` §9ze).
  - The console's row covers it for anybody but an admin (the whole screen,
    with Sign out); an admin works on under `.upgradebar` (led by the amber
    dot, Console: Upgrade in progress until …, Turn off ending the
    console's alone). Settings, Portal: Page availability (`team.upgrade`,
    All pages available or n pages unavailable) opens `#pgSheet`: the ten pages
    by group (Team, Clients, Creators, Public), each its state over when and
    Edit; Select ticks several (a press on a row, or the tick for all), Set availability asking once for all. The
    question asks Availability (a segment), Starts, Ends (each a date beside
    its time, MYT; empty start is now, empty end waits, a time with no date
    is today's), a note, a 中文 note and Show Chat on WhatsApp (not the
    console's), saying under the choice what it does to that page, refusing
    in the sheet a window that does not end after its start and now; Undo
    puts each page back.
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
  segment), Add holiday and each row's Edit asking Date and Name
  (`public_holiday_save(p_day, p_name, p_was)`: `taken` naming the holiday,
  `bad-name`, `bad-day`), Delete in its ⋯ (`public_holiday_delete`, asked,
  no restore); each filed `team.changed` under Public holidays, from and
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
  twice.
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
    mute line under the field (`.asknote`, its `aria-describedby`).
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
  PDF the leaving mark after the words, Add and New the plus, Issue Letter of Offer the letter), given as the
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
  (`YYYY-MM-DDT00:00:00Z`). Days are counted on the calendar, never by a
  device's midnight. Left as they are: calendar arithmetic in UTC on day
  strings, the report PDF's days (`dateOf`: the Malaysian day held as a
  local midnight), and the spreadsheet and CSV importers' own date reading
  (the user, 2026-10-12: never touched). `tests/myclock.js` holds Tokyo and
  Los Angeles across a month's end.
- `js/copy.js` says Copied one way. The fallback is `execCommand('copy')` over
  an off-screen textarea.
- `js/icons.js` (`ADspaceIcons.svg(name, cls)`, `platform(key)`,
  `journey(words, at)`) is the client pages' one icon set (outline glyphs at
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
    `reports.entry`, `reports.text`, `reports.check`), offered as the screen
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
    own line (`data-narrow="860"`), and a sheet outside the console body
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
    off their default), then the count and the primary as a filled `+`; any
    view segment on a second row.
  - The bar's own selects are moved into `#cmdSheet` and back, never copied.
    Clear sets `data-default` (else the first option) and fires `change`.
    A field the page hides (`.cmdbar-find[hidden]`) takes its search mark with it.
    `data-nofilter` marks a select that is not a filter (`#workWf`,
    `#workScope`). `data-view` marks a view kept in the card (`#workGroup`,
    `#regSort`): never counted by the badge, never reset by Clear.
  - A second action goes behind `.cmd-more` beside a primary; a bar of plain
    actions keeps its first and puts the rest there once it has three (the
    Performance Months bar); a button marked `data-rare` (with its `data-g`)
    is behind the ⋯ at every width, the ⋯ drawn at a desk for it alone and
    taking the focus back from what the item opens (Compare groups, Bulk
    import; SHELL-5, 2026-10-22); each item carries its button's
    `data-need` and follows its `hidden`, and the ⋯ leaves when nothing in it
    can be pressed. Its glyph is the row ⋯'s three dots across.
  - The Filters sheet focuses its card, never a select (a focused select wears
    the ring, and iOS does not open a select that already has focus).
  - A select the page shows or hides while the card or sheet is open is
    shown or hidden there at once (a `MutationObserver` on its `hidden`).
  - A Filters button over only hidden selects is not drawn.
  - At a desk every bar's search is a 32px mark that grows into a 280px field
    and shuts on Escape or when left empty.
  - At a desk the filters are behind the same Filters mark (after the bar's
    last select), in a card hung from it (`#cmdPop`, `ADspaceMenu.pop`,
    Clear, Escape or a press elsewhere shuts it); a `data-nofilter` select is
    a view and stays in the bar at a desk.
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
  column's check refuses; 2026-10-17: `javascript://` passed the scheme test). A link typed
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
  shadowed name fails at run time, not at create time.
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
- A seed is a first run, not a running list.
  - Catalogue rows (the rate card, `detail`, Marketing and Sales) seed only
    into an empty table.
  - Admin alone is ensured on every run.
  - `on conflict do nothing` does not protect a deleted row.
- Every `ops_`/`perf_` write goes through a security-definer function. The
  tables carry a select policy only, or no policy at all (`perf_`).
- Supabase grants EXECUTE on every new function to `anon` and
  `authenticated`. A helper no page calls (only other functions do) revokes
  itself from `public, anon, authenticated` in the file that creates it;
  one used by a policy, a view, a default or an invoker function keeps
  `authenticated`. A helper restated later keeps its revoke, never the
  grant of its first definition (2026-10-18: three were reopened so;
  `tests/sql.js` reads each helper's last word in the schema).
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
  is answered `sst_pct` and the term percentages alone, what a client page
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
  (`ADspaceAdmin.editSettings`: From, then each figure, under its
  section's heading where a key names one, a change already set from a
  later day said under its field with its unit as the Settings row says it
  and Withdraw on it; each untouched figure shows the value in force on the
  From day, and only a figure differing from it is sent, so one typed back
  to the figure before a planned change withdraws it (2026-10-20, SET-1)):
  Follow-up limits, Tax and terms (`ADspaceAdmin.TAX_KEYS`, eight figures
  in three sections), Due dates (report and revision days), each the
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
- A merge leaves no conflict marker in the schema or a migration
  (2026-10-18: a `=======` line from #491 stood in `schema.sql`;
  `tests/sql.js`).

### Access
- Access is a level per section, **none < view < work < manage**, in
  `team_roles.access` / `team_members.access`. `allowed(section, level)` is
  every policy's predicate.
  - The page names them No Access, View, Manage, Full Access (`LEVELS` in
    `js/team.js`); the stored keys never move.
  - Select is view, insert and update are work, delete is manage, each a
    policy of its own: never one `for all` policy, since Postgres checks a
    delete against USING alone (one reading at View let View delete;
    `2026-10-08-delete-at-its-level.sql`, `tests/sql.js` §DL). A draft
    report's rows delete at Work, the report's own steps.
  - The levels are drawn on reversibility (add, edit and publish are
    reversible; a permanent delete is not), never on CRUD verbs.
- One user group per person (`team_roles` → trigger → `team_members`); no
  per-person switches. A policy on `team_members` never queries itself; it
  takes inserts and updates at Team Full Access (`team_insert`,
  `team_update`) and no delete from anybody
  (`2026-10-18-colleague-row-never-deleted.sql`).
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
  2026-10-15) and `team.analytics` (Analytics, 2026-10-25); each offers Manage
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
  (`PART_DESC`). Issue Letter of Offer from a quotation asks Quotations,
  Service lines and Letters at Work; Issue document on the record asks
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
  One rule, `client_row_seen_by(stage, owner, sales_by, level)` (over
  `client_row_seen`), held by a restrictive
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
  `clients_billing_guard` (skipping a cascade, `pg_trigger_depth() > 1`) and
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
- On the page, `may(key, level)` and one body class per section and part
  (`no-manage-review`, `no-work-clients-billing`) hide controls. Every control
  names its part (`data-need="clients.documents:manage"`, listed in
  `css/portal.css`). A tab with `data-part` draws only where readable, and the
  address falls back to Overview.
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
  Every notice an admin or a colleague is sent reaches it as any other
  (Notices, a form answered, a quotation request, an overseas request; the
  user, 2026-10-24: "System account acts same as other admins";
  `2026-10-24-admin-notices-system-account.sql`); task reminders do not.
  The mark is set only with no sign-in (the connector or the SQL editor;
  a signed-in insert sending it, a `removed_at` or an `erased_at` is refused
  by trigger `team_members_insert_guard`, `2026-10-18-new-colleague-added-plain.sql`);
  trigger `team_members_system_guard` lets only the account itself change its
  standing, access date, group, admin mark or email (`system-account`).
  Team shows it with a System tag and no ⋯ for anyone else.
  - The team list is never derived from `auth.users`. The cutover sweep runs
    only while `team_members` is empty and skips client contacts.
  - A wrong row is stood down (`active = false`), never deleted.
  - `no_team_client_overlap`: one address is never both a colleague and a live
    portal contact. Where a legacy overlap exists, `portal_clients()` returns
    nothing for a team address.
- The Team group panel (simplified 2026-10-10; layout only, the stored map
  and every check unchanged):
  - `#grSum` reads the panel back as one sentence.
  - Start from Admin / Manager / Staff / View only; a panel matching none
    reads `Custom: n changes from {nearest}` (`#grPresetNote`, a quiet
    fold) over the changes (`#grChanges`, shut until it is pressed),
    worked out and never stored; a preset chosen over a Custom panel asks
    first (`Start from Staff?` · n changes will be replaced., S7).
    Admin in Start from is the only way to make a group admin, offered to
    an admin alone, as an admin group in any select is (S6, 2026-10-24).
  - Each group row reads its access as phrases held whole (`team-part`), Edit
    on every row the colleague may change (none on the Admin group, nor on
    an admin group for anyone but an admin), a ⋯ holding Delete beside it
    on an empty group alone (TEAM2-11, TEAM2-14). Services offers No Access,
    View and Full Access; Leads and Past clients offer no level above
    Clients; a client part that follows Clients is greyed while Clients is
    No Access (N2, N3). The panel reads the sections and the Activity
    record's parts in the rail's order (N1).
  - The Dashboard's row first (`#grDash`, On / No Access, no heading; a
    preset leaves it On), filed `Dashboard: On → No Access`, read in the
    group's line, the sentence, the Custom changes and Compare groups.
  - The sections in the rail's chunks (Work, Internal; `CHUNKS`), one row
    each: the name, its segment at the right edge, the line for its level
    (`DESC`).
  - A section's parts sit under its Customise (n), n counting exceptions;
    shut, `#grDiff-{section}` names only those that differ.
  - The acts an admin alone took are Admin tools (`ADMIN_TOOLS`): switches
    under Portal (Upgrade mode, Announcements, Notices, Business settings,
    AI usage), then each under its own section in the rail's order (My
    Work, Creator Campaigns, Reports, Documents, Team; 2026-10-12). The My Work views (List, Board,
    Calendar) are not offered; a stored one is kept through a save.
  - Compare groups (the bar's ⋯, `#groupCmpBox`) reads every section and
    the admin tools for every group, read only.
  - Clients they see (`#grScope`, All clients / Own clients only) sits in the
    Clients fold; Own makes the preset Custom. Own clients only is never
    given with any Activity record access, a section or a tab (the record is
    not scoped): the sheet refuses it and trigger `team_roles_scope_guard`
    (`scope-activity`) holds it for every group but an admin's
    (`2026-10-10-letters-held-to-their-lines.sql`).
  - No preset below Admin opens Team, HR letters or performance reviews,
    their history included (`activity.team`, `activity.hr` shut; S5).
- User groups are Team's Groups tab (`tab=groups`, `#teamGroupsPane`), beside
  Members, Performance and Health (`tab=health`, an admin's alone); the
  strip is drawn only where two tabs show.
- The Admin group has no ⋯ and cannot be deleted. A group delete takes
  `.select('slug')` and names a refusal.
- Only an admin makes a colleague or a group admin, or changes an admin's
  group, access, access date, email or standing (`team_admin_guard`,
  `team_roles_admin_guard`, `admin-only`; 2026-10-17): Team Full Access is
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

### Console search (`js/search.js`)
- One control in the console head (`#searchOpen`, before the bell and the
  account);
  Cmd/Ctrl + K opens it anywhere, `/` only when no field has the caret.
  Neither takes over another open sheet or the confirm bar.
- The panel is a sheet through `js/sheet.js` (`#searchSheet`): under the head
  at a desk, a card above the tab bar the screen's height on a phone. The field is a
  combobox: the arrows move `aria-activedescendant`, Enter opens, Escape
  closes and focus returns to what opened it. Typing marks the sheet clean.
- It asks only the sections `may()` grants, each its own table through
  `js/api.js` under RLS; no schema. `ilike` inside `or()` with the value
  double quoted; `"`, `\`, `%` and `*` are dropped from what is typed.
- Five rows a section, 200ms after the last key, two characters at least; a
  sequence number throws away a late answer to an older query.
- A refused read drops its section only. Every read refused is `failLine`
  with Try again, never No matches.
- Groups run in the rail's order (Creators List after Creator Campaigns; Suppliers by name or Supplier ID from `suppliers_list`, opening `supplier=`; the Handbook's live files by title, opening it filtered; a colleague opens their record, `member=`; `_` is escaped, never a wildcard; 2026-10-22; Settings last, a row by its name or its group's from the page's own list (`ADspaceSettings.rows`), opening its group with its control focused, no read; 2026-10-27, SET-9);
  Video Scripts by code or title, opening its record (`script=`); Reports
  by title or white-label brand, opening the report (`report=`). Content
  Review, Video Scripts, Creator Campaigns and Reports also find a record
  by its client's name or code (the user, 2026-10-14: "AC182 … only shows
  me client directory"): the clients matching the query are read once a
  query (`clientRows`, which the Clients group draws from too) and join
  each section's filter as `client_id.eq` terms. What was
  said is found too (2026-10-11): a task by its brief (`Brief: …`) or a
  remark as it reads now (`Remark: …`; an edited one by its latest words, a
  removed one never), and Calls and visits (`clients.calls`) by its notes,
  next action or who it was with, under its client, opening `tab=calls`.
  Each group's label leads with its rail glyph (`ADspaceAdmin.glyph`).
  A row is the name, its code in the token face, one mute line; the match
  in weight, never colour. No recent searches, no explanatory copy.
- A result writes the record's address first, then `show()` (a content set
  through `ADspaceAdmin.restore()`). Letters of Offer open the client's
  Documents tab. The Creators List, Documents, Short Links, Services and
  Team open filtered by their own search field, its bar opened.
- A task number is read from `#WT01008`, `WT1008` or `1008` (`task_no.eq`),
  since `ilike` cannot compare a number.

### Clients (`js/crm.js`)
- Four bands (the user, 2026-10-08: Paused folds on its own):
  - Leads;
  - Clients (active);
  - Paused;
  - Past clients (shut by default, remembered, keeping their count).
  - Each band draws thirty, then Show N more.
- Columns: Client, Stage, Industry, Person in charge, Last activity, chevron.
  - No Value column and no value on a heading.
  - Rows run newest Client ID first (digits as numbers), unnumbered after,
    newest first.
  - The row is one `<button>` with nothing nested.
  - The client's logo leads the name cell (`.cl-mark`, 32px, 28 on a phone;
    the record head's white disc, initials only while none is held or where
    it fails to load), and the Client ID sits under the name in the token
    face and is searched.
  - On a phone the row is two columns: name over meta, and the chip over the
    age in a fixed 120px track, top aligned. The meta omits what is not known,
    never showing a bare currency sign.
- Last activity (`loadLastSeen()`, one read: `client_last_activity()`,
  invoker, the newest of each kind a client): the newest of a logged call or visit, a
  stage move (`stage_since`; `Added` while it has never moved), or a document
  issued. The date sits over a mute word for which one.
  - A refused read is left out.
  - A future date never counts.
  - Nothing reads as a mute em dash.
- The Client ID (`^[A-Z0-9]{2,12}$`, unique) is load bearing: the letter
  serial uses it. A client becomes Active only holding one (the user,
  2026-10-18: a lead may come to no deal): the move asks for it, the next
  AC number offered (`client_code_next()`, one past the highest across
  every client, as wide as it), and both go in one write; trigger
  `clients_active_code` refuses Active with none (`active-needs-code`;
  `2026-10-18-client-id-at-active.sql`). A Letter of Offer before Active
  still asks for one at its Reference.
- The slug is set once from the name, never follows a rename, and a clash is
  numbered, a clash only the index sees (a client outside the colleague's
  scope; every Chinese name reads `client`) taking the next number, never
  the database's words (2026-10-19). It lives only in the console address (`clientByKey()` resolves a
  slug or a UUID by shape) and never grants access.
- Stage clock: `stage_since` and `stage_log` are stamped by
  `clients_stage_clock`, and only a real move restarts it. After a move the row
  is re-read (`refreshClient`). The move is tagged `client.stage`.
- Paused and Past say why (`2026-10-04-client-leave-reason.sql`): the stage
  select asks first (`askLeave`: Reason, required, of Budget, Results, Moved
  in-house, Business closed, No reply, Other; an optional note; the client's
  open tasks counted by `client_open_tasks`, "3 tasks are still open. They
  show as urgent delivery in My Work."), the select holding its stage until
  the answer. `clients.stage_reason` / `stage_note` ride the update and the
  clock keeps them on that move's `stage_log` entry; a move into Paused or
  Past without one is refused (`stage-reason`), and a move anywhere else
  clears both. The Timeline names the reason under the move, a pen at
  Manage: the reason and note are changed later (`ADspaceConfirm`, that
  entry of `stage_log`, and `stage_reason` / `stage_note` while it is the
  stage now; `.select('id')`, filed `client.edited` from and to); the
  activity row carries it. `clients_stage_notice` tells each owner of the client's
  open work once (`client_left`, "{client} moved to Paused · 3 open tasks to
  deliver", opening My Work).
- No Sales view (removed 2026-10-12, the user: "Priority is the dashboard";
  what it held that the Dashboard did not moved there); an old
  `view=sales` address opens the list. `js/sales.js` is the figures alone
  (`ADspaceSales.figures`, `reasonWord`), read by the Dashboard from each
  client's `stage_log`, `stage_reason`, `source` and `owner`: Won is a
  lead's first move to Active (or a client keyed in Active), Lost a lead to
  Past never Active, Churned Active to Past (Lost and Churned once a client
  in a period, only where the period's last move leaves it in Past),
  Resumed Paused back to Active, a Win-back Past back to Active; Committed
  monthly value a month of each confirmed monthly line (a term over one
  month, started by today) by market, never added across currencies.
- The follow-up limits (`staleH(c)`, settings `lead_followup_hours` 48 and
  `proposal_followup_days` 21, calendar days; a VIC client's
  `vic_lead_followup_hours` 24 and `vic_proposal_followup_days` 7,
  `2026-10-15-vic-followups.sql`, under VIC clients in the same sheet):
  - Lead and Proposal sent read Overdue past theirs;
  - Contacted has no limit.
  - An over-run stage reads "N days · Overdue" in red, and the group head
    counts them.
- Intake: Brand name (the trading name; the registered name belongs to Billing),
  Source, Salutation (the contact sheet's own list; 2026-10-14), Contact person, Phone, WhatsApp username, Email, Enquiry, Owner,
  Industry, Market, Urgency to commence (`clients.commence`, blank until
  asked; Within 3 months, 3 to 6 months, More than 6 months). After intake the enquiry is edited like any other fact, and a person
  becomes a row in Contacts. Under Own clients only the Person in charge is
  fixed: the colleague keying a lead holds it. Sales by (`crmSalesBy`, More
  details) is the colleague keying a new lead, changed only at Clients Full
  Access (trigger `clients_sales_by_guard`, `sales-by`), filed from and to,
  and read under Details. A contact refused after the
  client is made is said, and what was typed waits in the contact sheet on
  the new record (2026-10-19).
- The Clients list, and every read of all clients (`bridge.active`,
  `uniqueSlug`, the Dashboard), is read a thousand at a time
  (`ADspaceAPI.readPages`, the one copy; 2026-10-19); past its cap it
  answers `too-many`, never a list cut without a word (2026-10-22, BE-14).
- A client's address outside the colleague's reach (or gone) lands on the list
  with `#crmListMsg` saying so, never silently.
- The record head `.rec-id` (`auto minmax(0,1fr) auto`, centred):
  - Mark: `logo_url`, or `initialsOf()` (two characters of a Chinese name; else
    the first letters of the first two words that start with a letter).
  - The name and its meta (the main contact's preferred language and the person
    in charge; each left out when unknown).
  - `.rec-ctl`: Log call (`#crmLogCall`, Clients: Calls at Work, the phone
    glyph alone on a narrow pane, given to the pane's own head on Calls and
    visits, and gone from a head under 300px (`data-narrow="300"`, a 320
    phone); 2026-10-11), the stage select, then one ⋯ holding Edit and
    Delete (the item carries `data-need="clients:manage"`).
  - Phone (`.is-narrow`): `"mark . ctl" / "who who who"`.
  - The month line (`#crmMonthLine`, 2026-10-08), under the meta for an
    Active or Paused client and a reader of My Work: the month whose span
    holds today, `n of N done` (`ops_engagement_counts`), the overdue count
    and Report due (the span's end plus `report_due_days`) where the month
    owes one, led by its dot (red with any overdue, green when all done,
    else amber); it opens the client's Months view. It is read from the
    Engagements pane's answer, never a read of its own.
- Panes (`tab=`, pushed to history; Overview stays out of the address):
  six tabs (the user, 2026-10-15: the strip "gradually increasing"), each
  showing its parts one under the other (`#crmPanes`, 24px apart), each
  part keeping its heading and its own address (`tab=billing` opens
  Account on Billing, so every older link lands):
  - Overview; Calls and visits (`tab=calls`, Clients: Calls, never behind
    the Activity record's access; 2026-10-11); Engagements (the months,
    drawn for a client engaged now or before or holding anything, then
    Checklists; the tab stays for a lead's checklists); Services
    (Quotations and Service lines, with Requests once a contact has portal
    access or a request exists, then Documents, so a letter is issued where
    its lines are; the user, 2026-10-19: "when creating documents it has to
    go into below Account … extra steps"); Brand; Account (Contacts,
    Billing); a tab of several parts is drawn where any is readable;
  - the Activity record (the Record of changes, `tab=activity`) has no tab:
    the rail's Recent activity opens it (View all, `#crmLogAll`), the strip
    then marking none.
  - There is no Work pane. `tab=work` lands in My Work's Months view
    (`view=months&wc=slug`); there is no Reports pane, and `tab=reports`
    lands on Engagements.
- Below 1100 the rail splits. `.rec:not(.cportal) > .rec-rail` is
  `display: contents`, and the blocks take `order`:
  - Next action, the billing gate and Profile come before the tabs.
  - `.rail-after` (Timeline, Details, Recent activity) follows the pane.
- `.rec` is `grid-template-rows: auto 1fr`.
- Overview:
  - One `.ovcard` in the tabs' order: Calls and visits, Contact details,
    Services, Letters; a section whose part the reader may not open is not
    drawn, and one whose read was refused reads Could not load., never empty
    (`ovFailed`, 2026-10-11).
  - Built only from what the record has already loaded.
  - Enquired lines are left out.
  - An empty section says so in one line.
- Rail blocks (`.railblock`, `.railtitle` at 15px):
  - Next action: a written `next_action`/`next_at` beats `nextStep()`; a
    written one opens Calls and visits, where it is done. Its date is said
    there alone (the Timeline holds no Next follow up).
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
    - Client since is the first stage's start, opened on its Malaysian day
      (`dayOf`).
    - A stage never begins before the one before it, and no date is in the
      future.
    - One save writes `stage_log`, `stage_since` and `created_at` (a move's
      reason too), only over the row as read (`.eq('updated_at', …)`,
      stamped by trigger `clients_touch`): a move made meanwhile reads "Not
      saved. This changed since it was opened, and has been read again.";
      where only another column moved, the write goes again once
      (2026-10-19).
- Billing required before Active:
  - registered company name (capitals);
  - BRN;
  - billing contact (a select over Contacts: Primary contact · {name} first,
    held empty so it follows the main contact, which `issue_letter` answers
    the same way; another contact chosen stays, and trigger
    `client_contacts_bill_follows` lets go of one that stops being the main
    contact or is removed; 2026-10-13);
  - billing address.
  - Optional: old registration no., TIN, SST no., finance email.
  - Bill in (`clients.bill_sgd`, `2026-10-22-bill-in-rm-or-sgd.sql`; the
    user, 2026-10-22: "follow RM as usual unless and optionally choose to
    have it in S$"): RM / S$ on Billing for a Singapore client alone, RM
    by default, at Clients: Billing Work (`clients_billing_guard`), filed
    from and to; `client_bill_market(market, sgd)` is SG only where both
    hold. `get_portal`, `get_campaign` and `sm_report_snapshot` send
    `bill_market`; `issue_letter` keeps it as the letter's `market`, and
    in `bill_to` the client's market and, billed in RM, `fx_sgd` then in
    force, which the letter reads under its figure in bold (Approx.
    S$ …); `bukku_prepare` sends its currency. The market stays the
    number's, the registration's and Meta's taxes'. A version published
    before reads its market as drawn.
  - Trigger `clients_active_billing` refuses the move into Active while the
    registered name, BRN or billing address is empty or no billing contact
    (chosen, else a live main contact) stands (`active-needs-billing`,
    `2026-10-19-clients-audit-fixes.sql`); a client already Active keeps
    its place.
  - Billing entities (`2026-10-29-billing-entities.sql`, SQL Editor; the
    user, 2026-10-29: "one client several entities, however allow to set
    the main"; a company may bill several brands): `billing_entities` and
    `client_entities` (RLS on, no policy, no grant), one main a client. The
    main entity is the client's billing columns, kept equal both ways by
    trigger (`clients_entity_sync` carries only what a write changed;
    `billing_entity_put` carries an entity to every brand it is the main
    of, a billing contact only to the brand it belongs to), so every reader
    of a client's billing reads its main entity unchanged. A brand's billing
    contact for an entity is its own (`client_entities.bill_contact_id`, one
    of its contacts), else the entity's shared one (any brand's), else its
    live main contact (`entity_contact(p_entity, p_client)`; the letter's
    Attn, the overdue reminder and the pane read it; Bukku's billing person
    stays the shared one); where the entity bills other brands the sheet
    asks Use for every brand this company bills (`#crmBillShared`, ticked
    while the brand has none of its own; `client_entity_contact(p_client,
    p_entity, p_contact, p_every)`, `held` for the shared one Bukku holds),
    and a brand's own Billing sheet writing its contact sets its own
    (`2026-10-31-entity-contact-per-brand.sql`; the user, 2026-10-31: "Could
    be shared or different contact for different brand"). Billing reads the
    main as before (headed Primary billing entity where there are others,
    Also bills naming each other brand, opening its Billing), then Other
    billing entities (`#crmEntities`: its count and Add entity, each one
    row shut by default, its name over its registration no. and billing
    contact, a press opening its facts in place, remembered under
    `client-entities`, one just saved or added open; its ⋯ Edit, Make
    primary, Remove; the user, 2026-10-29: "how long is this"), read on each visit (`client_entities_list`); Add
    entity (`#entAddSheet`, Find a company) finds one held, every word
    typed in its registered name or the name or Client ID of a brand it
    bills, or its BRN digits (`billing_entities_find`, ten, only those
    billing a client the reader sees, or none; In the portal), a customer
    Bukku holds by every word of its name or its registration no.
    (`bukku-sync` `contacts`, read once as the sheet opens and found on
    the page, eight, held as Overdue invoices are, at Billing Work; In
    Bukku, one the portal holds by BRN left out, one the portal links
    marked Linked in the portal; Bukku not connected is left out, Bukku
    failing said in one line), which Add adds in one press (the user,
    2026-10-30: "just add and pull from Bukku"; `bukku-sync` `adopt`,
    `client_entity_from_bukku`: the entity made from Bukku's details and
    linked to its contact in one transaction, then held, so Bukku holds
    it; a contact the portal already links adds that entity, nothing
    made; `taken` where a supplier holds it; Undo where it happened, none
    for the primary), or opens Billing's sheet as New billing entity (no
    SST on quotes, no currency, no details form), whose Save reads Create
    in Bukku where Bukku answered the sheet: the entity added, then made
    in Bukku (`send` with `guard`), or linked to the customer Bukku holds
    of its registration no., never a second; a refusal leaves it added,
    said on the line, Link to Bukku on its band; Clients: Billing at Work, the
    client in scope (`client_entity_add`, `_save` with `p_expected`,
    `_main`, `_remove`: `no-name`, `bad-email`, `bad-contact`, `stale`,
    `taken`, `main`, `held`: an entity Bukku holds is saved to Bukku, never
    by the portal; the page then reads its band); an entity removed from
    its last client stays reachable to that client's team alone
    (`billing_entities.orphan_of`, `billing_entity_reached`), so Add entity
    finds it again; a BRN held is never made twice (`brn-taken`, the
    question offering that entity), two clients holding one BRN before
    stay two, merged by hand; Make primary and Remove (never the primary) offer
    Undo where they happened; an entity removed from this client and billing
    none is listed on asking (Show n removed entities,
    `client_entities_removed`) with Restore (never asks) and, at Clients:
    Billing Full Access where no letter or Bukku link names it, Delete in its
    ⋯ (`client_entity_delete`, the registered name typed back, no restore;
    `not-removed`, `bills-others`, `bukku`, `on-letter`, `bad-name`;
    `2026-10-31-billing-entity-delete.sql`, the SQL Editor's). Filed
    `client.billing` naming fields alone.
    Console search finds a client by an entity billing it (Billed by …,
    opening Billing). Bill to (`2026-10-29-bill-to.sql`): with two
    entities or more, the Letter of Offer sheet (`#pickBillTo`) and a
    client letter's Issue (`#docBillTo`) ask which, the main first and
    chosen; `issue_letter` takes `p_deal.entity` (an entity of that client,
    `bad-entity`; its name, BRN and address held, `entity-incomplete`) and
    prints its registered name, numbers, address and billing contact,
    keeping `bill_to.entity_id`; none chosen is the main as before. A
    quotation prints no billing. Each entity is its own Bukku contact
    (Bukku, below), and a brand's unpaid invoices and reminders cover every
    entity billing it (Overdue invoices, below).
  - The details form (`2026-10-14-client-details-form.sql`, `js/details.js`;
    the user, 2026-10-14): Billing's Request from client (the user, 2026-10-29; Details form until then, a supplier's Request from supplier) makes a link
    (`client_details_link`, Clients: Billing at Work; Copy link, Preview, the
    ⋯ Reset link and Close link, each asked; `client_details_close` ends the
    open form now, `no-link`, filed, `2026-10-31-client-details-link-closed.sql`)
    to `/details/?k=` with no sign-in, open
    `details_form_days` (14, Settings: Clients, Details form). The client's page reads the
    brand and closing day alone (`client_details_read`) and sends the
    answers once (`client_details_submit`: registered name in capitals, BRN,
    old BRN, TIN, SST no., billing address, finance email, the billing
    contact's salutation, name, mobile and email; refused by field), telling
    the team at Clients: Billing Work whose bands and client scope reach the
    client (kind `client.details`, opening Billing), filed under the actor
    Details form with the typed name in the detail. A move into Active or
    Past ends every link still open (trigger `clients_details_close`), and a
    Past client's link opens nothing (2026-10-22, BE-6). The Active gate's Billing sheet offers it in one line
    (`#crmBillAsk`: Create link, Copy link, or Use details once answered). The answers wait on Billing (`client_details_state`),
    one that differs from what Billing holds reading held → sent (2026-10-20, DTL-1): Use
    details fills the Billing sheet and its own Save takes them in
    (`client_details_used(p_id, p_client)`, refusing another client's form;
    opening Billing forgets an earlier Use details), picking the billing contact the client sent
    where Contacts holds them (email, else the number's last nine digits);
    while Contacts does not, the form keeps showing them, Not in Contacts,
    with Add as contact, before and after Use details, which opens Contacts
    prefilled and makes the contact saved the billing contact. The
    form never writes the record. `client_detail_forms` has RLS on, no
    policy, no grant. An open link offers Copy message (2026-10-31: the
    link in a formal message to the billing contact, else the primary
    contact, with its closing day); answers received carry a ⋯ of Request
    again (asked: they are set aside and a fresh link made,
    `client_details_link`).
  - Billing and Brand read first; Edit opens `#crmBillSheet` /
    `#crmBrandSheet`. The Active gate opens the sheet on the first missing
    field, and its Save, billing then complete, carries on into the move
    (the Client ID asked, the head brought back into view); Cancel forgets
    it (2026-10-20, CLI-6). A Save while that move still lacks a required
    field keeps the sheet on it and the move asked; a Save that changes
    nothing writes and files nothing (2026-10-27, CLI-13).
  - The billing columns (registered name, both registration numbers, TIN,
    SST no., billing contact, finance email, billing address) are withheld
    from the table by column grants. They are read only through
    `client_billing(p_ids)` (`ADspaceAPI.withBilling`): the values at
    Clients: Billing View, the name and address at Documents Work
    (`register_may('client', 'work')`), and `billing_missing` alone at
    Clients View, so the gate still names what is missing; it names a
    missing billing contact too (`bill_contact_id`, as
    `clients_active_billing` holds it), which the record reads until its
    contacts arrive, so the gate never changes under the reader
    (2026-10-27, `tests/billgate.js`).
  - Every read of `clients` names `ADspaceAPI.CLIENT_COLS` or its own list,
    never `*` (refused). A new column is granted by running the CLIENT
    BILLING COLUMNS section again; `script_key` stays withheld with the
    billing columns. The stand-in refuses `*` and every
    billing column, top level or embedded.
- Checklists (`tab=checklists`, `js/checklists.js`,
  `2026-10-15-client-checklists.sql`; the user, 2026-10-15: the team's New
  Client Onboarding and Pre-Advertising Checklists, ver. r1.1-26, once per
  client): one `client_checklists` row a client and kind (RLS on, no
  policy, no grant), the template copied in when it is first written
  (`checklist_template`). The pane lists both, `list=` opening one, on a
  record already open too, and kept in the address (2026-10-27, OVW-12) (its
  Back line and head brought under the bar, never below the fold), read
  first (the user, 2026-10-15: "the checklist is coming back in the wrong
  design"): a head card (title, version, state, Write with AI, Preview PDF
  (a tab opened at the press; PDF on a tight pane), Download beside it (no ⋯; 2026-10-22, CLI-7),
  the facts), then a card a section where a tick is pressed in
  place (its note and who and when under it) and every other answer reads
  as a fact (Not set where empty), a table as a table; no field stands open
  on the pane. A section's Edit (`#ckEditSheet`) opens all its answers in a
  sheet: a tick's Notes and Not applicable, words as a field, a choice as
  chips, a table a row at a time; Save sends only what changed. A platform
  section Not applicable (`client_checklist_set`, Clients Work,
  client scope; `locked`, `bad-item`, `bad-value`, `too-long`; filed
  `client.edited`); the pre-advertising one prefilled from the record (the
  registered name at Clients: Billing View, else the brand; the newest
  quotation at Clients: Services View; the brief's competitors, the
  confirmed Brand analysis's SWOT; `checklist_prefill`), the registered
  name and the quotation never stored: worked out for each reader on every
  read (2026-10-19, audit 3). Mark as prepared
  (`incomplete` with what is left), Sign off by a colleague who neither
  prepared it nor ticked or answered any item (asked; `own`; a tick keeps
  `by_id` beside its name, an answer or note `set_by`, an older tick read
  by its name, `checklist_filled_by`; the read's `filled_by_me` hides the
  button; 2026-10-19, audit 13), Send back, and Reopen at Manage (asked; the signed copy kept in
  `history`) through `client_checklist_step`; signed, it locks and ticks
  the month's check of that key (`ready`), and Reopen unticks it. A month's
  check is never ticked by hand (`ops_engagement_set_check` refuses
  `use-checklist`); My Work shows it with Open on the client's checklist.
  Download draws its PDF (FOR INTERNAL USE centred on the paper). The
  Pre-Advertising Checklist is ver. r1.3-26 (`2026-10-15-checklist-r13.sql`;
  a checklist started before keeps its template): Campaign Details asks
  Primary Destination and Monthly Budget; Meta Campaign Setup holds
  Campaign Setup, a table of Item, Details, Audience, CTA and A/Spend (kind
  `table`, twelve rows, 400 a cell, Add row and a row's ×, saved whole);
  Country, Ad Re-Targeting and Tracking (Pixel / Analytics Connection, Lead
  Destination, Tracking Relevance, Ads Reporting Schedule) are written
  answers, as the team writes them (the user's three checklists,
  2026-10-15). `checklist-draft` writes to that standard (`SYSTEM`: short
  working notes, approx., TBC, → to where a button leads, ad sets funded
  in order with MONTH 2+ / ON HOLD, the lead estimate, Budget note); the
  PDF draws → in the Chinese face, which holds it.
  Write with AI on it (Clients: Checklists Work, an open checklist; the user, 2026-10-15)
  asks up front the monthly ad budget, the objective, where the ads send
  people, the ad account and notes (kept under
  `adspace-checklist-inputs:{client id}`); with no confirmed Brand
  analysis the same press runs one first (the user, 2026-10-15: never Brand
  first and back again), read in `#ckBaSheet` and confirmed there with the
  declaration (filling the brief), then `checklist-draft` reads the
  confirmed Brand analysis (`no-analysis` without one), the Ad benchmarks
  and the linked Meta accounts and proposes every field but the ticks,
  following the playbook's Meta rules (the client's website sent as
  whether it has one, never its address); nothing is written until the
  colleague keeps the ticked proposals in `#ckAiSheet` (what a field holds
  now said under it), declares them read (`ADspaceConfirm.ai.declare`) and
  each is saved as if typed, Undo where it happened. Its own count
  (`ai_checklist_claim`: `checklist` 10, `checklist_admin` 20), priced and
  set on AI usage; the client's name goes as {brand}. Not signed off on
  an Active client, unless the month marks it Not needed, is a Dashboard
  Needs attention row (`client_checklists_due`), only where it was started
  in the portal or the client first became Active from 15 Oct 2026 (MYT):
  one onboarded before was checked on paper (the user, 2026-10-19;
  `2026-10-19-checklists-from-portal-onboarding.sql`). A client's passwords are
  never kept: the credentials item is a tick. The templates are edited in
  the migration, not in Settings, for now.
- Meta links (`2026-10-08-meta-links.sql`, `meta_links`, RLS on, no
  policy, no grant): a client, and each white-label brand, links ad accounts
  (up to 20), one Facebook Page and one Instagram account, each Meta's id and
  name, picked in `#crmMetaSheet` from `meta-import` `assets` (Clients: Brand at
  Work), never typed; a link Meta no longer shows stays offered. Read first
  on the Brand pane (`#crmMetaRead`, Edit at Clients Work; a brand's from its
  ⋯, Meta accounts); `meta_links_save` (Clients Work, the client in scope at
  Work, `bad-brand`, `bad-asset`; writes through insert on conflict, so two
  first saves at once both stand, 2026-10-19) files `client.brand` from and
  to, a brand's under its name; `meta_links_list` at Reports or Clients View.
- The content brief (`clients.brief`, `2026-10-10-client-brief.sql`; the
  user, 2026-10-09: "content not interesting"): one object of short texts
  (audience, pains, pillars, tone, avoid, competitors, hooks; 8,000
  characters in all), read with the record alone, read first on the Brand
  pane (Content brief) and edited in the Brand profile (Audience and pillars;
  Voice and references), sent only where a part changed, filed
  `client.brand` by the parts' names. Write with AI reads it and the brand
  notes for captions and scripts, masked as the rest (`{brand}`,
  `{handle}`); never a competitor named back.
- Write with AI waits for the brand (`ai_brand_ready(p_client)`,
  `2026-10-12-ai-needs-the-brand.sql`; the user, 2026-10-12): a caption or a
  script needs the brief's Audience, Content pillars and Tone of voice and a
  confirmed Brand analysis; reports are not held. The press asks nothing
  until then: one `.msg.warn` line under the button names what is missing,
  with Open Brand where the colleague reads Clients
  (`ADspaceAdmin.brandGate`, `brandSay`), and `caption-draft` and
  `script-draft` refuse the same (`no-brief` with `missing`,
  `no-analysis`) before a use is counted. Run analysis asks no brief
  (2026-10-15): it needs something to read, the website, a handle or a
  linked Meta account (`no-source`), and writes the brief itself
  (`analysis.brief`); confirming a version fills each empty part of the
  brief from it (`2026-10-15-analysis-fills-brief.sql`, at Clients Work in
  scope; a part already written is never replaced; filed `client.brand`,
  said on the Undo line).
- Brand analysis (`2026-10-10-brand-analysis.sql`, `brand-analysis`; the
  user, 2026-10-10: "deep analysis of this clients … target audiences,
  SWOTs, advantages disadvantages, ads targetting"; "anyone could run it"):
  the Brand pane's last read group (`#crmAnalysis`), Run analysis then Run
  again (the AI mark; asks first: what it reads, analyses left today, notes
  kept under `adspace-analysis-notes:{client id}`), for any colleague at
  Clients: Brand View on a client in scope. It reads as the caller the record
  (brief, notes, services), published reports, My Work's post results and,
  where `meta_checks_on()` and the client links Meta, six months of
  Instagram and Facebook posts, Instagram followers by age, gender and city
  and the ad accounts by objective and age, with Claude's web search
  (`web_search_20260209`, eight at most) on the brand's own pages and its
  competitors'; sections Brand positioning, Target audiences, SWOT,
  Content, Ad targeting, Sources (pages the search returned only), "A
  starting hypothesis to test" where the client has no reports, results or
  Meta posts. The team's client analysis playbook (2026-10-15): Run
  analysis asks up front a monthly ad budget, the main objective and the
  ad account (New, Mature; kept in this browser under
  `adspace-analysis-inputs:{client id}`), never a question back; the
  research checks the entity and its parent group first, labels each fact
  Official, Listing or Third party and marks one its sources disagree on To
  confirm, places a business by what buyers know, and maps competitors
  (direct, indirect, legacy, disruptor); a version holding them leads with
  What it is, What works and what is weak (trust leaks), Where ADspace fits
  (channels first, next, later; what to fix before paid traffic; the
  commercial angle), and ends with To confirm with the client and Next
  question, Ad targeting adding Budget realism against the Ad benchmarks
  (sixteen Business settings, `bench_*`, `2026-10-15-ad-benchmarks.sql`:
  cost per result by kind, impressions, the ad spend share of a budget
  83.75%, RM 30 a day an ad set), read by the function as the caller; an
  earlier version reads as it was. **The brand name goes to Claude for this function alone (the
  user, 2026-10-10, for the web research); never a contact, and an email or
  number typed into the words is masked.** `brand_analyses` (RLS on, no
  policy, no grant) keeps every run as the next version
  (`brand_analysis_save`, filed `client.brand`), listed newest first with
  who ran it (`brand_analyses_list`); a draft until Confirm asks the AI
  declaration (`brand_analysis_confirm`, Undo, then Withdraw confirmation in
  the ⋯), and a version's ⋯ Delete at Clients: Brand Full Access (asked, no
  restore; `brand_analysis_delete`, refused `in-use` for the latest
  confirmed version; `2026-10-31-brand-analysis-version-delete.sql`, the SQL
  Editor's). Only the latest confirmed one reaches Write with AI
  (`brand_analysis_brief`: positioning, audiences' pains and motivations,
  pillars) for captions, scripts and report drafts, masked as the rest.
  Counted apart (`ai_analysis_claim`: `analysis` 3, `analysis_admin` 10),
  its web searches kept (`ai_drafts.web_searches`) and priced at
  `ai_price_search` (US$10 a thousand, a Business setting). The response is
  streamed with a space every 8 seconds while it runs (140 seconds at most).
- A restricted account (`2026-10-10-account-restricted.sql`; the user: "account
  restricted"): `clients.restricted_platform` (Instagram, Facebook, TikTok,
  rednote, Other account), `restricted_since` and `restricted_note`, all or
  none, read with the record alone. The record's ⋯ Mark restricted
  (Clients Work; asks the platform, since when, a note) and the rail's red
  block (`#crmRestrict`, `.railgate.is-restricted`) with Clear (never asks,
  Undo where it happened), each filed `client.edited` from and to. The
  Dashboard's Clients tab lists them (Restricted accounts, the longest first).
- VIC, a Very Important Client (`2026-10-15-vic-clients.sql`; the user,
  2026-10-15, "VIC … Very Important Client not Person"): internal alone,
  never on a client page, link page or PDF. `clients.vic_at` (the day it
  became VIC), `vic_by`, `vic_note` (300) are written only by
  `client_vic_set(p_client, p_on, p_note, p_since)` (`clients.vic` at Work,
  the client in scope at View; `denied`, `not-found`, `too-long`,
  `bad-date`; filed `client.edited` from and to); trigger
  `clients_vic_guard` refuses any other write (`vic-function`). The console
  reads `vic_clients()` once beside `me()` and every screen asks
  `ADspaceAdmin.vic(id)`, never a read of its own. One tag
  (`ADspaceAdmin.vicTag(id, inRow)`, `.chip-vic`, the crown and VIC in
  gold): a button opening `#vicPop` (Very Important Client (VIC); prompt,
  priority attention; issues count double in performance reviews; the
  note; VIC since {day} · set by {name}) on a desk's hover, a press or the
  keyboard's focus, docked on a phone, Escape first; inside a row that is
  one button it is part of that button and shows its card on hover alone.
  Where it shows: the Clients list (the tag, the logo's gold ring, a VICs
  view drawn while any is held), the record head (tag and ring; the ⋯'s
  Mark as VIC, asking VIC since and a note, or Remove VIC, never asked,
  Undo where it happened; VIC since under Key dates, its pen at the part),
  Content Review's list and client head, My Work's rows, board cards and
  task card (a VIC client's work leads each band of the day axis, Urgent
  delivery a band above it), Waiting for you (VIC rows first), the
  Dashboard's Needs attention (VIC first among equals), the Creator
  Campaigns, Reports and Video Scripts lists, and console search. A notice
  about a VIC client's work is titled "VIC · …" (trigger
  `ops_notifications_vic`), the bell and the push alike. No priority is
  set by it.
- One set of handles and one logo per client:
  - Brand alone edits `handle_*` and `logo_url` (Content Review's sheet
    keeps the access code alone, 2026-10-29); its logo field has Upload
    (`wireLogoUpload`): the picture is drawn down
    to 800px in its own format and stored under the client's folder by
    `sign-upload`, so the address never expires as a Facebook picture's does.
  - `social_*` is backfilled by `handle_of()` (a bare handle, or a URL's last
    segment; nothing where that segment is a route) and never written.
  - `profileUrl()` derives the links.
  - Content Review re-reads the row on opening a client, so its head shows
    the handles and logo as Brand left them.
- Contacts:
  - A table, with `.plink` reach links.
  - Salutation (`client_contacts.salutation`, `2026-10-09-contact-salutation.sql`;
    the user, 2026-10-09): a select before the name (Mr, Ms, Mrs, Mdm, Dr,
    Prof, Dato', Datin, Datuk, Dato' Sri, Datin Sri, Tan Sri, Puan Sri, Tun,
    Tuan, Puan, Encik, Cik, or None), shown before the name on the row and
    filed from and to. `contact_greeting(salutation, name)` greets with the
    salutation and the whole name (the salutation said once), else the whole
    name where it opens on a salutation (never Tan, a surname too; Tan Sri,
    Puan Sri, Dato' Sri, Datin Sri and Datuk Sri kept whole), else the
    name's first word
    (`2026-10-15-whatsapp-greeting-and-counts.sql`). A name after its
    salutation says one salutation: one the name opens on gives way to the
    one set (`ADspaceWords.person` on every page, `contact_named` in SQL,
    `2026-10-29-salutation-said-once.sql`; 2026-10-29: Mrs Ms Agnes Ang).
  - WhatsApp: a username field with `@` prefilled (letters, digits, `.` and `_`;
    a pasted `wa.me/@name` taken whole). `client_contacts.whatsapp` holds
    `@name` or the number: the field opens on the stored number where it is
    no username, is sent only where it changed, and digits typed into it
    are stored as a number (2026-10-19).
  - The main contact changes in one transaction
    (`client_contact_make_primary`, Clients: Contacts at Work, in scope), so
    a refused change leaves the old one.
  - One builder for every wa.me link, `ADspaceAPI.waNumber` (the console,
    the client portal, the creator's page, the namecard), reading a number
    as `wa_number` does in SQL (WhatsApp, below).
  - Remove is soft, then Delete permanently at Manage.
  - A contact with a number offers Send on WhatsApp in its ⋯
    (2026-10-31): the composer (`purpose` message) opened on that contact
    (`contactId`); nothing goes until its Send.
- Portal access is one switch per contact (Enable / Revoke in the ⋯, with
  Undo), shown as Portal access after its green dot.
  - Enabling opens a sheet with **Send invitation email unticked**; a move
    into Active asks it of the main contact (Give client portal access?),
    the invitation ticked, never switched on by itself (2026-10-26).
  - Send invitation stays in the ⋯. Undo emails nobody.
- Services:
  - Quantity × rate × months from a start date; neither below zero
    (`client_services_rate_check`, `client_services_qty_check`; the sheet
    refuses it in words, the field taking focus).
  - Enquired / To quote / Confirmed. Confirmed comes from a verified signed
    letter (`verify_letter`) or the admin's reasoned override alone: the
    sheet never offers it (a confirmed line reads its state), and trigger
    `client_services_confirm_guard` refuses a page that inserts or moves a
    line into it (`confirm-needs-letter`; `2026-10-10-service-confirm-guard.sql`,
    audit S1).
  - Remove is soft with Undo; a removed line is listed on asking with
    Restore (`client.service_restored`) and, where no letter quoted it,
    Delete at Clients: Services Full Access (asked, `client.service_deleted`;
    2026-10-13); a line a letter quoted stays (`client_document_services`
    restricts it) and offers no Delete.
  - `detail` and `min_months` are seeded from the rate card and stay editable.
  - A line is chosen, never preselected (Choose a service), opens on To
    quote for a client at Proposal sent or Active, and takes no term where
    its unit is not by the month; for a client billed in S$ the card's RM
    is turned at `fx_sgd` to the cent and the rate reads Rate (S$), left
    empty while no rate is set; its term percentage is the live version's,
    as a quotation's (2026-10-22, SL-1, SL-3, SL-5 to SL-7).
- The term adjustment is a tick with a percentage (`term_pct`, stored whether
  the tick is on or not).
  - Prefilled from `termPct(months, at)`: the ranges 1–3, 4–5, 6–11, 12–17,
    18–23 and 24+ months, each percentage a setting (`term_1_3` 25,
    `term_4_5` 15, `term_6_11` 0, `term_12_23` −5, `term_18_23` −5 (seeded
    from 12's; `2026-10-14-quotation-terms.sql`), `term_24` −10), Tax and
    terms at `team.settings` alone, 0 for none; a quotation takes them from
    the live rate card version, so a change reaches quotes once the card is
    published again (a version without 18's takes 12's).
  - The field follows the card only while it still holds the card's figure
    (`svPctCard`).
  - `rateFor(rate, months, adjust, pct)`: a percentage bills the rate × pct;
    `null` uses the older factor table; only an explicit `false` turns it off.
    Rounded to the cent where charged.
  - `issue_letter` snapshots it and `get_portal` sends it.
- Calls and visits carry next actions and an Undo (Done or Reopen on the
  row; Edit and Remove, or Restore and Delete, in the row's ⋯), and who
  logged it by name (`by_whom`; an older entry's sign-in email reads as
  the active colleague's name, else nothing; 2026-10-15); a removed entry is listed
  on asking with Restore and Delete (Clients: Calls at Manage, asked first,
  `client.touch_deleted`). A Meeting entry
  (`2026-10-05-meetings-outside-a-month.sql`) takes a time (MYT), a length
  (15 to 240) and a Meet, Zoom or Teams link; while ahead with no link it
  offers Create Google Meet (`meet-create` with `touchId`, Clients: Calls
  Work), a moved time moves the event and an entry no longer a meeting
  takes it off; the client's Meetings lists it as Meeting (time, length,
  link while ahead), never its summary. The link is the `.plink` address.
  A meeting ahead offers Message to client, Show and Copy (2026-10-31):
  the team's Meeting message filled from it (`ADspaceOps.meetingMessage`,
  the one builder the month's card uses too; no content month, so no
  agenda line), copied to paste into the client's WhatsApp group.
- Nothing reaches a client by itself (the user, 2026-10-31): every
  client-facing send is a colleague's press, and most go into the client's
  WhatsApp group, which no API can post to, so a record offers its message
  to copy (Copy message) beside any WhatsApp template send.
- Requests (Request · Fee · State · ⋯):
  - Requested → Reviewing → Approved / Declined → Applied; Withdrawn is a chip.
  - Reply sets a fee and a reply the client reads.
  - Approval never edits a service line.
  - A reply or a move is written only over the request as it was read
    (`.eq('updated_at', …)`, stamped by `client_requests_touch`): one the
    client withdrew or a colleague answered meanwhile reads "Not saved. This
    request changed since it was opened, and has been read again." and the
    list is read again (audit C2, 2026-10-10).
  - Add request (`#crmAddRequest`, `#crmReqAddBox`; Clients: Requests at
    Work; the user, 2026-10-31): a request the client made on a call or in
    a chat, its kind as a segment, the confirmed line where the kind needs
    one, Requested by (a contact of the client or Not named) and a note
    (asked unless Cancel), kept as the colleague's
    (`client_request_add(p_client, p_kind, p_service, p_contact, p_note,
    p_idem)`, the client in scope at Work, the portal's own refusals with
    `no-service` and `bad-contact`, one key a sheet, filed
    `request.added`; `client_requests.recorded_by`); its row reads Recorded
    by {colleague} (for {contact}) where a client's reads its contact. The
    section shows on an Active or Paused client to a colleague at Work.
    Each row's ⋯ holds Delete at Requests Full Access (asked, no restore;
    `client_request_delete`, the client in scope at Manage, filed
    `request.deleted`).
- Engagements (`js/engage.js`, `tab=engagements`; the user, 2026-10-09:
  "one less tab to monitor"): the client's work by content month, its
  reports included. The tab is drawn for an Active, Paused or Past client,
  or one holding anything in it (a lead's waits for the answer, and its
  address falls back to Overview). The head holds Open Content Review /
  Enable Content Review, New campaign and New month (My Work at Work;
  2026-10-31: opens My Work's Months on the client, `new=month`, with the
  New month sheet), each behind its own check, while the client is Active.
  - A card a month (`ADspaceGroup.section`, route `client-months`), newest
    first: a month from today's on open, an older one shut until opened and
    remembered; a month starting on its `start_day` states its span on the
    heading, and the heading counts the month's overdue tasks in red, late by
    My Work's rule (`ops_engagement_counts` `late`, `ops_task_late`). A month
    is drawn only where the reader may see something in it.
  - A row a thing (`.cmonth-row`: the section's rail glyph on a tonal tile,
    the name over its facts, the state, the chevron), in the rail's order:
    Content (My Work View: `n of N done` as the month line reads it, red with
    an overdue task, Completed, Cancelled, No tasks; Report due while ahead;
    opens the client's Months view), each Content Review set (`review.sets`
    View; Published or Draft), the month's Video Scripts as one row
    (`scripts` View; `n scripts · n published`, Published once all are;
    opens the month's scripts), each creator campaign (`campaigns.campaigns`
    View; `W.campState`), each report (Reports View: Draft, In review,
    Confirmed, Published with Sent {day} or Not sent, On request and White
    label as chips; opens the report). A colleague at Clients View without
    Reports reads the finished reports alone (`sm_client_reports`), each
    with Download (`ADspaceReports.clientFile`, `sm_report_file`). A row
    opens its record as search does (the address, then the section).
  - Filed by content month: a report by the month whose span holds its last
    day (as `sm_report_gate` finds it), a set and a campaign by the day they
    were made (MYT), a script by its `period`; with no month holding the day,
    the calendar month. A reader of Reports without My Work takes the spans
    from `sm_report_months`.
  - Each block asks its `may()` before it reads and is read once for the
    client in one request (never one a month or a row): on opening the
    record, on entering it again and on a visit to the pane; a repaint reads
    nothing. A refused read is `failLine` for that block alone, above the
    months, with Try again. Nothing at all reads No engagements.
- Delete client:
  - in the record's ⋯, as a sheet counting from the loaded record;
  - the name typed back, plus the delete code where `delete_code_set()`;
  - `delete_client` re-checks at the press (an active colleague at Clients
    Manage, `Not allowed`) and files `client.deleted`
    itself, in the transaction that deletes (audit R1); the page files
    nothing.
  - Paused and Past are the everyday exits.
- Person in charge (`owner` holds a name as text):
  - Changed from one colleague to another only at Clients Full Access, or by
    Team Full Access carrying a stand-down or a rename (`clients_owner_guard`,
    `owner-change`); a lead nobody holds is taken with Take lead in the
    record's ⋯ (Leads at Manage).
  - The stage select greys a stage whose band the colleague cannot work, and
    New lead needs `clients.leads:work`.
  - Standing a colleague down, or Delete, asks who takes each kind of their
    live work (Team, below); the clients and open campaigns they are person
    in charge of are two of the kinds. Keep is first, and only active
    colleagues are offered.
  - The move takes `.select('id')` and files `client.edited` /
    `campaign.edited`.
  - A completed campaign keeps who ran it.
  - A rename carries onto every record.
  - Select clients (the bar's ⋯, `clients:manage`): each row shown becomes
    its tick inside the name cell (`label.client-row.is-picking`, the
    columns unmoved), a press anywhere on it ticking it; the bar
    (`#crmBulk`: a tick for every client shown, `n selected`, Done) offers
    Reassign, asking one colleague, moving each ticked client
    not already theirs through the same write (`.select('id')`, the guard
    re-checking, filed `client.edited` from and to), naming a refusal
    against its client, with Undo where it happened putting back each
    client's own.

### Documents (`js/documents.js`, `js/letters.js`, `js/register.js`, `js/verify.js`, `?s=register`)
- One pen (`ADspaceDocs.pen`) and one letterhead for every document. The PDF is
  never stored: a row holds the snapshot and the file is redrawn on Download.
- Every PDF the portal hands over goes through `ADspaceDocs.save(blob, name,
  tab, zh)` under its own file name (Safari names a `blob:` address
  Unknown.pdf, and names a file after the last part of its address). The
  page's worker (`js/file-sw.js`, imported by `admin/sw.js` and
  `client/sw.js`) holds the drawn file an hour at `{scope}file/{id}/{name}`
  (the hour kept on every read; signing out lets go of the page's own,
  `ADspaceDocs.forgetFiles`; audit F6, 2026-10-10),
  and a tab opened at the press opens there: every Preview, and on an
  iPhone or iPad every save (`ADspaceDocs.tabFor()`, which opens no tab at a
  desk), so Save to Files keeps the name and nothing is asked. A download
  link never points at the worker's address (Chrome sends a `download` past
  the worker): a desk downloads the `blob:` under its name. With no tab (a
  blocked window) an iPhone's save takes the share sheet with a named File,
  asking File ready · Save (`ADspaceConfirm`; the client portal loads it)
  only when Safari refuses a stale press (`tests/savename.js`).
- In the installed app on a touch screen (`ADspaceDocs.installed()`:
  display-mode standalone or `navigator.standalone`, on iOS or Android) no
  window is opened for a PDF: a window on the app's own address opens inside
  it with no Share, Done or Back (the user, 2026-10-22). `tabFor()` and
  `previewTab()` (every Preview's one opener, Drawing the PDF…) answer null
  there, the file goes to the share sheet as a named File (a stale press asks
  File ready · Share), and with no share sheet for files it is shown in a
  sheet with Close and Download (`#pdfViewSheet`); a window on another origin
  (the Handbook's signed link, an invoice) is left as it is (`tests/pwapdf.js`).
- pdf-lib and fontkit are fetched on the first drawing (`ADspaceDocs.lib()`,
  waited on by every render: letters, reports, performance records); no page
  loads them in its head (1.1 MB, about 600 ms of a phone's load). A
  refusal names what failed: a file that arrives and fails its hash has
  changed at its source (Please contact ADspace: client pages draw PDFs
  too), anything else is the connection
  (fetched once more and hashed; `tests/pdflibhash.js`).
- Letter of Offer (kind `offer`; older rows `intent`, `cover`):
  - Billing first (2026-10-26; the user: "billing should be before LoO"):
    trigger `client_documents_billing` refuses a letter while the registered
    name, BRN or billing address is empty or no billing contact stands
    (`needs-billing`, as Active holds); the letter sheet opens Billing on
    its first missing field instead, offering the details form, and Billing's
    Save carries on into the letter sheet.
  - Serial `AQL/{client_code}/{YYMM}{NN}` from the lowest free slot. The
    counter's row lock serialises; the scan is capped (`no-serial`); two
    digits is a floor, not a width.
  - A typed reference (`p_serial`, the `#pickRef` field, placeholder "Numbered
    automatically") spends no number and is refused where taken
    (`serial-taken`) or badly shaped (`serial-shape`).
  - A client with no Client ID is asked for one in the letter sheet
    (`#pickCode`, `#pickRefNote`), the next AC number a press away
    (`#pickCodeNext`, Use AC…); the letter is refused until it is set,
    which Issue writes to the client first (filed from and to) and then
    numbers the letter from (the user, 2026-10-27, CLI-15).
  - The file name swaps `/` for `-`.
  - Preview (`#pickPreview`, a `.btn-sm` under Terms, never in the foot;
    the user, 2026-10-31) draws the letter Issue would keep: the database
    makes it and rolls it back (`issue_letter_preview`, issue_letter inside a
    subtransaction, its refusals passed on, `2026-10-31-letter-preview.sql`),
    drawn under DRAFT (INTERNAL USE ONLY) with the reference PREVIEW; no
    letter, number or Activity record row is kept.
- Letter content:
  - Only To quote lines.
  - Terms of its own (`#pickTerms`, one point a line, ten at most, 400
    characters each; `bad-terms`): sent in `p_deal.terms`, kept in the
    snapshot as `bill_to.terms` and printed under TERMS after the term
    (`2026-10-23-letter-terms.sql`). The box opens on the validity, today
    plus `quote_valid_days` (Tax and terms; `ADspaceDocs.validLine`),
    editable, never a figure in the page; such a letter carries
    `bill_to.terms_own` and prints no validity of its own, one issued
    before redraws its 30 days (the user, 2026-10-23,
    `2026-10-23-letter-validity-in-terms.sql`).
  - Priced by the month when every line of more than a month shares a term
    (the amount reading per month; the summary ending Monthly incl. SST in
    bold, as a quotation's does); a one-month line beside them is a one-off
    item (reading one-off) billed with the first month: one summary of
    Monthly subtotal, One-off subtotal, one SST line, First month due in
    bold, then Monthly incl. SST (the user, 2026-10-15: "just provide first
    month due total"; `2026-10-15-letter-one-off-items.sql` prices it).
    TERMS states the term once, with the whole term's total incl. SST; the
    acceptance lists Monthly incl. SST, Minimum term, First month due (with
    a one-off item) and Total for the term incl. SST, under no Item / Value
    head and never "including SST" after a figure. Lines on two terms of
    more than a month: Total incl. SST; a quoted letter so keeps its
    quotation's term (2026-10-18): the row `12-month commitment (5%)`,
    First month incl. SST under the total as the quotation gives it, TERMS's
    minimum term with the total over the months stated for each line, and
    the acceptance's First month incl. SST, Minimum term and Total for the
    term. Wherever a monthly line runs months other than the term, the
    month's figures are the first month's, named First month (excl. SST,
    incl. SST; 首月 on `/quote/`), and the first month holds the one-off
    items (the one-off subtotal before SST, one First month incl. SST, no
    One-off incl. SST of its own), on the letter, the quotation's PDF,
    `/quote/` and Build quote alike; Monthly where every line runs the term
    (the user, 2026-10-18). Where SST does not apply (an exempt client,
    0%), all four read SST not applicable on its row, name no SST on a
    total (Monthly, First month, One-off total) and leave out the excl. SST
    row; the quotation's remarks say once what the amount includes (the
    one-off items, SST at 8%), naming no SST at 0% (`ADspaceMoney.sstApplies`,
    `SST_NONE`; review item 17).
  - `priceOf()` computes the snapshot and the drawing. A letter whose every
    line came from one quotation is priced as `quote_price` priced it: the
    term percentage once on the subtotal, SST at the quotation's rate
    (`quote_sst` on each snapshot line; 2026-10-17), exactly as
    `quote_adjust` totals it: a line the quotation bills by the month is
    monthly whatever months Build quote gave it, and where they differ the
    whole span takes the percentage and SST once, the one-off apart
    (`quote_term` on each snapshot line; one without it redraws as
    issued), and prints each line
    at its rate before the term with the term as one summary row
    (`6-month commitment (5%)`), so its rows add up to the subtotal.
    `issue_letter` works
    the same price from the stored lines (the term's rate rounded to the
    cent, by the month where every line of more than a month shares a
    term with a one-month line its own one-off subtotal, SST at today's rate
    unless exempt) and keeps the page's figures only within a sen, else
    refuses `stale` with its own (audit S4, 2026-10-10). A colleague at
    Clients: Letters who cannot list quotations reads the quotation's rate
    and term through `letter_quote_terms` (2026-10-26); a line with no code
    is priced at the client's rate in the same group as a coded line at
    that rate, and every total is rounded by `cents()`, never `Math.round`.
  - `verify_letter` confirms only the lines as printed: a line removed since
    (`archived-line`) or one whose quantity, rate, term or adjustment moved
    since the letter (`changed-terms`) is refused, and the letter reissued.
  - `client_documents` keeps its read policy alone: every write is a letter
    or register function.
  - `legalName` is resolved once.
  - Every line wraps.
  - The contact is addressed with their salutation (`bill_to.contact_salutation`,
    `2026-10-14-letter-salutation.sql`): Attn: Ms Jane Doe and Dear Ms Jane
    Doe; the Billing pane and its contact select, and a client letter's Attn,
    read it the same way.
- Letter layout:
  - The closing is reserved on its own. The acceptance opens under the
    letter's grey hairline across the column with room either side (never
    ink: it read as a heavy black bar), and carries the
    sentence naming the reference and date, then the figures; the page
    count is the signed sheet's foot (Page n of n), never a sentence again.
  - The execution block is one table in the grey hairline (the user,
    2026-10-23: smaller, tabular): the signing and stamp cell at the left
    spanning Name, Designation and Date, a label cell beside each value.
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
  - Rows: Document · Brand · Recipient · Issued · ⋯ (a phone leaves Brand
    out). The HR card heads Team in place of Brand (`teamOf()`: `member_id`,
    else an Employee ID in the reference). The search reads a dash as a slash,
    as `/verify` does, so a file name finds its row.
  - An offer row answers to `clients.documents` and offers Open client record,
    never Void/Delete/Reissue.
- Serials per family:
  - a quotation cover takes the accounting portal's, typed;
  - a client letter `ACL/{client_code}/{YYMMDD}{NN}` (ADspace Cover
    Letter; the letter's date; the lowest number free for that client that
    day from 01, under an advisory lock); older `AD/[SA/]…` letters keep
    theirs;
  - an HR letter `ADHR/{staff_code}/{code}{YYMM}`.
  - `-2`, `-3` where an HR base is spent. `serial_taken()` spans both tables.
- HR is its own part:
  - `register_may(family, level)` is the read policy and the check in every
    write;
  - an HR row never arrives without `register.hr`;
  - the activity record logs the kind alone, under subject `HR`.
- An HR letter is shared with the colleague it names
  (`2026-10-06-hr-letters-shared.sql`, `documents.shared_at` / `shared_by`):
  Issue's Share with {first name} tick (`#docShare`) is on by default and
  off for a letter not yet theirs (a reissue keeps the earlier choice); the
  row's ⋯ Share with {first name} / Stop sharing (`document_share`, HR
  Letters at Work, `not-hr`, `no-member`). Shared, the colleague is told once
  (kind `hr.letter`, its kind and never its words; the bell and a push open
  Letters) and reads it in My records, Letters (`my_letters()`, behind
  `perf_mine_gate()`, their own alone, a replaced version left out, a voided
  one marked Void), its PDF drawn in their browser: no Documents access is
  needed. Filed under HR with the kind alone.
- Add existing document (`register_add` / `register_update`, ten arguments with
  `p_member` and `p_supplier`; opened on a colleague or a supplier from
  their record):
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
  - Anyone the team does not hold is answered 30 lookups an hour a
    connection (`verify_tries` by `request_ip()`, RLS on, no policy, no
    grant), then `locked` with the minutes left before any reference is
    read, said as Too many checks (`2026-10-19-verify-lookups-counted.sql`:
    an HR reference is guessable); `privacy_retention` removes a row whose
    hour began over 30 days ago.
- The Chinese face (`ADSPACE_ORG.fontCjk`):
  - It is Noto Sans SC as TrueType in the repo (`css/NotoSansSC-Regular.ttf`,
    `css/NotoSansSC-NOTICE.txt`), embedded with only the characters used.
    The CDN's CFF face, embedded whole, made every Chinese PDF 8 MB and drew
    garbled in strict viewers. fontkit's subsetter needs every glyph's data
    at an even length, so the face is saved with its glyphs padded.
  - A CFF face is embedded whole, never subset (`isCff()`).
  - An unreachable face refuses the letter by name.
  - `fontMed` falls back to Slate Regular.
- Issue document (`#docSheet`):
  - The kind decides the fields.
  - The type seeds the title, salutation and body, with `{first name}` and
    `{role}` filled. A body somebody has edited is never overwritten.
  - The signatory is the signed-in person and their `designation`.
  - To be signed (`#docSigned`, sent as `p_signed`) is a tick prefilled
    from the type and fixed on a reissue: ticked, the letter leaves space to
    sign and needs a signatory; unticked, the name and designation follow
    ADSPACE PLT with no space and the foot reads No signature required.
  - The sheet runs in the letter's own order.
  - Preview (`#docPreview`, a `.btn-sm` under the letter's fields, never in
    the foot; DOC-6, 2026-10-22) draws the letter from the sheet
    on the same pen without issuing it: no row, no number spent, the
    reference reading PREVIEW (a reissue keeps its own), every page under
    DRAFT (INTERNAL USE ONLY) (the report's watermark, one copy:
    `ADspaceDocs.watermark`); a new tab, else a download.
  - A letter's foot is one row (the user, 2026-10-06): the reference, the
    verify line (`ADSPACE_ORG.verifyUrl`, digital.adspace.me/verify, on
    every PDF that names it), the page count; 7.5pt, 7 where the longest
    line cannot clear both.
  - The register's sheets (`#docSheet`, `#regAddSheet`, void, delete)
    close on an outside click only while untouched, as `js/sheet.js` holds.
  - `doc_types` is seeded once and is the team's to edit: Document types
    in Settings' Templates alone (2026-10-29), `register.types`
    (`2026-10-07-document-types.sql`). `#dtSheet` lists them by group, as
    My Work's Templates; `#dtEditSheet` edits one: Group (fixed once made),
    Name (unique), an HR letter's Reference code (required, its own among
    the HR letters offered; the sheet and the list spell the whole
    reference, `ADHR/{Employee ID}/{code}{YYMM}`, never "Code E"), To be signed, Offered
    on Issue (`doc_type_set_active`; never removed, an issued document names
    its type), the wording, and Fields. Saved by `doc_type_save`, filed
    `team.changed` under Document types from and to.
  - A type's fields are the words its wording holds in braces ({intern
    name}, {from}); {first name}, {role} and {client} fill themselves, and
    on an HR letter {name}, the colleague's full name; a client picked in
    the Register's sheet brings its main contact (else its first), and
    Issue refuses any word still in braces in the title, salutation or
    letter, naming it (2026-10-27, DOC-7).
    `doc_types.fields` says how each is asked: Text, Date or Paragraph (a
    name holding "date" is a date until set). Issue groups the kinds
    (Quotation, Client letters, HR letters) and asks for them under Details,
    filling each into the title, salutation and body as it is typed (a date
    as `16 September 2026`; words typed over are filled on Issue); Issue
    refuses a field still in braces ("Fill in From."), Preview draws it as
    it stands, and `body.fields` keeps what was typed. A reissue keeps its
    words and asks nothing.
  - The Register sorts newest first, with Oldest first and By reference in the
    bar.
- The reference on a row is a copy control (`.serial-copy`).
- A hand-added row's second line is its kind alone.
- The old list is imported by a SQL file handed to the user, never committed
  (real names).

### Suppliers (`js/suppliers.js`, `js/supplierform.js`, `?s=suppliers`; `supplier/`)
- A section of its own (`suppliers`, View / Work / Manage; the user,
  2026-10-18: "own section"), in the Internal chunk after Documents
  (`2026-10-18-suppliers.sql`, `2026-10-18-suppliers-own-section.sql`;
  the user: the Jotform supplier sign-up "via portal and data sync into it
  similar as client billing", "invite only, with create link and set the
  supplier id before sending", "nric only for individuals"); `supplier=`
  opens one. `suppliers` and `supplier_forms` have RLS on, no policy, no
  grant.
- New supplier asks the Supplier ID alone (the next AS number offered at
  the width in use, unique, `code-taken`; the user: "i wont know the
  company name first"), makes it Pending and its link
  (`/supplier/?k=`, open `details_form_days`; Copy link, Preview,
  the ⋯ Reset link and Close link, each asked; `supplier_link_close`
  ends the open form now, filed, `2026-10-18-supplier-link-closed.sql`). Until its form names it a supplier reads its
  Supplier ID, Waiting for their details, until its form comes back:
  then Details received, the answers read in place under the form before
  Use details; a supplier holding no details reads No details yet., never
  groups of Not set (2026-10-20, SUP-1 to SUP-3).
- The supplier's page (`supplier_form_read`, `supplier_form_submit`, anon)
  leads For ADspace · Supplier ID, Enter moving to the next field and
  submitting from the last alone (2026-10-20, SPF-2, SPF-3), a failed
  send naming ADspace, never an account manager (`W.notSentAdspace`,
  2026-10-27, SPF-6),
  reads the Supplier ID (and the name once held) and checks as the Jotform
  form did: Company or Individual, NRIC (XXXXXX-XX-XXXX) for an individual
  alone, a company's 12-digit BRN, TIN, SST no. (AXX-XXXX-XXXXXXXX), Office
  / mobile a Malaysian or Singapore number and Mobile / WhatsApp a mobile
  (`supplier_number_ok`, the page alike), the payment term (NET 7, 14, 30,
  45, 60, subject to approval), MYR or SGD, the bank from its list, the
  authorisation ticked; the team at Suppliers Work is told (kind
  `supplier.details`, opening the supplier). The answers never write the
  supplier: Use details fills its sheet and Save (`supplier_save`) takes
  them in. A move of status (Approve, Set inactive) ends every open link of
  the supplier, filed with the move. An Active supplier whose details change
  is sent an update link (`supplier_forms.purpose`
  `update`, `2026-10-20-supplier-update-link.sql`) or edited by hand: the
  form opens on the details held but the NRIC and the bank details, which
  it never reads and which, left blank, keep what is held; the record leads
  with Details update, each change from and to (the bank as Changed), and
  Use changes, held for a colleague at `suppliers.pay` where the bank
  changed. An Active supplier holds one Details update form section under
  Payment details in every state (Not sent, Sent and open until, Link
  ended, taken in), its acts in its own head (Create link; open, the link
  with Copy link and Preview, the ⋯ Reset link and Close link). The
  record's ⋯ holds Edit, Set inactive or Set active, and Delete alone:
  Issue document (its ⋯ Add existing document) heads Documents, Send email
  heads Emails (2026-10-20, the user: six items read as too many). A new payee, bank or account
  on an Active supplier, by link or by hand, puts it back to Pending until
  approved again (`repending`), and an approval names who approved, never
  a system account. The record is its head card over a strip (`#supTabs`,
  `tab=` pushed, Overview left out; SUP-4, 2026-10-22): Overview (a form
  waiting to be taken in first, then Client, Billing details, Person in
  charge), Payment (Payment details, the Details update form, Bukku),
  Documents, Emails; a pane with nothing in it is not drawn.
- Approve (`supplier_set_status`, a name, the details and the bank account
  whole, `incomplete`; under the record's head at its own width, `.sup-go`,
  2026-10-27, SUP-10) makes it Active; Set inactive / Set active in the
  ⋯, Delete at Manage with the name (else the Supplier ID) typed back
  (letters keep their words). The NRIC and the bank details are sent and
  saved only at `suppliers.pay` (granted), filed by name, never by value.
- A supplier's document is the Documents family `supplier`,
  `documents.supplier_id`, issued to an Active supplier alone, from its
  record (Issue document) or the Register (2026-10-20, DOC-3), listed on the supplier and under Supplier Letters
  (`register_may('supplier', …)` answers the Suppliers section); a reissue
  keeps the supplier. The one offered is the Supplier Service Agreement
  (`supplier_sca`, `2026-10-18-supplier-service-agreement.sql`; the user,
  2026-10-18; Letter to Supplier, `ASL/{Supplier ID}/{YYMMDD}{NN}`, no
  longer offered, its letters kept): `AD/SCA/{Supplier ID}/{YYMM}{NN}`,
  signed by both parties; its clauses are the type's wording (`# Heading`
  a clause, `1.` a numbered point, `a.` a lettered item; Document types);
  the Issue sheet asks its schedules in place of a recipient
  (`#docScaSec`): Schedule A Part 1 from the supplier (legal name, BRN /
  NRIC / Passport, registered address, contact, Start date), Part 2 from
  `doc_types.schedule` (platforms, tasks, reporting, response time, spend
  approval limit, budget tolerance; the Fee typed), Schedule B an account
  a row (the client from Clients, the ad account offered from its Meta
  links, the spend a month in the client's currency, start and end) with
  its notes, kept as `body.agreement` and refused without the legal name,
  start, fee and an account (`agreement-incomplete`, `sca_complete`). The
  PDF (`drawAgreement`, js/letters.js) prints the clauses numbered, both
  signing blocks, then Schedule A and Schedule B (as at its date) as
  tables. A new Schedule B is a Reissue: the same reference, as at the new
  date. No bank
  statement upload (the Jotform field was optional). A document kept
  outside the portal (an agreement, an NDA) is Add existing document's Supplier Letter
  (Documents' ⋯ on the record, or the Register), naming its supplier and no client
  (`register_add` / `register_update` `p_supplier`, `no-supplier`;
  `2026-10-18-supplier-entries.sql`, which filed the entries whose
  reference named a supplier's ID under it); on the record it opens its
  file link, and it is never offered as an email's document.
- A supplier that is also a client is linked to it
  (`2026-10-18-supplier-client-link.sql`, `suppliers.client_id`; the user,
  2026-10-18: the Supplier ID and the Client ID stay apart): the record's
  Client group, Link client or Edit (`supplier_client_set`, Suppliers Work
  and Clients View, the client in scope; `no-client`; filed
  `supplier.edited` from and to), the client opening its record; while none
  is linked `supplier_get` names the clients whose BRN, digits alone, is the
  supplier's (Same BRN; `match`, never the BRN itself) and the question
  opens on it. The client's Details name its supplier
  (`client_suppliers`, Suppliers View), opening it.
- Supplier emails (`2026-10-18-supplier-emails.sql`, `supplier-mail`,
  `docs/SUPPLIER-EMAIL-SETUP.md`; the user, 2026-10-18), sent by hand
  through Resend from `ADspace <noreply-supplier@sc.adspace.me>`, replies
  to ap@adspacestudios.com: Send email at the head of Emails (`#supMailSheet`,
  Suppliers Work, a supplier with an email) offers Supplier approved (an
  Active supplier) and Document (a letter not void, sent as its PDF, which
  `supplier-mail` takes only where its title names the reference), the
  words filled from the record (`supplier_email_prepare`) and editable,
  Copy the finance email ticked where it differs; Send asks first.
  Approve asks Send the approval email? (Send email / Not now), and the
  sheet that answer opens sends at its Send with no second question;
  nothing is sent by itself (the user, 2026-10-27, SUP-11). An email
  is filed before it goes (`supplier_email_begin`, refused `recent` within
  `wa_repeat_hours` unless asked again; `supplier_email_done` by its
  sender, filed `supplier.edited`), listed under Emails on the record
  (`supplier_emails_of`) with Resend's word on it (Sent, Delivered,
  Opened, Bounced, Failed, Not confirmed) from its signed webhook
  (`supplier_email_status`, the service role's alone, never stepping
  back); an email still Sending ten minutes after it was filed (its
  function stopped) reads Not confirmed (`mail_sweep`, pg_cron
  `mail-sweep` every fifteen minutes; overdue reminders alike). The two templates (`{contact name}` … `{sender name}`) are
  Settings, Documents: Supplier emails (`#supTplSheet`, Suppliers Full
  Access). `supplier_email_templates` and `supplier_emails` have RLS on,
  no policy, no grant. The email carries no unmonitored-mailbox line; a
  document's ends Verify this document at digital.adspace.me/verify.
- Send by email (`js/docmail.js`, `2026-10-31-client-document-emails.sql`;
  the user, 2026-10-31: "ok build but still same as whatsapp optionally
  send"): a quotation's ⋯ (not Cancelled, not a website quotation still
  awaiting review, not Do not contact), a Letter of Offer's (not voided or
  replaced) and a client letter's issued in the portal (Documents family
  `client`, not void) each offer Send by email in the Send group beside
  Send on WhatsApp; nothing goes by itself. Gated (the user, 2026-10-31:
  "Enable or disable at business settings"): Settings, Clients: Send by
  email, a switch (`client_email_on`, seeded Off; `client_email_set`,
  `team.settings`, filed under Settings); Off, no record draws it and
  prepare and begin refuse `email-off`. Access: Clients: Quotations,
  Clients: Letters, Letters or Documents: Client documents at Work
  (`client_email_may`), the client in scope. One sheet (`#dmSheet`,
  `ADspaceDocMail.compose`): From `ADspace <noreply-client@sc.adspace.me>`
  (`MAIL_CLIENT_FROM`), replies to the colleague who sends (else
  marketing@adspacestudios.com), To the client's contacts holding an email,
  the billing contact first, else the primary (`client_email_prepare`),
  Copy the finance email where it differs, Subject and Message the kind's
  template filled from the record and editable, the PDF drawn here as
  Download draws it with Preview PDF, Send asking first and Sent recently
  (the same record within `wa_repeat_hours`) asking again in warn.
  `supplier-mail`'s `client` branch checks the PDF names the record's
  reference, files it first (`client_email_begin`: the record's lock,
  `sending`, `recent` unless asked again), sends through `_shared/mail.ts`
  and closes it (`client_email_done`, filed `client.edited` on the
  client); Resend's word and `mail_sweep` reach `client_emails` as they do
  the supplier's. The record's row reads its last email under its
  reference (Emailed {day} · Delivered; `client_emails_of`, one read a
  visit to the client). The three templates are Settings, Templates:
  Client emails (`#dmTplSheet`, `team.settings`; filed `team.changed`
  under Client emails). `client_email_templates` and `client_emails` have
  RLS on, no policy, no grant.

- Tax codes per line (`2026-10-22-tax-codes-per-line.sql`; the user,
  2026-10-22: "make the 8% SST inside settings … choose to apply each under
  per item basis", Bukku's own codes): `tax_codes` (code, name, rate,
  active, `bukku_id`; RLS on, no policy, no grant), read by
  `tax_codes_list()` (the team), kept by `tax_codes_save(p_rows,
  p_replace)` (`team.settings`; `bad-row`; filed `team.changed` under Tax
  codes); Settings, Money: Tax codes (`#taxSheet`: active first, highest
  rate first, one no longer offered last; Edit, Add code, Read from Bukku,
  which lists Bukku's codes (`bukku-sync` `taxes`, asked of `bukku_config`
  as `fields` is; 2026-10-22, BE-12) to tick, those offered
  ticked, and keeps only the ticked ones offered: one unticked is set not
  offered, one never held is never added; each code's ⋯ Delete and Select
  delete through `tax_codes_delete(p_codes)`, all or none, refused
  `in-use` naming each code a service line, a quotation or a letter holds
  (`tax_code_uses`), the count typed back for several;
  `2026-10-22-tax-codes-chosen-and-deleted.sql`). A service line's Tax (`#svTax`,
  `client_services.tax_code`) and a Build quote line's (`.qb-tax`, the
  edit's `tax`; its rate set by `quote_tax_edits` from the table, never the
  page's; `bad-tax`) default to the client's SST (none where exempt) and
  else name an active code. Every total groups the lines by rate and rounds
  each group's SST once (`quote_totals`, `issue_letter`, `priceOf`,
  `quotePrice`; one rate reads as before, to the sen); `issue_letter`
  keeps `tax_code` and `tax_pct` on each snapshot line and refuses a code
  no longer offered (`bad-tax`); `verify_letter` refuses a line whose code
  moved since (`changed-terms`). A letter and a quotation PDF name SST by
  its rate (`ADspaceMoney.sstOf`) and, where the lines are on more than one
  rate, each amount says its own under it, (+8% SST) or (0% SST), never
  under the description (the user, 2026-10-23: it read as the item's). The quotation website keeps the client's
  SST; an issued letter keeps its snapshot. Account, classification code,
  tax inclusive and a line discount are not taken from Bukku.

### Bukku (`js/bukku.js`, `bukku-sync`, `2026-10-18-bukku-contacts.sql`, `docs/BUKKU-SETUP.md`)
- Phase 1 (the user, 2026-10-18: quotations, invoices and purchase orders
  are made in Bukku): a client's billing and an approved supplier's details
  are sent by hand as one Bukku contact. Billing's Bukku group and the
  supplier record's (`ADspaceBukku.group`: Contact, Last sent, Since then;
  Send to Bukku at Clients: Billing Work, Suppliers Work) open `#bkSheet`:
  the linked contact, else the contacts with the same registration number,
  then the same or a similar name (`find`, every page read), and New
  contact under Bukku's own next code (`C-{first letter}{nnnn}`); what
  changes field by field (`preview`); Send, Link and send where it links.
  What goes is `bukku_prepare`'s answer as the colleague (a company's name in
  capitals, a person's each word capitalised, `bukku_name_case`; the NRIC
  at `suppliers.pay` alone, the bank details never), the Client ID or
  Supplier ID in the Bukku custom field chosen on Settings, Money, Bukku
  (`bukku_config_set`, `team.settings`; `no-field` until chosen). An update
  reads the contact first and keeps Bukku's code, terms, accounts, groups,
  other people and addresses; its types gain Customer or Supplier and never
  lose one; nothing is deleted or archived in Bukku (`tests/bukkufn.js`).
  The address is read into Bukku's parts (street, postcode, city, state,
  country; a line break a comma), and an address or a billing person Bukku
  already holds however set out (the same letters and digits; every word of
  ours in Bukku's name) is kept; the person goes with the contact's
  salutation (`bukku_prepare` `salutation`), put before a name Bukku keeps,
  in place of a salutation Bukku's name opens on, never both;
  a person or address added ticks default billing alone, never default
  shipping; a supplier's payment term is set as Bukku's own term of the same
  days where Bukku holds one (the user, 2026-10-19). Link only (`#bkLink`,
  beside Link and send for a contact Bukku holds; kept apart from Link and
  send, the user, 2026-10-31) links it as it stands and sends nothing (`bukku-sync` `link`, `bukku_link_only`, filed Linked to
  Bukku, nothing sent; `2026-10-19-bukku-as-bukku-holds-it.sql`). What a
  record lacks (`bukku_prepare`) is read with the group: a record that
  cannot be sent draws no Send and says what is missing in one line
  (2026-10-20, BKU-1).
  The link is filed by `bukku_linked` (`bukku_links`, `bukku_settings`: RLS
  on, no policy, no grant; filed `client.edited` / `supplier.edited` Sent
  to Bukku · code); a supplier linked to a client is that client's contact.
  The record shows it as one shaded band at the foot of what it sends
  (`.bk-band`; the user, 2026-10-29: the group "looks incomplete"): Bukku,
  the contact's code and its state (Up to date, Details changed once a sent
  field moves (`bukku_print`), Not linked), Last sent under it, Send to
  Bukku and a ⋯ of Unlink at the right edge. Unlink (`bukku_unlink`, the
  record's Work level, asked first) lets go of the link alone, nothing
  changed in Bukku, a supplier and its own client together (one contact),
  kept in `bukku_links_gone` (RLS on, no policy, no grant) for Undo where it
  happened (`bukku_unlink_undo`: as it stood, `moved` once linked again),
  each filed Unlinked from Bukku / Linked to Bukku again
  (`2026-10-29-bukku-unlink.sql`, the SQL Editor's); Send to Bukku then
  offers the matching contacts again.
  One Bukku contact is one record's, a supplier and its own client sharing
  one: `bukku-sync` sends a linked record to its own contact alone and asks
  `bukku_contact_check` before it writes Bukku, and `bukku_linked` and
  `bukku_link_only` refuse `taken` (2026-10-22, BE-2).
  Bukku by entity (`2026-10-29-bukku-by-entity.sql`, the SQL Editor's; the
  user, 2026-10-29: one brand billed by several companies): a Bukku contact
  is a company, so `bukku_links` takes the kind `entity`; an entity's fold
  on Billing holds its own band (`.ent-bk`, read as it opens), Send to
  Bukku, Link only and Unlink at Clients: Billing Work on a client it bills
  that the colleague sees (`bukku_may`); what goes is the entity's
  registered name, numbers, address, finance email and billing contact
  (else its brand's primary contact), with the Client ID and market of the
  brand it is filed under (`entity_home_client`: the brand it is the
  primary of, else the first to add it); each step filed `client.billing`
  on every brand it bills, the company named (`bukku_file_entity`). A brand
  and its primary entity are one company and may hold one contact; any
  other two records may not (`bukku_contact_taken`); a record with no link
  of its own reads its company's, said as Linked through (`bukku_shared`).
  Billing from Bukku (`2026-10-30-billing-from-bukku.sql`; the user,
  2026-10-29: "we dont need two sides update", option A approved
  2026-10-30): once a client or a billing entity is linked and held, Bukku
  holds its billing and the portal's columns are its copy. An unlinked
  client or entity offers Link to Bukku (the user, 2026-10-30: "use link
  bukku instead of send to bukku"): its sheet links the contact chosen as
  Bukku holds it, nothing sent (Link, how the details differ shown), or
  makes New contact in Bukku (Create in Bukku). A link is held
  by Send to Bukku, or at its first read where every detail that differs
  is empty in the portal; one made by Link, or standing before, whose
  details differ reads Differs from Bukku, field by field, with Send to
  Bukku and Use Bukku's (asked; `bukku-sync` `hold`), nothing replaced
  until one is chosen. The band then leads Billing (`opts.lead`): Linked,
  Read {day, time}, Refresh and the ⋯'s Unlink, no Send and no Details
  changed; Billing is read once a visit to the record (`bukku-sync` `read`,
  one read at a time a record), a change made in Bukku taken in and said
  once on the band (Changed in Bukku since the last read), filed by Bukku;
  Bukku's billing person is the contact whose name, or every word of whose
  name, Bukku's holds (Angel in Ms Angel Lim; the only such contact,
  `bukku_person_contact`, `2026-10-30-bukku-person-by-its-words.sql`), as
  Send to Bukku keeps Bukku's whole name; one not in Contacts is said on
  the band with Add as contact, a `.btn-sm` at the line's right edge.
  Edit's Save reads Save to Bukku and sends only what changed
  (`bukku-sync` `save`, `bukku_prepare_with` as the caller, every other
  Bukku detail kept as Bukku holds it), refused `stale` where Bukku moved
  since the read (read in, the sheet kept), Undo where it happened writing
  the earlier values back; SST on quotes and Bill in stay the portal's.
  Bukku not answering reads Not read with the copy's time and draws no
  Edit; Use details from the client's form fills the same sheet and saves
  to Bukku. `bukku_take` (the service role's) writes only the fields that
  differ (a registration no. Bukku sets out otherwise is the same one),
  stamps the row, and writes the copy to the
  record's primary entity (to the brand through `billing_entity_mirror`)
  and files `client.billing` naming the fields (Read from Bukku by Bukku,
  Saved to Bukku, Took Bukku's details); every held link is read again at
  00:30 MYT (pg_cron `bukku-read-nightly`, the wake secret, 100 seconds a
  run, the oldest read first). An entity is the same inside its fold.
  Suppliers keep Send to Bukku as before.
  Secrets `BUKKU_TOKEN`, `BUKKU_SUBDOMAIN` (Supabase only).
- Overdue invoices (`js/invoices.js`, `2026-10-28-overdue-invoice-reminders.sql`;
  the user, 2026-10-28: "pull those overdues data from bukku and inside
  Portal and selectively send by users", Bukku's own reminder "fully bukku
  labeled"): Clients' second view (`#crmViews`, Clients / Overdue invoices,
  `view=overdue`), at Clients: Billing View. `bukku-sync` `invoices` reads
  Bukku's Outstanding and Overdue lists (every page, each invoice once)
  when the view opens and on Read again, never stored and never polled,
  held by `invoice_scope()` (as the colleague) to the Bukku contacts linked
  to a client they see (a contact linked to a billing entity bills every
  brand the entity bills: `clients`, its company `company`, its recipient
  the entity's billing contact and finance email, `invoice_recipient_for`;
  2026-10-29), one linked to no client only for a colleague who
  sees every client. An invoice is overdue where its balance stands and
  its due date (its one term, else the invoice's date) is before today
  (MYT); with instalments, the part past its date (`overdueOf`, a term's
  balances read in full where the list holds none, and where even the
  invoice read whole holds none, what is paid set against the terms'
  amounts in date order, else the whole balance from the earliest date
  passed, `overdueWhole`, never taken for paid), named by the terms it
  covers (Instalment 2 of 3, Instalments 1 to 2 of 3; `partWord`). One
  client's Billing asks Bukku for its contacts alone, and a colleague
  seeing no linked client asks nothing (2026-10-29). A card for each age
  (Over 90, 61 to 90, 31 to 60, 1 to 30 days), totals per currency, never
  added across; each row its last reminder's status (`invoice_reminders`),
  a bounce with Open contacts, Open in Bukku (Bukku's own host alone). At
  Clients: Billing Work the rows are ticks: Send reminders opens Review and
  send (`#odSheet`): one email a client, the clients at the left, the
  email at the right as it arrives, Edit changing that client's subject
  and message alone, Sent before as a table (When, Channel, Sent by,
  Status). Send asks first (Send again where a client was reminded within
  `wa_repeat_hours`, asked again for that client alone; one reminded by a
  colleague meanwhile is refused `recent` and asked about at the next
  Send), then `bukku-sync` `remind` reads each invoice from
  Bukku again, five at a time (one paid, voided or not yet due since is
  left out and named as such), files it first by
  the service role (`invoice_email_begin`: the contact's lock, `sending`,
  `recent` unless asked again, the billing contact greeted with their
  salutation else the main contact, sincerely to a name and faithfully to
  a company, the finance email copied where ticked; an invoice number of 1
  to 60 characters with no control character), builds the table where
  `{invoices}` stands (a View PDF a row for several, one small button for one,
  from Bukku's share link), sends through Resend from `ADspace Finance
  <noreply-finance@sc.adspace.me>` (`MAIL_FINANCE_FROM`), replies to
  einvoice@adspacestudios.com (`MAIL_FINANCE_REPLY_TO`), and closes it
  (`invoice_email_done`, filed `client.edited` on the client). A page never
  files or names a figure: begin and done are the service role's alone.
  Shut while sending, Review and send sends no further email and reads the
  list again once the one on its way answers.
  The words are Settings, Money: Overdue reminder (`invoice_email_template`,
  `team.settings`; two subjects, the message holding `{invoices}`, the
  legal note and the disclaimer, in the lighter grey). Resend's word
  reaches it through `supplier_email_status`. `invoice_emails` and the
  template have RLS on, no policy, no grant. A client's Billing (the
  user, 2026-10-28) holds Unpaid invoices (`#odClient`,
  `ADspaceInvoices.client`): `invoices` with `client`, the contacts of
  every company billing that client (its own, its entities') alone, each
  company under its name where there are several (`.od-co`; the user,
  2026-10-29: "All related entities should be shown as well"), and its
  invoices not yet due as well (Not due); a reminder sent there is filed on
  that client and addressed to the company it is for,
  Send reminder while one is overdue at Billing Work (the same Review and
  send), and its Reminders sent; read on each visit to the pane, drawn
  only for a client linked to a Bukku contact (Bukku's group above says
  when it is not). No Bukku branding; WhatsApp
  reminders are not built (the user, 2026-10-28: "dont build the whatsapp
  first").

### Content Review (`review/`, `js/review.js`, `js/mockups.js`)
- The client's gallery (`.shell-review`, 1480px, cards from 300px) runs four
  posts across on a desk from about 1400px and three at 1280.
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
  - A story draws no caption on its frame; its words are under Copywriting.
- A video waits on black under one play button (`.mk-play`, `js/mockups.js`)
  and plays in its card; the browser's own bar arrives once it plays. A press
  on the button or the video never opens the canvas (moving a video that has
  just started stops it: Edge spun, Safari opened the canvas); Close carries
  a playing video on in its card.
- The cover image card names itself once, in its head, and ends under its
  decision (`.is-cover`).
- A card's head is the original white head with no platform colour (the
  user, 2026-10-03), one line at every width (the title gives way first),
  and gives the shape as a ratio (`ADspaceMockups.ratio`: the file's size,
  within 3% of a common ratio reads as it), never pixels.
- A reel and its cover are one card (`.cardpair`): the reel's head, Reel and
  Cover as a view strip with each half's state in its tab, then the half on
  show. The cover names its reel (`posts.cover_for`, no foreign key; sent by
  `get_review_feed`, `2026-10-03-reel-cover-pairs.sql`); each half is still its
  own post, decision, round and canvas, the stage strip counts posts, and a
  pair opens on a half that matches the stage, and both tabs always show
  their half (`showHalf`; the user, 2026-10-03: a reel with changes
  requested opened on nothing). A pairing is not a revision.
  Add assets pairs a cover with a video by file name (`launch.mp4`,
  `launch-cover.jpg`), every name first, else the first free video after it
  (every pair the team has made has its video right after its cover), else
  the nearest before it, as a Cover for choice kept by hand. On the set page
  a video and its covers are one linked card (`.saved-pair`: a shaded frame,
  the video's row then the cover's, a line drawn from picture to picture;
  each row keeps its own state, ⋯ and notes; shown while either half is in
  the chosen stage, the other faded); a cover's ⋯ Pair with video changes
  or clears it (`post.edited`), offering only videos no other cover holds.
  A cover waits while it names no video the set holds (one whose video was
  deleted waits again). A video is named by its number in the set (shown on
  its row) and its title, else its caption's first words, else its file.
  While a cover waits, a line over the posts counts them with Pair covers
  (`#pairNote`, Work) opening `#pairSheet`: one card a cover, the cover and
  the proposed video (the same order rule; a video a paired cover holds is
  neither proposed nor offered) side by side at 9:16, the video playable,
  its select and a Pair tick;
  the foot reads Pair n, writes only ticked cards naming a video, refuses
  one video for two covers, files `Covers paired: n`, and draws Undo over
  the posts (`Covers unpaired: n`).
- The client's page opens on the client portal's name card (`#rvHead`: mark,
  name, handle and post count, `N to review` counted at load); the bar no
  longer names the client. The creator selection page opens on the same card
  (`#campHead`: the client's mark, the campaign, the client).
- A post is revised in place (`2026-09-30-post-revisions.sql`): a change to
  its file, copy or title after the client decided on its round is the next
  round (trigger `posts_revision`; `reviews.round` stamped by
  `reviews_round`), and the round it replaces is kept whole in
  `post_versions` for the team. Before any decision an edit is a
  correction. `get_review_feed` sends the round on show, the decision on it
  only, and `asked` (the request on the round before); never an earlier
  round's file or copy. The client's card heads the request it answers
  `Changes requested by {name} · {date}` (`.reask-head`), the note on its
  own line under it; never "Revision N" or "You asked" (the team's words).
- Both sides list posts under the stage strip (`.tabrow`: Pending,
  Changes requested, Approved, All, each with its count). The client's
  (`#stageStrip`) opens on Pending and is counted at load: a decision
  repaints its card but moves it only on the next load. The console's
  (`#postStages`, drawn once a decision exists) opens on Changes requested.
  On a phone the strip is the column's width, its tabs sharing it and
  Changes requested reading Changes (`.tab-short`).
- The caption is edited where it is read: Edit text beside Copy text at
  the heading's right (`.copyacts`, two small tonal buttons with their
  glyphs; `.copy-pen` hidden the moment a post is approved, shown in every
  other state, never only after a reload) turns each caption into a field in
  place and opens Request changes under it for a note and the name. While
  a request is open Approve and Request changes step away
  (`.approve.is-requesting`), so Cancel and Send request are the only acts;
  a failed send keeps the request and the edit open. A
  request takes a note or a caption edit, sent only where changed and kept
  as `reviews.suggested_caption[_zh]`; the console shows it as Suggested
  caption with Accept caption (the next round), whose Undo puts back the
  round kept in `post_versions` (`review_caption_undo`, refused `moved`
  once that round is decided or its file, title or caption changed since;
  2026-10-15). The noun is caption, never
  copy. The console's Edit replaces the file, uploaded at Save.
- A request not yet answered is changed with Edit request (the Request
  changes button while one stands): it reopens with the note and the
  client's own caption edit (`get_review_feed` sends `suggested_caption[_zh]`
  on the standing decision), and sending again replaces it. Approve over a
  standing request arms first in place (Approve as it is, "Approving
  withdraws your request for changes."), and the console keeps the request
  it replaced in sight (Earlier request). The decision pair and the
  request's Cancel / Send request are equal halves. While the request is
  edited its standing note steps away; leaving it (Cancel, or the armed
  Approve disarming) repaints the decision line, never blanks it. The note
  and the caption fields grow with their words to 60% of the screen.
- Confirm internally (`2026-10-01-review-confirm-internally.sql`) is the
  team's approval on the client's word, in a post's ⋯ in the console only
  (Content Review sets at Work, a published set, not already approved):
  `review_confirm` writes a `reviews` row with `source` team under the
  colleague's name, filed `review.approved` … confirmed internally. The
  console row reads Confirmed internally by {colleague}; the client's page
  reads Confirmed by {client name} on {date} (`by_team`), never the
  colleague; the feed sends a team decision with no reviewer, so the
  colleague's name never reaches the client. Its way back is Revert
  confirmation (`review_revert_confirm`, never asks, filed
  `review.unconfirmed`, Confirmation reverted): the row is kept with
  `undone_at`, only a team approval can be reverted, and the post falls
  back to the decision before it. Every read of `reviews` skips undone
  rows. A client's own approval is asked again with Request re-approval.
  Confirm internally shows only on a published set. The post ⋯ items carry
  their parts (`review.sets:work`; Delete `review.sets:manage`).
  `review.approved` reads Approved (the actor says who).
- A decision is on the version on show (`2026-10-10-approval-as-seen.sql`,
  audit F2): `posts.content_version` moves with the file, copy or title
  (trigger `posts_content_version`, never set by a write), `get_review_feed`
  sends it as `version`, and the page decides through
  `submit_review_seen(… p_version)`, which refuses a post changed since
  (`changed`: "This post was updated after the page opened. Please refresh to
  review the latest version.", with Refresh; a request for changes so
  refused is kept in the tab and reopened after it, its caption edit only
  where the caption stands; 2026-10-27, RVP-3) and keeps what was decided on in
  `reviews.seen`; `ADspaceAPI.submitReview` sends a decision with its
  version through `submit_review_seen` alone, a refusal never sent again
  without it (2026-10-22, BE-13).
- Approve needs a name. Approved reads outlined, with Request changes hidden.
  - The Copywriting label, and the copy control at the top.
  - No Save as PDF.
  - og:title `{client name} Content Review Portal by ADspace`, on `review/`
    only.
- The Review Canvas moves the card's own blocks and puts them back; there is
  one decision control. Prev/next, the arrow keys, Escape and a sideways
  swipe on a phone work. The head is the name (its size under it on a
  phone), then Previous, `n of N` and Next as one group, then Close at the
  right edge, the three filled tonal buttons. Below 860 it is one scroll: the
  post whole, then its copy and the decision; each post opens at its top.
- Console:
  - The client is a record: the mark, name and handles, and one ⋯ (Access
    code as a sheet with one Save, the handles and logo Brand's alone since
    2026-10-29, Reset link, Remove), the review link under it as every record's client link
    (`.rec-linktools`: the address, Copy link, Preview; 2026-10-10), the
    address and Copy link the review page's own link, Preview the page;
    a published set's head adds Copy link (`#copySetLink`, beside
    Publish, equal halves on a phone) for that link with `#s-{first eight
    of the set's id}` (2026-10-12; full links since 2026-10-15); the
    sets are a card a content month (`batches.period`, YYYY-MM, empty for
    Ad hoc; `2026-10-10-sets-by-month.sql`), newest first and open, Ad hoc
    last, a row a set (name, the state at the right, the post count read for
    every set in one request) the page's width. A new set takes this month
    (MYT); the set's ⋯ Content month changes it (last month to six ahead, or
    Ad hoc; filed `set.month` from and to), and the set's head names its
    client, then it, before whether the client sees it. Engagements files a set by its month,
    an Ad hoc one by the day it was made. A post is a row: the placement with the
    client's decision at the right, the file, the copy, and one ⋯ (Edit,
    Request re-approval, Delete); the re-approval note opens under the post.
  - A set is a page of its own (`set=`): its head is the record head (the
    name with the quiet `.rec-pen`, who can see it under it, the state and one
    ⋯ with Delete at the right edge, Publish at its own width below), its
    posts, and a rail (the client's
    review, the tasks naming it). Back returns to the client. Add assets is a
    sheet (`#assetSheet`) that shuts on Add to set.
  - A file over the size cap (S3's `s3.maxUploadMB`, else Supabase's) is
    refused at the pick, by name. A picked or Drive-read file stays on the
    device (an object URL preview) until Add to set, which uploads what is left with progress, then writes
    the posts; a removed file costs nothing. Cancel aborts; a failed upload
    keeps its draft; only uploaded drafts are kept for a reload; leaving
    with a file held asks first.
  - A video's thumbnail in a console row is its cover frame (`poster`),
    else its first frame (`#t=0.1`, `playsinline`), through `thumbOf()`:
    a bare `<video>` is blank on iPhone Safari until it plays. One whose
    file fails, after the media pass's retry, is a shaded tile with its
    kind's glyph (`.thumb-miss`), never the broken picture.
  - Sets are folded, one open at a time. Opening a set clears the last
    one's strip, covers line, progress and posts (`clearPostView`), and a
    read answered for a set already left is thrown away
    (`tests/crswitch.js`).
  - Publish (blue) / Unpublish (tonal); an empty set draws no Publish and
    Add assets is its blue (2026-10-15). Unpublish asks nothing and draws
    Undo where it happened (Unpublished. The client no longer sees this
    set.), which publishes it again (2026-10-20, REV-1). A client row and a set row count
    the posts whose latest decision is Changes requested (red dot), counted
    by `review_set_counts` in one request, never a read of every post. Add to set is Add assets' sheet foot.
  - Enable client (`#crEnable`, the bar's one action, Content Review
    settings at Work; the user, 2026-10-12, in place of Manage clients):
    drawn only while an Active client is out of Content Review (one read of
    the Active clients serves the list and it), it asks which
    (`ADspaceConfirm`, code first) and puts that client in through the same
    write as Remove's way back (`client.review_on`), Undo where it happened.
  - Resend with a note.
  - Drive import with progress (a folder link only).
  - S3 signed PUT.
  - Active clients only.
  - A set's name grows out of New content set; a title is renamed in place.
- Select posts (the set's ⋯, `review.sets:work`): a tick stands where each
  post's ⋯ was (`.saved-pick`), the row its target; the bar under the stage
  strip (`#postBulk`) counts the ticked posts shown and offers, each through
  what one post takes and refused against its post: Confirm internally (a
  published set, posts not approved; asked, `review_confirm`, Undo
  reverting each), Request re-approval (posts the client approved; one
  reason for all, filed per post) and Delete (`review.sets:manage`, red,
  the count typed back, `.select('id')`). A set opened afresh holds no
  ticks.
- Deleting a set is `can_remove` / Manage, drawn behind it
  (`body.no-remove #deleteSet`). Both deletes take `.select('id')`.
- Remove (the Content Review client's ⋯) hides the client and nothing else
  (`clients.review_hidden`, Content Review settings at Work, asked in warn
  with nothing typed): every set, post and approval is kept, Undo is drawn
  over the list, and Enable Content Review on the client's record is the way
  back later, with the same link. While hidden the link opens nothing
  (`get_review_feed`, `submit_review` answer `not_found`;
  `2026-10-03-hidden-from-content-review.sql`).
- A new lead or client starts outside Content Review (`review_hidden`
  defaults to true, `2026-10-19-content-review-by-hand.sql`; the user,
  2026-10-19: "make it manually"): it joins only when a colleague enables
  it (Enable client in Content Review, Enable Content Review on the
  record); a client standing before kept its place.
- Every everyday write leaves an activity row. An edit names the fields it
  changed.
- Write with AI (2026-10-08, one caption from 2026-10-10; the user: "one
  post only allowed one caption"): under a post's caption field in Add
  assets' drafts and a saved post's Edit, at Content Review: Sets at Work
  (`.capwrite`, `writeCaption()`, the AI mark before the words). A post has
  one caption; the 中文 field is drawn only on a saved post that already
  holds Chinese. It asks first (`ADspaceConfirm`: n captions left today;
  Language, a select of English, Bahasa Melayu, 中文, English and 中文
  (`CAP_LANGS`; both languages in the one caption, English first), from the
  main contact's preferred language; XHS Safe Mode on a
  rednote post alone, unticked until the colleague ticks it; Notes for the
  caption, kept in this browser under `adspace-caption-notes:{post id}` or
  `{set id}:{draft key}`, else the brief of a task naming the set), then
  `caption-draft` (Verify JWT off, as `report-draft`: it asks
  `allowed('review.sets', 'work')`, reads the set and client as the caller,
  claims `ai_caption_claim(p_batch)` before Claude, marks `ai_draft_done`,
  keeps tokens through `ai_draft_tokens`; secrets `ANTHROPIC_API_KEY`,
  `CAPTION_MODEL`, unset `claude-opus-5-5`; sends the placement, the set's
  and post's titles, the notes, industry and market, never an image, a
  contact or the client's name: the name reads `{brand}` and a handle
  `{handle}`, filled on the page with the name and the platform's `@handle`).
  The words go into `caption` in place, saved only by the post's own Save
  (Add to set for a draft), with Undo where it happened (Written by AI. Read
  before saving.) putting the earlier words back; a refusal is one line
  under the button. Saving words written with AI asks the declaration
  first (`ADspaceConfirm.ai.declare`: Written with AI, read in full, the
  person who confirms is responsible and an error may be raised in their
  performance review; a tick that refuses until ticked), filed with the
  save (… written with AI, read and confirmed). Words typed by hand ask
  nothing.
  The house style (benefit first, a hook, an emoji and bold title where it
  suits, one CTA, no dashes, MY/SG context, Chinese written as Chinese, the
  platform's own voice, brand names exactly) and XHS Safe Mode's rules live
  in the function's `SYSTEM` and `SAFE`.

### Creator Campaigns (`js/campaigns.js`), creators, the creator portal
- Booking steps:
  - Confirmed → Pending visit → Pending draft → Submitted → Reviewing →
    Changes requested → Scheduled → Posted → Completed, each gated by its data,
    each with Revert.
  - Withdraw / Replace / Reinstate in the ⋯.
  - Deleting a campaign or a creator takes the name typed back; every
    campaign write takes `.select('id')` and names a refusal (Confirm
    creators counts the bookings not confirmed).
  - In production and Completed are derived (`syncCampState` off
    `loadOptions`): every booked creator at Completed completes the
    campaign, one reverted puts it back in production, none open returns it
    to Open, and an Open campaign whose bookings fill every slot again (a
    creator reinstated) is in production; filed `campaign.stage`. Nothing
    presses it. Open with bookings and a free slot is a reopened selection.
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
  - The sheet reads the request the file answers and its caption first
    (`#qcCap`; `No caption.` in warn when there is none).
  - A file added or removed while Submitted voids that round's checks
    (`option_qc.voided_at`, trigger `campaign_deliverables_qc_void`); the
    same colleague's check is taken again (`2026-10-10-released-files.sql`,
    audit S5).
  - Release stamps `campaign_options.released_round` (the newest round
    handed in), and `get_campaign` sends that round's files alone, never a
    round handed in after the client asked for changes until it is released
    in its turn, never a hidden file.
- Every decision on a draft is a row in `option_reviews`, told apart by
  `source` (client, team) and never removed (`undone_at`, `undone_by` when
  taken back): the client's through `review_draft`, the team's send-back
  through `campaign_send_back` (a note required; the round moves on), and
  the team's approval for the client through `campaign_proceed`.
  - At Reviewing the card offers Confirm internally (asked first) in place
    of the plain step forward: a `source` team approval under the
    colleague's name. `get_campaign` sends it as `by_team`, and the client's
    page reads Confirmed by {name}. Revert out of Scheduled is
    `campaign_revert_approval` (the approval kept, undone). The card names
    who approved (`.kapproved`).
  - The card shows the open request (Changes requested, who, when, the note)
    and, once the creator hands in again, what it answered (Asked for;
    `requestHtml`). A team round from before the record is `drop_reason`.
  - Revert out of Changes requested is `campaign_revert_changes`: the
    client's back to Reviewing on the round last checked (refused
    `new-files` once the next round is handed in), the team's back to
    Submitted. A plain write into Reviewing is refused by the release gate.
  - `get_campaign` counts the client's own rounds only and never shows a
    request taken back. The client's page shows no round count.
- A handed-in draft always shows its caption field, with `No caption.` in
  warn when it is empty.
- A booking card has one Save: its notes and link, then each placement
  whose results moved (2026-10-20, CMP-5); from Scheduled on it offers no
  hand-in guide or link to paste (CMP-4), and Release to client says
  Released to the client. on the card (CMP-6). Its actions stand at the
  card's foot, after Results, reading Revert, Request changes, Save, then
  the step forward at the right edge (its own row on a phone); an empty
  note is a quiet Add note growing into the box, a result figure reads
  with its separators, and every step taken on a card is answered on that
  card (`cardSay`), never in the head (2026-10-22, CMP-7, CMP-10, CMP-16,
  CMP-M2). Bookings and the Schedule list booked creators alone, a
  shortlisted one staying on Selection (CMP-13). The record says post,
  never publish, of a booking's date: Post date, Next post date, Posted on
  (CMP-11); a time reads 2:00pm (CMP-12). On a phone a move that is not the
  blue Publish (Unpublish, Reopen selection, Resume campaign) is the head
  ⋯'s lifecycle item (`#campLifeItem`), never a row above the tabs (CMP-M1).
- A booking's plan (date, a time picker, location, contact, phone, or the
  tracking no.; draft due; post date) is written only on the Schedule,
  saved on change and filed with what changed. The card reads it
  (`planFacts`, Edit in Schedule) and keeps only the notes. The creator's
  page shows location and contact. The Schedule is the Creators tab's
  register (`.bookreg.sched-reg`): Upcoming then Past, a folded row a booking
  (name, shoot date and time, post date; Not set where none; where the
  head is hidden each date leads with its head's word, Shoot or Delivery,
  Post date; on a narrow pane each date its own line under the name), the plan's
  fields opening under the row on the name's x; a booking stays open through
  a save, and a lone booking opens by itself. On a phone Draft due and
  Post date share a line.
- The client's selection closes by trigger the moment the bookings fill the
  slots (`campaigns.selection_closed_at`); only Reopen selection clears it,
  offered only while closed with a free slot, whether the campaign is Open
  or In production (every booking reverted puts it back to Open, still
  closed; 2026-10-10). While closed, `save_selection`
  and `confirm_selection_with` refuse (`closed`), except backups where opened and
  every slot is taken. The Creators tab folds options and backups under Not
  selected (`#campUnpicked`) while closed.
- The one stage step in blue on a card is Release to client; every other
  step, and every Save on the card, is tonal. A shoot date moved moves Draft
  due only while it is empty or still the old date plus 7, said on its row
  (2026-10-15).
- Each booking's card names its step under its head (`.kcard-steps`), the
  client's six steps as the selection page draws them (`ADspaceIcons.journey`,
  `stepOf`), a delivery campaign's own; none before the creator is booked
  and none once Completed. On a phone a booking's head is two lines: the
  name (one line, cut with an ellipsis) with its link and ⋯, then the
  state (its dot and whole word, never shortened) at the left and its date
  at the right (the user, 2026-10-15; `tests/geom.js`). A completed campaign offers no state move (no
  Resume, no Unpublish: its link stays live for the results).
- `submitted` opens by itself and carries `.is-waiting`.
- A video plays (`.filecard-video`, 9:16, black ground). Media are 9:16 cards;
  anything else is a `.filepin-row` line.
- The team hands a file in for a creator (`teamDeliver()`, at pending draft /
  changes / submitted), with `campaign.file_added`. 1 GB per file
  (`ADSPACE_CONFIG.s3.maxUploadMB` 1024). Picked files are held on the card
  (`teamHeld`, × each) and upload only on Hand in N files.
- Removing a handed-in file arms first (`.filearm`), then soft removes, then
  offers Undo in place, until the client approves (audit S6, the user,
  2026-10-10). From Scheduled on a file is the client's record: its control
  is Hide from the client (the struck eye; `campaign_file_hide`, Creator
  Campaigns: Campaigns at Work, client scope, filed `campaign.file_hidden` /
  `campaign.file_shown`, Undo where it happened), it waits under Hidden from
  the client (`details.filehidden`, Restore, never asks), and only the granted
  part `campaigns.files_delete` deletes it, once hidden, from its ⋯
  (`campaign_file_delete`, asked, `campaign.file_deleted`; the stored file
  is kept). Trigger `campaign_deliverables_guard` (as the caller) refuses a
  page removing an approved file (`approved-hide`) or setting the hidden
  columns (`hide-function`). `campaign_deliverables` reads at Campaigns View,
  adds and changes at Work and deletes at the part, four policies.
- A campaign name that would render as nothing reads `Untitled campaign` and
  stays editable. A new one is refused on save.
- The campaign's form is one sheet for New campaign and Edit (`#addCampBox`);
  the record's ⋯ holds Edit and Delete, last.
- The campaign record:
  - Its panes (`pane=`) are Overview, Creators, Schedule, Selection,
    Finance, Activity; the address's pane is read before the address is
    written, and a new campaign opens on Creators (2026-10-27, CMP-17,
    CMP-18).
  - A draft with no creator draws no Publish and Add creators is its blue,
    the empty list offering no second one (2026-10-20, CMP-1).
  - Below 1100 Details, Key dates and Timing follow the pane (`.rail-after`);
    Selection stays before the tabs (CMP-2).
  - Selection is a view over the bookings. It never writes.
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
  - With `ADSPACE_CONFIG.s3.privateInvoices` on (after
    `docs/S3-STORAGE.md` §5), the PDF is signed under `private/` and the row
    keeps the key, never an address; View invoice and the client's PDF link
    ask `sign-download` for a five-minute link, the file found from what the
    caller may read (the campaign row; `get_campaign` for the client's key),
    never from a path the browser sends, and only a key under the campaign's
    own client's folder (`private/{client id}/`; `tests/signdownloadfn.js`).
    The link is a CloudFront signed URL on
    mycdn.adspace.me while `cf_private_ready` is `on` in `app_secrets` (on
    since 2026-10-03, `docs/S3-STORAGE.md` §5d), else an S3 presigned one. An older invoice keeps its public
    address. A refused open on the client's page is one line in its
    language (`#amountMsg`).
  - Remove PDF, with Undo.
  - `get_campaign` withholds `invoice_no` and `invoice_url` until a creator is
    confirmed.
- Confirm creators is reachable from Client selection, from the Creators tab
  (`#campLock2`), and from the header line's Review and confirm (`#campNextGo`).
- Confirming is one act a press (audit F1, S3, C1;
  `2026-10-10-confirm-once.sql`): the selection page's Confirm sends the
  creators on screen, the rate shown for each and a key made as its sheet
  opens to `confirm_selection_with` (anon; `empty`, `closed`, `over-slots`,
  `stale`, `prices` with the rates now), which saves the selection and files
  the confirmation with what was confirmed (`snapshot`) in one transaction;
  a refusal for rates or creators reads the campaign again under the open
  sheet, said in the client's words. The console's Confirm creators is
  `campaign_confirm_creators` (Creator Campaigns at Work, client scope;
  `stale` with the count): the confirmation, the bookings and the campaign
  move together, filed `campaign.locked`. The same key again answers `again`
  and files nothing. The older `confirm_selection` is dropped (2026-10-26).
  `get_campaign` sends the client's last confirmation (`campaign.confirmed`:
  person, time, the creators chosen); while the picks match it the bar reads
  Confirmed by {name} on {day} with no Confirm (2026-10-15).
- A campaign never books more creators than its slots
  (`2026-10-18-slots-hold-their-bookings.sql`): `confirm_selection_with`
  and `campaign_confirm_creators` refuse `over-slots` (with `slots` and
  `booked`) where those booked (`campaign_booked`) and those confirmed now
  pass the slots, and trigger `campaigns_slots_floor` refuses slots below
  the bookings (`slots-booked`), whoever writes them. The selection page
  reads `over-slots` in its own words with how many may still be chosen
  (`overSlots`), shuts the sheet and rests Confirm while the picks and the
  bookings pass the slots (2026-10-20, SEL-1). The autosave
  (`save_selection`) counts the booked alike (`over-slots`, 2026-10-26).
- A client's confirmation is the record of what was accepted
  (`2026-10-18-confirmations-kept.sql`): `campaign_confirmations` is
  written by `confirm_selection_with` and
  `campaign_confirm_creators` alone (its insert, update and delete policies
  admit nothing), keeps the campaign's title and client (stamped on insert),
  and has no foreign key, so a deleted campaign leaves it. A campaign's
  delete is filed by trigger `campaigns_deleted_log` (`campaign.deleted`,
  the title and invoice number); the page files nothing.
- Timing (`paintCampTiming`) is read from `campaigns.state_log`,
  `campaign_confirmations.created_at`, `confirmed_at` and `completed_at` (all
  stamped by triggers). A stage it cannot date is left out.
- The Creators List:
  - Creator · Profiles · Campaigns · Client rate · ⋯, with no monogram. The
    figure is the client's price with markup, never the creator's payout, so
    it is never headed Fee.
  - Rate bands: Up to RM 300, RM 301 to 500, RM 501 to 800, Above RM 800, On
    quote. Inactive in its own band.
  - A platform filter.
  - The record cell counts and dates (`DONE_STATES` from `confirmed`,
    `submitted` included) and never names a campaign.
  - `nameKey()` trims, collapses whitespace and ignores case. The name is
    stored that way, and the duplicate is refused before any link is typed.
  - The word is Creators List, never "roster".
- A campaign's rates are in the client's currency (`mkt()`): for a client
  billed in S$ the Creators List's RM is turned at `fx_sgd` to the cent and
  the field reads S$, left empty while no rate is set; a creator made from
  such a campaign keeps the list's rate in RM (2026-10-22, CMP-1).
- Adding creators, its Undo and Remove are filed under the campaign
  (`campaign.offered`, `campaign.unoffered`); Remove asks nothing and
  offers Undo, which puts the same row back (2026-10-22, CMP-3, CMP-4).
- Add creators is a sheet (`#addOptionBox`, 2026-10-10; the user: "messy …
  no proper grouping"): the strip Creators List / New creator; a search by
  name or handle and a platform; the Creators List's fee bands (stood down
  left out) and Already in this campaign last, each its state; a tick a
  creator opening its client rate and platforms, prefilled from the list;
  the foot's count and sum of the rates, and one Add N creators inserting
  every tick at once (all or none), Undo where it happened. A creator
  withdrawn or replaced here (not goodwill) is offered from the same list:
  their one row (`unique (campaign_id, creator_id)`) moves back to Offered,
  its reason cleared, filed `campaign.reinstated` … offered again. Ticking a
  platform with no link grows the box into the field (`.pbox`), saved to the
  creator through `readProfile()`.
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
    record. Typed, it reads as printed, `7K2M-9PQR`: the dash comes by
    itself after the fourth character and goes with a deletion (`codeShape`;
    the user, 2026-10-27), and is never sent. Its eighth character, typed or
    pasted, checks it with no press (`autoCheck`; the same code is not sent
    again until it changes, nothing while an input method composes; Open
    stays). A wrong code is counted against the caller's address
    (`creator_code_try`, `link_tries` kind `creator`,
    `2026-10-27-creator-codes-counted.sql`): five within 15 minutes lock it
    out, the right code included, for 15 minutes, then an hour, then a day;
    a right code resets nothing; no count across addresses. `get_creator`,
    `creator_set_profiles`, `push_subscribe` and the creator branch of
    `share_link_preview` all ask it; the page says `locked` as a link's lock
    is said (`W.lockedLine`).
  - `get_creator` sends the creator's own booking only.
    - Never the client's stage, commercial state, amount, other creators or
      the team's notes on the row.
    - It sends the open request's note (`change_note`) from the record,
      either side's and never one taken back (a team round from before the
      record reads `drop_reason`). "As noted below" is said only where a
      note is below.
    - Never `rate` or `currency`: the rate is the client's price with markup.
  - Uploads: `creator_can_deliver` at pending draft / changes / submitted;
    `creator_can_retract` shuts at submitted.
  - A file's kind falls back on its extension (`typeOf`, `kindOf`,
    `mediaKind()`).
  - Signed PUT via `sign-upload`, using `creator_may_upload` with a key built
    from the verified option. `creator_add_file` records only the address
    `sign-upload` made for that booking (`bad-file`), a name of 1 to 255
    (`bad-name`) and a kind of image, video or file (`bad-kind`;
    `2026-10-17-creator-files-held-to-their-folder.sql`).
  - Picked files are held on the device (`held`, `.filecard.is-held`, ×
    each) and upload one by one only on Submit or Update; each row is
    written after its file is stored. A failure keeps that file held and
    hands in nothing; every failure is named after the repaint.
  - A caption typed and not handed in is kept a booking in this tab's
    session (`adspace-creator-drafts:{code}`), through a booking switch, the
    language and a repaint; Submit and Forget this device clear it, and
    leaving with it asks first. Nothing but Submit sends it (audit F4,
    `tests/capdraft.js`).
  - Payment details (AP01) are asked for once posted (`payDue`: posted only),
    never on the draft's approval, and the line never says Approved.
  - `creator_rate` takes 1 to 5 at completed and is never shown to the client.
  - Post and results (Scheduled, Posted; read-only at Completed): per
    placement, the post link (the platform's own host, `post_link_ok()`),
    its date, and views, engagements and impressions over the count period.
    `creator_post_save` writes them (`entered_by` creator, filed
    `campaign.results`; a link holding `"`, `'`, `<`, `>`, a backslash or a
    backtick refused `link`, `2026-10-17-post-links-plain.sql`); numbers are refused (`period`) until the team sets
    `measure_from`/`measure_to`, which only the console writes; until then
    the page says nothing about the period. The first link at Scheduled
    moves the booking to Posted.
  - The countdown is amber, then red once passed.
  - The page is a queue ordered by what is owed, with one booking open in
    `location.hash`. A lone booking has no queue and runs the page's width.
  - A completed booking ranks with the ended ones, faded last, and the page
    opens on a running one; its card is its name and state, the rating while
    not given, and Booking details folded shut with no steps
    (`.booking-fold`; the user, 2026-10-14: "subsequent new bookings could
    be the main focus").
  - The open booking (2026-10-08): its six steps by name
    (`ADspaceIcons.journey`; Submitted and Reviewing are Review); what is
    owed (Next up: Submit your draft, or the revision, its countdown, the
    change note, the files and one large Add photos or videos area, the
    caption opening two lines) above the facts, else where the booking
    stands as one line in ink there (`.cx-status`), so after Submit it is read
    without scrolling; the facts carry their glyphs, the place Directions
    (Google Maps), the contact WhatsApp and Call.
  - The Draft step's `?` hint opens by itself three times, then retires
    (`hint()`, `bumpHint()`).
  - Sign out is named, and hidden until there is a session.
- Creators selection page (`creators/`, `js/creators.js`):
  - The detail card is folded and shut by default. The purpose and brief sit
    inside it; the due date (else the count) is on the head.
  - When the slots fill, the unpicked leave.
  - At 640 and under (the phone line, a folded-open phone at 626 too) a
    creator's row is the phone's: no column heads, the name over its
    placements (Posting on), the profiles and Backup under them, the fee
    at the right of the first line on every row (the iPhone Duo pass,
    2026-10-18).
  - Backups only with `campaigns.backups_open` (`save_selection` refuses
    otherwise).
  - A placement line on each row (`platsOf()`).
  - The campaign room (2026-10-08): under the name card, where it stands (n
    of N posted, a segment a booking in its state's dot, a legend, the next
    shoot); a booking waiting on the client (a draft at Reviewing) leads the
    page in its own card (`#needBox`: Waiting for your approval, the draft and
    the decision) and leaves the list below while it waits; each booking is
    numbered, never a photo (the user, 2026-10-07), the numbers carrying on
    through Available creators, with its six steps by name (a Submitted draft
    is the client's Draft step; none once Completed, 2026-10-10); the results
    lead with one figure (views, else impressions), then impressions,
    engagements, engagement rate and per engagement, and the top post where
    more than one is live.
  - Each live post on a booking reads as the Top post does (`postRows`,
    `.cx-post-item`; the user, 2026-10-10): the booking's picture, the
    platform and its day, views (else impressions) and engagements as glyphs
    named for a screen reader, Measured {day}, and View post on {platform}
    (`.postlink`; 查看小红书笔记 in Chinese) at the row's right edge at a
    desk, the card's full width on a phone. Never a results table. The
    campaign's one live post keeps its figures in the results card alone.
    The card's Posted and Posting on facts leave once a post row says them;
    the approval line leaves once the post is out.
  - A draft is decided on the card (`draftPreview`); in `#needBox` at a
    desk the pair stand 220px each at the card's right edge, Approve last,
    and Open the draft at its own width (2026-10-22, CP-17); a phone keeps
    equal halves.
  - `review_draft` rules on a draft at Reviewing alone, the booking held
    while it does (a page left open from before a request for changes
    cannot approve the unrevised draft; audit 2026-10-29).
  - `review_draft` logs under the typed name. `get_campaign` sends the last
    review.
- Client-side decisions write an activity row under the typed name:
  `submit_review`, `confirm_selection_with`, `creator_submit`, `creator_rate`,
  `portal_withdraw`. `save_selection` does not (it autosaves).

### Dashboard (`js/overview.js`, `?s=dashboard`)
- Named the Dashboard on the screen (the rail, the tab bar, the heading,
  its guide; the user, 2026-10-11). Its address is `?s=dashboard` (the
  user, the same day), written by `queryNow()`; an old `?s=overview` opens
  it and reads `s=dashboard`. Inside, the route, `sectionOverview`,
  `ADspaceOverview` and the access key stay `overview`. A
  record's first pane (a client, a campaign, the client portal) stays
  Overview.
- The start page of a group one of whose cards is allowed
  (`ADspaceOverview.any()`, asked by `sectionAllowed('overview')`): Full
  Access on a section with no card (Short Links, Services, Team) is never
  offered an empty page. `firstAllowed()` lists it first, then the rail's
  order with My Work first, the Handbook the floor, so `/admin/` with no
  `?s=` lands there, and every other page names itself (the Clients list
  writes `s=clients`; a client's record reads as Clients from `client=`
  alone). Anyone else is never offered the row and its address falls back.
- A group may hide it (Team's group panel, Dashboard On / No Access; the
  user, 2026-10-11, option A): `overview` in the access map, stored only
  as `none` (On stores nothing, as every group stood before), read by
  `sectionAllowed('overview')` for anyone not an admin, page-side alone
  (no policy or function reads it; members copy the map by trigger). It
  only hides the page; every card still asks Full Access on its section.
- Two pages, from the mockup the user approved (2026-10-12, task 47;
  `digital-form-tests` `mockups/dashboard/`) and then read as the company's
  director would (the user, the same day: "act as the company ceo"; the
  second page "continuous instead of hiding"): Summary, then Detail, the
  strip `#ovwPages` (the view strip, `pg=detail` in the address, Summary
  left out) at the bar's left, a sideways swipe anywhere on the page
  turning it as the strip does (`data-swipe="ovwPages"`; the user,
  2026-10-12); every turn slides (a still copy of the page left moving out
  as the new page comes in from the side moved toward, Detail from the
  right, `--t-slow`, the bar holding still, the copy clipped below it), and
  at each page's foot the way on
  (`#ovwTurn`: Continue to Detail, Back to Summary). The bar's right holds
  the period (`#ovwPeriod`, a select of This month, Last month, This
  quarter, Last quarter, This year: five, so never a segment; `p=`, This
  month left out; each measured on the period before it the same days long,
  Last quarter on the quarter before, This year on last year), with the
  span and the time read beside it; both pages read the one period.
  - Summary, in this order (2026-10-22, OVW-M1; the user's "Fix all"
    reopening the order approved on 2026-10-12): the glance (`#ovwGlance`,
    the rings alone: the on-time ring, `ADspaceChart`
    `meter` from `ops_report.on_time` for the period: met over the tasks
    that reached client review plus `late_open`, the open work late by the
    late rule, counted in the period its deadline fell in and in one that
    runs to now (`2026-10-19-on-time-counts-late-open-work.sql`), empty and
    reading a dash where nothing was due; beside it the Posted on time
    ring from `ops_report.posted`: of the content whose post date (MYT)
    fell in the period and has passed, or which went live, how much went
    live by its post date, as the review's On-time posting reads it
    (`2026-10-19-posted-on-time.sql`; the user, 2026-10-19: on-time
    delivery stays the team's own measure)); then Needs attention
    (`#ovwAttention`): one list of every source (late
    tasks, open work for paused and past clients, reports owed and in
    review, cold leads, restricted accounts, requests, sets waiting, no set
    this month, bookings past their date, the quality check, unsigned
    letters, last month's reviews, overdue invoices at Clients: Billing
    Full Access, a row a client opening its Billing, counted and never an
    amount), its head a strip of the sources
    holding rows (`#ovwSrcs`, the view strip at the card's width: All, then
    each source's short word and count, red where it holds late work; a
    tab narrows the list to it; one source draws no strip and the head
    counts it), What · Section (a grey tag naming the
    rail's section, never a record's kind; 2026-10-20, OVW-3) · Who ·
    Since, late first by the days late, then what waits, the longest first,
    then what has not started; five rows, then Show N more, a tonal toggle
    with its chevron that reads Show fewer once open and folds the list
    back to five (the user, 2026-10-12: "5 show only"); a row writes the
    record's address and opens it as search does; then Sales (New leads,
    Won, Churned, Committed monthly value)
    and Operations (Open tasks, Oldest late, Delivered, Reports published for last
    month) as tiles (`.ovw-kpi`: the label, the figure, its change on the
    period before (`on Sept`, `on last quarter`) and its trend
    (`ADspaceChart.spark`) where it has a history; every tile keeps the
    trend's room and the two groups share their rows, so the eight stand
    one height); then the two trends, On time by month (delivered and posted,
    two lines) and Active
    clients by month (each figure over its column, this month lighter).
  - Detail, under its labels: Sales (Leads to clients, one-line bars, each
    step's share of the one before; Pipeline now, a ring with the whole in
    its middle; Sales moves: lost leads, paused, resumed, win-backs, lead to
    won as a median, conversion of the leads decided, churn of those active
    at the start, and for Services View the monthly value won and lost; By
    person in charge, a table of counts, never a ranking; New leads by
    source; Why clients paused or left), then Operations (Open work by
    person, one-line bars, the late share red; Where work waits, each
    stage's median with its slowest 10% the mark and its open work beside
    it; On time by person, the late share red, with the median cycle; Reports
    for last month, its slices in their status dots; Creator bookings). These
    were Clients · Sales and My Work · Report, both removed the same day.
  - Each chart names its way out at its title's right edge (its section);
    side by side, a row's cards share four rows (a subgrid: head, chart,
    key, Figures), so their Figures start on one line, open or shut,
    whatever each table holds; Figures' hairline a step below the chart;
    three in a row run three across. In Sales moves, Churn rate and the two
    monthly values take a row each.
- Each tile, signal, chart and list source asks its own `may()` before any
  read, at Full Access (`manage`) on its section or part; the granted parts
  (`ops.reports`, `ops.all`, `team.performance`) at their grant; the lead
  tiles, chart, signal and rows ask `clients.leads` too. What is not
  allowed is not drawn and nothing of it is read. Reads are shared within
  a visit, one request a source whatever draws from it (`R` in
  `js/overview.js`: one read of the clients serves the sales figures, cold
  leads, the pipeline and restricted accounts; one of the bookings serves
  the chart, those past their date and the quality check), read again on
  every visit and on a period change (a page turn reads nothing again),
  never polled. The work figures (the period, the one before it and, once a
  visit, the last six months) are one `ops_reports(p_ranges)`, ops_report's
  own answer a span; the sets with none this month read a year back.
  Where a set's posts stand is one `review_set_counts(p_sets)`, read a
  thousand at a time (`readPages`; every list a function answers is)
  (invoker; posts, approved, changes, undecided, the oldest change), here
  and in Waiting for you alike, never a read of every post and decision;
  every set named is counted, with no cap
  (`2026-10-18-review-set-counts-every-set.sql`).
  The sales figures are `ADspaceSales.figures`. A refused read is `failLine` with Try again (in the list, that
  source alone; a tile reads Could not load with Try again; a signal Could
  not load), never nothing.
- Needs attention lists a piece of work once: a late report task is its
  owed report's row, and a late task of a paused or past client keeps its
  late row with Urgent delivery in its meta; Reports owed counts every
  report not published, as the tile does (2026-10-22, OVW-3, OVW-4).
- Committed monthly value is its one money figure (the user, 2026-10-12):
  for whoever may open a client's Services (`clients.services` at View),
  a month of each confirmed monthly line started by today (never a one-off
  item) by market, read from `client_services`
  under that part's own policy; anyone else reads Active clients in that
  tile, and the lines are not read. No other value, revenue or fee.
- Reports for last month (`sm_reports_owed(p_period)`,
  `2026-10-07-reports-owed.sql`, Reports Full Access, client scope): the
  reports the months of that period ask for (their Reports ticks), found or
  not started, and every report made for the period no tick asked for (a
  report is the month's whose span holds its last day, else its calendar
  month's); a client with neither is never listed (the user, 2026-10-07:
  not every client is a monthly engagement); a row opens the report, else
  its task.
- `batches.published_at` is stamped by `batches_published_at` on the move to
  published and cleared on Unpublish.

### Analytics (`js/analytics.js`, `?s=analytics`)
- Trends over months, apart from the Dashboard's period (the user,
  2026-10-25; mockup `digital-form-tests` `mockups/analytics`): the rail
  row after the Dashboard, for whoever holds the granted part
  `team.analytics` (an admin's by itself; `2026-10-25-analytics-admin-tool.sql`
  adds it to `team_roles_admin_guard`, so only an admin grants it), never
  the start page, never a tab of the phone's bar (under More). The data is
  read under each table's own policies; only an AI analysis is stored.
- Tabs (`tab=`, Sales left out; the view strip, a swipe, the arrows), each
  drawn where its section is at Full Access: Sales (Clients and Leads),
  Clients (Clients); no tab for a section until it holds a trend's history
  (2026-10-25, review 7). The period (`p=`: Last 12 months by default, 6,
  24, This year, Last year) is measured on the same span before it, ending
  at the same moment of its month, and a month a figure is divided by is
  the share of it passed (`prevOf`, `monthsIn`; review 2). A group at Own
  clients only reads one line, Your clients only., under the bar
  (`.anl-own`; review 4).
- Sales and Clients read every client once a visit (`readPages`, the stage
  log) through `ADspaceSales.figures`, one figure call for the whole
  history (a source named as Clients names it, `ADspaceCRM.sourceWord`;
  a card's span takes its own line under its title at every width, so
  cards side by side read alike; 2026-10-27):
  Sales' tiles (new leads a month, win rate, lead to client,
  clients lost), its trend of leads and new clients by month, What
  changed (rules worked out on the page, never written), the busiest
  months, sources and lost reasons; Clients' tiles (active, joined, left,
  time as a client), active by month beside its own What changed, joined
  and left, by industry, by market, why paused or left, and how long
  active clients have stayed.
- Better or worse (`2026-10-25-analytics-alerts.sql`; the user,
  2026-10-25: "i dont see whether this analytics trend is good or bad"):
  every tile that compares and every What changed finding says Better,
  Worse or Steady (`judge`: each figure's own good direction, leads up,
  churn, days to win and clients lost down; a move under the Business
  setting `analytics_change_pct`, 10, or of under 2 in a count, is
  Steady), the dot and its word in ink (`.anl-verdict`), a finding's arrow
  in `--ok` / `--err`. Churn a quarter (clients lost over those active at
  the start, `churnOf`) above `analytics_churn_pct` (10) reads Above alert
  on Clients lost and leads What changed (Churn above the alert; More
  clients left than joined; an industry most leavers came from), Sales'
  What changed taking the client findings that are Worse. Each trend
  says where the last six full months head (`direction`, a least squares
  slope: Rising, Falling or Steady, judged the same way). Both settings
  are Settings, Clients: Analytics.
- Write with AI (`analytics-read`, `2026-10-25-analytics-read-with-ai.sql`;
  the user, 2026-10-25: "use AI to do analytics deep analysis and
  reporting"): the AI analysis card heads both tabs (`.anl-ai`), the
  latest version read first: Health (good, mixed, poor), a headline, a
  summary, then a fold of risks (by severity, each level High risk, Medium
  risk or Low risk in one column at the right, `.anl-ai-risk`; 2026-10-26),
  what is working, the
  forecast's credibility, three to five actions and caveats, and Version n
  · period · Written by AI for {name}. Read before using. Write with AI
  asks first (what it reads, n left today, notes kept in this browser
  under `adspace-analytics-notes:{colleague id}`) and sends the figures this page worked
  out for the period on show (`figuresOf`: both tabs, the period before,
  the verdicts, the months, the forecast, `leads_complete_from` the setting
  `analytics_from`)
  and never a client's name; every number Claude quotes is checked against
  them (a point quoting another is left out, a headline or summary refused
  `ai-incomplete`). Its own count (`ai_analytics_claim`, `analytics` 3,
  `analytics_admin` 10, team.analytics at Work; AI usage lists it), kept
  as the next version (`analytics_reads`, RLS on, no policy, no grant;
  `analytics_read_save`, `analytics_reads_list` the last twenty), filed
  `team.changed` under Analytics. Its ⋯: Versions (one shown at a time),
  Download (asks the AI declaration; drawn in the browser, FOR INTERNAL
  USE, never stored) and Delete (asked, no restore,
  `analytics_read_delete`, filed). Secret `ANALYTICS_MODEL` (unset,
  `claude-opus-5-5`).
- Full months count from the Business setting `analytics_from` (YYYYMM,
  seeded Sept 2026, Settings, Clients: Analytics, a month chosen from a
  list; `2026-10-25-analytics-counts-from.sql`, the SQL Editor's): before
  it the portal held won clients typed in later, never the leads lost
  (review 1), so a span before it judges no leads or win rate and the
  Sales tab says Leads are counted from {month}. (`leadsComparable`); an
  unrecorded source, or one holding every lead, is never a finding
  (2026-10-27, ANL-1, ANL-2). A forecast (dashed, over its likely range: the mean of the
  last six full months times the month's usual share, ± the last twelve's
  spread) is drawn only once 12 full months are held, from the month still
  running (its count so far in its name, the line of what happened ending
  at the last full month; review 8) to three ahead; the busiest months only
  once 24 are; until then each card says how many are held and when it
  opens.
- A refused read is `failLine` with Try again (`tests/analytics.js`, the
  forecast's arithmetic included through `ADspaceAnalytics._forecast`).

### My Work (`js/ops.js`, `?s=work`, permission key `ops`, mapped once in `sectionAllowed()`)
- Views (`view=`):
  - list (default, out of the address), board, calendar, months (an older
    `view=clients` reads as it). No Report view (removed 2026-10-12: the
    Dashboard carries the team's figures, its Detail page what only the
    Report held); an old `view=report` or `view=load` opens the list.
  - Each draws through `paint()` and `viewBox()`, never straight into a hidden
    box (`setView` draws a frame after the press).
  - A view without its permission falls back to the list.
- The list:
  - Show (`#workStage`): Open (`day`, the default: banded Overdue, Due
    today, In progress, Ready for review, Upcoming, No due date, Waiting,
    Completed today shut), Completed (`done`), All (`all`). Where the work
    has got to is Group by's question (stage, status), never a Show option.
  - The period select (`#workPeriod`): This week, This month, Last month,
    Last 7 days, Last 3 months, Last 6 months, This year. Every one runs to
    now but Last month, which ends where this month begins.
  - Group by day / stage / status / assignee / client / month; every
    card is shut off the day axis, and the heading carries its overdue count
    (`marksOf()`).
  - A search opens every card; a stage filter does not. A search finds any
    task the colleague may see, open or finished, any month, by title, code,
    description or number (`#WT00001`, `WT1`, `1`; `findAny`); the view,
    Whose work and the period do not narrow it.
  - The period draws only while finished work is listed and is named
    Completed (This week … This year); This month is its default
    (`data-default`), so it is counted only once moved.
  - An empty list says what it holds back: No open tasks. (Show completed),
    No completed tasks. (Show this year).
  - Whose work (`#workScope`) is a view, not a filter: Assigned to me,
    Created by me, The whole team (only with `ops.all`). No Following.
  - Clear filters returns the search and Show to Open; Whose work and
    Group by stay.
  - Mine keys on the owner's id, never their name.
  - The count is read against the chosen view.
  - Waiting for you (`#workWaiting`, 2026-10-08): above the list on Open,
    Assigned to me, with no search, one card of what waits on the reader's
    decision: an extension asked of them (Decline / Approve in the row,
    `ops_decide_due_change`), a report they review, a booking Submitted on a
    campaign they run, a client request Requested and a set with Changes
    requested on a client they hold (Person in charge); each read asks its
    own `may()`, late first, then oldest, each row opening its record. Drawn
    only while it holds something. Awaiting approval (2026-10-10): a
    published set on a client they hold with posts the client has not
    decided, from `published_at`, and a booking at Reviewing on a campaign
    they run, from its last `option_qc` check, once either has waited
    `approval_reminder_days` (3, Due dates); Remind (tonal, while the
    approval reminder's template is on and `ADspaceWhatsApp.may('approval')`)
    opens the composer on the client's main contact with what waits and its
    link (the review page, the selection page) filled in.
- The read is bounded, and open work is not part of the bound. Open work is
  read in full, a thousand rows a page in id order (`readPages`) and put back
  in the final date's order; finished work is read from the period on (three
  filters, not one `.or()`). The period select draws only while finished work
  can be on the page. Who owns what is read for the tasks read alone
  (`readOwners`, 150 ids a part), never every assignee in the company.
- A colleague's own task on a client outside their reach names its client
  through `ops_task_clients(p_tasks)` (the name alone, tasks they may see;
  `2026-10-03-task-client-names.sql`).
- The row:
  - A tick (everyday task) or a progress ring (content task).
  - The name cell opens the task; the row is not one button.
  - The stage select moves the task (`moveTo()` is the one path for the row,
    the card, a drop and the task's head).
  - Under a finger a row swiped left shows its next step (`rowSwipe`; the
    user, 2026-10-11: quick actions): the name and date stay in sight, the
    stage and the ⋯ fade under one blue button at the right edge named as
    the task's own (`verbFor`), made as the swipe begins and gone as the row
    settles (a row at rest holds only its cells), pressed through `stepFromRow` as the select
    is. The swipe shows the act, never takes it, because a sideways swipe
    elsewhere changes the view (the row is `data-noswipe`); a press
    elsewhere, a scroll or another row's swipe puts it back.
  - One select for every task (`stageCell`): the whole workflow in position
    order, the current stage chosen, an unreachable stage greyed (never left
    out), a retired stage and Blocked listed only for a task on them.
  - Going back, skipping ahead, Cancelled and leaving a finished content task
    ask Why? under the control (`askWhy`, `ADspaceAsk.note` once); the reason
    rides the move (`p_note`, or `p_skip_reason` for a skip).
  - A move into AQC review asks who takes it (`openStep`, the creator first
    where that is somebody else) from the row, a board card and the task's
    own button alike; the same move never gives two results.
  - The outcome or refusal is named under the row (`.task-note`).
  - The stage track is 170px. A narrow row ends with the stage at a stated
    width; `is-tight` gives it its own line.
- Stage tone by `stage_group` (the status dot, `STAGE_TONE`):
  - not started and ready to start: grey;
  - in hand (in progress, a revision): amber, still running;
  - waiting on a person: amber;
  - cleared: green;
  - blocked: red.
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
  - Every column runs the board's full height and takes a drop anywhere in
    it; in a gap the nearest column does. A card held at the board's edge
    scrolls it. A card never starts the browser's own drag, and a press on
    it selects no text (a stray selection cancelled the next drag).
  - The capacity strip fills each person's bar from the `estimate_minutes`
    of their open tasks due by the week's end, overdue included, against
    `capacity_minutes_week` ("5h planned of 40h"); nobody logs hours. It is
    drawn only while somebody shown has a capacity set.
- The calendar shows every task on its due date (the stage tone) and its
  post date (`--pub`), with a Due / Post key. A task whose next date is
  its post date shows once. A day holds five chips (`CAL_SHOW`), each two
  lines at 11px (`.cal-chip`), each its own block cut to the cell: the
  client (Internal, Lead · name; the stage dot before it) over the code and
  the format's short word (`2610W204 · Reel 30s`, `formatShort`), a task
  with no code its name; never the whole description (the user,
  2026-10-09). Then `+N more`. On a phone it lists only the days holding
  work, so a month with none reads "No tasks this month." (`.cal-none`).
- Months view (`view=months&wc=`, the tab named Months) is one bar, as every
  view (2026-10-22, WRK-M1): the view strip, the client (`#workClient`,
  `data-nofilter`, kept in the bar on a phone), the search, Filters, the
  count, the section's ⋯, New month and Add task, no label or heading; the
  list's own bar steps away (`placeMore`); on a phone the strip takes its
  own row, New month goes into the section's ⋯ and the count into the
  Filters sheet's head. Then that client's months, meetings and tasks
  (`clientWork()`), the client remembered per browser. A month's ⋯ is Add tasks (the New sheet on that client and
  month), Edit, Cancel month, Delete. A month whose tasks the filter hides
  says No matches (Show all), never No tasks this month.
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
- A move back along the line is allowed with a reason
  (`back-reason-required`, filed `back: true`); never into a revision or a
  retired stage (`retired-stage`). A skip never files a revision or a
  retired stage as skipped.
- Reason categories are stored keys, named by `reasonWord()`: Client request,
  Scope change, Internal capacity, Pending assets, Pending confirmation,
  Incorrect date listed. The date sheet asks for one each time (Choose a reason, required;
  never prefilled), and its act reads Send request where it will only ask.
- Task fields:
  - Type: Retainer (key `engagement`), Ad hoc, Goodwill, Other (key
    `special`, 2026-10-09).
  - Format: the rate card's formats, optional.
  - Priority: Urgent, High, Medium, Normal (keys 1, 2, 4, 3: Medium took
    the key Low left, `2026-10-11-priority-deadlines.sql`, which made every
    Low task Normal once; an old 5 reads Normal; rows read in that order,
    `PRIORITY_RANK`). A priority is a deadline from when it was set
    (`ops_tasks.priority_at`, stamped by trigger `ops_tasks_priority_at` on
    creation and on every change of level): Urgent 24 hours, High 48,
    Medium 72 (Business settings `priority_{urgent,high,medium}_hours`, as
    at the day it was set; the Settings page's Priority deadlines). Only
    whoever created the task, My Work Manage or an admin changes it
    (`ops_update_task`, `priority-not-yours`;
    `2026-10-18-priority-set-by-whoever-set-the-task.sql`); Normal
    has none (the user, 2026-10-11: a task due the 29th raised to High on
    the 12th at 9am is owed by the 14th at 9am). Worked out on every read
    (`deadlineOf`, `ops_priority_by`), never written; the due date is never
    changed. It stops once the task reaches client review (an everyday
    task's Review) or is finished; On hold and Blocked count on. While it
    runs the row and a board card carry a strip down their left edge in the
    level's colour (red once over); while it comes before the due date its
    words stand in the Due column as a filled tag ("High · 31h left", red
    "High · 5h over", "Urgent · 19 days over" once over by a day; WRK-6), and the task card says Set to High … · deliver within
    48 hours, by … under the next step.
  - Complexity: Light, Standard, Complex (the key `simple` reads as Light).
  - The post date is required on a new content piece (below). It seeds
    the content month and week until they are touched (`ntTouched`). My
    Work says post, never publish (Post date, Set the post date).
- Duplicate (`ops_duplicate_task`: a new code, none of the history).
- Repeat (`ops_set_recurring`: weekly, monthly on a day, or every N days; ends
  on a date or a count). `ops_generate_recurring` is idempotent on rule and
  date.
  - The task a rule copies is its first occurrence: nothing is made on or
    before its day.
  - A monthly copy keeps its task's week; a weekly or every-N-days copy takes
    the week of its own date.
  - Made once is made: every date a repeat makes is kept
    (`ops_recurring_made`, by rule and by the task it copies; no policy, no
    grant), so a deleted copy is never made again and a repeat turned off and
    on again makes no date twice.
  - A task deleted stops its repeat (trigger `ops_tasks_stop_repeat`): a rule
    is seen and turned off only from its task.
  - One rule never stops the others: a make refused or failing is undone
    alone, kept on the rule (`last_error`, `last_error_at`, cleared by its
    next task), answered in `errors`, and named in the admins' morning
    notice (`jobs_watch`); the run goes on to the next rule.
- Repeats run themselves; nobody presses Run:
  - a client's month confirmed (its meeting set or marked not applicable)
    makes that client's repeats for it at once, as the person confirming
    (trigger `ops_engagements_confirmed`; a refusal never fails the
    confirmation);
  - every morning at 00:10 MYT (pg_cron `ops-repeats-daily`),
    `ops_recurring_daily()` makes this month's, and next month's in this
    month's last seven days (`ops_recurring_periods()`), each rule as the
    colleague who set it, else its task's owner, with that colleague's own
    access (`request.jwt.claims`). A rule neither can make waits.
  - Neither function, nor the trigger's, is callable from a browser.
- The bar's ⋯ holds Select tasks (Manage: a sticky bar with Reassign and
  Delete), and New month on a phone's Months; it is drawn only where one
  applies. Task templates (`ops.workflows` Work: edits families and makes
  no task, `ADspaceOps.openTemplates`), Task numbering (`ops.numbering`)
  and Due dates are Settings' alone (2026-10-29).
- A template is a family (`ops_template_variants`): one checklist and the rate
  card formats it serves, each with its own hours; a format belongs to one
  family (`format-taken`, naming it). A task's format fills it from its family
  inside `ops_create_task` (the checklist and the variant's hours; the
  caller's workflow and the month's dates stand), so every piece of the New
  sheet and every repeat alike. Reels (30s, 60s, 120s), Graphics (Static, GIF, Carousel),
  Report. Its sheet (`#tplEditSheet`) asks only that: Name, Active (a
  `button.switch`; an inactive family fills nothing), the formats with their
  hours and the checklist; a save sends the stored title, owner, due offset,
  estimate and workflow back unchanged (the user, 2026-10-12).
- A task is named by a code plus a description.
  - The code (`ops_code_of`: `YYMMW{week}{NN}` for the content month) is made
    once under an advisory lock; the owner or an admin corrects it in place
    (the name's one pen on the card opens the
    code and the description as one field, each part changed going to its own
    function; `ops_set_code`, `2026-10-08-task-code-editable.sql`:
    its shape kept, `bad-code`; the client's own for the month,
    `code-taken` naming the task; filed `code_changed`; Undo where it
    happened). The `#WT` serial stays the identity.
  - NN follows the month's plan (`2026-10-08-task-numbers-planned.sql`,
    trigger `ops_tasks_code_slot`): a Retainer piece (not a report task)
    takes the lowest free of 01 to `planned_count`, refused `plan-full` past
    it; any other task the lowest free after it (a month with no plan from
    01); a deleted number is used again; a type moved across is numbered
    again; a typed number keeps its range (`plan-range`, `extra-range`); the
    code is rebuilt from its month, week and number, so W1 is Week 1. The
    New sheet rests Retainer once the month's content reaches its plan.
  - The description is edited in place (`ops_set_content_desc`).
  - The number is `#WT00001` (`ops_serial`). The next number is set under `ops.numbering`
    (`ops_set_next_task_no`, refused at or below the highest in use).
- Scope is Client / Lead / Internal, checked once at creation
  (`ops_scope_error`):
  - Client offers active clients (paused by default; past on request);
  - Lead offers lead / contacted / proposal.
- Add task asks for a client or Internal every time.
- The content form offers Lead only where `clients.leads` is at Work, and
  Include past clients only where `clients.past` is; a refused read of the
  clients is named in the sheet, never an empty list.
- Add task and the content form open on one segment, Task / Content
  task (`.kindseg`). Switching swaps the sheet in place.
- Add task is one act: it saves, the sheet shuts, the list is read again and
  the new row says Added. (`state.rowSaid`).
- Every task has an owner from creation (the creator by default); the sheets
  offer no Nobody.
- A colleague whose group holds My Work below Work (No Access or View)
  takes no tasks (the user, 2026-10-15, option A: contract staff on sales;
  no setting of its own; View since 2026-10-18,
  `2026-10-18-tasks-need-my-work-at-work.sql`: a task asks Work to move):
  every My Work picker leaves them out (`ADspaceAdmin.takesTasks`,
  an admin always offered), Team's hand-over offers them for clients,
  campaigns and reviews alone (`TASK_KINDS`), the noon reminder skips them,
  and the database refuses them a live assignment or a month to manage
  (`ops_takes_tasks`, triggers `ops_task_assignees_takes_tasks` and
  `ops_engagements_takes_tasks`, `no-tasks`;
  `2026-10-15-tasks-need-my-work.sql`). Work already theirs is left as it
  is.
- Every colleague picker on a create form starts on the person creating it
  (Assigned to, a new month's Manager or one with none, a new lead's and a new
  campaign's Person in charge); they change it where someone else takes it.
- **Only the owner or an admin moves a task** (`ops_owner_may_move()`;
  `not-owner`). `mayMove(t)` hides the controls. The step says who has it.
- The step asks who takes the work.
  - One picker, Assign to, on the card and the step sheet alike (the user,
    2026-10-11: no switch, no tick box): its first choice keeps it with
    whoever has it (Me (name) for the reader's own; `__keep`), chosen on
    the owner's own steps; a hand-off opens on the person it usually goes
    to, else Choose a person.
  - The step sheet's act reads Move: its head names where it goes, so the
    label keeps one line in a phone's half.
  - `ops_transition_task` takes `p_assignee` and `p_skip_reason`.
- Skipping a step is ops Work with a reason, and never into a revision.
- Reassign (`ops_assign_task`, `ops_hand_over_task`;
  `2026-10-05-assignee-reassigns.sql`): the person a task is assigned to
  (My Work at Work, their own task) and any group above them (Manage, an
  admin); helpers and the reviewer stay a manager's, and both functions ask
  `ops_may_see_task`. `mayReassign(t)` draws the controls.
- Open to take (`2026-10-04-open-to-take.sql`, `ops_tasks.open_at` /
  `open_by`): the assignee or an admin offers an open task to the team
  (Offer to team / Withdraw offer in the ⋯, never asks;
  `ops_set_open`, filed `offered` / `offer_withdrawn`); any colleague at My
  Work Work whose client scope holds its client sees it (`ops_may_see_task`)
  and takes it (Take, asked first, naming who is told; `ops_take_task`,
  `not-open`, `already-yours`, `stale`), becoming its one owner, filed
  `assignment_changed` `taken`, the owner before told (kind `taken`). Any
  change of hands ends the offer (trigger `ops_assignees_close_offer`). The
  owner's row carries the Open to take chip; everyone else's own queue
  heads it under Open to take with Take where the stage would be.
- Urgent delivery: every unfinished task of a Paused or Past client reads
  Urgent delivery (`urgentDelivery(t)`, the red chip in place of the
  priority's; the first band on the day axis, above Open to take), worked
  out from the client's stage on each load (the list embeds
  `clients(name, stage)`; a client out of reach answers through
  `ops_task_client_facts`, else `ops_task_clients`), never written to the
  task, so the client back at Active clears it.
- On hold, Blocked and Cancelled go back only to the stage the task left
  (`ops_tasks.held_from`, stamped by trigger `ops_tasks_held_from`), and
  Cancelled also to the start of the line (`held-resume`; the user,
  2026-10-18: keep My Work's gates light, no AQC rule;
  `2026-10-18-held-tasks-resume-where-they-left.sql`); a task held before
  the column keeps the workflow's own steps. Reopen works on every
  cancelled task. Leaving Cancelled clears `cancelled_at`.
  A task finishes and reopens through `ops_transition_task` alone; the first
  model's functions are dropped (`2026-10-26-unused-functions-dropped.sql`).
- A task read that finds no row (deleted, or out of reach) closes its sheet
  or record and lands on the list with "That task is no longer available."
  (`taskGone`, `.maybeSingle()`); never the database's words.
- `derive(t)` is the one source for the head status, the next step and the
  stepper.
  - The next step is the one blue primary, a hand-off (`btn-go`) or your
    own progress (`btn-primary`) alike (2026-10-07).
  - One next-step button, named for where it goes (`verbFor`: "Move to
    Client review"); no stage move beside it.
  - Draft due and Post date are a content task's: an everyday task (a
    month's report task included) shows its Due date alone, and its post
    date never reaches the calendar (the user, 2026-10-11).
  - The card's ⋯ is Take or Offer to team / Withdraw offer (where they
    apply), Duplicate, Repeat, Delete; who has the task is
    changed on its Assigned to row (the name and a pen at the facts' right
    edge, named Reassign; 2026-10-11), a task nobody holds from the
    next step's Assign, never from the ⋯. The row's ⋯ holds only what the row cannot do (Take where the row
    shows none, the offer, Delete) and is not drawn when empty. No timer,
    Revert, Move to another stage, Mark blocked or Cancel.
- The SOP workflow, numbered in this order: Ready to start, In progress, AQC
  review, Revision (Internal), Client review, Revision (Client), Approved,
  Scheduled, Live (`ops_mark_live`; a reason where the date differs),
  Performance review (+7 days, back to the creator), Completed, then On hold,
  Blocked, Cancelled, Taken down; rated 1–5 (`ops_rate_task`). Planning,
  Content meeting scheduled, Changes requested and Published are retired
  (`ops_workflow_stages.retired`): the month holds planning and the meeting.
  On hold and Cancelled are reachable from every open stage on the line,
  and lead back only to the stage left (above).
  General and Video are retired for new tasks.
- Results (`2026-10-10-post-results.sql`; the user, 2026-10-09: "doesn't
  have high views"): a client's task gone live records its views and
  engagements (`ops_set_results`, My Work at Work, `not-live`,
  `bad-number`; stamped `result_at` / `result_by`; filed `results_set` from
  and to) from the card's Details (Results, Not recorded until then), the
  week after it went live at Performance review. A month in Planning or
  Ready lists last month's best and weakest posts by views
  (`lastMonthRows`, three each), worked out on the page.
- Checklists for reach (`2026-10-10-checklists-for-reach.sql`, with its
  preview): Reels gains four checks (the hook in the first 3 seconds,
  licensed music, original footage, no absolute claims) and Graphics three,
  appended once each where the template holds them nowhere; the team edits
  them in Templates as any other.
- The everyday workflow: To do, In progress, Waiting, Review, Done, Cancelled.
- Time records: one stage table in workflow order (Stage, Visits, Time, a
  Total row); the sheet shows it open, with Recorded only where there is any.
- A draft link is optional. Without one the step asks Sent on (`#stepVia`,
  WhatsApp / Others; the user, 2026-10-11: "no need type in where to send
  every single time"): WhatsApp files Sent to the client on WhatsApp., Others
  asks How it was sent; the database accepts the link or a note.
- A task is one card beside the list (`#taskDrawer`, `.sheet-side`,
  `open=`; the user, 2026-10-09: the full record was little used): an
  older `task=` address, a new task and a copy open it there; there is no
  full record.
  - The name with Copy title; under it one line: the client, the format and
    the month, the month itself opening its Months view (never `content` or
    `Graphic:`).
  - Next step, headed by the workflow's strip (`#dwSteps`, `paintSteps`:
    done quiet, the current step named, the next said; never buttons), then
    the report row on a month's report task, then Assigned to, Dates and
    Details (with Video for a task that has video details: Script and
    Footage readiness as selects saved by `ops_set_video`, since editing
    waits on footage), Checklist and Remarks stay open (Remarks: the
    comments, Add remark, Post); Brief, Files and links, Time records and
    Recent activity fold under More (`#dwMore`, shut each open).
  - A month's report task (`source_type` `report_social` / `report_ads`)
    carries its report (`paintReportRow`; the month's own, never one on
    request): once made, where it stands and
    Open report; before, Start report, made on the month's own span (a
    month starting on the 16th runs to the 15th) as New report does.
  - A link's Kind select sits left of its Address.
- The card's Details are changed where they are read (2026-10-08): Format,
  Type, Priority and Complexity as small selects drawn as the value
  (`.select.tdetail`: no box, the tonal ground on hover and focus, as
  `ADspaceAsk`'s field) (`ops_update_task`,
  `2026-10-08-task-details-editable.sql`: `deliverable_type`, `task_type`,
  `complexity`, `estimate_minutes`, each refused by name), and the Month and
  Week where the code may move (`ops_set_code` with the code built from
  them); each saved on change, put back on a refusal, filed `details_changed`
  from and to. For stays fixed: the client and its scope hang from it.
- Everything added can be corrected and taken back:
  - checklist items, links and comments (edit and delete are later events);
  - the brief and the priority (`ops_update_task`).
  - A required check has no ⋯.
  - A checklist tick repaints its own row only.
- A link may name a record (`ops_link_record`; kind `record`, `ref_type`
  campaign or set):
  - only the task's own client's, and once while the link stands;
  - Record in the Kind select (a client's task only) swaps the address for a
    picker of the client's campaigns and sets, less those already named;
  - it opens the console route in the same tab, reads the record's title as
    it is now (Deleted once gone), and has Remove and no Edit
    (`record-link`);
  - it is filed on both sides (`campaign.task_linked` / `set.task_linked`,
    `_unlinked` on Remove);
  - the campaign's Overview (`#campOvTasks`) and the set's panel
    (`#setTasks`) list the tasks naming them (`ops_record_tasks`: only tasks
    the reader may see, nothing without the record's section), drawn only
    where one does;
  - a task still owing its draft, with a set named, opens the link form on
    Draft with the client's review link written in.
- Dates:
  - The first draft is the team's own (`ops_due_decider` null) and must fall
    before the final date by calendar day (`ops_due_order_ok`, checked inside
    `ops_change_due_date`).
  - The final date moves only through the creator's approval
    (`ops_request_due_change` → `ops_decide_due_change`), except for its
    creator or an admin, who move it directly; `ops_change_due_date`, which
    both reach as definers, is closed to every browser
    (`2026-10-18-due-date-moves-through-its-ask.sql`).
  - Late = past whichever deadline comes first (the user, 2026-10-11): the
    final date, short of client review (`isLate()`, `reviewFloor()`), or a
    priority's, short of its review (`deadlineOf`). The Overdue band, the
    task card, `ops_report`'s late list (`over_minutes` for a priority's,
    read in hours under a day), open work by person, the on-time figures
    (met only where both were met) and the performance review's Timeline
    adherence figure (`perf_ops_rate`) read the same rule.
  - The control is named for what it will do: Request extension, or Change due
    date.
  - A row's date already set opens the due sheet (`openDue('final', row)`),
    which asks the reason; only a first date is set in place.
  - The ask is drawn under the dates:
    - Approve and Decline for the person asked;
    - Withdraw (`ops_withdraw_due_change`) for the asker;
    - nothing for anyone else.
  - The word "Move" is on no date control.
- A notification is written by `ops_log` / `ops_notify`, deduplicated per
  minute (a comment by its words).
  - The owner is told about another person's change.
  - A new owner is told they were assigned; a step that hands the task on
    tells them once (Handed to you … at …), never again for the move
    (`ops_log`, `2026-10-18-one-press-one-notice.sql`).
  - Nobody is told about their own act.
  - The bell is drawn for every colleague (a row is its reader's own), and
    re-reads every minute while visible, and on return, in the page's one
    check (`page_pulse`).
  - Each item leads with its section's rail glyph (`.notif-tile`,
    `ADspaceAdmin.glyph`): My records for a review, reflection, health or
    HR letter, Reports for a report, Video Scripts for a script, My Work
    otherwise. The bell lists
    unread first, then Earlier (`.notif-earlier`): read notices of the
    last seven days, ten at most (`.notif-item.is-read`); marking read
    keeps a notice there, never removes it. A colleague's notice (kind
    `notice`) leads with Team's glyph, says From {sender}, wraps its title,
    shows three lines of its message and opens nowhere: a press reads it
    whole in place and marks it read, the list left as it is (a row redrawn
    under the press read as a press outside the bell and shut it); one
    withdrawn is left out (`hidden_at`, asked for until a database without
    the column refuses it once).
  - A noon reminder (`2026-10-08-tasks-reminder.sql`,
    `ops_tasks_remind()`, pg_cron `tasks-reminder` at 12:00 MYT, Monday to
    Friday): every active colleague but an admin with no open task
    assigned to them, or who has never added a task, is told once that day
    (kind `tasks.empty`, opening My Work).
  - Task reminders (`2026-10-13-task-reminders.sql`, `ops_tasks_nudge()`,
    pg_cron `tasks-nudge` hourly from 10:00 to 17:00 MYT, Monday to Friday;
    the user, 2026-10-13: "not every single task needs to have a noti but
    it should have something"): each task's owner (never a system account)
    is sent one notice of what of theirs needs them, each task counted once
    as the first of Overdue (the late rule), Urgent (its deadline running),
    Due today (the due date or a priority's deadline), Not started (a
    starting stage, its draft due, else due date, within `task_start_days`
    (2), or with no date assigned that long ago); one task names it and
    opens it, several are counted ("5 tasks need attention: 2 overdue, 1
    Urgent, 2 not started.") with the first three named, opening My Work
    (kind `tasks.nudge`, push tag `tasks-nudge`), never more often than
    `task_remind_hours` (3); a VIC client's tasks are named first and
    counted apart ("2 for VIC clients"), and one that falls overdue after
    the colleague's last reminder is told at once, inside the window too
    (2026-10-15); both Business settings (Settings, My Work:
    Task reminders, 0 sends none). Not sent on WhatsApp.
- The month (engagement):
  - Made by hand, never derived from the client's service lines (the portal
    is supplementary: quotations and invoices are issued in Bukku). New
    month, New task and Duplicate offer last month and the next six
    (`fillMonths`).
  - It owes reports and starts on a day (`2026-10-04-month-reports.sql`):
    `reports` (`social` Accounts report, `ads` Advertising report, both or
    none) and `start_day` (1 to 28; the 16th runs to the 15th,
    `ops_month_span`), ticked and picked in the month sheet (Reports, Starts
    on), a new month taking both, and its Posts planned, from the
    client's month before (2026-10-27, WORK-3). Each
    report ticked is one live task (`ops_engagement_sync_reports`: the
    everyday workflow, format Report, the month's manager, one date: due
    23:59 MYT `report_due_days` (7) after the month's last day, no first
    draft date (the user, 2026-10-05), never from the Report template's
    offsets; `sm_report_gate` reads the same day; `source_type`
    `report_social` / `report_ads`); unticked, a task still To do is
    cancelled and a started one kept (`ops_engagement_cancel_reports`, the
    one copy); only a start day moved moves an open one's dates (filed), so
    another save never undoes an extension. Deleting the month cancels its
    report tasks nobody started first (`2026-10-04-month-delete-reports.sql`),
    and its question says so. `ops_engagement_counts` adds `content` (live
    less report tasks, `2026-10-04-month-counts-content.sql`): the New
    sheet's `n added` reads it; `live` / `open` still count the report, so
    the month stays in production until its report is done.
  - Two checks (Onboarding checklist, Pre-advertising checklist), seeded only on
    a client's first month and handed on when that month is deleted
    (`ops_engagements_hand_on_checks`), ticked by the client's checklist
    signed off (Clients, Checklists) and marked Not needed by hand.
  - Its stage is worked out on every load (`engPhase()`), never picked:
    Planning until the ticks are answered and the meeting set (or not
    needed); Ready until the meeting has passed and the month holds a task;
    In production while any task is open; Ready to close (amber) once every
    task is finished and one done, where the card asks Add task or Complete
    month. A tick repaints the chip in place. The counts are
    `ops_engagement_counts` (the whole month, whoever asks; a refusal falls
    back on the tasks the page holds).
  - Only Completed (refused while a task is open, `tasks-open` with the
    count), Cancelled (the ⋯, asks, `Keep month`) and Reopen (back to
    Planning, never asks) are stored. Cancelled cancels the report tasks
    nobody started (`ops_engagement_cancel_reports`), Reopen asks for them
    again, and a report task nobody started follows the month's manager
    (`2026-10-05-month-edits-reach-reports.sql`). `ops_engagement_set_status` refuses
    Ready and In production (`derived-state`); a stored one from before reads
    as open. A task moves into production on the ticks and the meeting, never
    on the stored word.
  - The meeting is `meeting_minutes` (15–240) plus a link (Meet, Zoom or Teams
    only). It is booked no earlier than the next half hour (`nextSlot()`: at
    3:00pm or 3:10pm the first slot is 3:30pm); the date and time fields
    start there and an earlier time is refused on the sheet. A meeting
    already held keeps its time when its sheet is opened. An On site
    meeting asks for no link and may be written down after the day
    (`2026-10-09-on-site-meetings.sql`; the user, 2026-10-09); once it has
    ended, whoever led it (else the month's manager) is told once to submit
    the outstation record (`ops_outstation_remind()`, pg_cron
    `outstation-reminder` every fifteen minutes, kind `outstation`,
    `outstation_told_at`; a moved meeting is told again), the notice
    carrying the form's address in `ops_notifications.link` (https only),
    which the bell and a push open in place of a console page.
  - The card (`engCard`) never repeats its heading: the month is named by the
    card above it, whose state chip (`.eng-mark`) shows only while shut. The
    meeting, link and message are `.eng-row`s (label, value, controls at the
    right edge), the message to the client set off by the card's hairline; under `is-tight` the label and controls share the first line
    and the value runs full width beneath.
- New month never edits a month held: it offers only the months the client
  does not hold and sends `new: true`, which `ops_engagement_upsert` refuses
  `exists` (2026-10-22, WRK-1), opening on this month, else the next one
  free (2026-10-27, WORK-2).
- A press on one task reads that task alone, as does a task made alone or
  copied, which joins the list behind its card (2026-10-27, WORK-1); the catalogue is read once a
  visit and Waiting for you on entering and after a decision; a failed
  Waiting read is said in the card with Try again (2026-10-22, WRK-3, WRK-5).
- Every client deliverable goes into a confirmed month: one that exists, is
  open, and has its meeting set or marked not applicable (`no-month`,
  `month-closed`, `month-not-confirmed`). This holds for the New sheet,
  templates, Duplicate and repeats (a repeat waits, `held`). Everyday,
  internal and lead tasks are exempt.
- The New sheet (`#taskSheet`) is the one way work is added; there is no Bulk
  add or Run repeating tasks.
  - It reads Task details (For as a small segment with Include past clients
    at the right; Client and its Content month, Month for a lead, neither
    for Internal) and Posts, nothing else: complexity, a brief and a repeat
    are set on the task card (the user, 2026-10-12: "not so useful can
    remove so it looks nicer"). A client with no confirmed content month
    takes no posts: the posts step away for its line and Open Months
    (`#ntOpenMonths`), which shuts the sheet on the client's Months in My
    Work; a lead and an internal post need no month.
  - A content deliverable is posts, one shaded group with Add another
    inside it, each post one task headed Post n with its × once there are
    two: its description and format; its week and three dates; who it is
    Assigned to, its Priority and its Task type (the user, 2026-10-12: "7
    posts (6 retainers 1 adhoc) each have different dues different
    handling person, different urgency"), the deadline a priority sets
    from now said under that post ("Deliver within 48 hours, by 14 Oct,
    9:00am.", none for Normal). Add another draws the next as the post
    above (format, person, priority, type) with the week after (after
    Week 4, Week 1). Every post shares the client and month. Month reads
    `{n} planned · {n} added` (`ops_engagement_counts`); Retainer rests on
    a post once the other posts take what the plan has left.
  - `ops_create_pieces(p_payload, p_idem)` makes them through
    `ops_create_task`: 1 to 60 (`bad-count`), all or none, the same press
    twice the same act; each piece's own `owner_id`, `priority_level` and
    `task_type` stand over the payload's shared ones
    (`2026-10-12-pieces-of-their-own.sql`).
  - Every piece's line carries three dates, typed by whoever plans it and
    never worked out (`2026-10-06-three-dates-a-post.sql`,
    `dates_as_given`: no template offsets): Draft due (ready for AQC
    review), Due date (for client review) and Post date, each required
    (the user, 2026-10-09: "to curb delays";
    `2026-10-09-piece-dates-required.sql`): a line missing one is refused
    on the page and by `ops_create_pieces` (`dates-required` with the
    `piece`, "Post 2 needs its Draft due, Due date and Post date."), and
    nothing is made; a passed date, a draft due after the due date, or a
    post date before it is refused on its line. A task made before keeps
    what it has (Not set where blank); Add task, templates, copies, repeats
    and report tasks are unchanged. With several posts the button reads
    Create N tasks.
  - A move into Revision (Client) pushes the due date to today (MYT) plus
    `revision_due_days` (1) working days (weekends and public holidays passed
    over, `ops_add_business_days`; `2026-10-18-working-days-skip-holidays.sql`),
    only where that is later than the one held
    (trigger `ops_tasks_revision_due`, filed `due_changed`, reason Client
    request).
- Google Meet: only `meet-create` touches the calendar (the refresh token lives
  in its secrets).
  - It asks `ops_engagement_meet_prepare` (a month) or
    `client_touch_meet_prepare` (a Calls and visits meeting) as the caller.
  - It refuses a slot only where another online meeting overlaps it (a Meet
    link, or a Meet, Zoom or Teams address on the event; `slot-taken`,
    answered with the clash's start and end alone, never its title: it may
    be another client's); other events on the shared calendar do not count.
  - It re-reads until `hangoutLink` appears, and records `meet-pending`.
  - A record's event has one id, made from the record's (`admonth` or
    `adtouch` and its id's hex, Google's letters; 2026-10-19): a second
    press is answered 409 and takes the event the first made, never a
    second booking; its own event in the slot is no clash; one deleted and
    booked again is put back, confirmed, with a new Meet (`tests/meetfn.js`).
  - It names a setup fault (`meet-not-set-up` with the missing names;
    `google-token`; `google-refused`).
  - `ops_engagement_set_meet` accepts only a `meet.google.com` link. A null
    pair removes the event and its link, and leaves a typed Zoom or Teams link
    alone.
  - A month's Google Meet is deleted from its Link row's ⋯ (Delete, My Work
    at Work, asked first: `meet-create` `delete`): the event leaves the
    shared calendar and the link goes, the date and time stay, and Create
    Google Meet books a new one (the user, 2026-10-12); a link the database
    refuses to clear is said (`not-saved`), never answered deleted
    (2026-10-22, BE-8).
  - Not connected is not a failure of the save.
  - `clientMessage()` fills the one bilingual template, the team's words
    (`meeting_message_template`, `2026-10-29-meeting-message.sql`; Settings,
    Templates, Meeting message at `team.settings`; `meeting_message_save`
    refuses words without {date}, `no-date`, filed under Meeting message;
    the sheet refuses a field it cannot fill, naming it, 2026-10-29):
    {meeting}, {date}, {time}, {month}, {channel}, {link}, a line whose
    field has no value left out and a heading left empty with it; read once
    a visit, the seed's words standing in until it answers, Show and Copy
    filling it again at the press.
- The client portal shows meetings read-only (`portal_meetings`), never a task.
- Deletes:
  - `ops_delete_task` (Manage; the number typed back; a reason; an
    `ops.deleted` activity row);
  - `ops_delete_tasks` (bulk; the count typed back);
  - `ops_delete_engagement` (a reason; its tasks stay, its untouched report
    tasks cancelled).
- The task sheets live in `#workSheets`, outside the section.

### Performance (`js/perf.js`, `?s=team&tab=performance`, `?s=mine`)
- Grades: Distinction, Strong, Baseline, Needs support, Improvement plan
  (keys A to E never move).
  - C is reward eligible unless the month before was also C.
  - An L3 or L4 breach makes the month not eligible.
  - Pacing counts only for people who run ads.
  - Grade bands, breach points (by level, a repeat, lateness) and their
    cap are settings from a quarter on (`2026-10-05-performance-rule-settings.sql`:
    `grade_a`…`grade_d` 90/80/70/60, `ded_l1`…`ded_l4` 3/7/15/30,
    `ded_repeat` 5, `ded_late` 5, `ded_cap` 35; `perf_grade_at`,
    `perf_deduction_at`), a month graded by its own quarter's, each issue's
    line and the figure its logging answers read with the same month's; `perf_calc`
    returns the `cap` and `points` it used, and the page names them from
    there, never a figure of its own.
  - An issue's points are kept as a number (`perf_points_at`, settings to
    two decimals, the VIC multiplier on the exact sum); the month's total is
    rounded once, to the 0.1 step the scores take, before the cap.
  - L3 caps at B; L4 caps at D.
  - An issue may name the client it concerns (`perf_breaches.client_id`,
    the issue sheet's Client, optional; `bad-client`); on a VIC client's
    work it is stamped `vic` at logging (trigger `perf_breaches_vic`, never
    changed after: `vic-stamped`) and its points are times `ded_vic` (2,
    from Q3 2026, Performance settings' Months part, 1 to 10;
    `perf_deduction_vic_at`), still under `ded_cap`; the review sheet, the
    member's page and the printed record read "VIC client · ×2" on it
    (`2026-10-15-vic-performance.sql`). Never a score in a notification.
- A member sees nothing of a month, breaches included, until it is released.
  - A dispute window from release of the month's `dispute_days` setting
    (7; 3 before 2026-10-01; a month keeps the window it was given), item
    by item. Every Performance figure is edited in Performance settings,
    an admin's: Settings' Performance group (2026-10-29; the gear beside
    the padlock is gone), one row a part (Months, Quarters, Bonus and trip,
    Commission), for `team.performance` at View, each asking the master
    code where no unlock stands (`ADspacePerf.openSettings(view, opener)`;
    an unlock run out asks again) and opening the sheet on that part
    (`#rwSView`), each label the rule in plain words (`RW_SET`). On a phone
    the padlock closes the Performance view row (`placeTools`), so the
    Team tabs stay whole.
  - Date of evaluation (`evaluated_on`, `2026-10-01-performance-date-of-evaluation.sql`):
    the day the numbers were reported to the member. The sheet prefills
    today while none is set; release fills it where empty; management corrects it until final (in or after the month, never
    after today in MYT, `bad-eval-date`). The sheet, the member's page and
    the printed record's head show it beside Queries until.
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
  token's `amr` within 15 minutes): Use passkey first where the
  person holds one of their own, Email a code beside it. The code field takes 6 to 10
  digits. The Magic Link template prints `{{ .Token }}`.
- The review list is chosen (`perf_people.reviewed`, off by default; admins
  off unless added). The month lists the people on it plus anyone whose
  review of that month has begun; the Review list sheet ticks colleagues code
  first, A to Z (`perf_profile_set`, Work).
- Department and role standard (`role_family`) live on `team_members`.
  Performance reads them; `perf_profile_set` sets only its two ticks.
- Departments (`2026-10-23-departments.sql`, its SQL Editor part
  `2026-10-23-departments-editor.sql`; the user, 2026-10-23: "can add more
  departments?"): `departments` (key made once from the name and never
  moved, name, active, in_prize, five `criteria`; RLS on, no policy, no
  grant), seeded with Creative and Marketing in the prize. A colleague's,
  a review profile's and a prize score's department reference it
  (`*_department_fkey`). `departments_list()` (the team) is read once
  beside `me()` (`ADspaceAdmin.depts`, `deptName`; a failed read leaves
  the two of `W.dept`). Settings, Portal: Departments (`team.settings`):
  Add department, Edit (Name, In the department prize, its five criteria,
  each 2 to 60; `department_save`: `bad-name`, `taken`, `criteria-needed`,
  `bad-criteria`), the ⋯ Set inactive / Set active (never asks; offered to
  nobody, out of the prize, its colleagues keep it) and Delete where
  nobody is in it and no record names it (`departments_list` `in_records`:
  a colleague active or not, a review profile, a prize score;
  `2026-10-24-departments-in-records.sql`, TEAM2-15), asked under the title
  Delete (`department_delete`, `in-use`); a row's line holds each part
  whole (`team-part`); each filed
  `team.changed` under Departments, from and to. The department prize
  (`perf_quarter_calc`, `perf_quarter_confirm`, `perf_dept_save`) takes
  every active department in the prize in the list's order, each with its
  criteria names (`names`, kept in a confirmed snapshot); Confirm waits
  for each one's scores; with none, `no-departments`. The maxima stay 25,
  25, 20, 15, 15.
- Months start from June 2026. The padlock sits at the right end of the tab
  row, outside the strip (`.tabline`), never inside it as a third tab.
- The print is drawn in the browser on the letterhead and never stored. It
  carries no version and no signature lines: a member acknowledges in the
  portal.
  - Under the letterhead it is the Social Media Report's design
    (`drawRecord`): sizes and spaces on `S(k) = 10·φ^(k/2)`, headings in
    title case, tables of white cells under a #f2f2f2 title row and grid,
    the month's grade shaded in one row of the five, the final score the
    one bold figure; page one the result (who, Result, Scores, What This
    Grade Means), page two the follow-up (Issues, If This Result Repeats,
    Improvement and Follow-up, Queries, Record of This Document); a
    heading keeps its block, a short paragraph never splits; the foot
    PRIVATE & CONFIDENTIAL beside the page count, the reference and who
    downloaded it above.
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
- The review sheet reads Rates behind the scores above Scores (the user,
  2026-10-11: the rates suggest the points): each rate a percentage
  management types, and Save works out each category's suggested points
  from them (`perf_calc` `suggested`), never the score. Two carry what My
  Work knows (`perf_ops_rate`, `2026-10-11-review-my-work-figures.sql`), a
  press making it the rate: On-time posting, the content tasks the
  colleague owns whose post date fell in the month (MYT) and has passed, and
  how many went live by its day; Timeline adherence, the tasks they own
  that reached their review in the month, and how many by every deadline
  they had (My Work's late rule).
- Notifications never carry a score.
- Release carries Notify {name}, ticked by default on every month
  (`perf_release(p_token, p_review, p_rev, p_notify default true)`, filed
  `notified`); unticked, the member is not told and the sheet says so.
  A draft month's Notify, Save (tonal) and Share (the one blue) sit at the
  review sheet's foot (`#pvFoot`, `.qfoot`), where the scores end; never a
  `.sheet-foot`, whose primary Enter presses: Enter in a score never shares
  the month.
- Self-rating (`2026-10-07-performance-self-rating.sql`, `perf_self_ratings`,
  RLS on, no policy, no grant): a colleague on the review list rates
  themselves on the six scorecard categories in My records, Reviews (one
  Rate yourself card, a row a month newest first, the newest still to rate
  tagged Due and its button the one blue, a rated month its total and Edit;
  MINE-1, 2026-10-22), for each month from June 2026 to last month while its
  review is not shared (`perf_self_open`: `bad-month`, `shared`,
  `not-reviewed`; `perf_self_mine`); `perf_self_save` refuses a missing
  score (`incomplete`) or one outside its category's maximum or off a step
  of 0.1 (`bad-score`), filed `self.saved`. Management reads it beside its
  own scores (Self-rated n under each category, the total in one line); it
  never moves the grade.
- A month whose query window has closed with no query open is acknowledged
  and finalised by itself, earlier months too (`perf_close_windows()`,
  pg_cron `perf-close-windows` at minute 7 of every hour, `finalised_by`
  null); History and the printed record read Automatic, queries closed, and
  the review card says while the window runs that it becomes final then.
- A member's first open of a shared month is stamped (`perf_seen`,
  `perf_reviews.opened_at`, filed `opened`) and listed as Opened in History
  and the printed record.
- Reminders (`2026-10-07-my-hr-reminders.sql`, `my_hr_remind()`, pg_cron
  `my-hr-reminders` 09:05 MYT): one notice a colleague a day at most, naming
  only what is owed: on the 1st and `remind_again_days` (3) on, last month's
  self-rating and reflection (the review list only); `remind_before_days`
  (3) before the month ends, its reflection; the same before each half
  month ends, the health check-in, only to a colleague whose agreement
  stands, the days held to the half's own (a February's second half is
  reminded on its first day at the latest;
  `2026-10-18-half-month-reminder-always-comes.sql`). Both days are Performance settings (Reminders, 0 to 14, 0 sends
  none). The bell and a push open the view (`perf.remind`, `perf.reflect`,
  `health.remind`, tag `my-hr`); never a score or a note.
- An admin deletes a member's month in any state (`perf_delete`: the
  performance part at Manage, a live unlock and admin; never their own), from
  the row's ⋯ and the review's ⋯, with the name and month typed back
  (`{name} {Month YYYY}`) and a reason. The review, its disputes and scores
  go; its history rows stay (the link set null, which `perf_events_frozen`
  lets through below another write), one `deleted` row says who and why
  (Record deleted), and `perf_deleted` keeps a printed reference so
  `/verify/` answers it Void. There is no restore.
<!-- Performance rewards (2026-09-28) -->
- Initiatives and the reflection (`2026-10-04-initiatives-reflection.sql`,
  `perf_initiatives`, `perf_reflections`, RLS on, no policy, no grant):
  - My records (`?s=mine`, the account menu's first item; never My
    performance, the user, 2026-10-06: it holds more than reviews; never My
    HR, 2026-10-07: it read oddly) is five views
    (`#mineViews`, `view=` in the address, Reviews left out): Reviews,
    Initiatives, Reflection, Letters, Health, all behind the fresh proof
    (`perf_mine_gate()`, the card Your records are locked).
  - An initiative (title 3 to 140, Improves: Client work, Process, Tool, SOP,
    Other; details; an https link) is logged in this month as Proposed and
    edited while Proposed; Withdraw (Undo in place, Restore in the ⋯) is its
    author's way out. Management (`team.performance` Work, a live unlock)
    moves it Proposed → Adopted / Not now (each asks, with an optional note
    the author reads, and tells the author, `perf.initiative`) → Done (the
    month it is done); Revert back to Proposed never asks. Performance's
    Initiatives view (`view=initiatives`) lists everyone's but the caller's,
    by state (Not now and Withdrawn shut). Nobody decides their own (`own`).
  - The review sheet shows beside the scores the colleague's initiatives
    logged or done in that month and, once they share it, their reflection
    (`perf_review_context`); nothing scores itself: the reviewer still
    scores Initiative and improvement.
  - A reflection is Proud of, Found hard, Want to learn, for this month or
    last, until that month is final (`bad-month`, `final`); Share with
    management asks first, Stop sharing never asks; management reads it
    only while shared, and it is never scored.
  - Every step is filed in the review trail (`initiative.*`,
    `reflection.shared` / `unshared`); `perf_activity` does not list them.
- Rewards (`2026-09-28-performance-rewards.sql`) are Performance's views
  Months, Quarters, Bonus and trip, Commission (`view=`, `q=` the quarter or
  the period's first quarter).
  - Worked out on every read (`perf_quarter_calc`, `perf_flex_calc`,
    `perf_period_calc`, `perf_commission_json`) from finalised months, but
    the quarter's ranking, which reads every month released to its member
    (any state but draft; `2026-10-05-performance-quarter-live.sql`; it
    waits on reviews, a person's month each, never called months), so
    management sees the order as it stands: `provisional` while the quarter
    runs or a month is not final or not entered, each row's `finals` said
    under its average (`2 of 3 · Not final`), and whoever is ahead reads
    Leading (the user, 2026-10-05). Confirm
    (Work) keeps a snapshot in `perf_rewards`; Reopen (Manage) removes it,
    files it and never asks. A month inside a confirmed quarter or half is neither
    reopened nor deleted (`period-confirmed`, naming it) until that period
    is reopened. Quarters begin with Q3 2026.
  - The quarter (`2026-10-01-performance-quarter-ranked.sql`) is Ranking and
    rewards: best to worst by average, `rank` shared by equal averages, a
    short quarter's months under its average (`2 of 3`), and the individual
    prize from the average of the final months (a weak month can be made up),
    whole to the highest eligible average with no minimum (a tie shares it;
    the user, 2026-10-05).
    Confirm is drawn only once every review in the quarter is final
    (`months-open` refuses otherwise) and asks first where an ended month
    has no review (`missing_months`). The member's own quarter never carries
    `rank`.
  - The department prize goes to the winning department whole (`share`,
    named "{Department} won"); its team leader decides the split, so no
    member's row carries a figure for it. Tied departments are joint winners
    and one that does not qualify drops out. The department scores are
    `team.perfadmin`'s alone (`perf_dept_save` refuses `admin-only`, the page
    offers Department scores to that part alone; 2026-10-18), never of the
    scorer's own department (`own-department`, by `team_members.department`).
  - Flexible hours: a month decides the next only once every active member on
    the review list has a final review of it.
  - A bonus period is a half of the year (Q1 and Q2, Q3 and Q4; `perf_half`),
    named by its first quarter; any date reads as its half. Like a quarter,
    its Confirm is drawn and accepted only once every review in its six
    months is final (`months-open`, `scope` period; `open_months`), a
    draft of a colleague who has left aside (it can never be released);
    the chip names the reviews it waits on (`open_reviews`). Revenue and profit are
    read and written only by `perf_is_admin()` and filed by name only; the
    rest of management sees the amounts.
  - Every share is rounded down to the cent and the remainder stated.
  - Every figure the rewards are worked out with is a setting
    (`2026-10-05-performance-reward-settings.sql`, `perf_settings`: both
    prizes, the department total, flexible hours' share and month, the pool
    and trip gates, the pool's share of profit, months at B, units by grade,
    the commission floor), each from a quarter on and read as at the
    quarter, month, half or deal month (`perf_setting`). Reward settings
    (`#rwSetSheet`, from Settings): management reads, `team.perfadmin`
    changes them from a quarter on (`perf_settings_set`), never into a
    quarter or half already confirmed (`confirmed`); each change is filed
    from and to (`settings_set`), and every calculation says the rules it
    used (`rules`), kept in the snapshot on Confirm.
  - Commission is pending until its month is final; the member sees it once
    decided. Nobody enters their own.
  - The caller's own row arrives with its name alone (`perf_hide_own`); the
    member reads theirs through `perf_rewards_mine()` behind the fresh code.
  - `perf_today()` is the one clock the rules ask; `tests/perf.js` replaces
    it, and the stand-in reads `window.__perfToday`.

### Health (`js/health.js`, `?s=mine&view=health`, `?s=team&tab=health`)
- A colleague's own check-in every half month (`2026-10-07-health-check-ins.sql`;
  `health_consents`, `health_log`, `health_checkins`, `health_talks`, RLS on,
  no policy, no grant). Health is sensitive personal data (PDPA 2010):
  nothing is asked before the colleague agrees, and every agreement and
  withdrawal is kept (`health_log`).
- Before agreeing, the card speaks as the company, the one place the console
  says "we" (the user, 2026-10-07): Your health matters to us; work and home
  both shape body and mind; answer honestly, there are no right or wrong
  answers; if something feels heavy, ask for a talk, reaching out early is a
  strength. Beside it, shaded, What you agree to (five questions every two
  weeks; ADspace management reads the answers by name, only to understand
  and support; never part of a performance review; withdraw at any time);
  then I agree, which never asks (`health_consent`). The words are the
  database's (`health_wordings`, each version whole, a new version a
  migration; `2026-10-18-health-terms-are-versioned.sql`): `health_mine()`
  sends the latest, an agreement names the version shown (`stale-wording`)
  and stands only on the latest (`health_agreed`), so a new version pauses
  the check-ins, the talks, the reminders and Team: Health (Terms changed)
  until the colleague agrees again. Withdraw asks (warn),
  stops the check-ins and takes the answers out of Team: Health; Agree again
  is the way back.
- The check-in: Body, Mind, Sleep, Energy, Workload, 1 to 5 each (5 is well,
  a word for every step; each scale's two ends named under it, `hcE_*`,
  2026-10-27, MINE-7) as segments, and an optional note of 1,000
  characters, once a half month (the 1st to the 15th, the 16th to the month's
  end, MYT), edited until it ends (`health_checkin_save`: `no-consent`,
  `incomplete`, `bad-score`, `too-long`; the page names the half its sheet
  showed, one ended refused `stale-half`, the answers kept and the sheet
  naming the half open, `2026-10-18-checkin-keeps-its-half.sql`); the sheet opens on There are no
  right or wrong answers. Answer as you truly feel today.
- The view: the half month's card (Checked in on {day} under its title; the
  five answers across it, two across in a narrow pane with the fifth taking
  the row; the note under them), Your check-ins (a half month a row), Talks,
  then Agreed on {day} with Withdraw as one quiet line, never a card; one
  12px step between them. A low answer (2 or under), with no talk asked
  for, opens Talks with a word of care. A low answer is a warn figure with
  its word, never a colour alone; Health's pink marks its glyph and the
  chosen answer, nothing else.
- Ask for a talk (`health_talk_ask`: a colleague, an optional note;
  `already-asked`, `bad-colleague`) tells the colleague asked (`health.talk`,
  the asker's name, never the note); the asker withdraws it and asks again,
  the colleague asked marks it done and reopens it (`health_talk_set`); a
  withdrawn talk, which the colleague asked and Team: Health no longer
  read, is its asker's to delete from its ⋯ (`health_talk_delete`, asked,
  no restore, `bad-status` for an open or done talk;
  `2026-10-24-health-talk-delete.sql`, the SQL Editor's).
- Team: Health (`tab=health`) is an admin's alone, behind the Performance
  master code with its 15-minute unlock (`health_check(p_token)`,
  `health_team(p_token)`, `2026-10-18-team-health-is-an-admins.sql`; the
  same unlock either page takes; never a granted part, never offered to a
  group): the half month's averages as
  bars (warn under 3) with `n of m checked in` (with nobody agreed, the one
  line No colleague has agreed to check-ins.), Colleagues (every active
  colleague: this half's five answers, Checked in, or Not agreed /
  Withdrawn as a chip), each opening their history, and the last 90 days'
  talks. `health_team()` sends a colleague's answers only while their
  agreement stands and only those saved since it was made
  (`2026-10-18-health-answers-follow-the-agreement.sql`), and a talk's names, state and dates, never its note,
  which only the two colleagues in it read
  (`2026-10-18-health-talk-notes-stay-private.sql`). The
  answers never reach a review, the Activity record or a notification.
- Health data is kept for a time (`2026-10-18-health-data-kept-for-a-time.sql`,
  PDPA 2010): `privacy_retention` removes a check-in for a half month that
  began more than `health_keep_months` (24) ago, and the check-ins,
  agreement, log and talks of a colleague no longer active who was removed
  or whose access expired more than `health_leaver_months` (6) ago; both
  Business settings (Settings, Portal: Health data kept, `team.settings`;
  6 to 120 and 1 to 60 months).

### Reports (`js/reports.js`, `js/smreport.js`, `?s=reports`)
- Reports is its own section (`reports` View / Work / Manage), not a part of
  Clients. `clients_read` also answers Reports View.
- Flow:
  - Draft → Submit (Work) → Confirm (Manage; never the submitter,
    but an admin may confirm their own after a question saying nobody else
    checked it: `2026-10-02-report-admin-confirm.sql`) → Publish
    (Manage).
  - A report is submitted to a named reviewer (`sm_reports.reviewer_id`,
    `2026-10-04-report-reviewer.sql`), asked for in Submit's question from
    `sm_report_reviewers` (Reports Full Access or an admin, never the
    submitter, the client's last reviewer chosen; an admin submitting is
    offered as Me and chosen, and confirms their own:
    `2026-10-16-admin-reviews-own-report.sql`). Only the reviewer, or an
    admin after "Confirm in place of {name}?" (filed "in place of"),
    confirms (`not-reviewer`); the reviewer, an admin or the submitter
    (Take back) sends it back. Change reviewer in the head's ⋯ (submitter,
    reviewer or admin; `sm_report_assign`, filed `report.reassigned`). The
    reviewer is told on Submit and on a change, the submitter on Confirm
    and Send back, each through the bell and a push opening the report
    (`ops_notifications.report_id`). The step reads "Waiting for {name} to
    confirm."; the list row names the reviewer. A report in review from
    before keeps the earlier rule until Assign reviewer (the same ⋯) names
    one. Only the functions set the reviewer.
  - The month's gate (`2026-10-04-report-month-gate.sql`, reports from
    October 2026): `sm_report_gate` finds the client's month whose span
    holds the report's last day and names what it lacks (`no-month`,
    `not-ticked`, `no-task`, `content`: content tasks fewer than planned,
    report and cancelled tasks not counted) and the due time (the report
    task's). Check and submit shows it as rows under the report's checks
    (Month in My Work, Report task with Open where My Work is readable,
    Content, Due). Submit is
    refused `month-gate` unless an admin or Reports Full Access gives a
    reason, and `late-reason` once past due until one is given; Submit's
    question asks for it beside the reviewer, kept as `gate_note` /
    `late_reason` and filed. At Work a month not in order rests Submit.
  - The month's report task follows its report
    (`2026-10-08-report-tasks-follow.sql`, trigger `sm_reports_task_follow`,
    the task found as `sm_report_gate` finds it; the user, 2026-10-08): a
    report made puts it In progress under its maker; in review, confirmed
    or published and not yet sent, Waiting; marked as sent, Review. Done is
    the owner's own press: a finished or cancelled task never moves, nothing
    moves one to Done, and a white-label brand's report leaves it alone; a
    report given a brand after it was made puts the task back to To do
    under the month's manager (unless another of the client's own reports
    in the month holds it), and one given back to its client takes it
    again (trigger `sm_reports_brand_task`, `2026-10-15-white-label-task.sql`).
    Each move is filed on the task with `report_id`; a fault never fails
    the report's write. A draft report deleted puts its unfinished task
    back to To do, filed Report deleted (`sm_reports_task_reset`,
    `2026-10-09-report-month-at-start.sql`).
  - A report begins in its month (the same file; the user, 2026-10-09): a
    report from October 2026 with no white-label brand is made only for a
    month in My Work whose span holds its last day and whose Reports ticks
    ask for its kind (trigger `sm_reports_month_gate`, `month-gate`), unless
    an admin or Reports Full Access makes it. New report asks Monthly or Ad
    hoc (`#rpNewMode`; the user, 2026-10-11). Monthly offers the client's
    content months in My Work alone (`sm_report_months`), each named and
    spanned as the report will be (a month starts on its `start_day`), one
    report of a type a month: a month already holding it (same brand, same
    span) reads its stage (`· Published`) and is not offered; one whose
    Reports ticks do not ask reads Not asked for, offered only to an admin
    or Reports Full Access; a client's own Accounts Report needs the month's
    planned content (`No planned content`; `sm_reports_month_gate`
    `no-content` at every level, `2026-10-11-reports-need-content.sql`).
    A white-label client is held to neither of the last two, for its own
    reports and its brands' (a brand takes the partner's months), either
    type. Ad hoc is a start and an end, any period, made on request. The
    month sheet's Accounts report tick rests while Posts planned is empty
    for a client not white label (`ops_engagements_accounts_content`:
    `accounts-needs-content`; a new month with no plan leaves out the tick
    it took from the month before).
  - On request (`2026-10-09-reports-on-request.sql`, `sm_reports.on_request`;
    the user, 2026-10-09: "Sometimes we need to create report on demand"):
    New report's Ad hoc makes a report the client asked for, on any period (`sm_report_create_for(…, p_on_request)`, filed On request).
    No month gate, no month rows under Check and submit (`sm_report_gate`
    answers `applies` false), the month's report task never moved or reset
    by it, never the month's report in `sm_report_months` or
    `sm_reports_owed`; a month's report never carries on from one, and an
    Advertising Report asked for compares with the same length just before
    it. The list marks it On request; the head reads Requested, By the
    client.
  - Then Revise (the next version as a draft) or Unpublish (with a reason).
  - Mark as sent (Reports at Work; `sm_report_sent`, `sm_reports.sent_on` /
    `sent_by`): one date, today by default, never after today nor before
    the period (`bad-date`); filed from and to. The head's Sent fact is the
    one control: a Mark as sent button, then the day with its pen; the ⋯
    holds only Mark as not sent (2026-10-09: it repeated the pen). A
    published row reads Sent {day} or Not sent. Once a
    published report not yet sent has its PDF drawn (Preview PDF or
    Download), a line under the head asks Sent to the client? (`.rp-sentask`:
    Mark as sent, today, and a close mark; kept through a repaint until
    answered or closed), and the way back is Undo where it happened; no
    Share or WhatsApp button (the user, 2026-10-06).
  - Download (the head's ⋯, every report, Reports View) saves the PDF under
    its own name with no tab: Preview PDF's tab holds a passing `blob:`
    address that cannot be shared, and the browser may name a file saved
    from it at random.
  - Transfer client (the head's ⋯, `reports.transfer`, a draft only;
    `sm_report_move`, `2026-10-06-report-move-client.sql`) moves a report
    started under a temporary client to an Active one with no report of its
    kind for a day of its period (`not-draft`, `not-active`, `exists`); its
    rows and AI uses follow it, filed `report.saved` under both clients.
  - White label (`2026-10-07-white-label-on-the-client.sql`): the partner
    is the client (billed, with its portal) and ADspace services the
    partner's own clients under its name, so the report stays under the
    partner. A client is made a partner on its Brand (Reports, White label:
    `clients.white_label`, read with the record alone, never the list), and
    ticked it needs its wide logo (`clients.report_logo`, a PNG drawn down to
    1200 by 400; the sheet refuses Save without it and the database's
    `clients_white_label_logo` too; filed `client.brand`). Both the tick and
    the report's choice are Reports: White label at Work (a granted part;
    `clients_white_label_guard`, the Brand sheet's Reports section drawn only
    for it). The Brand pane reads it as one White label group (`#crmWlBrands`:
    White label, Wide logo, then Brands with Add brand; 2026-10-15). Brands (`2026-10-07-white-label-brands.sql`): a white-label
    client keeps a saved list (`client_brands`, RLS on, no policy, no
    grant; `client_brands_list`, `client_brand_save` at Reports: White
    label; unique within the client in any case, `taken`; stood down, never
    removed; a rename reaches its reports not published; filed
    `client.brand`), on its Brand with Add brand and each brand's ⋯ Rename /
    Set inactive. A report is its client plus a brand (`sm_reports.brand_id`;
    the client's own has none): one a client, kind, period and brand
    (`sm_reports_client_brand_period_idx`), New report's Client list (each
    active brand straight under its client, `{client} › {brand} · White
    label`, value `b:{brand id}`; one pick, no For field; the user,
    2026-10-15; `sm_report_create_for`), the head ⋯'s White label (any
    report not published, drawn only where the client is white label and
    holds a brand; 2026-10-22, RPT-2; `sm_report_brand`, `exists`, `bad-brand`, filed
    from and to), accounts carried from the same brand's last report and
    the AI quota counted by brand (`ai_drafts.brand_id`, filled by
    trigger). A brand's report sets `label_client` to its own client and
    `brand_name` to the brand. A white-label report is not transferred
    (`white-label`). The list names it by its brand with a White label
    chip, the client under it. There is no list of partners
    (`report_partners`, `report_partner_clients` and `sm_reports.partner_id`
    were dropped on 2026-10-24, `2026-10-24-unused-tables-dropped.sql`, with
    `activity_viewers`, `ops_kpi_targets` and `video_script_reviews`). Each brand says whose mark heads
    its reports (`client_brands.logo`, `partner` by default or `adspace`;
    `client_brand_logo`, the brand's ⋯ Use ADspace logo / Use {client} logo,
    never asks, filed from and to; the row's `ADspace logo` chip;
    `2026-10-07-white-label-brand-logo.sql`). `sm_report_snapshot` sends that client (its name and wide
    logo, while still ticked and the brand takes it) and, with a brand, the brand as the client's
    name and no client logo; the PDF draws the logo at the head of every page
    in place of the ADspace wordmark (15pt high, two fifths of the line at
    most; the name in the wordmark's face where no logo is held) and a
    published version keeps both. Everything else stays ADspace's (the
    glossary link, the file's properties). The report head's facts read
    For {brand} and Logo {client}.
  - An account on a platform the database's list does not hold is kept as
    `other` with `sm_report_platforms.platform_name`
    (`2026-10-06-report-platform-names.sql`, carried forward by
    `sm_report_create`): the account sheet offers 抖音, Pinterest and
    大众点评 by name, and Other asks for the Platform name (required).
    `platWord()` (both scripts) names it everywhere; never "Other". An
    account kept as Douyin before reads 抖音 (`RENAMED`; the user,
    2026-10-07).
  - A trigger refuses row edits once a report is not a draft, and refuses
    status or stamp changes outside `sm_report_*`.
  - Publishing freezes `sm_report_versions.snapshot`.
  - Kept as sent (`2026-10-07-report-files-kept.sql`): once a version is
    published its PDF is drawn from that snapshot and stored once under
    the bucket's `private/{client}/` (`sign-upload` private, then
    `sm_report_keep_file`: Reports Work, the key under the report's own
    client, never replaced; `file_key`, `file_at`, `file_by`; its own
    write passes `client_scope_guard` under `adspace.keep_file`, so a
    client seen at View is kept too, `2026-10-07-report-file-kept-in-scope.sql`). A file
    stands for the publish it was drawn after (`file_at` not before
    `published_at`), so a version published again keeps the next file.
    Every download of a published version (the head's Preview PDF and
    Download, Select's Download, the client record's Engagements, the
    client portal) hands over that file, read back as bytes through
    `sign-download` `{ reportVersion }` (`sm_report_file_key`, asked as the
    caller: a colleague at Reports or Clients View on a client they see,
    any version; a client's contact only the version the portal shows),
    never a link; a version with no file is drawn from its own snapshot and
    kept then, and a kept file that does not open is drawn again with
    "Drawn again: the kept file did not open.". The head's ⋯ Versions
    (`#rpVerSheet`) lists every version newest first (published when and
    by whom; On the client portal, or Unpublished and why) with its own
    Download, and its ⋯ Restore and Delete (the user, 2026-10-25,
    `2026-10-25-report-versions-restore-delete.sql`): Restore
    (`sm_report_version_restore`, Reports at Work, a draft or published
    report, asked first, over a draft in warn saying its edits are lost
    with no undo (2026-10-27, RPT-13); `in-review` otherwise) writes that version's kept
    snapshot back over the report's rows and commentary as the draft, a
    published report becoming the next version's draft, the portal keeping
    what it shows until a version is published, filed `report.revised`
    Restored from version n; Delete (`sm_report_version_delete`, Full
    Access, asked, no restore) removes a version the portal no longer
    shows (`on-portal` for the newest not withdrawn), filed
    `report.version_deleted`, its PDF left in S3.
  - Delete (the head's ⋯, Reports Full Access, the period typed back as the
    page writes it, which `sm_period_word` writes alike: 16 September to 10
    October 2026; `2026-10-13-period-words.sql`) removes
    a report in any state with every version (`sm_report_delete`,
    `2026-10-11-report-delete-seen.sql`; the user, 2026-10-11); one the client
    has read says so in its question and in the record (`report.deleted`:
    had been published, n versions removed from the client portal).
- The list is one tab a stage (`#rhTabs`, the view strip, swipe and the
  arrows; `tab=` in the address, Drafts left out): Drafts, In review,
  Confirmed, Published, each with its count, opening on the first that
  holds any. Under the tab, a card a report month (`period_start`), newest
  first, a published row's Sent or Not sent in its own right column on a
  narrow pane (`.rh-sent`, 2026-10-27, RPT-11). Published is held to a period (`#rhPeriod`, Last 3 months by
  default, Last 12 months, This year, All months; drawn only on that tab),
  only its newest month open; a search (client, code, month, type) looks
  through every report, whatever the tab and the period. New report opens
  on the type as a segment (Accounts Report / Advertising Report). Only
  Active clients.
- Select reports (the bar's ⋯, Reports View) turns each row of the tab into
  its tick (`.rh-row.is-picking`, the row a `label`) under a bar
  (`#rhBulk`: a tick for the whole tab, `n selected`, Download, Mark as
  sent on Published at Work, Publish on Confirmed at Manage,
  Done); changing tab clears the ticks. Each act runs one report after
  another through the function one report uses (`sm_report_sent`,
  `sm_report_publish`), and what is refused is named against its report
  (`#rhBulkMsg`). Mark as sent asks one day for all (today, never before
  the latest period), with Undo over the list putting back each report's
  own day. Download saves each file under its own name.
- Four steps, a strip with each step's summary, Next: {step}, and Check and
  submit. Every step's foot reads Next: {step}, Save beside it where the
  step saves, and the editor's way out is Back (2026-10-22, RPT-7); the
  Commentary step is done, its tick drawn, only once every block is
  written (RPT-8).
  - The head is the record head: the name, then the state, Preview PDF and
    the ⋯ at the right edge; the meta under them (type · period alone),
    then the facts each under its label (`.rp-facts`: Version, Client
    portal, Sent, For, Logo; one left out where it has nothing to say;
    two across in a narrow pane). On a narrow pane the
    button reads PDF (`.rp-pdf-short`). Preview PDF opens a tab at the
    press (`openTab()`, "Drawing the PDF…") and puts the drawn file in it
    (a `blob:` address), so the browser previews it; where the tab is
    blocked the file downloads (the user, 2026-10-05).
  - The step foot is an action row, the primary at the right edge.
  - Check and submit ends in one too (`.rp-actions`): Send back, then the
    step forward at the right edge, each at its own width (the base `.btn`
    is `flex: 1`, so an action row states `flex: 0 0 auto`); who it waits on
    sits to their left; on a phone the pair are equal halves under it.
  - An empty step's line does not repeat the head's Add.
  - An account is named by its handle (`account_name`, labelled Handle):
    a new account takes the client's Brand handle for the platform picked
    (`handle_ig`, `handle_fb`, `handle_tiktok`, `handle_xhs`) and follows the
    platform while untouched. The PDF names the platform, never the handle.
  - The commentary has no title or headline. An ads report's is four
    fields. An accounts report's is the summary, then one block a platform
    group (written to its lead account: Summary line, What worked, Areas to
    improve, Focus for next month, the advertising report's words) and,
    under its own Top posts label (`.rp-tophead`), Why it stood out for
    each of its top three posts (`ADspaceSmReport.topOf`, ranked on that
    platform alone). The older across-platform fields show under Across all
    platforms only on a report that holds some; an account sheet shows its
    own remarks only where it is not its group's lead and holds some. The
    step counts the summary and each platform (`commentaryState`).
- The client record lists a client's reports on its Engagements pane, each
  in its content month (Clients: Engagements); there is no Reports tab on
  the record.
- The client portal reads only the newest version that has not been withdrawn
  (`portal_reports`, `portal_report`), and names it as its cover does
  (`ADspaceSmReport.titleOf`).
- Accounts carry forward.
- Posts paste from a spreadsheet, or its CSV file, by header name. Thumbnails
  are 320px JPEG data URLs.
  - A slashed date is day first unless the paste shows otherwise (a second
    part over 12) or is a Meta export (`Post ID` and `Publish time`), which
    is month first.
  - A Meta Business Suite export: Title is never a title (it repeats the
    caption, and is the caption where Description is empty, as on a
    Facebook photo; the post is named by its format and date, its caption's
    first line under it), Description is the caption, Publish time the date
    (written in US Pacific time, read as the Malaysian day of that moment,
    `metaDay`), Reactions,
    comments and shares the interactions, Post type (and a `/reel/` link)
    the format. Where a paste names no interactions (Instagram: Likes,
    Comments, Shares, Saves) they are the sum of those parts, and where it
    names no engagements they are the interactions, so either figure an
    account shows is filled. One post a Post ID: a Lifetime row is taken as it is (figures
    to the day of the export); day rows are added up inside the report's
    period, reach left blank (it cannot be added across days). The summary
    line says which, and says in warn before Import a file with no Views or
    Reach column (Meta's daily breakdown carries neither).
  - A post already in the account is matched by its link and updated, never
    added twice; a blank cell never clears a figure.
  - Select (`data-a="pickposts"`) ticks posts: Move to account (two accounts
    or more) and Remove (asks, naming how many), each with Undo.
- Ads reports (`kind = 'ads'`):
  - Meta and TikTok in one report (`2026-10-05-ads-platforms.sql`): each ad
    names its platform (`sm_report_ads.platform`, `meta` default or
    `tiktok`); Meta's figures stay at the top of `ads_totals`, TikTok's under
    `ads_totals.tiktok`, and reach is never added across platforms. The
    import and the ad sheet ask the platform (a segment, Meta first; a paste
    with TikTok's own headers picks TikTok until the person picks), a paste
    matches only its own platform's ads, and TikTok's hook is 2-second views
    over impressions, its hold 6-second over 2-second. Only where both are
    held: the ads list and the PDF head each objective with its platform
    (Leads · Meta, Traffic · TikTok), Step 1 asks TikTok's figures apart,
    the summary is a By platform table (impressions and spend totalled,
    reach not), the tax note reads On Meta, and Open in Ads Manager is
    Meta's alone. TikTok's campaign report (the team's first export,
    2026-10-10) is read as it comes: a row named by its campaign where no
    ad is named, Spend the amount spent, Results its result (Conversions
    only where no Results column), a CTR given as a fraction read as a
    percentage where clicks over impressions say so, and its Total of N
    results row the account's figures for Step 1, never an ad. It holds no
    reach, age or video figures: an ad level export with them is asked for.
  - `first_month` carries the reading guidance; a later month compares against
    the previous period, which is carried forward. A new report is never a
    first month by itself (`2026-10-01-ads-first-month-unticked.sql`: most
    clients advertised before the portal); with no earlier report the period
    before is prefilled (the previous calendar month, else the same length
    just before) for the team to type its figures, and the team ticks a
    client's true first month.
  - One row per ad and objective.
  - Ads Manager's own cost per result; a reach result reads `RM 1.33 / 1,000`
    under Cost per result in every table, never Per 1,000 reached; the
    console's row and the PDF read one rule (`ADspaceSmReport.cprOf`,
    `perThousand`; 2026-10-22, RPT-1).
  - Paste from an Ads Manager or Ads Reporting export (2026-10-01). A row on
    the report is one creative (the name without its creator code), objective,
    ad set and result type: its copies, age bands and days are gathered into
    it; two result types (Post engagements, Interactions) are never added
    together; Post engagements reads Engagements. Ad ID ties each row to its ad; without it, one name with two
    result types is refused, and a row that would match two of the report's
    rows is left out and listed as unclear, never written to the first. The row keeps its Ad IDs and the Account ID
    (`ad_ids`, `ad_account`) as the team's reference: the row and the Edit
    sheet's foot (left of Cancel) name how many (`2 Ad IDs`, a `.linkbtn`)
    and open them over the page (`#rpIdsPop`, a `.popcard` through
    `ADspaceMenu.pop`, above a sheet, Escape first): each a copy control,
    Copy all, Open in Ads Manager; never the IDs in a line under the name. A
    later paste is matched by them first, and never to a row of another ad
    account (`sameAccount`: a creative of one name in two accounts is two
    rows, each under its account's name in the console, `Ad account ending
    4321`, never in the PDF; the user, 2026-10-30); never printed in the PDF. A table's total row gives the figures once.
    The export's first row (no ad name) is the account's own reach,
    impressions and amount spent for the period, reach counted once: it
    fills Step 1 where empty, and a typed figure is kept (the sheet says so).
    A paste naming ads already in the report updates them with what it holds
    and adds the rest: a day export the dates (first and last day with
    impressions), an age export the age split, an export with neither the
    figures and reach as Ads Manager counts them per ad. Dates otherwise:
    Starts and Ends held inside the period, else the reporting range. Rates:
    a Hook or Hold rate column's formula is found from the rows; without one,
    hook is 3-second plays over impressions and hold ThruPlays over 3-second
    plays. Rows from two ad accounts are refused. The result type comes from
    the first row naming one (never `mixed`), read as its word
    (`ADspaceSmReport.resultWord`). The creator code (`_000` to `_999`) is
    dropped on import and hidden on the list and the PDF
    (`ADspaceSmReport.adName`).
  - Write with AI on the Commentary step of both kinds (`report-draft` edge
    function, secrets `ANTHROPIC_API_KEY` and `REPORT_DRAFT_MODEL`,
    `docs/REPORT-DRAFT-SETUP.md`): sends the report id and Notes for the
    draft (`#rpAiNotes`: reasons, changes, goal, next month's budget; kept
    in this browser under `adspace-draft-notes:{id}`, never saved with the
    report); the function reads the report as the caller (Reports Work, a
    draft) and sends Claude its figures, the notes and the client's last
    finished report's commentary, the client's name (and a white-label
    brand's) masked as `{brand}`, never a contact or image. The drafts and
    the check name the client by `{brand}`, filled with the name the report
    is for once the answer is back (`brandIn`, which also puts 贵公司, 贵司,
    贵品牌 and the like back to the name); never "your company" or a Chinese
    honorific (the user, 2026-10-07). It writes in a formal, client-facing house
    style taken from the team's approved reports (`SYSTEM`, `SOCIAL_SYSTEM`),
    held to its fields by structured output: the model in use refuses a
    forced `tool_choice`. An accounts report sends the platforms and top
    posts the step shows (`platforms`, `posts`) and gets back each
    platform's four fields and each post's remark, read platform by
    platform. Every press asks first (Write a draft?, or Replace the
    commentary? over written text), saying it uses one draft and how many
    are left; nothing is saved until Save.
  - A report has a draft language (`sm_reports.lang`, 'en' or 'zh',
    `2026-10-01-report-language.sql`), the English / 中文 segment beside
    Draft with AI (`#rpAiLang`), saved at once; a new report takes the main
    contact's preferred language. It decides only the language Draft with
    AI writes in (`ZH` in `report-draft`): the PDF's template is English
    throughout and what the team wrote prints as written (the user,
    2026-10-01: Meta's own terms read in English). The PDF's Chinese layer
    (`ZH_WORDS`, `ZH_COUNT`, `ZH_RULES` in `js/smreport.js`) is switched off.
    Chinese drafts read smooth and easy, as an account manager writes to
    the owner, never a stiff audit report (`ZH`, TONE IN CHINESE; the
    user, 2026-10-16).
    Chinese text is drawn in Noto Sans SC (`ADSPACE_ORG.fontCjk`, below).
  - Every draft keeps to `SHARED`: only what the client needs, a few points
    a field, one sentence a point, and candid both ways (the user,
    2026-10-07: never "creative is bad", never so protective it reads as if
    nothing ever goes wrong). The result is judged, never the work we made;
    a shortfall is said plainly with its figure, how far short and what we
    will change; a month weaker than the last is called weaker in the
    summary; a slip on our side the notes name is owned in one sentence; a
    win credits the choice behind it, with its figure; where the figures
    show no cause it says so; nobody is blamed without the notes; no result
    is promised. The words in `AVOID` (English and Chinese: judgements of
    our work, praise no figure carries, comfort phrases in place of a figure,
    words that colour a figure) are never used, and the check finds them and
    a picture brighter than the figures. The ads field `fix` is headed Areas
    to improve: an ad that cost more is read against its objective's own
    cost per result (`group_cost_per_result`, the marked ads left out) or
    the previous period, never against the best ad by name, as a multiple
    or a gap, or as the worst or highest (the user, 2026-10-16: "is this a
    proper way … to present client-facing report"), and an ad within about
    a fifth of that figure is not an area to improve.
  - Every press is counted by the database before Claude is asked
    (`ai_draft_claim`, `2026-10-01-draft-with-ai-limits.sql`), by subject
    (the report, or any of the same client and kind whose period shares a
    day with it, deleted or not: `ai_drafts` keeps client, kind and period,
    `2026-10-04-ai-draft-subject.sql`), a day from 12:00 am MYT and reset
    each midnight (`ai_draft_day()`, `2026-10-04-ai-draft-daily-reset.sql`).
    Every limit is a setting in `ai_draft_limits` (null is the standard,
    0 stops it; `2026-10-05-ai-limits-per-version.sql`): `person` a
    colleague's AI uses a day, drafts and checks together (10), `admin` an
    admin's (20), a colleague's id their own (`ai_day_cap`); then by who
    asks, on that report, today (`2026-10-05-ai-limits-per-person-day.sql`,
    the user: a report left to the last minute waits for the next day):
    `report` a colleague's drafts (1; the same period of the same client is
    the same report, `ai_draft_same`), `report_admin` an admin's (5), both
    refused `report`; `check` a colleague's commentary checks (1; a revision
    brings none the same day), `check_admin` an admin's (5), both refused
    `report_check`; every refusal names the reset time. There is no team cap: the team's and a group's totals are
    their colleagues' limits added up (`team` refused `bad-scope`). A
    press the API refused before it generated keeps no tokens, is marked
    failed and is not counted; one that reached the model and ended with
    no answer (its length, a refusal, nothing usable) is `incomplete` and
    counted (`ai_draft_done`, `ai_draft_tokens`; 2026-10-17, the user:
    "count every failure except rejected") against the day, never against
    the report's one draft or check of the day (`ai_draft_same`,
    `ai_check_claim`), so Try again works; nor does a run still `pending`
    ten minutes on (its function was stopped; 2026-10-18). `ai_drafts` has RLS on, no policy and no grants. A refusal
    (`ai-limit`) names the scope, the limit and when the next draft is free.
    Beside the button the count left reads `1 left` (`ai_draft_left`, the
    lesser of the report's and the colleague's, read without writing); at
    0 the button rests and the line under it says why and when the next
    is free.
  - The Report audit (2026-10-09; the user: "there shouldnt be any
    mismatches"; `2026-10-09-report-audit.sql`): one card under Check and
    submit's checks (`.rp-aicheck`: Report audit, Run audit with the
    commentary checks left, then a check row a part, `.rp-part`), in two
    parts, each reading No issues / n to fix / Not run.
    - Against Meta (no AI use): `meta-import` with `audit: true` reads every
      ad account the client (or its brand) links, or the linked Page and
      Instagram account the report holds an account for, and the page runs
      Meta's export through the importer's own plan (`adsPlan`, `parseRows`,
      a post matched by `linkKey`: Instagram by its shortcode, else host and
      path without www., trailing slash or tracking query), so a difference
      is exactly what an import would change. Exact, at the precision held,
      but Reach (Meta's estimate, revised while a period runs), which
      matches within `reach_allowance_pct` (Business settings, 0.5 from
      the start, 0 to 5; `2026-10-10-reach-allowance.sql`; the card then
      says Reach within n% of Meta on n figures): each figure Meta gives an
      ad (by Ad IDs, else name,
      audience, objective, result type), its age split, Step 1's impressions
      and amount spent (reach only where one ad account answers), an ad Meta
      ran with spend and results that the report lacks (Add; one with no
      spend or no results is never asked for), one with figures Meta shows no
      delivery for (Remove, its own press alone), each post figure and a
      post on either side. The differences are one table (`.rp-metatable`:
      Where, Figure, Report, Meta in ink at 600, Difference, the act at the
      row's end; in a narrow pane the three figures side by side under their
      labels; words and splits wrap, figures keep their line);
      Meta's rows carrying an Ad ID a report row holds are gathered into
      that row as it was made (a spreadsheet with no ad set column makes one
      row of a creative's copies in two ad sets; 2026-10-12), for the audit
      and Import from Meta alone (`fromMeta`), never a spreadsheet or CSV
      file. A result type is the same however it is named (Leads (form) and
      Leads, Estimated ad recall lift (people) and Ad recall lift, Reach and
      reach; `resultKey`); a cost per result the report does not hold is
      the one it works out, to the cent; Meta's play time is to the second;
      an empty count is Meta's 0. A figure an export may carry no column
      for (result type, hook and hold rate, play time, retention, the age
      split) that the report does not hold is listed apart, Not in the
      report, and never counted (2026-10-12); Use Meta's figure fills it. The ad account's own time zone
      (`meta-import` `tz`) is named on the card where it is not GMT+8.
      Use Meta's figure, Add, Remove, and Update all from Meta (the figures
      and missing rows, never a Remove) write through the rows' own writes
      with one Undo, file `report.saved` (Report audit · n figures taken
      from Meta), file the reading again from the same answer, and check
      the commentary again where it had been checked and a check is left
      (else its line says the figures changed since). It runs only when
      Run audit is pressed (and an Advertising Report at Publish), never by
      itself (the user, 2026-10-09: every open page filed a reading), and
      reads the report's figures again at the press (`freshFigures`), so a
      page opened before a colleague took Meta's figures never files them
      as differences.
    - Each reading is filed (`sm_report_audit_save(p_id, p_outcome,
      p_rows, p_note)`: `match`, `mismatch`, `unavailable` with Meta's
      refusal, `override`; `sm_report_audits`, RLS on, no policy, no grant;
      the figures' print taken by `sm_report_meta_print`; the same reading
      again refreshes its time; a new outcome filed `report.audited`,
      Report audit) and read by `sm_report_audit_last` (Reports View). A
      match reads Matches Meta as of {day, time}; a figure changed after it
      holds the report again.
    - The gate (`sm_report_audit_blocks`, `meta-audit`), only where the
      client links Meta (`sm_report_audit_needed`; else Not linked, with
      Link accounts opening the client's Brand at Clients Work): Submit
      waits on a match of the figures as they stand (the page rests it:
      Match the figures to Meta to submit.); Publish reads an Advertising
      Report again at the press and needs a match since confirmation, while
      an Accounts Report publishes on the reading it was submitted on (a
      post's figures are lifetime totals that grow by the hour; one
      submitted before the audit is not held). Meta moved since: Send back
      with Meta's changes (its reviewer, submitter or an admin in review,
      Manage once confirmed) returns it to draft with the changed rows as
      its note. Meta not answering (not connected, token, not shared, busy,
      failed) reads Not checked: Meta unavailable and holds it; an admin
      alone continues without it (Continue without Meta, a reason, filed;
      the part's mark then the amber dot, never the done tick),
      at Publish since confirmation. Reports Select's Publish does
      not read Meta: an Advertising Report it holds is refused by name.
      While the period runs (today in Malaysia on or before its last day;
      `sm_report_running`, `2026-10-12-audit-while-period-runs.sql`; the
      user, 2026-10-12) nothing is counted: a reading is shown for
      reference and never filed, Submit is not held, and an Advertising
      Report's Publish is refused `period-running` until the day after.
      What the reader must know or do is a note under its part
      (`.rp-anote`: `--sunk`, led by the amber dot, ink at 13px), never the
      part's mute line.
  - The Commentary (the figures check until 2026-10-09; `report-draft` with
    `mode: 'check'`, `2026-10-04-ai-check.sql`):
    the commentary as it stands, drafted or written by hand, read against
    the report's figures; it lists only what is wrong (a figure not in the
    data, a claim the figures contradict, a comparison across result types
    or platforms, a word against our own work), each as where it is, the
    words, what the figures show and the words to use (Use). A report in
    draft or in review, Reports Work, asked first (Run audit's question names
    both parts and the AI use); the colleague's check on
    the report for the day (`check`, an admin's `check_admin`) and one of the
    colleague's AI uses a day (`ai_check_claim`; what is left read by
    `ai_check_left`, the button resting with the reason at 0), never one of
    a report's drafts
    (`ai_drafts.purpose`, `ai_draft_same` drafts only). Kept with what it
    read (`ai_check_done`, `result`, `basis`) and read by anyone at Reports
    View (`ai_check_last`), so the reviewer sees the same check; a
    commentary changed since says so. Filed as `report.ai_drafted` (AI used)
    with Report audit · Commentary and the count (older rows keep Figures
    check). A finding is put right where it is
    found (2026-10-09): on a draft at Work, Apply puts its words in place of
    the quoted ones (Remove words where it gives none), Apply all does every
    one still standing, each through the draft's own save with Undo where it
    happened and filed `report.saved` (Report audit · Commentary · n
    corrections applied); a finding whose words are gone and whose fix stands reads
    Applied.
  - A draft and its check agree (2026-10-09): Write draft reads its own
    answer with the check's rules before handing it over and puts right what
    the check would flag, inside the same press (never one of the day's
    checks; skipped past 70 seconds), and takes out a word that colours a
    figure (only, just, 仅, 只有) before a figure or a number word (only
    one, only a single; never "the only") wherever it still stands
    (`plainFigures`, `tests/plainfig.js`); a place among
    ads or posts (the cheapest, the second most viewed) is said only from
    the ranks the function works out (`cost_rank`, `rank_views`,
    `rank_engagements`), never read off the figures; tokens are kept once a
    press, every call added up.
  - What the AI is told sits apart from the report's own words: one shaded
    block (`.rp-aidraft`, `--sunk`) holds Draft language (the pill) at the
    left and Write draft at the right edge with what is left before it
    (`.rp-airow`; on a phone a line each), then Notes for the draft under a
    hairline; the hint and the fields follow it (the user, 2026-10-05).
  - The words: Write with AI (Commentary, Write caption and Write script
    alike, the AI mark before the words; 2026-10-10, the user: "not clear
    that this is going to be written by AI"), Writing while it runs, Written
    by AI. Read before submitting. on the Undo line; Run audit (Check and
    submit); AI usage (the Settings page); filed under subject AI; never
    "Draft with AI" or "Write draft".
  - Commentary written with AI is declared read at Submit (2026-10-10):
    `ai_written(p_report)` (`2026-10-10-ai-written.sql`, Reports View)
    answers whether Write with AI drafted the report; where it did, Submit's
    question carries the declaration (`ADspaceConfirm.ai`: the line and a
    tick that refuses until ticked), and the submit files `report.saved`
    Commentary written with AI, read and confirmed.
  - AI usage (the Settings page, `reports.ai`;
    `ai_draft_usage()`), a usage page (the user, 2026-10-04): Resets at
    12:00 am, then used today over the limit with a bar (`.aiu-bar`, warn
    when full): Whole team, then each user group with its colleagues, most
    used first, the totals added up on the page; then Limits, each person:
    one limit a use for everyone (the user, 2026-10-11: "just unified
    across everyone"; AI uses, Drafts and Checks each report, Captions,
    Scripts, Brand analyses), a use changed saved to the colleague's and
    the admin's setting alike and nothing else saved (2026-10-14,
    ux-audit SET-3: one change had lowered all five admin limits), a row
    reading `· admins n`, and its field `Admins n a day` under the name,
    while the stored two differ. Edit limits turns those rows into small tonal fields in place
    (`.aiu-limits.is-editing`, Save and Cancel in the foot; never a sheet
    of boxes); a colleague's own limit is set by pressing their row
    (`button.aiu-row`, one field, empty meaning the standard); the totals
    and Limits rows only read. 0 to 500; only what
    changed goes through `ai_draft_set_limit`, each filed `team.changed`
    under AI from and to. No list of colleagues in a form (the user,
    2026-10-05). No explanatory lines.
  - Captions (2026-10-08, `2026-10-08-caption-writer.sql`) are their own
    count (`ai_drafts.purpose` `caption`, with `batch_id`): `caption` (20)
    a colleague's a day and `caption_admin` (40) an admin's, settings in
    `ai_draft_limits` read by `ai_caption_claim` / `ai_caption_left`, never
    counted in the day's report uses. Brand analyses (2026-10-10) are their
    own count too (`analysis` 3, `analysis_admin` 10, `purpose`
    `analysis`), listed under Brand analyses today and priced with their web
    searches. Scripts (Video Scripts' Write script,
    2026-10-09) are a count of their own the same way (`script` 10,
    `script_admin` 20, `ai_drafts.script_id`); the reports' limits count
    drafts and checks alone (`purpose in ('draft', 'check')`). Limits lists
    Captions and Scripts with the rest; Captions today and Scripts today list the team and
    each colleague who wrote one; This month prices Scripts apart.
  - Cost (the user, 2026-10-08: "Also check costing"): every call keeps
    `input_tokens`, `output_tokens` and `model` on its `ai_drafts` row
    (`ai_draft_tokens(p_id, p_in, p_out, p_model)`, once, the caller's own
    row, from both functions, drafted or failed). This month (MYT) reads the
    estimated cost in US$, by use (Report drafts, Commentary checks, Captions),
    the tokens and the prices, each row priced at the prices of its own day:
    `ai_price_in` (4) and `ai_price_out` (20), US$ a million tokens, Business
    settings (`app_settings_set`, from today; Edit prices, `team.settings`).
    A use from before tokens were kept is counted as not priced.
  - A draft is paid for once asked, so it is saved to the report as it
    arrives (`storeDraft`) and to the page's copy, the strip reading it at
    once (`localDraft`, 2026-10-27, RPT-10), with Undo putting the earlier text back
    (`restoreDraft`); a save that fails puts the draft in the fields with
    "Save before leaving.". While one runs, closing or reloading the tab
    asks first (`beforeunload`), and an answer that lands after the person
    moved to another step or screen is saved all the same and shown when
    that report's Commentary is next opened, once (`aiKept`).
  - Out of a draft the commentary check's findings fold under one line,
    and once confirmed or published they read as found, never to fix
    (2026-10-20, RPT-6, RPT-7).
  - Check and submit ends in Key dates (`keyDates()`, two marks at least):
    Started (by whom), Submitted (by whom, to whom), Confirmed (by whom),
    Published, the names on their own line under the date (`.tl-who`), each with
    the time since the step before, and the total (so far); the rows sit in
    the card's own `.ovsec`, never on its bare edge.
  - Each objective lists its ads as the PDF ranks them: cheapest cost per
    result first, then those with no result by spend, most first. An ad's
    name opens its Edit; its ⋯ reads Open in Ads Manager, then Edit and
    Duplicate, then Mark or Clear ad error, then Remove (`data-g`); on a
    narrow pane a table with no picture gives up the picture's track and
    the dates wrap between their parts (2026-10-22, RPT-4, RPT-5).
  - Ad error (`sm_report_ads.ad_error`, `2026-10-16-ad-error.sql`; the
    user, 2026-10-16: a Meta delivery fault read as the cheapest ad): an
    ad's ⋯ Mark ad error asks a reason (200 at most) on a draft at Work, the
    row reads the Ad error chip and sits last in its objective, Clear ad
    error never asks, each filed `report.saved` with Undo where it
    happened. It stays in every total and table; the PDF never ranks or
    bolds it, puts it last with ¹ and one neutral note under the table (Not
    ranked: minimal delivery), never the word error. Nothing marks one by
    itself (an ad made days before the period ends spends little).
    `report-draft` reads it as `not_ranked` (left out of `cost_rank`, its
    reason never sent) and never names it an error or a mark, even where
    the notes do; the check flags those words (`AVOID`).
  - ROAS (`sm_report_ads.purchase_value`, `2026-10-25-ads-purchase-value.sql`;
    the user, 2026-10-25): a Sales ad alone holds a purchase value (the ad
    sheet's Purchase value with its ROAS read beside it; Ads Manager's
    Purchases conversion value column; `meta-import` from `action_values`),
    never below nought. ROAS is purchase value over amount spent
    (`ADspaceSmReport.roasOf`, `roasWord` `3.25x`), the objective's over the
    ads holding a value. Where any Sales ad holds one, the step, the PDF and
    `report-draft` (`roas_rank`) rank its Sales ads by ROAS, highest first,
    those without after by cost; the PDF's summary adds Return on ad spend
    and the Sales table's ROAS stands where CTR does, each marked ² with one
    note (as reported by Meta, from purchases its tracking attributes, may
    differ from the client's own records). A report holding none reads as
    before; `sm_report_meta_print` adds the value only where set.
  - Select on the Ads step ticks several ads (`.bulkbar`): Move to objective
    and Remove (asks, naming how many), each with Undo.
  - The Ads and Posts step heads keep the import and Add on show; Select,
    Import from Meta and Pictures from Meta sit behind one ⋯ (`secMore`),
    each item drawn where its button was, the ⋯ leaving once none can be
    pressed (2026-10-20, RPT-2). In a narrow pane a row's figures carry
    their unit (`rp-unit`: 12 results, / result, views).
  - The age split must total 100% (±0.5).
  - Step 1's Results by objective show, until a figure is typed, each
    objective's results as the PDF adds them from its ads (the field's
    placeholder, read live; a mix of result types named part by part) and
    its amount spent beside them (`.readfield`, never typed).
- A step read and not edited (in review and after) is the facts card
  (`factsCard()`: `.ovcard` > `.ovsec`, each label beside its value, written
  text keeping its lines), one section a group: This period, Results by
  objective, Previous period; the commentary's fields, then a block a
  platform.
- Figure fields (`numFields()`, `data-num`) show a count with separators, a
  percentage to 1 decimal, and money as RM or S$. `numIn()` reads them back.
- Money fields take `inputmode="decimal"`; counts take `numeric`.
- New report: Monthly and Ad hoc are never both live, End's `min` is
  Start, and an empty date reads Select date.
- The ads PDF:
  - Ad performance ranks each objective's ads in a table; the cheapest is
    marked only among results of the same kind. Each objective's heading
    counts its creatives and the ads Meta ran (each Ad ID once, a typed row
    one ad) where those differ (`Leads · 21 creatives · 64 ads`), else its
    ads; under the glossary line (in the first month's How to read this) the
    page says a row combines every variation of one creative and what a
    weak row means (`VARIATIONS`). Creative performance then
    gives each creative (the name without its creator code) one card: one
    image, a line per objective and result type (amount spent, results,
    cost per result, reach, CTR; a missing figure a dash) under a head in
    Slate Regular, as every table in the report, the age split and video
    figures from the line that spent the most (2026-10-01).
  - The executive summary's Results by objective is one table under an
    italic band naming it (`band`), each objective's results, amount
    spent, cost per result and share of spend as a percentage; no bars.
  - An image added to one row of a creative is put on its other rows.
  - A result in a PDF table is its count alone (0 where an ad spent with
    none): the objective heads the table and the client reads the cost per
    result. The console's rows carry no result word either (the user,
    2026-10-02); `ADspaceSmReport.shortResult` stays for the sheet.
    A full block step separates one objective's table from the next.
  - The tax note follows the market: WHT and SST for MY; DCC and GST for SG.
  - Ad names never break at an underscore.
- Import controls read Import from spreadsheet and Import from Ads Manager.
- Meta checks (2026-10-10, `2026-10-10-meta-checks-switch.sql`; the user,
  2026-10-09: the imported figures did not tally with Meta, so hide it
  without touching manual entry, and keep it a setting): Import from Meta
  and the Report audit's Meta part run only while `meta_checks_on()`: the
  setting `meta_checks` is 1 (Business settings, the Settings page's switch,
  from today; 0 from the start) and the colleague holds `reports.meta` at
  Work (granted). Off, the import buttons are not drawn, `meta-import`
  answers `meta-off` for ads and posts, `sm_report_audit_needed` answers
  false so Submit and Publish never wait on Meta, and every manual import
  (spreadsheet, Ads Manager export) is untouched. The stand-in seeds it on.
- Import from Meta (`meta-import`, `docs/META-SETUP.md`, 2026-10-08): in the
  step head's ⋯ beside Import from Ads Manager (Advertising) and Import from
  spreadsheet (Accounts),
  drawn only on a draft at Work whose client (or brand) has a link
  (`meta_links_list`); with two ad accounts, or a Page and Instagram, it asks
  which (`ADspaceConfirm`, choices). The function reads Meta with the system
  user's token (`META_SYSTEM_TOKEN`, Graph `v26.0` unless
  `META_GRAPH_VERSION`, `appsecret_proof` with `META_APP_SECRET`), as the
  caller (Reports at Work, the report read under its own policies, the asset
  one the client linked), writes nothing, and answers Meta's export as text
  (`shape.mjs`: Ads Manager's with the account's row first and an Age text
  after; Meta Business Suite's Lifetime export, the Malaysian day). The page
  opens the existing import sheet (`pasteAdsSheet(opener, pre)`,
  `pasteSheet(opener, pre)`) named Import from Meta with it in, so one
  importer, one matching (Ad ID, link) and one summary line; the age split
  follows the figures in the same press, updating only ads it holds; an ad
  with no spend or no results is left out and counted in the summary line
  (`adsPlan` `withResults`, the audit alike; the user, 2026-10-09), and a
  copy of a creative that never ran is read after the copies that did and
  never writes over the ad they fed (its result type and zeros); posts go
  to the report's account on their platform; filed `Imported from Meta` /
  `From Meta`. An ad's reach is its age bands' sum where they name an
  Unknown band (`reachWithAges`, 2026-10-13): the Graph API's own reach
  leaves out people Meta could not age, which Ads Manager's export by age
  counts (2609W3_Balance: 800 against 6,484). Then each ad or post with no picture of its own takes
  Meta's (an ad's creative, a post's image or a reel's cover frame), read
  through `meta-import` `pictures` (Meta's own image hosts alone, one
  reader for a creative and `pictures`, `readMeta`: a redirect followed by
  hand, three hops at most, each held to them before it is asked, six a
  call, streamed and cut at 4 MB; 2026-10-22, BE-7; Meta's addresses expire within days; each ad's creative,
  as each post's metric here and in `brand-analysis`, asked of Meta on its
  own: Graph v26 refuses the `?ids=` read of many at once, 2026-10-12), drawn down to the
  320px JPEG and kept on the row (`.is('thumb_data', null)`: a picture the
  team chose is never replaced), filed `From Meta: n pictures added`; a
  picture Meta refuses leaves the row without, never the import. A refusal is one line under the step's head (`META_SAID`:
  not connected, token, not shared with the system user, busy, link gone),
  never Meta's words. Every figure is Meta's; none is AI's.
- Pictures from Meta (2026-10-13; the user: "can the import from meta take
  the creative image only"): on a draft's Ads step wherever the client
  links an ad account, whatever Meta checks says (a picture is not a figure;
  the user, 2026-10-13: the audit "inaccurate", the pictures needed without
  it), drawn while an ad holds Ad IDs; `meta-import` `creatives` (never
  `meta-off`) reads, for the
  report's own rows (three a call), the creative of the first Ad ID in an ad
  account the client links (the image, a link's or carousel's picture, a
  video's cover, its preferred frame, then the thumbnail at 1080), never a
  preview of the ad and never a figure. It asks first, a tick replacing the
  pictures already held; only `thumb_data` is written, an ad left without
  is counted in one line, filed `From Meta: n pictures added` / `replaced`,
  and Undo puts each earlier picture back.
- The PDF:
  - Every section on its own page, on a golden-ratio scale, with a 33.3pt
    margin; no Methodology page. Page titles and the commentary's block
    heads are in title case (Executive Summary, Ad Performance, What Worked,
    Areas to Improve): a formal document.
  - Tables are white cells under a shaded title row, the title row and the
    grid in one grey (#f2f2f2: `HEAD` = `EDGE` = `FILL`, as the rate card
    draws it; every table head, a creative card's line head, a top post's
    figure labels), heads in Slate Regular, figures at one weight and
    centred (2026-10-02). A summary table (`roomy`: the account table, Results
    by objective, By platform) takes S(4) rows; working tables keep S(3).
  - Commentary reads one block per part: its head, its points numbered
    under it, on both kinds of report (never a label column beside the
    points).
  - The ranking table gives the ad's name the widest column, so a name reads
    whole; a missing cost per result or CTR is a dash. A figure never breaks
    inside its cell: each figure column is at least its widest entry in the
    cheapest row's heavier face, every objective's table shares those
    tracks, and the name takes the rest.
  - The foot is PRIVATE & CONFIDENTIAL and the page count on the margin's
    line; no draft or version line.
  - A draft carries DRAFT (INTERNAL USE ONLY) and a report in review PENDING
    REVIEW (INTERNAL USE ONLY), repeated over every page and drawn last
    (`WM` in `js/smreport.js`, drawn by `ADspaceDocs.watermark`) on the report's golden scale: S(4) in Slate
    Book at the golden angle (31.7°), the size times φ² apart along a row and
    φ⁴ between rows, each row offset half a step, grey at a tenth's opacity;
    confirmed, published and every version the client reads carry none.
  - A page break falls between points, never inside one: each numbered or
    lettered point is one unit (`unit`), split only when taller than a page.
  - A top post card is named by its title, else its type and day; its meta
    line adds only what the name does not (the platform where a page holds
    two, the date and type under a title). Its figures run the column's
    width. It carries no caption: the appendix row prints the caption whole,
    each paragraph wrapped (`captionLines`; past 40 lines it runs together
    and ends on `…`), the row as tall as it needs. The appendix has no Date or
    Format column: the Post column takes their room, a post named by its type
    and day says both, and a titled post carries them on a line under it.
  - Views by week colours each platform as its own (`PLAT_COLOR`, one
    Pantone family of equal depth, never the platforms' fluorescent brand
    colours: Facebook 7455 C, Instagram 7425 C, the two together 2945 C,
    TikTok Black 6 C, rednote 186 C;
    a missing or repeated colour takes the next of `MORE_COLOR`); only the
    marks take colour. An account on platform Other is named by the account
    (the PDF names the platform otherwise, never the handle).
  - Every emoji is drawn and embedded before any page is laid out
    (`sh.ready()` before `draw`).
  - A "bold font" letter pasted into a caption (Unicode's mathematical
    letters, U+1D400 to U+1D7FF: 𝗙𝗿𝗼𝗺) prints as its plain letter, a bold
    one in the heavier face (`plainOf`, `boldMath`), never as an emoji
    picture.
  - An accounts report reads: Executive summary; Insights and
    recommendations, one block a platform; each platform's page with its top
    three posts ranked on that platform alone, each with its figures and its
    remarks; the appendix of every post with its figures. Posts are never
    ranked across platforms.
  - Named `{client} {report} {period}.pdf`.
  - The first kind is the Social Media Accounts Report.

### Services (the rate card)
- Two tables, Services and Add-ons, with categories that carry their count.
  Admins edit; everyone reads. Rates are in RM. At Services Full Access the
  price on a line is changed where it is read (`ADspaceAsk.rename`, empty is
  On quote), into the draft as the sheet's Save is; a rate below nought
  stays open with its refusal, a database refusal said on the row
  (2026-10-27, SVC-10).
- `detail` (one inclusion per line) and `min_months` seed a client's line.
- A line's key is its slug, made from its name: a name already on the card
  is refused as such ("A service with this name is already on the card."),
  the SKU's own clash as the SKU's; Set inactive, Save and Delete repaint
  the list from the row as written, a new line reading the card alone
  (2026-10-22, SVC2-1, SVC2-7).
- A line carries its Bukku item code (`services.sku`,
  `2026-10-15-service-sku.sql`; the user, 2026-10-15): typed in the line's
  sheet beside Category (letters, digits and . _ / -, 40 at most,
  optional), one line each ignoring case (`services_sku_idx`, "That SKU is
  already on another line."), shown under the name in the token face
  (`.svc-sku`) and found by the Services search and console search; filed
  from and to; not part of `rate_card_draft`, so it never marks the card
  Changed. Shown on the rate card alone, never on a quotation, letter or
  PDF.
- A line leaves by Set inactive, then Delete permanently (Manage). The delete is
  refused while any live `client_services` line names the slug, and the refusal
  says how many.
- The schema seeds the whole card once, into an empty table, and `detail` only
  where it is null. A new service is added on the page.
- Versions (`2026-10-13-rate-card-versions.sql`; the user, 2026-10-13: the
  card "should run based on versioning"): the lines and the card's words
  (`rate_card_text`, a block a key, changed only by `rate_card_text_save`)
  are a draft; Publish (`rate_card_publish(p_version, p_valid_until,
  p_note)`, Services Full Access; `bad-version`, `version-taken`,
  `bad-date`, `no-change`; filed `service.published`) keeps the lines, the
  words, SST and the term percentages whole in `rate_card_versions`, and
  `rate_card_current()` answers the latest (at Services or Clients: Services
  View). A client's line, a quote and the
  export are priced from the live version, never the draft; with none
  published, the card as it stands. The page: one command bar holding the
  search (Rate card alone), the version line (Live v.{n} · valid until,
  Review n changes, Publish) and the acts (Download,
  Add service on Rate card alone; on a phone the line under the marks where
  a search stands, else beside the ⋯; the user, 2026-10-14), then Rate card,
  Versions (`tab=`; an older `tab=words` opens the card); the wording is
  edited from Settings' Templates, Rate card wording (`#rcwListSheet`,
  `ADspaceCRM.openWording`, 2026-10-29), each block's pen opening
  `#rcwBox` and its Save or Cancel back to the list, and still published
  with the card here; a line or block the draft changed reads
  Changed (or New). A line the live version still offers is not deleted.
  Review n changes (`#svcReview`, a tonal toggle, `aria-pressed`; equal
  halves with Publish on a phone; the user, 2026-10-22: "approve") shows
  only what the draft holds that the live version does not: the lines
  changed, each naming what moved from and to (`ADspaceRecords.changes`),
  the lines removed, the blocks of wording changed, under Showing the n
  changes not published. with Show the whole card, the search set aside;
  Publish's question lists the same, five, then and n more (SVC2-M1).
- A block of wording is edited as the card prints it (`#rcwBox`; the user,
  2026-10-13: one box of lines read "ugly and untidy unstructured"): a list
  as numbered points (a field each, Add point, Move up, Remove), a table a
  row at a time under the columns its label names (Add row; one row fixed
  where the card prints one), a sentence as one field; saved as the lines
  the PDF reads. On a phone a point's number and acts share its first line.
- Download on the version line, and on each version's row on Versions (the
  version read whole at the press) (`js/ratecardpdf.js`,
  `ADspaceRateCardPdf.draw`; the user, 2026-10-13: the card in "their exact
  format", FOR INTERNAL USE kept) draws the live version as the team's six
  A4 pages, never stored: the cover, Ala Carté, Social Media Services,
  KOC Programmes, KOL Programmes, Add-ons with the term commitment and the
  Terms of Service, each table from the version's lines by `spec.role`, its
  words and settings (`{valid until}` filled), the foot PRIVATE &
  CONFIDENTIAL, the page count and `v.{version}.dp exp. {YYYYMMDD}` (`.dp`
  marks a card the portal drew, saved as `ADspace Rate Card v.{version}.dp.pdf`;
  one made by hand carries the version alone); the document's own type
  (11pt cells 5.76pt in, rows from 18.72pt, 18pt titles) on its 54pt
  margins; a line
  set inactive, or one no page holds (additional content, on request), is
  never printed. The Add-ons table opens on `addons_included`
  (`2026-10-13-rate-card-included-revisions.sql`, Wording).
- What a quote reads of a line is `services.spec` (`service_spec_ok`), set in
  the line's sheet under In quotes: a plan (letter, with or without ads,
  platforms, contents a month, its content options, the ad budget it
  covers, Best for), a platform's management fee, Meta advertising and an
  ads booster (the budget each covers), translation (an added language), a
  content format, a verification's own fee, a KOC package's creators, the
  KOL management fee's tiers, an add-on's group on the card.
- Quotations (`js/quotes.js`, `js/quotepdf.js`,
  `2026-10-14-quotations.sql`; the user, 2026-10-13: a quotation sent is
  honoured, and a client may hold several; the totals' rows on Build
  quote, the PDF and `/quote/` are `ADspaceMoney.quoteRows`, one copy,
  each page its own words, 2026-10-22, QT-4): one calculation,
  `quote_price(snapshot, selection)`, its totals worked by
  `quote_totals(lines, term, pct, sst)`, which `quote_adjust` and
  `issue_letter`'s quotation branch call too, never a copy of their own
  (2026-10-18), prices every quotation from the live
  version (`quote_card`), never the draft and never the page, on 3, 6,
  12, 18 or 24 months (`bad-term`; 1 for one-off items alone; the user,
  2026-10-14; the pages' one list `ADspaceMoney.QUOTE_TERMS`, held equal to
  `quote_price` by `tests/sql.js`; an extra content's line found by its
  `spec.kind`, never its slug), a plan included: a plan, its platforms (a dearer one inside the
  plan adds the difference, one past its count is an Additional platform
  at its fee), extra contents at the plan's whole saving to the nearest
  RM 10 (`extra_rates`), Translate every content (a content a language
  after the first), the advertising budget past the plan's cover (Meta
  advertising, then coverage; past the largest, on request), one-off items
  apart; the term's percentage on the monthly subtotal, SST on the rest at
  the rate in force on the day it is priced (MYT), none for a client whose
  `sst_applies` is false (`quote_tax_snap`; a preview names its client in
  `p_sel.client`, never kept; `2026-10-15-quotation-tax-day.sql`). A
  client billed in S$ is quoted in S$ (`2026-10-15-quotation-in-sgd.sql`,
  `quote_fx` since `2026-10-22-bill-in-rm-or-sgd.sql`; the user,
  2026-10-15): `fx_sgd`, the ringgit to S$1 (Tax and terms,
  Singapore; four decimals, unset until the team sets it), turns every
  rate on the card to the cent (`quote_fx_snap`) and every RM figure in a
  line's words to whole dollars (`quote_fx_out`), the totals marked
  `currency` SGD with the `fx`; the budgets the page sends stay the card's;
  refused `no-fx` while unset (Build quote says so; a website lead is
  billed in RM, so quoted in RM, until Billing sets S$); Build quote, the row, the PDF and the
  website read S$, and a Letter of Offer takes the S$ lines as they stand.
  `quotations` (RLS: read at Clients: Services View under client scope;
  writes through functions alone) keeps each as sent: reference
  `ADP/QT{YYMM}-{Z}{NN}` (`quote_ref`), the version, the selection, lines
  and totals, valid `quote_valid_days` (30, Tax and terms) from issue;
  never edited. The Services pane lists them above the lines
  (`#crmQuotes`; the Overview opens on them while any stand): the state
  worked out on read (Valid until, Expired, Ready to proceed, Revised, Letter of Offer requested, Not
  proceeding, Letter of Offer issued once a live letter holds its lines),
  the row two short lines (the plan and term, then who made it and when;
  2026-10-26), Download on the row, and on a row that can be offered
  (Valid, Ready to proceed, Letter of Offer requested) Issue Letter of
  Offer beside it (at a desk under the figure, the reference kept whole;
  equal halves under the meta on a phone); the ⋯
  Duplicate, Send on WhatsApp, Cancel / Restore (Cancelled), Remove with Undo
  (the user, 2026-10-22, QT-M1: "approve"). Show n removed quotations
  (`#qtGone`) opens a small list (`#qtGoneList`, `.qt-gonerow`, a `--sunk`
  box; the user, 2026-10-31: "it should make it small list"): a line each,
  the reference, what it was, Removed {day} by {name}, Restore and a ⋯ of
  Download and Delete, Delete at Clients: Quotations Full Access, the
  reference typed back, no restore (`quotation_delete(p_id, p_ref)`, the
  client in scope at Manage; `not-removed`, `bad-ref`, refused while a
  service line holds it, `lines` with the count, a letter quotes it,
  `letter` with its number, or a quotation revises it, `revised` with its
  reference; filed `client.quotation` {ref} deleted;
  `2026-10-31-quotation-delete-team-requests.sql`); a deleted reference is
  kept (`quotation_refs_kept`, RLS on, no policy, no grant), which
  `quote_ref` counts, so it is never issued again. The pane's one
  blue follows the deal (`paintDeal`, SL-M2): nothing quoted and no To
  quote line, Build quote; one quotation that can be offered, its Issue
  Letter of Offer (none blue where two can); To quote lines no live letter
  holds, Issue letter, drawn only once a To quote or Confirmed line
  exists; else none. An empty Quotations list carries Build quote on its
  line; an empty Service lines list reads the enquiry (else No service
  lines.), its Add service the heading's alone (the user, 2026-10-27). Build quote (`#qbBox`; Preview PDF under its lines, `#qbPreview`, draws the quotation as priced under DRAFT with the reference PREVIEW, nothing made and no number spent, and a quotation's ⋯ opens with Preview PDF, the kept file in a tab; the user, 2026-10-31; as the approved
  board: plan cards under Without ads / With ads, content, platforms with
  what each adds, extra contents as steppers with the plan's rate,
  languages, budget and term, one-off items as steppers two across, the
  lines and totals from `quote_preview` as ticked, Monthly incl. SST kept in
  the foot (`#qbSum`); with no plan the
  platforms run four across and the budget sits beside the term) makes one (`quotation_create`, a key a press,
  made again whenever the selection changes; the same key twice, even at
  once, answers `again` with the first, and only for its own client, a
  website key its own visitor's email; 2026-10-19, audit 15; 2026-10-22,
  BE-4).
  Each line's Qty, Rate (RM) and Months (a monthly line's; the term
  until typed) are fields in the lines table (`p_sel.edits` by the line's
  `key`, kind|slug|label; `2026-10-15-quotation-rates.sql`, the user,
  2026-10-15: "fully customised for the rates qty and months"): priced
  again by `quote_adjust` inside `quote_preview` and `quotation_make`
  (`bad-edit`), the card's rate kept as `list_rate` and named under the
  line (Rate card RM …), the commitment counting each line's months,
  filed `n lines changed`, Issue Letter of Offer giving each line its
  months; a website quotation is never adjusted; empty puts the card's
  figure back. A line may be priced at RM 0, a complimentary line (the
  user, 2026-10-19): never refused.
  A plan card names its platforms, its contents (`6 contents: 2 graphics, 4
  reels`) and the ad budget it covers; choosing a plan ticks Meta where no
  platform is ticked; the budget opens on the plan's own (`Included: up to
  RM 4,000`, value 0, as the website sends it) and offers only larger steps
  from the card's Meta advertising and boosters, None where no plan covers
  one (the user, 2026-10-14). The pane reads Quotations (Build quote) over
  Service lines (Add service), each heading over its own list.
  Issue Letter of Offer (`quotation_offer`, once, refused `expired` past
  `valid_until` and not offered then) makes the quotation's
  lines the client's To quote lines (`quotation_id`, its term and
  percentage) and opens the letter sheet on them alone. The PDF (`js/quotepdf.js`,
  three pages; the user, 2026-10-31: one document, the quotation acting as
  the Letter of Offer): the Quotation Cover drawn by the letter engine
  itself (`ADspaceDocs.letterPages`, the team's Quotation Cover type in the
  console, the type as seeded on /quote/; signed off by who prepared it);
  the quotation on a continuation page with no second letterhead (a lead
  sentence, Description · Qty · Rate · Amount between hairlines, each
  amount in its currency with per month, one-off or its months under it,
  the totals at the right ending at the one bold figure, TERMS: validity,
  SST, budget billed separately, the whole term's commitment, binding once
  accepted and signed with the Service Terms, the rate card line); and
  Acceptance of quotation on a page of its own (the figures agreed, Issued
  for and on behalf of ADSPACE PLT: Prepared by and Reviewed by, then the
  client's block to sign and stamp, Name, Designation, Date). Prepared by
  is the quotation's `made_by` (a website quotation's person in charge)
  with their position; Reviewed by the colleague who approved it, once
  reviewed; a signed copy draws the client's signature in its box and how
  it was signed under it (online: when, the email the code went to, the
  address and country, the fingerprint; paper: the day). Every page's foot: the reference, PRIVATE &
  CONFIDENTIAL, Page n of 3 (`ADspaceDocs.letterFoot`); named `ADspace
  Quotation {ref}.pdf`.
- Quotation signing (`2026-10-31-quotation-signing.sql`; the user,
  2026-10-31: "Jane picks the reviewer, approve"): the client accepts on
  the quotation's link (a team's quotation takes one from
  `quotation_link`): company details and billing contact (prefilled from
  the record), the figures agreed, name, designation, a signature drawn
  or typed and the authority tick, then a six-digit code emailed by
  `quote-request` `sign` (`quote_sign_code`, the service role's alone,
  kept hashed, 15 minutes, five tries, five an hour; Turnstile) and
  entered in six boxes (`quote_sign_finish`, anon), which keeps the
  signature with its record (time, email, `request_ip()`,
  `request_country()`, device, fingerprint) and tells who prepared it and
  the person in charge (`quote.signed`). The link then reads Accepted
  (`accepted`), Welcome once reviewed and Active. The colleague who
  prepared it checks the entries (each company field correctable, kept
  from and to) and submits to a reviewer they pick
  (`quotation_reviewers`: Clients: Quotations Full Access or an admin,
  never themselves; `quotation_submit`); the reviewer, or an admin in
  their place after asking, approves (`quotation_review`: Billing filled
  where empty, needing Billing Work, `billing-access`, left alone where
  Bukku holds it; the quotation's lines Confirmed, made where none) or
  sends back with a note. Signed on paper is kept by hand
  (`quotation_paper`: the day and a link to the scan); Request signature
  again (`quotation_resign`) keeps the earlier one in `sign_history`.
  `quote_sign_codes` has RLS on, no policy, no grant.
- The quotation website (`/quote/`, `js/quote.js`,
  `2026-10-14-quotation-website.sql`; the user's approved canvas, Website
  1 to 6): What do you need?, Platforms and plan (where social media is
  asked; each plan names its content, `4 content pieces per month: 2
  graphics and 2 reels of up to 60 seconds`, its budget on a line of its own, and
  once a plan is chosen its Additional content pieces per month are asked
  under the plans, after Content pieces per month where the plan holds two content
  options (1 graphic and 3 reels, or 4 reels; sent as `mix`, a string; the
  user, 2026-10-27); the user, 2026-10-14), Customise (languages: each
  content piece is in one language, the month's content pieces divided
  across those chosen at no charge, Make every content piece bilingual the
  translation rate a content piece, each additional language; 2026-10-27; budget,
  commitment; with a plan, Content production lists only the formats its
  additional contents do not),
  what is chosen and typed kept in the tab only while the steps are gone
  through (a refresh keeps the place) and cleared whenever the opening page
  shows (the user, 2026-10-14: "dont cache my record"), Your details (salutation, optional, from the contact sheet's list, kept on the lead's contact (`2026-10-14-quote-website-salutation.sql`); name, work email, a Malaysia or
  Singapore WhatsApp number, brand, industry, Planned commencement
  (required on the page: Within 3 months, 3 to 6 months, More than 6 months;
  kept as the lead's Urgency to commence, moved on a lead asking again and
  named in the team's notice; no price reads it;
  `2026-10-29-quotation-website-commence.sql`), consent; a free email is
  advised against, never refused), then the quotation priced by
  `quote_price` through `quote-request` (Turnstile, every request refused
  while the secret `TURNSTILE_SECRET` is unset; Verify JWT off), which calls
  `quote_website_create` (the server's alone): a lead one of whose contacts
  holds both the email and the number is used again while Lead, Contacted
  or Proposal sent, else a lead made (Source Website, nobody's), the
  quotation kept with `source` website, its key (`?q=`) and the brand typed
  (`contact.brand`, what the visitor reads back), five a contact a day
  counted under a lock on each, only the selection keys the price reads
  kept, the number read as `wa_number` reads it (`quote_website_number`;
  `2026-10-15-quote-website-guards.sql`, audit S1, S2, I2). No rate is
  shown before the quotation (`quote_catalogue`, anon, holds none). A
  quotation holds at least one priced line: items quoted on request alone
  (a KOL campaign, a custom creator list) are refused on the page before
  the details are asked and by `quotation_make` (`nothing-priced`, no lead
  made; `2026-10-29-quotation-needs-a-priced-line.sql`). The price waits
  for the team (the user, 2026-10-29, Option 1;
  `2026-10-29-website-quotation-reviewed.sql`): a website quotation is
  kept with `reply_due` (`quote_reply_days` working days) and the leads
  team told Quotation to review; until a colleague sends it
  (`quotations.released_at`) the link reads Request received and the day
  it will be sent on WhatsApp, in one column, and `quote_website_read`
  answers no lines, totals, version or validity while it is unsent,
  whatever its stage (`quote_proceed` refuses `not-sent`). On the lead's Services it reads
  Awaiting review · Send by {day} with two ways to show it, each asked and
  valid from that day (`quotation_release`, no page's to call; Clients:
  Quotations at Work, the client in scope; the user, 2026-10-31: "publish
  quotation / send quotation", never a tick): Send quotation
  (`quotation_send`), drawn only while the `quote_ready` template is on
  and never for a prospect marked Do not contact (`no-contact`), queues
  that WhatsApp, filed as sent on WhatsApp, and is the pane's one blue;
  Publish (`quotation_publish`, the Publish glyph, tonal beside it, the
  blue where Send is not drawn) shows the rates on the link alone, nothing
  queued, filed published on the quotation link;
  Adjust and send beside them, no Send on WhatsApp; the managers are told
  six hours before the reply is owed while it waits (`quote_proceed_remind`).
  Once sent, the rates show, with Download (the A4 PDF); the website asks no
  billing and never a Letter of Offer, which the team sends after a
  conversation, the billing through the Details form
  (`2026-10-26-quotation-website-follow-up.sql`; the user, 2026-10-26).
  Beside it (under it on a phone) Ready to proceed?, never a free
  proposal: when they would start (Within a month, In 1 to 3 months) and
  whether they decide (Yes, I will involve others), both asked, then
  Proceed with this quotation (`quote_proceed(p_key, p_start, p_decider)`,
  anon; `bad-answer`, `expired`, `not-proceeding`; `proceed_at`,
  `proceed_due` the moment plus `quote_reply_days` working days, 2, Tax
  and terms), Request received with the day the team will be in touch.
  Once a colleague takes the lead the page names them (Your
  representative: name, position, Chat on their WhatsApp only where their
  namecard shows the mobile, else the office's); until then every step
  offers the office's Chat on WhatsApp (2026-10-27, QTE-2). The link shows the latest
  revision (`quotations.replaces`, `quote_shown`: Revised on {d}. It
  replaces {ref}.). The link follows the prospect to the client portal
  (`2026-10-26-quotation-to-client-portal.sql`): `quote_website_read`
  answers one `stage` (quote, ready, billing with the client's open
  details form's key, billing_sent, letter while a Letter of Offer stands
  on the quotation's lines, never lines made with no letter, signed,
  welcome once verified and Active, expired, closed once Cancelled;
  billing only on the website quotation that made the lead, never one
  that matched an existing lead; `quote_proceed` judged on the revision
  shown; a name or brand holding a web address refused, `bad-name`,
  `bad-brand`, `quote_link_like`) and the panel beside the
  quotation follows it, the representative under each step; Welcome
  offers Sign in to your client portal (`/client/`) where the prospect's
  address holds portal access, never a sign-in itself; expired keeps
  Request received where they had said they were ready, with New
  quotation and Chat on WhatsApp. The team who work leads are told at each step (kinds
  `quote.website`, `quote.proceed` with the answers;
  `ops_notifications.client_id` opens the lead's Services); while nobody
  has taken the lead, the managers (Clients: Leads Full Access, or an
  admin) are told once six hours before the time ends
  (`quote_proceed_remind`, pg_cron every fifteen minutes). The prospect
  is sent one WhatsApp, `quote_ready` (greeting, brand, reference; its
  link button the key), when a colleague sends the quotation; nothing is
  sent by itself (`quote_wa_day` now limits nothing). On the lead's Services a website quotation reads Ready to
  proceed · Contact by {day}, offers Adjust and send (Build quote on its
  selection, saved as its revision through `quotation_replace`, then the
  WhatsApp composer) and in its ⋯ Do not contact / Allow
  contact (`quotation_set`, a website quotation's alone; no reminder
  while marked); a revised one reads Revised · By {ref}. A KOL campaign
  and a custom KOC list are quoted on request.

- A website quotation's ⋯ Preview (`quotes.js`, any reader of it; the
  user, 2026-10-30) opens `/quote/?q={key}&preview=1`: the prospect's page
  as they see it under one bar (`#qsPreviewBar`, `.annbar.previewbar`:
  Preview: the page as the prospect sees it. Nothing can be sent from it.;
  its × hides it, a refused press bringing it back),
  Proceed, a new quotation, Change selection and the billing form refusing
  in place (Not available in preview.), page-side; reading the link writes
  nothing. Once the quotation is sent, Copy link beside it gives the
  prospect's own link (no `preview`) to send again by hand, and Resend on
  WhatsApp (drawn while the `quote_ready` template is on) queues the
  quotation-ready message again (`quotation_resend(p_id, p_again)`,
  `2026-10-30-quotation-resend.sql`: Clients: Quotations at Work, the client
  in scope; `not-sent`, `expired`, `revised`, `not-proceeding`,
  `no-contact`, `wa-off`, `no-number`; within `wa_repeat_hours` `recent`
  with when and by whom, asked again in warn; filed under the colleague)
  (`tests/quotesite.js`, `tests/sql.js`).
### Client portal (`client/`, `js/portal.js`)
- It is one client at a time (a company select where one login holds access at
  several). The head is the console record's (`.rec-mark`, `.rec-who`,
  `.rec-ctl`): the mark, the name over the registered name, the state and
  Request change, which asks which change as a segment (2026-10-27,
  POR-1): Change of details, Upgrade,
  Downgrade or Cancel, the last three against a confirmed line (`#reqPick`);
  a line's ⋯ asks for that line alone.
- Under it one tab strip (`#cpTabs`, the view strip, `role="tablist"`, the
  arrows and Home/End move along it) and one pane at a time
  (`.cp-panes`, `data-swipe="cpTabs"`, `data-narrow="640"`). The pane rides in
  `?tab=` (Overview left out) and pushes history; a refresh lands on it. Every
  section is a white card (`.panel.cp-card`) with its title inside
  (`.cp-card-head`); a table inside a card is the card's rows.
  - Overview: the summary on the left on the record's proportion (one column
    at 900): Services (Confirmed and To quote as lines, open requests),
    Next content meeting (the soonest ahead: a calendar leaf and the time in
    MYT, Join and Add to calendar, an .ics), Latest report (Download),
    Engagements (the token links with a tile, Open at the right edge); each summary card's
    View all opens its tab. On the right: Your account manager (the person in
    charge, WhatsApp and Email) and Company (the facts).
  - Services: confirmed and To quote lines (enquired never shown), with
    Upgrade / Downgrade / Cancel in a confirmed line's ⋯ and, for a line of
    two months or more, where its term is (Month n of N, ending); then Requests once
    one exists (Withdraw with Undo while Requested). A request sent opens
    this tab.
  - Letters: Download redraws the snapshot.
  - Reports and Meetings: tabs drawn only once there is one; an address
    naming one before it is drawn opens it when it is. A meeting ahead with
    a link offers Join on its row, never in a ⋯ (2026-10-20, POR-2).
  - Account: Contacts read-only, Portal access (Person · Sign-in email),
    Payment only once `ADSPACE_ORG.bank` is set.
- The portal never writes a record. A request is a row the team applies.
  Request change opens through `js/sheet.js` (focus held, Escape, focus back
  to the button, a press outside never closes it over typed text), and an
  unsent note comes back when it opens again until it is sent (audit F8,
  2026-10-10). Send keeps one key until the request is filed
  (`portal_request_once`, audit C1), so a reply lost on the way and a second
  press file one request; `portal_request` is the same with no key.
- A sign-in address is text, never a mailto pill.
- Covers: Client sign-in, Check your email, Access denied, Unable to load.
- A contact reads its name with Primary contact at the right of the line, the
  role under it, then the reach chips; who signs in is said once, under
  Portal access. A past meeting is Completed (已完成), a future one Upcoming.

### Short Links (`workers/links/`, `hi.adspace.me`)
- The Worker reads `link_resolve(p_slug, p_qr)` with the anon key and gives one
  of four answers (ok, missing, paused, revoked).
  - Redirects are 302 and `no-store`.
  - The client's parameters are carried over, minus `q`.
  - `go.adspace.me` is never retired: printed QR codes encode it.
  - The host is `ADSPACE_CONFIG.linkHost`.
- A live link's row offers Copy, Open (its short address, a new tab), QR
  codes and the ⋯ (LNK-2, 2026-10-22), four fixed tracks on a phone
  (LNK-8). The Worker keeps which kind an `/s/`
  key is a day at its edge (`caches.default`, a kind the database named
  alone), so a person's visit is sent on without a read (LNK-3).
- Bulk import is behind the bar's ⋯ (`data-rare`) and is a sheet (`#importBox`, `links:work`, as the QR sheet's
  Create, Revoke and Restore): every line taken shuts it; a skipped line stays
  in the box.
- Pause and Resume live in the ⋯ (`links:work`).
  - Pause asks first; Resume asks nothing.
  - Both take `.select('id')`, filed as `shortlink.updated` with the detail.
  - `ADspaceGroup.keep` opens the card the row moves into.
- No Status column. A paused link stands in the Paused card, which says
  it once: no chip on the row (2026-10-27, LNK-10).
- Every colleague's namecard slug is listed under Namecards, between Live and
  Paused (read from `team_members`; Short link, Destination the card's own
  address, Colleague; Inactive or Card off as a chip; Copy and Open, no ⋯:
  edited in Team or My namecard), so a slug in use is in sight; the count
  takes them in and the search finds them by slug or name; a refused read
  is said (Could not load the namecards.), never drawn as none (the user,
  2026-10-07).
- After Live, Namecards and Paused, the list shows the addresses the host
  answers by itself (2026-10-14; the user: "there should have a place to see
  all hi.adspace.me/{slugs}"), each a card shut until opened: Content
  Review (`/r/{key}`, an Active client in Content Review), Video Scripts
  (`/v/{key}`, `/s/` before 2026-10-15, read through `script_links()`: the key is withheld from the
  table, `2026-10-14-script-links-list.sql`), Creator selection (`/s/{key}`, `/c/` before 2026-10-15, not a
  draft; Completed as a chip) and Creator pages (`/p/{code}`, Inactive as a chip); each read only
  where its section (or `campaigns.creators`) is at View, a failed read
  `Could not load the {group} links.` with Try again; Copy and Open, no ⋯
  (changed where the record is). The count and the search take them in.
- A short link never takes a colleague's card slug (`links_card_clash`,
  named `/{slug} is a colleague's namecard.`).
- A slug, a short link's or a card's, is three characters at least
  (`links_slug_min`, `team_card_slug_min`, `2026-10-14-slug-three-characters.sql`;
  the user, 2026-10-14): every one and two character address on the links
  host is the portal's own. A card's slug made from a short name takes the
  sign-in email's name, else the name with `card` after it.
- A client's review link as a short link (2026-10-12; the user: "dynamic
  title: {Content Set} {client brand name} - Content Review Portal by
  ADspace"): `/r/{review key}` and `/r/{review key}/{first eight of a set's
  id}`, nothing stored, so nothing to clean up. A link preview's reader (a
  chat app's user agent) is answered a page titled `{set} {brand} - Content
  Review Portal by ADspace` from `review_link_preview(p_key, p_set)` (anon;
  a live key with no passcode, shown in Content Review; a published set),
  with no image; everyone else a 302 to `/review/?k={key}#s-{set}`, which
  opens on that set alone, unfolded, and takes the mark out of the address
  (`tests/links.js`, `tests/reviewlink.js`).
- The other links a client or a creator is sent, as short links the same
  way (2026-10-13; the user: "video script and creator campaigns and creator
  portal"): `/s/{selection key}` a campaign's creator selection, `/v/{script
  key}` a client's Video Scripts, `/p/{creator code}` a creator's own page,
  and `/c` alone the client portal's sign-in (re-lettered 2026-10-15, the
  user: "use v for video script, take s back for selection", "C reserved
  for client portal"; `2026-10-15-short-links-relettered.sql`). A link sent
  before keeps working: `/s/` a Video Scripts key opens the scripts
  (`share_link_preview` `which`), `/c/{key}` its campaign. The console
  writes the new letters once `shareLetters` is on in js/config.js (the
  Worker live first), `ADspaceAdmin.shortLink(kind, …)` by kind
  (`campaign`, `script`, `creator`). A preview reader is
  answered from `share_link_preview(p_kind, p_key)` (anon): the brand for
  scripts (a script published), the campaign and the brand for a selection
  (no access code, not a draft) and for a creator with one open booking,
  else the plain title. The console's address and Copy link give the
  page's full digital.adspace.me link (the user, 2026-10-15: "full links
  everywhere except namecards"; `shareLinks` off in js/config.js, which
  `ADspaceAdmin.shortLink` and `shareUrl` read), and a namecard keeps its
  short link; the Worker still answers every short link already sent.

### Video Scripts (`js/scripts.js`, `js/scriptpdf.js`, `?s=scripts`; `script/`, `js/script.js`)
- One script is one full video (the user, 2026-10-09), its own section on
  the ladder (`scripts`, every group starting at its Content Review level;
  `2026-10-09-video-scripts.sql`), in the Work chunk after Content Review.
  Three kinds: Detailed scenes (Visual and Script a scene), Products and
  scenes (Products and context, then the scenes), Story and voice-over (Hook
  and story, the scenes, Script (read here)).
- A script is a client's content month's (`2026-10-09-scripts-by-month.sql`;
  the user: "we are working on content month, monthly basis"): `period`,
  `seq` and `code` YYMMVSNN (`2610VS01`), NN the lowest free a client a
  month (unique), `engagement_id` the client's My Work month where one
  exists (never required). New script asks the client, the month (last
  month, this month and the next six, as My Work offers) and the type,
  and Add script (at the end of the month's tabs) the month's next: each
  opens a New script editor and stores nothing until Save
  (`video_script_new`, then `video_script_save`; Cancel back to where it
  was opened; 2026-10-15); Write with AI on it says the script is saved
  first, taking its number (`script-draft` reads the row). Save takes
  the month's next number, Add script's with the header copied (platform, language,
  shooting date and time, venue, duration, cast) and the script empty; the
  editor's Content month moves it, taking that month's number (filed with
  both codes). `series_id` / `video_no` are no longer read.
- The list is a card a content month, newest first, the newest open (the
  user, 2026-10-10: thirty to fifty videos a client a year), a row a
  client's month (the client over its codes and count, the next shoot else
  the last, Published or n of N), opening its record on its first script
  (on the script a search found). A
  script opens in its content month's record (the user, 2026-10-09: one link
  for the client, the videos as tabs on top): the head names the client and
  the month (`n scripts · n published`; the month opens the client's Months
  in My Work where it is there), Preview PDF and one ⋯ of Download and Reset
  client link, then the client's link once (`.rec-linktools`: the address,
  Copy link, Preview), the key read once a client and made at Work the first
  time; under it the month (`month=` in the address; the user, 2026-10-10:
  thirty to fifty scripts a client a year) is a card of its scripts
  (`#vsMonthList`: Scripts with Add script in its head, a row a script, its
  whole code (2611VS01, as its head reads) and title over its type, the shoot, the state, in number order), a
  row opening its script on a page of its own (`script=`): Previous, `n of
  N` and Next over it (`#vsNav`, a sideways swipe on a phone), Back
  returning to the month and the month's Back to the list; the script's
  card headed by its
  code and title over its type with the state, Edit (the pen), Publish in
  blue or Unpublish (asks) and a ⋯ of Delete at the right edge
  (`.vs-cardhead`), its facts under it (`.vs-factcard`, the reference video
  with them), and the script in the next card (the user, 2026-10-09: key
  information apart from the scenes). A script deleted opens its month,
  the last one gone the list.
- On the day, in the console and the installed app alone (the user,
  2026-10-09: "make it simple to enter"): each scene's VC# (the clip number
  on the camera) is one field; Enter records it, ticks the scene shot and
  moves to the next scene's field, and an empty field offers the number
  after the last one recorded (C0042, then C0043), which Enter takes; a
  Shot tick is its own press; each saves as it changes and is put back on a
  refusal (`video_script_shot`).
- Edit is a page of its own (`#vsEditView`, `edit=1` in the address; the
  user, 2026-10-09: a sheet shut by a stray press would lose a long
  script): the head, the facts card (Video, Shoot), the script card, and
  Save / Cancel at the foot of the screen (`.vs-editfoot`, sticky above the
  tab bar). Cancel with changes asks (Discard changes?); with changes held,
  Back, the rail and a return to the section bring the editor back as it was
  ("Save or cancel the changes first."), and closing the tab asks
  (`beforeunload`). Saved by `video_script_save` (from and to, `stale` with
  the row).
- Write with AI (2026-10-09, `script-draft`, `2026-10-09-script-writer.sql`):
  on the editor's Script heading (`.readgroup-head`), at Video Scripts Work.
  It asks first (`ADspaceConfirm`: Video length 15s, 30s, 60s or 120s; XHS
  Safe Mode on a rednote script alone, unticked; Notes for the script, kept
  in this browser under `adspace-script-notes:{id}`; n scripts left today;
  Replaces the script in these fields where it holds words), then sends the
  type, title, platform, language, length, venue, how many in the cast (never
  their names), the notes and the script so far; the function reads the
  script, the client (industry, market) and the month's other titles as the
  caller, masks the client's name `{brand}` and handles `{handle}`, claims
  `ai_script_claim` before Claude (`script` 10 a colleague, `script_admin`
  20 an admin, a day from midnight MYT, settings in `ai_draft_limits`;
  `ai_script_left`), and answers the type's fields by structured output
  (secrets `ANTHROPIC_API_KEY`, `SCRIPT_MODEL`, unset `claude-opus-5-5`;
  Verify JWT off). The words fill the fields in place, `{brand}` and
  `{handle}` filled on the page; Undo where it happened (Written by AI.
  Read before saving.); Save asks the declaration first (as Write caption,
  2026-10-10) and files `script.saved` Script written with AI, read and
  confirmed; an answer landing after the editor shut is put in at its next
  open. The house
  style and XHS Safe Mode's rules are the function's `SYSTEM` and `SAFE`.
- Publish (`video_script_share`, Undo where it happened; not drawn on a
  script with no scenes) shows a script on the
  client link, `/script/?k=` on the client's own key (`clients.script_key`,
  `script_link`; Reset link asks and retires the old key). The link is
  for the client to read the scripts (the user, 2026-10-09: "no need show the
  approve or changes at client side"; "remove from all client-facing
  site"): the name card, a tab a content month (drawn where there are two),
  then the month as a list, a row a script (code and title over its type,
  the shoot at the right); a row opens its script alone (All scripts, n of
  N, Previous and Next, a sideways swipe on a phone; `#id` in the address,
  Back returning to the list), its facts card and its script card. A month
  of one script opens it. It reads only `get_scripts` (shared scripts by
  month and their scenes; never a clip number, a tick, who ticked, a
  colleague's name or a version; `2026-10-09-script-shots-internal.sql`).
  Nobody decides or records there.
- The PDF (`ADspaceScriptPdf.draw`, drawn in the browser, never stored)
  carries the Reports PDF's furniture and scale (the user, 2026-10-09:
  "refer back to the Reports style"): the Optima wordmark in ink at the head
  of every page and the client in small capitals at its right, PRIVATE &
  CONFIDENTIAL in Slate Medium on the margin's line with the page count, the
  S(5) margin and S(k) type, white cells under a #f2f2f2 title row. Its
  content is the user's template: Video Script over its month (its type, or
  the count of scripts), the header table (Video # reads the codes,
  Platform, Client/Brand, Language, Shooting Date & Time, Venue, Est.
  Shooting Duration, Cast Members/Talent), each script under its code and
  title (its type and reference under it) by kind, every scene numbered
  with a Shot box and a VC# cell (a tick and a clip number recorded in the
  console printed, empty ones left for the pen; the context box has
  neither), the words said in Slate Regular and what is seen in Slate Book,
  and its own Notes / Remarks with room to write (2026-10-10: the crew reads
  one sheet a shoot day). Scripts of a month sharing their header share one
  header table, whatever their kind; Preview PDF (a tab
  opened at the press) and Download from the month draw the whole month;
  on a script's own page they ask This script or Whole month once there
  are two.
- Delete is Full Access, the title typed back (else the code).

### Handbook (`js/handbook.js`, `?s=handbook`)
- The company's internal files: Employee Handbook, SOPs, Policies, Templates
  and forms, Other (`handbook_docs`, `handbook_versions`,
  `2026-10-01-handbook.sql`). Every colleague reads (`is_team()`); `team.handbook`
  alone adds, edits, versions, archives and deletes (`handbook_save`,
  `handbook_add_version`, `handbook_archive`, `handbook_delete`, each
  `allowed('admin')` and filed `handbook.*`). No acknowledgement step.
- A file lives in the private Supabase Storage bucket `handbook` (50 MB a
  file), never in S3 or behind the CDN, at `{doc id}/{time}-{name}`. It is
  opened only through a signed link of 60 seconds made at the press
  (`createSignedUrl`), the tab opened before the link returns; nothing
  stores an address to a file. The bucket reads at `is_team()`, writes and
  removes at admin.
- A file is never overwritten: New version adds an object and a row, and
  Versions opens every earlier one. A document may be a link (https only)
  instead of a file.
- Archive (asks) hides a file from everyone but an admin; Restore never
  asks. Delete takes the title typed back, removes the rows, then the
  files (`paths` returned by `handbook_delete`).
- A colleague who is not an admin sees no Add file, no archived file, and
  a ⋯ only where there are Versions.

### Team (`js/team.js`)
- Members sit under their group. Your own row shows the neutral `You` chip.
- A member row reads the initials, the name with the Employee ID beside it (`.team-eid`,
  mute; still searched), then department and position (and Until), then the
  email; the state column names only the exception: Inactive, Access
  expired, Removed, or Card off for somebody still working. Inactive,
  expired and removed colleagues leave their group's card for one Inactive
  card after the groups, shut until opened (opened for the row a stand-down
  or Delete moves there). A success line under the bar goes after 8
  seconds; a refusal or a warning stays until the next act.
- A colleague is a record of their own (`member=`, `mtab=`; the user,
  2026-10-18: "build it similar as client individual section"): the
  list is the Clients list's shape (the user, the same day: "it should be
  the same as client"), a row one button (the initials' disc, the name,
  the email, the exception, the chevron), no ⋯ on the list; it opens in
  place of the list and the Team strip, Back returns; the head is the
  mark, the name, Employee ID and post (the group and department are
  Overview's; TEAM-1, 2026-10-22), the state and the one ⋯
  of every act on a colleague (`memberMenu`, `wireActs`); panes Overview
  (Sign-in and access, Employment, Namecard, each value changed where it
  is read at Team Full Access: a word or a date its pen, a choice a
  select drawn as the value, saved alone through `patchMember`, refused
  in place as the sheet refuses, a name, email or Employee ID another
  colleague holds included (2026-10-27, TEAM-2), filed from and to; no Edit button; the
  user, 2026-10-18), Work (each open task they own, each client they are
  person in charge of, each open campaign they run, a row a record opening
  it as search does, one line at a desk, an overdue task's date in red;
  the tasks' counts first (overdue, due within 7 days, later, no due
  date), ten rows of a list, the rest behind Show all; the other kinds
  `team_work_held` counts on one line; Hand over at Team Full Access),
  Documents (every HR letter that is theirs in the register's own rows
  (`ADspaceRegister.paintForMember`): naming them, or carrying their
  Employee ID in its reference, and their downloaded performance records;
  an HR letter naming nobody takes the one colleague whose Employee ID its
  reference carries, trigger `documents_hr_member`,
  `2026-10-18-hr-letters-find-their-colleague.sql`; Issue document and
  Add existing document open on them), Performance (Open reviews: the months searched for their name,
  behind its own lock) and Health (their check-ins and talks from
  `health_team`, an admin's behind the master code), each drawn only where readable
  (`tests/teamrec.js`).
- A colleague's record has a rail, as a client's (`.rec`, 1.618 : 1,
  splitting below 1100, its blocks leading the tabs on a phone; TEAM2-9,
  2026-10-24): Their work (Team Full Access, off the Work pane: the counts
  `team_work_held` and their open tasks answer, read once a visit and
  again after a hand-over, overdue in red, Open Work and Hand over work)
  and Access (the access end off Overview, where it is set; at Team Full
  Access `team_member_seen(p_id)`: Active 2 hours ago / Active today,
  9:14am, Last sign-in 22 Oct, 9:14am from `auth.users`, else Not signed
  in yet and Invitation sent {day}). `team_members.last_seen_at` is
  stamped by `page_pulse` for the team audience alone, once in 15
  minutes, never moving `updated_at`; withheld from the column grants,
  read through `team_rows()` at Team Full Access (null below), cleared on
  erasure (`team_members_erased_seen`;
  `2026-10-24-colleague-last-seen.sql`).
- Set inactive / Set active sits in the record's ⋯ (never on your own record). Send
  invitation asks first.
- Add member, Set access expiry, a member's values and Set inactive, and a
  group's ⋯ are Team Full Access (`team_admin`); Send invitation is
  `team.invite` (`invite-member`), which makes a team login only for an
  address an active colleague holds (`not_team_member`) and claims every
  invitation first, twenty a caller in 24 hours (`team_invite_claim`,
  `team_invites`, the service role's; `too_many`;
  `2026-10-18-invitation-goes-to-a-colleague.sql`); Add member invites only
  where `team.invite` stands, else adds the colleague plainly (2026-10-20,
  TEAM-12). A row with nothing it may press draws no ⋯.
- A colleague and a group are written only over the row as read (`.eq('updated_at', …)`,
  `team_roles_touch`, `2026-10-18-stale-team-save-refused.sql`): one changed
  meanwhile reads "Not saved. This changed since it was opened, and has been
  read again."; the group sheet stays open until its write answers, a refusal said in it with
  every change kept (2026-10-20, TEAM-2).
- Changing a member's email asks first, and is an admin's alone: the page
  offers it to an admin, and trigger `team_email_guard` refuses anybody else
  (`admin-only`; deleting a colleague's details empties it as before;
  `2026-10-18-sign-in-email-through-an-admin.sql`).
- The member sheet adds a colleague and nothing else; a colleague is changed
  on their record's Overview, Performance's Edit on Members opening it
  (TEAM2-6, 2026-10-24). Overview's User group asks first ("{name} moves
  from Marketing to Sales and takes that group's access."), Undo where it
  happened; on one's own record it is a fact (TEAM2-1). A refused read of
  the team says so on both lists with Try again (TEAM2-2).
- A member row carries:
  - Employee ID (`staff_code`, `^[A-Z0-9]{3,8}$`);
  - department, from the Departments list (below; a segment while four
    choices or fewer, else the select, `ADspaceForm.segFit`);
  - Position (`designation`);
  - role standard;
  - `capacity_minutes_week` (entered as hours);
  - Access until (`access_until`, a day in Malaysia, with an optional time
    `access_until_time`, five-minute steps, offered only once a day is set;
    no time is the day's end; empty for no end), never on your own row
    (`own-expiry`);
  - Mobile, Mobile on card Show / Hide (`card_mobile`) and Card On / Off
    (`card_on`).
- Add member asks Name, Sign-in email, User group (required) and Employee
  ID; Access until, department, position and mobile fold under More details;
  Send invitation email, unticked, is drawn only at `team.invite`; Add opens
  the new colleague's record, which says what happened (TEAM2-10,
  2026-10-24). Role standard, capacity and the namecard are set there.
- A colleague's row is never deleted, only stood down or removed (the user,
  2026-10-14; `2026-10-14-colleague-hand-over.sql`,
  `2026-10-14-colleague-remove.sql`, the second run in the SQL Editor):
  - Set inactive and Delete (the ⋯'s last item, red, Team Full Access, never
    one's own or a system account, not drawn once their details are
    deleted) first ask who takes each kind of live work the colleague holds,
    a picker a kind, only kinds they hold, Keep with them first for Set
    inactive; Delete's opens on Choose a colleague, required while anything
    is held, Keep still offered (TEAM2-5); with two kinds or more All their
    work to comes first and each kind reads Same as above until a colleague
    or Keep is chosen for it (`team_work_held`, read whatever the caller's
    client scope, `2026-10-24-hand-over-takes-clients.sql`): clients they
    are person in charge of and open campaigns (by name, listed for the
    Work pane), open tasks, months they manage,
    meetings ahead they lead, repeating tasks, reports in review waiting on
    them (left with them where the colleague chosen submitted it or may not
    review, and said), extension requests waiting on them, and templates
    naming them as default owner (`team_hand_over`, each filed on its
    record and one line under the colleague: Work handed over: 2 open
    tasks → Aisyah; …; the person in charge moved past the caller's own
    client scope, `adspace.team_owner`). The work moves first: Set inactive
    stands them down, and Delete removes them, only once it has (TEAM2-4).
    Work left with them, or a hand-over refused, is said with Open Work,
    the button to their Work pane, whose head holds Hand over work over a
    line of all they hold, the same pickers, and says after what moved
    what stayed (TEAM2-12). A rename is carried onto every client and
    campaign naming them, completed ones included, each filed, by trigger
    `team_members_rename_owner`; the page carries nothing.
  - Delete then asks Their data, Keep / Erase personal details, and the name typed back
    (the question opens on it); `team_member_remove_check` answers the
    removal's own refusals before any work moves
    (`2026-10-15-colleague-remove-check.sql`), then `team_member_remove` (`own`,
    `system-account`, `bad-name`, `last-admin`) sets them inactive and
    stamps `removed_at` (the row reads Removed, with no Set active);
    Erase personal details also removes the mobile, the namecard (off, its short
    link freed), the sign-in email and its login, their health check-ins,
    consents, log and talks, devices, guides met and section order
    (`erased_at`). Their name, Employee ID and group, their name on past
    work and the documents they signed, and their own HR letters and
    performance records are kept either way.
  - Leaving (`2026-10-15-colleague-leaving.sql`, audit I3, I4, S6, S9, I9):
    a Delete whose hand-over failed removes nobody (the question stays open
    saying so); an erased colleague's card slug stays empty
    (`team_card_slug`); `team_hand_over` refuses `own` and
    `system-account`; a removed colleague is never made active again
    (`team_access_guard`, `removed`: with a sign-in a removal or an
    erasure, once made, is never moved or cleared, and moving an
    expired-then-removed colleague's date brings nobody back;
    `2026-10-18-a-removal-stands.sql`), so one who returns is added again:
    a name, sign-in email and Employee ID are unique among colleagues not
    removed (`team_members_{name,email,staff_code}_live_idx`,
    `2026-10-18-removed-colleagues-free-their-details.sql`), the page naming
    the field that clashes, and an edge function finding a colleague by
    email reads the active row first; an extension on a task whose creator
    has left is asked of the first active admin who is not a system account
    (`ops_due_decider`); an on-site meeting's outstation reminder goes to
    its leader while active, else the month's manager; trigger
    `team_members_leaving` takes a colleague's notification devices on Set
    inactive, an expiry or a removal, and on a removal ends their helper and
    reviewer places on tasks; trigger `team_members_talks_closed`
    withdraws every open health talk they asked or were asked the moment
    they stop being active (`2026-10-18-leavers-talks-closed.sql`).
- Access expiry (`2026-10-01-team-access-expiry.sql`,
  `2026-10-03-team-access-time.sql`):
  - every five minutes (pg_cron `team-access-expiry`) `team_expire_access()`
    stands down each active colleague whose moment has passed
    (`team_access_ends(day, time)`, MYT) (`active` false, `expired_at` stamped, filed `team.changed` by
    `system`), never the last admin with access; each open task they hold
    goes back to its creator where the creator takes tasks (told, kind
    `assigned`), else is left with no owner and open to take, the active
    managers told (`tasks.unassigned`), each move filed on the task
    (`team_expiry_hand_back`, `2026-10-18-expired-access-hands-tasks-back.sql`);
  - the row reads Access expired and Access until reads Ended {day} with its
    pen, the ⋯ holding no Extend access (TEAM2-8); moving the date to
    today or later brings them back at once (`team_access_guard`), and Set
    active on a passed date is refused (`expired-date`);
  - the bar's ⋯ Set access expiry (`team_set_expiry_at`, Team at Manage)
    asks for a date and an optional time, refusing a moment passed in the
    question (TEAM2-7), and sets them for every active colleague but the
    caller and a system account (an admin's for an admin alone), naming
    how many own end dates it replaces, Undo putting each back
    (2026-10-27, TEAM-3);
  - an expired address signing in reads Access expired
    (`my_access_expired()`), not Access denied.
  - the moment passes before the run comes: `is_team()`, `allowed()`,
    `ops_me()` and `me()` count a colleague only while
    `team_access_ends(access_until, access_until_time)` is ahead (an admin
    is the run's, which keeps the last admin with access), so nothing waits
    for the five minutes (`2026-10-18-access-ends-on-the-minute.sql`).
- Digital namecards (`js/namecard.js`, `/card/?k=`, `2026-10-03-team-namecards.sql`):
  - every colleague has a `card_key` (eight characters from the link keys'
    alphabet), made by trigger and never changed, so a printed QR keeps
    working; the card answers only while the colleague is active and their
    card is on (`card_on`, Team's sheet; off answers the cover, and the
    same address works again once on);
  - `namecard_get(p_key)` (anon) answers name, position, mobile, the
    sign-in email (`2026-10-03-namecard-login-email.sql`; whatever its
    domain, interns' personal addresses included; `card_email` is unread)
    and the card's short link (`slug`, 2026-10-07) alone; never the
    Employee ID, group or access;
  - the email row never breaks inside the address: it shrinks to 12px
    (`fitMail`), else breaks only before the @;
  - the pair under the card (turn, QR code) is two equal halves of the
    portrait card's width on every face, so a turn never moves them;
  - every pill on the card (Save contact, WhatsApp, the turn and QR pair)
    is 44px under a finger, the landscape card's too (the iPhone Duo pass,
    2026-10-18);
  - every card has a short link on the links host (`card_slug`,
    `2026-10-03-namecard-short-links.sql`): made as the colleague is added
    from the name's letters and digits run together (Xue Yi `xueyi`; a
    name with none, written in Chinese, takes the sign-in email's name),
    numbered with no dash where taken (`xueyi2`; `card_slug_from`,
    `2026-10-07-namecard-short-link-shown.sql`; the user, 2026-10-07),
    never following a rename, edited in the Team sheet's Namecard and by the
    colleague in My namecard (`namecard_save`; emptied, made again from
    the name); one slug is never both a card's and a short link's
    (`slug-taken`, both ways); `link_resolve` answers it with the card's own
    address while the colleague is active and the card on, else missing; My
    namecard shows and copies it; the card's QR face names it under the
    name (`hi.adspace.me/{slug}`, never the long address; the user,
    2026-10-07) while the QR itself keeps the card's own address;
  - whether the mobile is on the card is the colleague's own choice
    (`card_mobile`, Mobile on card Show / Hide, shown by default;
    `2026-10-03-namecard-mobile-switch.sql`): one card, one link and one QR,
    and hidden, `namecard_get` sends no mobile, so the card, its WhatsApp and
    Save contact go without it; set in My namecard (`namecard_save`, one
    write with the mobile and short link) and in the Team sheet, filed from
    and to;
  - the card is the signboard's lockup on the brand's five tones (`--nc-*`,
    light in both themes) in golden proportion: the wordmark runs the card's
    width over φ² (`--nc-sw` from the card's width), the tagline at 0.46 of
    its size runs it over φ (the signboard's 1.64), and the pair is centred
    on the card both ways; landscape at 760 and over (`is-land`), portrait
    under; it turns over to the person and the office (`ADSPACE_ORG`),
    turns its front to a QR of its own address, and Save contact is a vCard;
  - every number reads with its country code (`ADspaceCard.phone`:
    +60 12-345 6789, +60 18-762 5233, +65 8123 4567);
  - the colleague keeps their own mobile and short link in My namecard (the
    account menu, `namecard_save`, filed `team.edited`); the Team sheet edits
    everybody's; a row ⋯ offers Open namecard while the card is on. No bar on
    the card's page: it is the card alone on white.
  - the page is named eNamecard by ADspace (`<title>`, og:title) and, once
    the card loads, `{name} • eNamecard by ADspace`; a link preview reads
    the page before it runs, so it shows the general title.

### Activity record
- Every tag written is named in `ACTION_LABEL` (`js/admin.js`).
  `activity_section()` in SQL restates the map, and `tests/sql.js` §21 compares
  the two.
- A tag nothing names files as `other` and falls back to the section.
- One part per section (`activity.clients`, `.whatsapp`, `.ops`, `.team`,
  `.review`, `.scripts`, `.campaigns`, `.links`, `.register`, `.reports`,
  `.services`, `.handbook`, `.hr`). The link draws where any part is readable.
- An HR letter's history (a Documents tag filed under subject HR) is its own
  part, HR letters (`activity.hr`), after Documents in the Section select:
  `activity_read` answers it only at `activity.hr` and `register.hr` View
  together, and Documents reads without it (`2026-10-24-hr-history-apart.sql`,
  S5; the user: "file it apart").
- Reports files a report's steps (`report.*`: started, submitted, returned,
  confirmed, published, revised, unpublished, deleted), every save
  (`report.saved`, filed by the page through `fileReport()`: the period and
  version, then the step or sheet and what it held) and every Draft with AI
  (`report.ai_drafted` with its language, `report.ai_failed` with the
  reason) (`2026-10-01-activity-reports-tab.sql`).
- Performance follows Team (`team.performance` View, no master code), read
  through `perf_activity()`: when, the step, whose month, who; never a score,
  a grade, a breach or a dispute's words, and never the caller's own review.
- The sections are one Section select (`#activitySection`, its label at its
  left; 2026-10-11, in place of a strip of fourteen tabs): All sections
  first (never Everything), then only the sections whose part the reader
  holds (Performance at `team.performance`), in the rail's order, opened on
  the section the record was opened from where it is offered, else All
  sections; ten or more open the finder. The sheet holds no swipe region.
- The panes key on the subject the row was written with, so a rename leaves
  older rows behind.
- The Activity record reads its chosen section alone (`.in('action', actionsOf(k))`), newest first, 200 a page, Show older reading the next; a failed read is `failLine` with Try again (ACT-1, ACT-2, 2026-10-22).
- Every history (the Activity record, a client's and a campaign's Activity and
  rail, a task's log and recent activity, and every Performance history) is
  drawn by `js/records.js`
  (`ADspaceRecords.paint`): at 720px and over one 12.5px line an entry
  (`.reclist.is-wide`: time, what and on what, the detail cut at the line's
  end in the soft ink, who at the right edge in a 150px track, a hairline
  between entries); narrower, two lines (time, who in mute ink, what and on
  what; the detail under it), each cut at its end; a cut entry opens on a
  press. A heading a day, and a run of the same act by one
  person on one thing within ten minutes folded into one entry (`×n`). On a
  campaign's own page a booking's entry is about its creator (`lead`, the
  detail's first part), and `detailOf()` drops words the first row says
  (`quality checked by …`, `schedule updated`). Sticky entries never fold: Performance, HR, voids, deletes,
  removals, billing, rates, invoices, access and groups, a client's decision
  on a draft and a creator's hand-in (`stickyOf`).
  `ADspaceAdmin.record(row)` is the one reading of an `activity_log` row.
  A run folds only on the same thing: its `key` (a document's subject and
  reference; a booking's campaign and the creator its detail names first,
  written once on the folded line; the record a pane belongs to) else its
  subject; with neither,
  only identical lines fold. A field changed twice reads as its path
  (`Admin → Team → Admin`), a run reads `· 3 times`, and a cut entry is a
  button with `aria-expanded` (`is-long`).
  `register.added` / `register.edited` read Document added / edited.
- Every save files what it changed, from and to (`ADspaceRecords.changes`:
  "Label: old → new", empty reads "not set"); a save that changed nothing
  files nothing. Client details, brand, contacts, rate lines, team members,
  groups and access (`accessMoves`) name values. Billing names the fields
  only (`{ names: true }`), never their values. A Documents edit is filed by
  `register_update` itself (the serial, then each move; `register_day` writes
  `12 Sept 2026`); an HR row is filed under `HR` with its type, date, note
  and file only.
- `document.*` and `register.*` rows file under Documents.
- The record keeps three years: `privacy_retention()` (pg_cron
  `privacy-retention`, the 2nd of each month) removes older rows, and
  clears a WhatsApp message's number, name, variables and link code twelve
  months after it was queued, never one still queued or sending
  (`2026-10-18-personal-data-kept-for-a-time.sql`), and removes a caller's
  address against a link's passcode (`link_tries`) once its last try and
  last opening are 30 days old and no lock stands
  (`2026-10-18-passcode-tries-kept-for-a-time.sql`).

### WhatsApp (`js/whatsapp.js`, `?s=whatsapp`, `wa-send`, `wa-hook`, `2026-10-09-whatsapp.sql`, `2026-10-10-whatsapp-section.sql`, `2026-10-10-whatsapp-approval-reminder.sql`, `docs/WHATSAPP-SETUP.md`)
- Messages go through the WhatsApp Business Platform (Cloud API), each with a
  template Meta approved (the user, 2026-10-09: report to client, team
  reminders, creator updates, a feedback request sent by hand). Phase 1
  (2026-10-10): the section, the composer, the delivery status; no inbox, no
  message to a colleague but the queued reminders, nothing sent to an AI
  service.
- A section of its own, `whatsapp`, the last of the Work chunk (the user,
  2026-10-10: "whatsapp tab should go to the last inside work"): View
  reads the messages, Work (Manage on the panel) sends, Manage (Full Access)
  sets the templates. Its parts `whatsapp.report`, `whatsapp.feedback`,
  `whatsapp.booking`, `whatsapp.approval` (2026-10-10) and
  `whatsapp.documents` (Quotations and letters, 2026-10-14) follow it or are
  shut (No Access), nothing between
  (`VIEW_PARTS`); they replaced `reports.whatsapp`, `clients.whatsapp` and
  `campaigns.whatsapp` (a shut one moved across, the old keys taken off). A
  send asks the section and its purpose's part at Work and the record's own
  section at View (Reports, Clients, Creator Campaigns), a plain message a
  contact's Clients: Contacts or a creator's Creators List at View, an
  approval reminder Content Review: Content sets or Creator Campaigns:
  Campaigns at View and the record it names at its own, a quotation
  Clients: Services at View, a Letter of Offer Clients: Documents at View
  (`wa_may_send`, `ADspaceWhatsApp.may`); at No Access no record offers
  WhatsApp. Groups started once: Admin Full Access, Clients Work or above
  Work, Clients View View, else none.
- Messages (the landing view, `wa_messages(p_month)`, client scope): one
  table of the chosen month's messages (Malaysia time, read from
  `ADspaceClock`, `9 Oct, 2:05pm`), never a card naming the month again,
  newest first (2026-10-22, WA-2, WA-3), a row who it
  went to (name; client, Creator or Colleague; the number as
  `ADspaceCard.phone` writes it), what it was (Report, Feedback request,
  Booking, Reminder, Message over the template, which gives way, and its
  category, read whole; on a phone the meta line leads with what was sent,
  the number leaving first; WA-4), who sent
  it (Automatic for the queue) and the status over when: Queued, Sending,
  Sent, Delivered, Read, Not confirmed (check the chat before sending again), or Failed with the reason in the team's words
  (`REASON`, by Meta's code) and Open contacts (a client contact's
  Account) or Open creator (the Creators List) where the reader may
  (2026-10-27, WA-10). An empty month reads No messages. alone, New
  message being the bar's (WA-8). Above it the month's templates sent by
  category (Utility, Marketing; Authentication where any; a message Meta failed left out). The bar: search
  (name, client, template, a number as typed), Month (a view, the last
  twelve), Type and Status behind Filters, the count, New message (Work).
- At Full Access the queue (waiting, sending, not sent and not confirmed
  in 7 days, `wa_messages` `queue`; `#waQueue`) heads the messages. The
  templates are Settings' Templates, WhatsApp templates (`#waTplSheet`,
  `ADspaceWhatsApp.manage`; 2026-10-29: the section's Templates tab gone,
  an older `tab=templates` reads the messages): one template a purpose (`wa_templates`: `report`,
  `feedback`, `reminder`, `creator`, `approval`; name, language, category, how many body
  variables, On): Edit chooses from Meta's approved list read through
  `wa-send` (never typed; the report's needs a Document header and no other
  takes one; a link button's variable refused only for the team reminders, which the portal sends by itself (`NO_BUTTON`);
  only templates the purpose can take are offered, 2026-10-20, WA-2; one
  whose link button's fixed part holds a variable typed by hand, `%7B%7B1%7D%7D`,
  is never offered, its row and the composer name it and Send rests,
  2026-10-22), each row's
  switch (`.switch`) turns it on or off at the press (one with no template
  asks for one first); `wa_template_set`, filed `wa.template` under
  WhatsApp from and to. A purpose that is Off sends nothing and its record
  button is not drawn. The account menu holds no WhatsApp item.
- The composer (`ADspaceWhatsApp.compose`, `#waCompose`), one sheet every
  record shares: To (`wa_recipients`: client contacts named with their
  client, active creators; never a colleague; one with no number listed
  last as · No number), the number as it will be
  sent, else why not (a username alone cannot be messaged), with Open
  contacts on the client's Account where Clients: Contacts is readable
  (2026-10-22, WA-5); Template
  (Meta's approved ones the portal can fill: a Document header, a text
  header with one variable, body variables positional or named, one link
  button variable); each variable prefilled from the record (the greeting
  by `contact_greeting`, then the client or the report's brand, or a
  creator's campaign; the report; a named one by its name), a typed one
  kept; the link button the record's own, shown and never typed: `wa-send`
  fills it from `wa_compose_prepare` alone (a creator's `code`; an approval
  reminder's `link`, past the button's fixed base) and refuses `wa-no-link`
  where the record holds none (2026-10-19); a numbered one named for what fills it
  (Greeting, Client, Campaign, Report, Reference, What waits, Link); a Report select only for a Document
  header, the recipient's client's published reports newest first, its file
  the kept PDF the client portal hands over (`ADspaceReports.keptPdf`), which
  `wa-send` reads itself as the caller through `sign-download`, never the
  page's bytes, a quotation's or letter's refused unless it is a PDF whose
  title names the record's own reference (`_shared/pdfref.ts`, the one
  reading, supplier-mail's too; 2026-10-22, LEAN-1) (each stream inflated with only
  its one closing line break cut, the file's streams inflating to 20 MB
  at most, past which it reads as not naming it; `bad-file`; audit S3,
  2026-10-15;
  the letter's PDF titled `Letter of Offer {number}`); the
  message previewed as it will read. Send asks (`ADspaceConfirm`, naming
  the recipient, the number and the category), then `wa-send` `compose`
  asks `wa_compose_prepare` as the colleague (the number and the record are
  the database's), reads the template again from Meta, files it as Sending
  first (`wa_send_begin`, below), sends and closes it (`wa_send_done`, the
  sender's own row: Sent, Not confirmed or Failed; `wa.sent`, WhatsApp in
  the Activity record; a booking's under
  its campaign as `{creator} · Booking sent on WhatsApp`). Purpose: a
  report attached is `report`; else the record's (`feedback`, `creator`),
  else `message`. The record buttons stay where they were and open it
  prefilled: Send on WhatsApp beside Mark as sent (then marked as sent
  today), Request feedback in a client's ⋯, Resend booking in a
  booked creator's ⋯ at Confirmed and Pending visit alone (the booking goes
  out by itself on confirming; the user, 2026-10-11).
- A quotation and a Letter of Offer (`quotation`, `offer`,
  `2026-10-14-whatsapp-documents.sql`, the purposes added by
  `2026-10-14-whatsapp-document-purposes.sql` in the SQL Editor; the user,
  2026-10-14: the team decides which to send once a client proceeds): Send
  on WhatsApp in a quotation's ⋯ (not removed, not Cancelled) and a
  Letter of Offer's ⋯ on the client's Documents (not voided or replaced;
  `wa_compose_prepare` refuses either `void`), each drawn once its template is on; the composer takes the
  record fixed (`o.doc`: `#waDocOne`, a readfield, never a select of one),
  its PDF drawn in the browser as Download draws it and sent as the
  Document header; variables the greeting, the client, the reference; to a
  client contact of that client alone; filed as Quotation / Letter of Offer
  sent on WhatsApp. Sent by hand only: the one automatic send to a client
  or creator is a creator's booking confirmed.
- Sent recently (`2026-10-14-whatsapp-sent-recently.sql`; the user,
  2026-10-14: "so no duplicate would be repeated sent"): before a send the
  composer asks `wa_sent_recently(p_to_kind, p_to, p_purpose, p_ref,
  p_template)` for the newest message not failed to that recipient for that
  purpose and record (a feedback request its client, a plain message its
  template) within `wa_repeat_hours` (24; Settings, WhatsApp: Sent again; 0
  to 168, 0 asks nothing); found, Send asks in warn instead (Sent recently:
  to whom, by whom or automatically, when and how long ago; Send again),
  and `wa-send` refuses `recent` unless that question was answered
  (`again`), so a send made meanwhile asks too. A queued booking counts.
  The check and the filing are one step (`wa_send_begin`, 2026-10-19): a
  lock on the recipient, purpose and record, then `sending` while the same
  message is on its way (even with `again`), then `recent`, then the row
  filed as Sending before Meta is asked, so two presses send once. A
  feedback request or a plain message is Sent recently for any message of
  the same template to the same recipient, whatever purpose it was filed
  under (`2026-10-20-whatsapp-feedback-sent-once.sql`, WA-1).
- Variables of the queued ones in order: reminder (first name, title,
  message), creator (first name, campaign; its link button's variable the
  creator's code, `wa_outbox.button`); a template takes the first n.
- The approval reminder (`approval`, 2026-10-10; the user: "yes" to the
  chaser, sent by hand, never automatic): to a client contact, `p_ref` a
  published set of their client or a booking at Reviewing on a campaign of
  theirs (`not-found`, `not-waiting`), filed against it (`ref_kind` `set` /
  `option`) as "Approval reminder sent on WhatsApp to …"; variables in order
  the greeting, the client, what waits; the link to approve it rides a
  link button (`https://digital.adspace.me/{{1}}`, filled `review/?k=…` or
  `creators/?k=…`), else a fourth body variable. Its purpose
  is added to the check in `2026-10-10-whatsapp-approval-purpose.sql`, run
  in the SQL Editor (the connector stops on the check's replacement).
- Delivery (`wa-hook`, Verify JWT off): Meta's verification answered only
  with `WHATSAPP_VERIFY_TOKEN`; a POST believed only with its
  `X-Hub-Signature-256` over the raw body keyed by `META_APP_SECRET`; each
  status recorded by `wa_status_record` (the service role's alone) against
  `wa_outbox.wa_id`: `delivered_at`, `read_at`, `failed_at` with
  `fail_code` / `fail_title`, Meta's pricing category; a delivered or read
  message never turns failed; a status the database could not take is
  answered 500 after the rest are recorded, so Meta sends it again
  (2026-10-22, WA-1). Messages sent in and coexistence echoes are
  not read.
- A number is `wa_number`'s international form, read as the team types it
  (`2026-10-09-whatsapp-numbers-resend.sql`): a leading 0 is Malaysia (60
  for the 0), any other eight digits Singapore (65), nine or ten starting 1
  a Malaysian mobile without its 0 (60), else as typed with its country
  code; the console's wa.me links read them alike; a `@username` cannot be
  messaged (`no-number`). A client's main contact's WhatsApp number, else
  its phone; a colleague's mobile; a creator's `creators.whatsapp` (the
  Creators List sheet).
- `wa-send` answers `report` and `feedback` with bad-request (2026-10-19). A refusal is one
  line in the team's words (`SAID` in js/whatsapp.js), never Meta's.
- Queued by trigger, never failing the write: a reminder in a colleague's
  bell (`tasks.empty`, `outstation`, `perf.remind`, `perf.reflect`,
  `health.remind`; `ops_notifications_wa`) and a creator's booking
  confirmed, with their code for the link button (`campaign_options_wa`,
  `wa_enqueue`; `2026-10-09-whatsapp-creator-link.sql`; changes requested
  and cleared to post stay on the creator's page and push) go to
  `wa_outbox` with their template's category; `wa_kick` (pg_net) wakes
  `wa-send`, which claims with the service role (`wa_claim`, `wa_done`;
  three tries of Meta's own refusal, then Failed), and pg_cron
  `outbox-drain` wakes it and `push-send` every five minutes while their
  queue holds something. A send whose answer never came (a dropped
  connection, a timeout, Meta's 5xx, a row cut off at Sending) is Not
  confirmed (`unknown`, filed `unknown:`), never sent again by itself, and
  counts as Sent recently (2026-10-17); a request that never left (DNS,
  connect, TLS) is filed `not sent:` and queued again with its try given back
  (`2026-10-18-whatsapp-outage-spends-no-try.sql`; Meta's throughput limit
  130429 filed the same way), and ends that drain
  (claimed again at once, a short outage spent all three tries). A message
  still queued 48 hours after it was queued is Failed by `wa_expire`
  (`expired:`, read "Not sent within 48 hours"; `wa_claim` and pg_cron
  `wa-expire` hourly), so Sent recently lets it be sent again and
  `privacy_retention` clears it in its time. The queue is
  claimed one row at a time (`wa_claim` gives one, five at most) and no
  send starts after 90 seconds, so a claimed row is never left at Sending. The queue and its tables are
  closed to every page.
- Secrets: `WHATSAPP_PHONE_ID`, `WHATSAPP_WABA_ID` (the templates),
  `WHATSAPP_TOKEN` (else `META_SYSTEM_TOKEN`, the user's choice, 2026-10-09:
  one system user holds both), `META_APP_SECRET` (`appsecret_proof` on every
  call, as `meta-import`; `wa-hook`'s signature), `WHATSAPP_VERIFY_TOKEN`
  (`wa-hook`), `META_GRAPH_VERSION`; Verify JWT off on both (pg_net and Meta
  call with no session).
- A wake of `wa-send`'s `drain` or of `push-send` carries the database's
  wake secret (`app_secrets` `wake_secret`, made once, never shown) as
  `x-adspace-wake`, which each function asks of `wake_secret_ok` (the
  service role's alone) before touching a queue, else 401; `wa_kick` and
  `push_kick` send it, once a transaction, so a statement queueing forty
  rows wakes each sender once (`2026-10-19-wake-calls-carry-a-secret.sql`).

### Push notifications (`js/push.js`, `js/push-sw.js`, `push-send`)
- A device follows what the page it turned on from proves: the console the
  signed-in colleague (`team`), the selection page a campaign by its token
  (`client`; never a campaign behind a passcode or a Past client's,
  `push_target`, `2026-10-18-a-clients-device-follows-only-a-link-that-opens.sql`),
  the creator's page the creator by their code (`creator`).
  - One colleague and one creator a device; a client's device any number of
    campaigns (`push_subscriptions`, unique `(endpoint, target)`). A target
    takes five new devices an hour and twenty in all (`too-many`), and none
    is pushed out for another (2026-10-22, BE-11).
  - Only a push service's address is stored (`push_endpoint_ok`: Google,
    Apple, Mozilla, Microsoft), and `push-send` checks it again: the sender
    never posts anywhere else.
- What is sent (`push_outbox`, queued by trigger only where a device
  follows):
  - a colleague: every `ops_notifications` row, opening the task;
  - the client: a draft released (Submitted → Reviewing) and a post live
    (Scheduled → Posted);
  - the creator: booked (from option, shortlisted or backup), changes
    requested, and cleared to post (Scheduled from Submitted, Reviewing or
    Changes requested).
  - Only a forward move is told; a Revert tells nobody. Words are the
    device's language (`title_zh` for a Chinese device).
  - A notification never fails the write that caused it (the triggers
    swallow their own errors).
- `pg_net` wakes `push-send` after the commit (`push_kick`, once a
  transaction, with the wake secret; WhatsApp, above). A run stops claiming
  after 90 seconds and each send waits 10 at most (2026-10-26). It claims 50 at
  a time for five minutes (`push_claim`, skip locked), sends a day's TTL, drops
  a device the service answers 404/410 for (`push_done`) and keeps a month.
- The VAPID pair is made by `push-send`'s first run and kept in `app_secrets`;
  only `push_public_key()` leaves the database. No key, no control.
- Each page registers its own worker (`/admin/sw.js`, `/client/sw.js` (files only), `/creators/sw.js`,
  `/creator/sw.js`), all importing `js/push-sw.js`. The client pages carry a
  manifest with no `start_url`, so a Home Screen copy opens its own link.
- Controls:
  - the console: Notifications in the account menu, a switch
    (`role="switch"`, On / Off at the row's right edge); the menu stays open
    and answers under the item (`#acctPushMsg`);
  - the client pages: the bar's bell (`#pushBtn`) opens `#pushPop`, a named
    dialog with one line and one action, its words in `W.push`.
  - An iPhone not on the Home Screen is told to add it; a blocked site is
    named; neither shows a button that cannot work.
- Signing out of the console, and Forget this device on the creator's page,
  stop the device's notifications first.

### Sign-in, security, secrets
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
  (`/client/`, `/review/`, `/creators/`, `/creator/`, `/script/`, `/card/`)
  load the same while it stands: the client portal signed in as a sample
  client's main contact (`client@example.com`), the rest on their sample
  links alone, each key holding a 0 that no real key's alphabet holds
  (`demo0r…`, `demo0c…`, `DEMO0…`, `demo0s…`, `demo0…`), so a real link
  opened while the demo stands is the real page; each under the bar edge
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
  access (`team.settings`): On / Off and a PIN, 4 to 8 digits, kept as a
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
    same least time (`FLOOR_MS`, 900 ms; a fault logged, never a 500), so
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
  private); the record must be the named client's and the caller's client
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
  `2026-10-18-a-callers-address-is-cloudflares.sql`), five within
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
  and under `private/` (write and read, for invoices and each published
  report's kept PDF) once §5 is done;
  `private/` is closed to CloudFront by the bucket policy. `content/` is
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
  report filed as failed or not arrived in 26 hours, and of each repeat rule
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
  `{ "all": true, "redo": true }` remakes only copies over the cap.

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
  `hwwuigvdfubuymchsvyx`, the user, 2026-09-28), in the order the release
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
  `meta-import`, `caption-draft`, `script-draft`, `wa-send`, `wa-hook`, `brand-analysis`, `quote-request`, `checklist-draft`, `supplier-mail`, `bukku-sync`, `analytics-read`) is
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
- Every go-live report names the version the console shows exactly as the rail reads it (`v{YY.MM.DD} · {commit}`), so the person can match it.
- Never ask for a URL, key or asset the repo or config already holds. Check
  `js/config.js` and `css/` first.

### Folder and file rules
- Never edit the user's root files: `ap01.html`, `ap02.html`, `ap03.html`,
  `ap-dale.html`, `accv-new.html`, `3pform.html`, `einvoiceinfo.html`,
  `interview-quiz.html`, `sales-program.html`. `index.html` and `404.html`
  are the portal's; `supplier.html` was retired for `/supplier/` (the user,
  2026-10-18: "no longer in use").
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
  (`visitSection`; the user, 2026-10-09; `tests/visit.js`); only Back and
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
- The same error twice is a stop: name the cause, never try a third time.
- A fault between two pages, tabs or sides (a cookie, a pass, a lock) is
  fixed and tested in both orders, never only the one reported. A file that
  will not load is tested at its source before any page is blamed: ask
  `media-pass` as the page does and fetch the file with its cookies
  (refused without, served with, is a browser fault). The media pass broke
  this way twice (2026-10-12, 2026-10-15).
- Partial work is labelled partial, never reported as done.
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
