<!-- triggers: js/api.js js/money.js js/acts.js js/clock.js js/otp.js js/copy.js js/icons.js js/words.js js/captcha.js js/decide.js js/swipe.js js/chart.js js/tpl.js supabase/functions/_shared/prompts.ts -->
# Shared mechanisms

Moved from `CLAUDE.md` §2, One copy of each mechanism, on 2026-11-23. Each is the one copy of its mechanism: no page keeps its own.

- The agency profile (restructure release 6, 2026-11-28) is the one source
  of every value that names the agency: `agency_profile` in the database
  (`agency(key)` for a function, `agency_profile_read()` for a colleague
  and the edge functions through `_shared/agency.ts`), and on the
  page `window.ADspaceAgency` in `js/config.js`, the install's copy, held
  equal to the seed by `tests/agencysql.js`. `ADSPACE_ORG` and
  `ADSPACE_CONFIG`'s agency fields alias it (`ADspaceAgency.alias`), never a
  copy; a script reads them with no typed fallback (`brandguard` counts
  one). The General mailbox is `mail_boxes`, answered as
  `email`, never copied into the profile; a sender's address is held to
  the profile's `sender_domain`. A page script joins a profile value into
  its words (`var AGENCY = window.ADspaceAgency || {};` at the top of its
  IIFE, then `'Contact ' + AGENCY.trading_name`), never types it: a line,
  a filename, a PDF's author, a link's host, a pattern on the CDN
  (`js/media.js` builds its patterns from `cdn_base`); a field's example
  (an email, a website, a profile link) and the map's search are
  `ADSPACE_CONFIG.examples` and `mapSearch`. Words built so follow the
  demo's sample agency by themselves (its alias setters write the
  profile), so no script swaps names after drawing them.
  On the server (release 8, 2026-11-28) a
  database function reads `agency(key)`, an edge function
  `_shared/agency.ts` (the email layout's wordmark and company line, the
  sender's fallback, every link and name it sends; `layout` and
  `codeEmail` are async), and the links Worker its own settings
  (`PORTAL_URL`, `HOME_URL`, `AGENCY_NAME`, `WORDMARK_URL`), set equal to
  the profile because the public key it reads with is not answered it.
- Every prompt an edge function sends Claude (restructure release 17,
  2026-11-28) is a template in the store (`templates`, kind `ai-prompt`,
  English, key `ai.{function}.{part}`), read by `_shared/prompts.ts`
  (`prompts(db, keys)` through `template_render` as the colleague, before a
  press is counted; a prompt names another by `{ai.key}`), never a literal
  in a function. A key not live answers `ai-not-set-up` and sends nothing;
  the seed lives in the private tests repository (`prompts/`), never in
  this public one (`tests/promptstore.js`). Tool and schema descriptions
  stay with the code that reads their answers.
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
    S$ beside it (`approx(n, c, at, fx, zh)`, ` (approximately S$ 952.38)`,
    in Chinese `（约 S$ 952.38）`, at a record's `fx`, else `fx_sgd` on `at`).
  - SST at the rate in force on the document's own day (`taxOf(sub, m,
    applies, at)`, `taxLabel(m, at)`; a letter passes its `issued_at`, a
    campaign's booked creators the client's last confirmation (`kind`
    client), a selection still to confirm none)
    unless `sst_applies` is false.
  - Two decimals on every total, each charged figure (`rateFor`, `taxOf`)
    rounded by `cents()`, a half away from nought as Postgres rounds, the
    float nudged first (1,234.50 × 0.95 is 1,172.7749… in a float).
  - `TERMS` holds the older factor table (used when `term_pct` is null).
  - `ADspaceMoney.load()` reads the business figures (`app_settings_read()`,
    anon too), never for the page's life: a load() five minutes on asks
    again, so does a return to the page or its focus a minute on, a new
    Malaysian day, and another tab's `load(true)` (a save) through the
    `adspace-settings-at` stamp; nothing on a timer; every read dispatches
    `adspace-settings`, and a screen holding a figure from it (Build quote's
    S$ rate) prices again on it (2026-11-26, F4; `tests/sgd.js`) and `setting(key, at)` answers them;
    the console waits for it beside `me()`, the client portal beside
    `get_portal`, the selection page beside `get_campaign`. `FIRST` is used
    only where the read fails, and is the one copy of a default (no page
    keeps its own); a failed read is not kept, so the next `load()` asks
    again. A figure is read at the day it applies to, as the database reads
    it (a report's deadline at its period's end).
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
- `js/acts.js` (`ADspaceActs`) is the one table of act glyphs and the one
  pending state (the user, 2026-10-10): every console `.btn` whose words are
  an act carries its mark (Publish the plane, Unpublish the struck eye,
  Edit the pen, Download the file, Copy the copy mark, Preview and Preview
  PDF the leaving mark after the words, Add and New the plus, Issue Letter of Offer the letter, Invite, an email sent and Send code the envelope, Use passkey the key, Open in Bukku the leaving mark after, Open {a console page} and View the chevron after; a quiet button as a filled one), given as the
  button is drawn where a screen wrote words alone; a form's own commit
  stays words; a way out (Preview, Download, Copy) and another way in (a
  passkey, a code sent) are never a commit, keeping the mark inside a form
  or beside a field. A press whose write disables its button shows, after 150ms,
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
  field; a whole code arriving presses the field's Enter once until it changes, never while an input method composes, the page's one check (2026-11-22: /creator/'s own second check sent each code twice).
- A function's file answer (a trip photo, an employee record file) comes
  as `application/octet-stream` or a PDF, the only types supabase-js hands
  over as a file (an image/jpeg answer arrives as text), and the page names
  it by its first bytes through `ADspaceAPI.fileOf` (JPEG, PNG, PDF or
  null), the one copy (2026-11-24). The stand-in answers as the library
  does.
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
  an off-screen textarea. Words the server makes at the press are copied by
  `later(btn, promise)`, the write begun inside the press (a ClipboardItem
  holding the promise), never after the answer alone (Safari refuses it).
  A reference a person comes to copy is the control itself:
  `ADspaceCopy.ref(text)` draws it (`.serial-copy`) and one capture-phase
  listener copies it without opening the row (the Register, quotations).
- `js/icons.js` is the one glyph set of every page, console and client
  alike (the user, 2026-11-26), and its drawing the standard: 24 grid,
  stroke 1.8, round ends, outline in ink, never filled or coloured; a new
  glyph is drawn the same way, never copied from elsewhere. One thing, one
  glyph, everywhere: a section, a record or a part of one is asked for by
  its meaning (`MEANS`: `scripts`, `review`, `campaigns`, `meetings`,
  `invoices`, `edit`, `send` …), so the rail, tab bar, search, bell and
  records draw what the client portal, /quote/ and the creator pages draw.
  A script asks `ADspaceIcons.glyph(name, cls, attrs)` where its place
  sizes the glyph (the console) or `svg(name, cls)` for the 15px `.ic`;
  a page's markup writes `<svg data-ic="name"></svg>` and the set draws it
  on load; a ring of progress, a signature and a plotted line are
  `ring()` / `drawing()`; `js/acts.js` names its acts' glyphs from the set.
  No script writes an `<svg>` but the set, `chart.js`, `frames.js` and
  `mockups.js`; a name it does not hold draws nothing (`tests/glyphs.js`).
  `platform(key)`, `journey(words, at)`: the platform glyphs and the booking's one step track (`.cx-journey`), drawn
  alike on the selection page and the creator's page, its words `W.journey`
  in `js/words.js` (Booked, Shoot visit or Delivery, Draft due, Client
  review, Post date, Results; never a bare verb or a word that could read
  as one, the user, 2026-10-15), each breaking at its space, never cut;
  with discs, each step's column is its part's width, so a name wider than
  its part never moves its disc off the centre its lines are placed from
  (`demo` measures every line clear of both discs).
  `mark(key)` is a platform's own mark beside the platform's name where a
  prospect chooses platforms (/quote/): single colour in ink, never a brand
  colour fill, the cut-outs in the card's ground (`.ic-cut`), Meta drawn as
  Facebook and Instagram together (the user, 2026-11-24).
- `js/words.js` holds every word two pages share (covers, statuses, actions) in
  English and Chinese, plus the tones (`W.TONE`, `W.tone`) and `W.dept`.
  - Pages merge with `ADspaceWords.of({en, zh})`; `/review/` takes
    `ADspaceWords.en`.
  - The console's `STAGES`, `SV_STATE`, `RQ_STATE`, `RQ_KIND`, `OPTION_WORD`
    and `STATE_WORD` are built from it, never typed again.
  - `ADspaceWords.brnCheck(value, market, kind)` is the one reading of a
    business registration number, and `brn_check` its one copy in SQL
    (ONE BRN RULE, 2026-11-28): spaces and dashes dropped; Malaysia 12
    digits, a year from 1900 to this year, the entity code 01, 02 or 04 a
    company and 03 Sole / Partnership (`kind` holds the code to the choice);
    a Singapore client (`market` SG) bills through either country's
    company, so a UEN or a BRN; no market in SQL takes the same.
    Its refusals are `brnBad` and `uenBad`. /quote/'s intake and signing,
    the details form, Billing, the supplier form and a creator's payment
    details read it; no form types its own pattern.
- `js/captcha.js` is Turnstile (`interaction-only`, `flexible`, `theme` from
  `data-theme`).
  - One box per `[data-cf]` card; otherwise after the button's row (grid or row
    flex), else after the button.
  - The site key is `ADSPACE_CONFIG.turnstileSiteKey`. A token rides every
    emailed sign-in; where Cloudflare is unreachable the email still goes.
- A short month is `Sept`, never the browser's `Sep` (Safari): every English
  short-month format ends `.replace(/\bSep\b/, 'Sept')`, and My Work builds
  its dates from `MON_SHORT`.
- The template store (`templates`, `2026-11-28-template-store.sql`; restructure
  release 11, layer 3): agency wording a person reads is one row a version,
  a key in a language (`en`, `zh`), its `kind` naming the sender's field
  list (`template_fields`). The database renders what is sent
  (`template_render(key, lang, record, values, at, strict)`: the version in
  force on the Malaysian day, 中文 going out in English where none is live
  and saying so, a record's fields bound at the reader's access by
  `template_values`, a value given never overriding a record's); `js/tpl.js`
  (`ADspaceTpl.fill`, `names`, `render`, `said`) previews what is typed the
  same way, and `templatesql` holds the two equal case by case. A value is
  escaped where it is inserted (`ADspaceWords.esc`); a field with no value
  is kept as `{field}` and named in `missing`, refused `missing-field` where
  `strict`, never sent blank. A page that prints a set of templates (the HR documents) reads
  them in force on the record's own day through its area's function and
  fills them with `ADspaceTpl.fill`, a field left empty printing nothing.
