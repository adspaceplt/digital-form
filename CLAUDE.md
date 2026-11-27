# ADspace Digital Portal — working rules

@DESIGN.md
@STANDARD.md

Static site, vanilla ES5 IIFE scripts, no build step, no framework, served by
GitHub Pages at digital.adspace.me (CNAME in the repo). Pages: `admin/`
(console), `client/` (client portal), `creators/` (the client's creator
selection), `creator/` (a creator's own page), `review/` (content review),
`script/` (a client's video scripts), `verify/` (public reference check), `card/` (a colleague's namecard), `quote/`
(a prospect's own quotation), `details/` (a client's billing details form),
`feedback/` (a client's feedback on its link),
`supplier/` (a supplier's details form; `supplier-details/` forwards to it),
`careers/` (a candidate's own page), `/` and
`404.html` (covers). Supabase behind
`js/api.js`; schema in `supabase/schema.sql` (re-runnable). Migrations are
applied by Claude through the Supabase connector (§3). A change to one function or one
column ships as a dated file in `supabase/migrations/`: narrowly scoped, safe to
run twice, its own rollback, mirrored in `schema.sql`.

`DESIGN.md` holds the design system and architecture; its components, laws,
copy and print rules are `docs/rules/components.md`, `laws.md`, `copy.md` and
`print.md`. `STANDARD.md` holds the instruction priority and the Project Memory
(departures, open findings, what is not built); the general standard, the
working method and the completion gate are `docs/rules/standard.md`.
Where they disagree, `STANDARD.md` §2 settles it and this portal's documented
behaviour wins.

## 0. Where things are written

- These three files are **rules only**, loaded on every turn: a rule needed
  only while one kind of file is changed lives in a `docs/rules/` file under
  that file's triggers, with one loaded line naming it. The history behind
  every rule (what was reported, measured, tried and rejected, and why, and
  who asked when) is in `docs/DECISIONS.md` and `docs/DESIGN-NOTES.md`. They
  are not loaded.
- **Before changing an area, search the archive for it**
  (`grep -n -i "<class, function, table or word>" docs/DECISIONS.md docs/DESIGN-NOTES.md`)
  and read what matches. A rule that looks arbitrary has its reason there. Never
  undo a recorded decision without reading it.
- **One place per fact.** A rule learned is written the same push, as one line,
  in the one file it belongs to (behaviour, data, tests, workflow: here, or
  an area's own `docs/rules/` file for that area alone; look, architecture:
  `DESIGN.md`; components, laws, copy, print: their `docs/rules/` file;
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
- The stand-in's rules, the harness facts, the gate's workings (its lanes,
  waits, output, the uxaudit and matrix lane, the server) and what the two
  walks measure: `docs/rules/tests.md`, read whole before changing any
  `tests/` path.

**One command, one result:** `bash tests/gate.sh <suites… | all | ui>`.
- Every shell command runs without a permission prompt (`.claude/settings.json`
  `Bash`; the user, 2026-10-10: "Auto allow bash"), as do the read-only GitHub
  and Supabase lookups (workflow runs, a PR, edge functions, logs,
  migrations; 2026-10-04). Supabase's logs are read only while a fault is
  being found, for the shortest window that holds it, never to confirm a
  deploy (the Pages run and a live read do that): every log read counts
  against the organisation's log query allowance. So
  is a release's own work (the user,
  2026-10-11: "auto merge all PRs and allow all sessions"): opening,
  updating and merging a PR, applying its migration and deploying its edge
  function, in the order the release states, and starting or messaging a
  session and adding a repository it needs; any other write still asks.
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
  - Merge first, gate once a day. A request is
    built, `node tests/affected.js --run` passes (never uxaudit or matrix,
    which run once, in the day's full gate), its touched
    screens are screenshotted and read (1280 and 390, both themes in the
    console; every screen a shared layout, CSS or component change
    reaches), and it merges on its train's PR (§3, Token economy). Beyond the suites
    the diff reaches, a suite runs by hand only while a fault is being
    found. A migration still runs `sql` and its
    area's Postgres suite before it is applied to the live database. The
    full gate runs once a day, on main, after the day's merges (`all`:
    every suite, `ui`, uxaudit and matrix included);
    what it finds is the next batch, each fix its own release. Never weaken an assertion or
    change an expectation merely to pass. A failure in code a request did
    not touch is logged in `docs/rules/logged-defects.md` until it ships.
  - After `main` is merged into a branch, only the suites that failed
    before the merge run again.
  - Never poll with sleep.
  - Never watch suites one by one.
  - Never wait on a `pgrep` pattern: the loop's own command line matches it and
    the wait never ends.
- A suite passes on exit code 0, some output, and no line starting `FAIL`
  anywhere in it. **Never count `FAIL` lines** to call a suite
  green: a suite that throws prints none. Every suite asserts what it walks;
  one that only prints what it saw is a diagnostic, never in the gate
  (audit T3). `tests/gateself.js` runs the gate's own judgement on
  synthetic suites.
- Every CDN script on a portal page names its version and carries its
  `integrity` hash and `crossorigin="anonymous"` (`tests/sql.js`); a new
  version is hashed from the file the CDN serves.

**Tiers: what checks each kind of change, in the day's full gate and by hand while a fault is found; before a merge, only the row's screenshots and `node --check` (a migration also its Postgres suite).**

| Change | Run |
|---|---|
| Docs or `.md` only | Nothing, but confirm the `@` imports at the top of this file still name real files |
| Any `js/*.js` | `node --check` on each changed file, then the suites that cover it (`node tests/affected.js --run`) |
| Copy, markup a script draws, a state of one screen | The above, plus screenshots at 1280 and 390 of every touched screen (both themes in the console), each opened and read against the phone checklist (`docs/rules/laws.md`). `SHOTS=1 node tests/uxaudit.js tests` writes the walk to `tests/walk/` |
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

**Before every merge**: `node tests/affected.js --run` (`node --check` on each changed
script, then those suites through `gate.sh`, in the background, uxaudit and
matrix left out and named as the full gate's; it writes
`/tmp/affected-pass/{commit}` on a pass). A run stopped partway is stopped
with every suite process it started, never its shell alone. The merge check
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

**Global > parent > child**: a
base element (button, field, select, chip) is styled by its own rule and its
variants; a section arranges it and never restyles it. `tests/cssguard.js`
(run with `ui`) fails a new section rule that sets a base element's ground,
edge, corner, height, colour or shadow; the ones standing on 2026-10-11 are
its baseline, all folded into the shared rules by 2026-11-22: the baseline
is empty and only shrinks (`--write` refuses to add).

**Also required:**
- Before a push, scan the diff for a number, word, colour, address or id
  typed into logic: a business figure goes to
  `app_settings` / `perf_settings`, shared words to `js/words.js`, a colour or
  size to a token, an id or endpoint to `js/config.js`, a secret to Supabase
  only. The report names what became configurable.
- Every script, stylesheet or picture address that is stamped is written
  `?v=dev` and nothing else: the Pages build (`.github/workflows/pages.yml`)
  writes each as its file's content stamp (`.github/stamp.js`), and stops on
  a stamp naming no file. Never type a stamp (`tests/stamp.js`).
  A merge's resolution keeps every script tag a page holds:
  `tests/pagescripts.js` fails a page missing a script its own scripts call.
  A page holds no script nothing on it calls: a client page's weight is
  every visitor's.
- A new route or pane joins `tests/uxaudit.js`'s walk and `tests/matrix.js`'s
  route list in the same push that builds it.
- A new thing joins every shared list of its kind in the same push that
  builds it, checked before the PR opens and named in its Test plan: an email its row in Settings › Messages (`js/mailtpl.js`,
  English and 中文); a number or reference its Settings numbering
  (`id_formats`); a business figure its setting; a word two screens say
  `ADspaceWords.line`; a part of a client's record a place within the six
  tabs (`docs/rules/clients.md`), never a seventh; a route the walks; a page
  Page availability (below).
- A new portal page joins Page availability in the same push that builds it: its key taken by `page_set`, the page loading
  `js/maintenance.js`, its row in `#pgSheet`.
- A new state (a second row, a file, an error) is seeded in the walk, because a
  pane that walks empty is a pane nobody has measured.
- The deploy is confirmed from the GitHub Pages workflow run for the merge
  commit (`Deploy the site`, success; `pages build and deployment` until
  Settings › Pages › Source reads GitHub Actions). A deploy GitHub cancelled on its
  timeout is never re-run (the re-run reuses the cancelled deployment): the
  next commit on main deploys the site whole. `curl` to the site returns
  403 from the sandbox and proves nothing.
- Assert the mechanism, not the sentence: measure geometry. Never read a value
  out of markup or a comment.
- Assert that withheld data is absent from the function's payload. Never assert
  a value you believe correct.
- A link handed out for one step of a record ends when the record moves
  past that step, and a suite seeds the link still open at that move.
- A control hidden, a message moved or words taken off a row is first
  grepped by its id or words across the suites and `GUIDES`, and each suite that reads
  it is changed in the same push.
- Before a push, every word the diff puts in front of a person is drafted
  and checked by `docs/rules/copy.md` (DESIGN.md §6), How copy is drafted, and `tests/words.js`
  passes (a word the user rejects is added to it in the same push); copy is
  never left for the user to review. Once a release, before
  its merge, the words that release adds or changes (copyscan's `+` lines,
  never the standing words of a whole file; those are read once a day in
  the tone sweep, §3 Token economy) are read by a second reader: the
  `/copy-review` skill lists them
  (`tests/copyscan.js`) and hands them, with §6 alone, to a fresh agent
  that did not build the change, asking also whether a newcomer would
  understand each label at once as a familiar app's word; every finding is
  fixed or answered, and the PR's Test plan names the review. A line two screens say lives
  once in `ADspaceWords.line` (`js/words.js`); `tests/words.js` fails a
  script that types one, and its PATTERNS stop kinds of wording (a system
  word, a refusal that is no instruction, a tab named wrongly), not only
  phrases already met.
- A word table holds one key a word: a new field's label takes a key of
  its own, grepped in the table first.
- A function's name is declared once in its script: a second declaration
  of the same name replaces the first for every caller; `tests/jsdupes.js` holds it.
- A function removed is first grepped by name across the suites with no
  cap on the output: a suite that cuts a script at `'  function name('`
  uses it.

## 2. Load-bearing invariants

Each line is a rule that broke once. Its reason is in the archive.

### Pages, chrome, boot
- Every page's head, bar, foot, covers, favicon, share card, listing, time zone bar, safe areas, the console's boot, on-demand scripts, PWA, worker, build line and Refresh app: `docs/rules/chrome.md`, read whole before changing any of them or adding a page.

### One copy of each mechanism
Each mechanism's rules are in its `docs/rules/` file, printed on the first
edit of its script; no page keeps a copy of its own.
- `js/api.js` is the only Supabase client (with `phoneWord`, how every phone number reads, and `openStored`, how a stored file opens): `docs/rules/mechanisms.md`.
- `js/money.js` is the only money formatter and the only place a price is adjusted: `docs/rules/mechanisms.md`.
- `js/menu.js` is the only copy of where a ⋯ or a popover card opens and of what a ⋯ holds: `docs/rules/sheets.md`.
- `js/sheet.js` is the only copy of how a form sheet opens and shuts: `docs/rules/sheets.md`.
- `js/confirm.js` is every question with a consequence. **No `window.confirm`, `prompt` or `alert` anywhere.** `docs/rules/sheets.md`.
- `js/ask.js` asks for one value, in place: `docs/rules/sheets.md`.
- `js/grow.js` is the only way a typed box grows: `docs/rules/sheets.md`.
- `js/decide.js` records a client decision: `docs/rules/mechanisms.md`.
- `js/swipe.js` is the only swipe: `docs/rules/mechanisms.md`.
- `js/chart.js` is the only chart (no chart library): `docs/rules/mechanisms.md`.
- `js/media.js` (every video player, the media pass): `docs/rules/media.md`.
- `js/acts.js` is the one table of act glyphs and the one pending state: `docs/rules/mechanisms.md`.
- `js/clock.js` is Malaysia's clock: every page reads a day, a month and today from it: `docs/rules/mechanisms.md`.
- `js/otp.js` is the code from an email typed as a box a digit: `docs/rules/mechanisms.md`.
- `js/copy.js` says Copied one way: `docs/rules/mechanisms.md`.
- `js/icons.js` is the client pages' one icon set and the booking's one step track: `docs/rules/mechanisms.md`.
- `js/guide.js` is the only first-visit guide: `docs/rules/guide.md`.
- `js/state.js` owns loading, empty and failed. **A failed read is never drawn as an empty list.** `docs/rules/cmdbar.md`.
- `js/group.js` draws every directory card: `docs/rules/cmdbar.md`.
- `js/cmdbar.js` owns the command bar: `docs/rules/cmdbar.md`.
- `js/form.js` owns forms, segments, the one save check, the finder and every date field: `docs/rules/form.md`.
- `js/words.js` holds every word two pages share, in English and Chinese: `docs/rules/mechanisms.md`.
- `js/captcha.js` is Turnstile: `docs/rules/mechanisms.md`.
- `js/trace.js` is the viewer's trace over a screen of personal data: `docs/rules/security.md`.
- A short month is `Sept`, never the browser's `Sep`: `docs/rules/mechanisms.md`.

### Writes, refusals, reversibility
- The lines only SQL meets (grants, function hygiene, PL/pgSQL, a function's
  today, seeds, guard triggers, policies) are `docs/rules/database.md`, read
  whole before changing `supabase/`. A business figure the team may change is
  a setting an admin edits, effective from a date (`app_settings`,
  `perf_settings`), never a number typed into code: `docs/rules/database.md`.
- An import from another system (Bukku, Meta, a spreadsheet) lists what
  it found and takes only what the person ticks, never all of it at once;
  and whatever a person can add, they can delete (where nothing names it)
  from its own ⋯ and several at once through Select.
- Every email box takes an address alone (`ADspaceWords.emailOk`, the one reading): a value that is no
  address (digits, a host with no domain, a space, a list) is refused where
  it was typed as Enter a valid email address., nothing written; the
  console's sign-in, the client portal's, a lead's, a contact's, Billing's
  finance email, a colleague's, a supplier's, the details and supplier forms
  and /quote/ alike (`tests/emailbox.js`). Page-side only.
- Every page's `esc` is `ADspaceWords.esc` (`js/chrome.js` keeps its own,
  loaded before it; one copy), escaping `"` and `'` as well as `&`, `<`, `>`: a stored
  value is drawn inside attributes.
- A value is never drawn raw because of what it starts with: a fact not set
  is a flag (`null` drawn as Not set), never sniffed from its text.
- A stored address drawn as a link is held to the web twice: a check on its
  column (`^https?://`, an invoice `https://` or `private/`) and the page
  drawing it only on http or https (`ADspaceWords.absUrl`, the one copy, answers nothing for another
  scheme, nor for a space, quote, `<`, `>`, backtick or backslash the column's check refuses; a booking's file and a document's file link likewise, opened by `window.open` too). A link typed
  bare takes `https://` (a month's Drive folder too, its column https
  alone); one `absUrl` answers nothing for is refused where it was typed
  (Enter a web address.), never saved as none. A value
  drawn as HTML is escaped where it is put in, never where it is joined.
- **A write that changed nothing is not a success.** PostgREST answers a refused
  delete or update with 204 and no error. Every delete and every
  policy-refusable update takes `.select('id')`, and an empty answer is named
  (`Not deleted. The database refused the request.`).
- Use `.then(ok).catch(bad)`, never `.then(ok, bad)`: `bad` never sees what
  `ok` throws.
- A function's refusal reaches the page whole: a call wrapper hands back the
  answer with what came with it (`recent`, `paid`), never the code alone.
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
- Every forward move is walked backwards before it ships.
- `expected_version` refuses a stale write with the current row, and the page
  repaints from it.
- A comparison of two copies (a migration and its schema section; the
  `ACTION_LABEL` map and `activity_section()`) is enforced by a suite.
- A merge leaves no conflict marker in any file: the merge check
  (`verify-gate.sh`) holds a commit carrying one in every mode but off.

### Access
- Access is a level per section, **none < view < work < manage**, in `team_roles.access` / `team_members.access`; `allowed(section, level)` is every policy's predicate, and a control the database would refuse is not drawn. Every other access rule: `docs/rules/access.md`.

### Directories and the command bar
- Every console directory's cards, a filter, a list's order, how a list reads, the command bar's end, the rail's one sequence, a route's purpose line and its standing note: `docs/rules/directories.md`, read whole before changing a list.

### Area rules (read before changing an area)

Each area's rules live in its own file under `docs/rules/`, out of what every
session loads. The shared rules (each one-copy mechanism, the tests and
the stand-in, access, sign-in and security, the database) live there too, each
under its own triggers, with one loaded line here naming its file. Before changing an area, read its file whole. The first
edit of a path in its triggers prints the file's name (`.claude/hooks/area-rules.sh`);
a change reaching an area with no path of its own (a schema band, a function)
is found with `grep -rln "<function, table or word>" docs/rules/`. An
area's rules live in its `docs/rules/` file alone: a block about one area
(a section, a page, a tool) is never written in this file or `DESIGN.md`,
only a one-line pointer to it.

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
| Creators | `docs/rules/creator-campaigns.md` | `js/campaigns.js`, `js/creators.js`, `js/creator.js`, `js/decide.js`, `creators/`, `creator/`, `supabase/functions/creator-mail` |
| Dashboard | `docs/rules/dashboard.md` | `js/overview.js` |
| Analytics | `docs/rules/analytics.md` | `js/analytics.js`, `supabase/functions/analytics-read` |
| My Work | `docs/rules/my-work.md` | `js/ops.js`, `supabase/functions/meet-create` |
| Outstation record | `docs/rules/outstation.md` | `js/outstation.js`, `supabase/functions/outstation-geo` |
| Performance | `docs/rules/performance.md` | `js/perf.js` |
| Personnel | `docs/rules/personnel.md` | `js/personnel.js`, `js/xlsx.js` |
| Health | `docs/rules/health.md` | `js/health.js` |
| Reports | `docs/rules/reports.md` | `js/reports.js`, `js/smreport.js`, `supabase/functions/report-draft`, `supabase/functions/meta-import` |
| Services | `docs/rules/services.md` | `js/quotes.js`, `js/quotepdf.js`, `js/ratecardpdf.js`, `js/quote.js`, `quote/`, `supabase/functions/quote-request`, `js/money.js` |
| Client portal | `docs/rules/client-portal.md` | `client/`, `js/portal.js` |
| Client feedback | `docs/rules/client-feedback.md` | `js/feedback.js`, `js/fbform.js`, `feedback/` |
| Short Links | `docs/rules/short-links.md` | `workers/links` |
| Video Scripts | `docs/rules/video-scripts.md` | `js/scripts.js`, `js/scriptpdf.js`, `js/script.js`, `script/`, `js/frames.js`, `js/animatic.js`, `supabase/functions/script-draft`, `supabase/functions/script-pictures` |
| Handbook | `docs/rules/handbook.md` | `js/handbook.js` |
| Team | `docs/rules/team.md` | `js/team.js`, `js/namecard.js`, `js/card.js`, `card/`, `supabase/functions/invite-member` |
| Activity record | `docs/rules/activity.md` | `js/records.js` |
| Messages: WhatsApp and Email | `docs/rules/messages.md` | `js/whatsapp.js`, `js/mailtpl.js`, `supabase/functions/wa-send`, `supabase/functions/wa-hook`, `supabase/functions/_shared/mail.ts` |
| Push notifications | `docs/rules/push.md` | `js/push.js`, `js/push-sw.js`, `supabase/functions/push-send` |
| Settings and Public holidays | `docs/rules/settings.md` | `js/settings.js` |
| Page availability, the latest build, Announcements, Notices | `docs/rules/portal-notices.md` | `js/maintenance.js`, `js/announce.js`, `js/notice.js` |
| The phone tab bar and Arrange sections | `docs/rules/tab-bar.md` | none (`js/admin.js` is shared; grep `tabBar`, `railSheet`) |
| The front door | `docs/rules/front-door.md` | `index.html`, `img/front-door` |
| Media and the media pass | `docs/rules/media.md` | `js/media.js`, `supabase/functions/media-pass` |
| The demo | `docs/rules/demo.md` | `js/demo.js`, `demo/` |
| Overseas access | `docs/rules/overseas.md` | none (grep `abroad`) |
| Shared mechanisms (Supabase client, money, acts, clock, code boxes, icons, words, Turnstile, decide, swipe, chart) | `docs/rules/mechanisms.md` | `js/api.js`, `js/money.js`, `js/acts.js`, `js/clock.js`, `js/otp.js`, `js/copy.js`, `js/icons.js`, `js/words.js`, `js/captcha.js`, `js/decide.js`, `js/swipe.js`, `js/chart.js` |
| Menus, sheets, questions, typed boxes | `docs/rules/sheets.md` | `js/menu.js`, `js/sheet.js`, `js/confirm.js`, `js/ask.js`, `js/grow.js` |
| The first-visit guide | `docs/rules/guide.md` | `js/guide.js` |
| Loading states, directory cards, the command bar | `docs/rules/cmdbar.md` | `js/state.js`, `js/group.js`, `js/cmdbar.js` |
| Forms and dates | `docs/rules/form.md` | `js/form.js` |
| Tests, the stand-in, the walks | `docs/rules/tests.md` | `tests/` |
| Access | `docs/rules/access.md` | `js/team.js`, `js/delreq.js`, `js/admin.js`, `supabase/` |
| Sign-in, security, secrets | `docs/rules/security.md` | `supabase/functions/`, `client/`, `admin/index.html`, `js/passkey.js`, `js/portal.js`, `workers/`, `js/trace.js` |
| Database | `docs/rules/database.md` | `supabase/` |

### Sign-in, security, secrets
Every sign-in and security rule: `docs/rules/security.md`.
- Secrets never enter the repo or the chat:
  - The Supabase anon key and the Google browser key are public by design.
  - The Turnstile secret, the Google refresh token, the Meta system user's
    token and the performance master code live only in Supabase.
  - The delete code lives in the database.
- Nothing deletes from S3: every uploaded file is kept, Content Review files and creator drafts included (`docs/rules/security.md`, S3).

## 3. Workflow and constraints

### Git and delivery
- The branch the session is given (any account: the work carries in the
  repositories, a release in progress on its PR, never in a session); a
  branch with an open PR is continued, not replaced. Squash-merged by
  Claude. Releases are
  grouped by risk: related batches share one PR and
  one deploy where the combined diff, the migration sequence and the
  rollback stay understandable; unrelated or independently risky changes
  go apart.
- At most four sessions run at once: each holds one request on its own branch and PR,
  merges `main` in where another merged first, and merges as soon as it
  is built, never waiting to be asked. One gate a machine still holds.
  "Hand over" means: commit and push both repositories, then post
  or replace one comment on the open PR (else a draft PR) stating the
  commits, the checks passed, failed and not run, the steps done and
  still open in order with their rollback, and what waits on the user. A
  session opening on an open PR reads its latest handover first and
  continues its branch.
- The session that starts others checks every one it started every 30
  minutes while any runs (`list_sessions` children and their status line
  alone, never a transcript; a `send_later` check-in), never waiting for a report: one blocked or idle with its PR
  unmerged is unblocked, or its PR merged by the starting session; a
  session's own brief says it merges without asking.
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
- How a migration is applied (the Supabase connector, project `hwwuigvdfubuymchsvyx`, or the Management API) and how an edge function is deployed (whole, read back, from a branch with `main` merged in, with its `_shared/` files): `docs/rules/release.md`, read whole before either.
- The report lists what the user does by hand: a dashboard setting.
- Every go-live report names the version the console shows exactly as the rail reads it (`{YYMMDD}.{commit}`: `git log -1 --format=%h --abbrev=7` on the merge commit, its last four), so the person can match it.
- Never ask for a URL, key or asset the repo or config already holds. Check
  `js/config.js` and `css/` first.

### Token economy (the user, 2026-11-26; binding on every account and session)
Every session, agent and check-in is paid for in the account's usage, so
work is shaped to spend it on the fix, not on overhead.
- **Release trains, not a PR a fix.** A hotfix (a fault that blocks work
  or that a client sees) ships alone at once. Every other fix, word and
  polish is built on one branch per area through the day and ships as one
  minor release per area once or twice a day: one test run, one screenshot
  pass, one copy review, one merge. A feature with a migration is a major
  release on its own PR. (This replaces "one request, one release".)
- **Short sessions.** A session's context is re-read on every turn, so a
  long session costs more each hour. A session holds one train or one
  major release and ends when it merges; the next work starts in a fresh
  session from the repo and the PR's handover, never by continuing a long
  one. A coordinating session hands over and is replaced daily.
- **Copy review reads what changed.** Per release, the second reader gets
  copyscan's added and changed lines alone; the whole screens' standing
  words are read once a day, in one tone sweep after the day's merges.
- **Screenshots of what changed.** The changed screens at 1280 and 390;
  both themes only where a stylesheet or a theme token changed.
- **One test run per release.** Commit, then gate a frozen copy
  (`tests/snap.sh`); never edit what a running gate tests, and never stop
  and restart a run for a further edit: the edit waits for the next train.
- **Whole-portal audits** (unslop, ux-audit, security) run only when the
  user asks, once.
- **Held SQL runs through the connector.** The user approves running a
  migration's `drop` or `delete` statements directly (2026-11-26: "Run all
  sql dont care if its drop delete"): nothing waits for the SQL Editor; the
  release applies it and verifies it live (`docs/rules/release.md`).
- **Agents and sub-sessions get a tight brief** (the goal, the files, what
  not to do) and report in under 600 words; their transcripts are never
  read whole.

### Folder and file rules
- Never edit the user's root files: `ap01.html` and `accv-new.html`, the
  Jotform pages left (the user, 2026-11-12, every other removed: AP02,
  AP03, AP Dale, 3P form, e-Invoice info, interview quiz, sales
  programme). `index.html` and `404.html` are the portal's;
  `supplier.html` was retired for `/supplier/`.
- `drafts/` (holding the old Jotform verify page) is excluded from Pages.
- Portal pages are folders with an `index.html` and clean paths; never `.html`
  in a URL.
- New pages start from `docs/PAGE-TEMPLATE.html`.
- Two stylesheets, never more:
  `css/portal.css` holds the tokens and every rule a client page can meet,
  and is the only sheet a client page loads; `css/console.css` holds the
  rules only the console meets, loaded by `admin/` alone right after it. A
  rule moved between them keeps its place in the cascade (equal
  specificity and a shared property against a later rule of the other
  sheet keep it in `portal.css`); a console base and its own `@media`
  override share a sheet, the override after it (`cssguard`). One script per section, and the one-copy
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
  (`visitSection`; `tests/visit.js`); a press on
  the section already open (the rail, the tab bar, a mark at the rail's
  foot) goes back to its list, as an iPhone's tab bar does: the open
  record is left by its own Back, one at a time, never pressed twice, and
  a press on the list takes it to its top; the bell and search still open
  the record whose address they wrote (`railPress`); only Back and
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
  `serviceTermsUrl`; never typed (`tests/demo.js`).
- Emails:  - support and issuer: advertise@adspacestudios.com (the client portal's
    contact line too);
  - every email the portal sends goes from `portal@sc.adspace.me` under its
    section's name (clients, suppliers, creators, careers, finance, team;
    `mail_senders`, `mail_sender(p_key)` through `_shared/mail.ts` `sender`;
    never a no-reply address, `2026-11-18-portal-sender.sql`;
    Supabase's own sign-in emails from the same address, set in its SMTP
    settings), and replies to a company mailbox, never a
    colleague's own address: General
    advertise@ (clients, invitations to colleagues, all else), HR hr@
    (careers: every email to a candidate), Accounts
    payable ap@ (suppliers, creators), Finance finance@ (invoices and
    reminders), e-Invoice einvoice@ (e-invoice submissions alone), Legal
    and compliance legal@ (named by /verify/ where a copy does not match,
    `verify_details` `contact`); the six are
    Settings, Messages: Reply-to mailboxes (`mail_boxes`,
    `mail_boxes_set`, `team.settings`, filed `team.changed` under Reply-to
    mailboxes), the pages reading them through `mail_senders_read`
    (`ADspaceDocMail.showSender`) and the Email log's From through
    `mail_log` `senders`;
  - every link an email carries is on adspace.me (the sending domain,
    `sc.adspace.me`), the foot's website `adspace.me` in its words too,
    and the wordmark at the head opens it (Resend's check: a link off the sending domain reads as spam);
  - admin login: adspacestudios@gmail.com.
- Google Drive import uses the browser key (restricted to
  `digital.adspace.me/*`, Drive API only).

### Guardrails the user gave
- "This should be automatic on your structure when designing": every rule in
  `DESIGN.md` and its `docs/rules/` files (components, laws, copy, print) is applied before the user sees a screenshot.
- A first build is the finished design, never text first and design later:
  every new screen is built from the v3 components it needs (facts, a
  timeline, figures, thumbnails, the phone row) in its first release, and
  its screenshots are read for runs of text a component would carry.
- "Do not state the obvious." "Be concise and direct." No explanatory copy.
- "Every action needs a way back." "Same status throughout." "Prefilled, not
  fixed." "A phone screenshot is reviewed, not just taken." "A change a client-facing page shows is shown to the user as screenshots and approved before it merges; a console change merges once tested." "Intake asks for
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
- A place the user names by a word two areas share (a console section, a
  Settings group) is checked against where the thing already lives before
  anything moves.
- Every change adds value the portal keeps: a fix goes to its cause in the shared
  mechanism, so the same fault cannot recur elsewhere, never a patch on the
  one screen reported; a change with no lasting gain is not made.
- A change asked of one list or screen is made on every one of the same
  shape in the same push.
- A value only read is drawn as words at the field's height with no box
  (`.readfield` on a `p` or `div` is that, on an `.input` the shaded copy
  field): a shaded slab with its words on the edge, out of line with the
  fields under it, reached the user twice (Reports' Amount spent; Send
  email's From, Replies go to and To), so a sheet's screenshot
  is read for every value only read, and `tests/suppliers.js` measures it.
- Every mistake that reaches the user or the gate is written in the push
  that fixes it: the rule,
  one line, in its loaded file; the story in `docs/DECISIONS.md` Part 3
  (what broke, why, how it was found).
